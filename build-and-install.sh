#!/bin/bash
# DriMacIME - Build and Install Script
# Run this on your Mac with: bash build-and-install.sh
set -euo pipefail

APP_NAME="DriMacIME"
BUNDLE_ID="com.drikin.DriMacIME"
BUILD_DIR="/tmp/${APP_NAME}_Build"

echo "=== Building DriMacIME ==="

# Create bundle structure
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"

# Create a minimal icon (16x16 blue D)
python3 -c "
import struct, zlib
def png(w,h,p):
    def c(t,d): return struct.pack('>I',len(d)) + t + d + struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w): raw += bytes(p[y*w+x])
    return b'\x89PNG\r\n\x1a\n' + c(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0)) + c(b'IDAT',zlib.compress(raw)) + c(b'IEND',b'')
pix = []
for y in range(16):
    for x in range(16):
        if (x in (2,3,4,5,6,7,8) and y in (2,13)) or (x==2 and 3<=y<=12) or (x in (9,10) and y in (3,12)) or (x==11 and 4<=y<=11):
            pix.append((100,180,255,255))
        else:
            pix.append((0,0,0,0))
with open('/tmp/drimac_icon.png','wb') as f: f.write(png(16,16,pix))
" && sips -s format tiff /tmp/drimac_icon.png --out "$BUILD_DIR/$APP_NAME.app/Contents/Resources/main.tiff" &>/dev/null

# Create Info.plist
cat > "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Application is background only</key>
	<true/>
	<key>CFBundleIdentifier</key>
	<string>com.drikin.inputmethod.DriMacIME</string>
	<key>CFBundleName</key>
	<string>DriMac IME</string>
	<key>CFBundleDisplayName</key>
	<string>DriMac</string>
	<key>CFBundleExecutable</key>
	<string>DriMacIME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>InputMethodConnectionName</key>
	<string>com.drikin.inputmethod.DriMacIME_Connection</string>
	<key>InputMethodServerControllerClass</key>
	<string>DriMacInputController</string>
	<key>NSPrincipalClass</key>
	<string>DriMacApplication</string>
	<key>tsInputMethodCharacterRepertoireKey</key>
	<array><string>Latn</string><string>Jpan</string></array>
	<key>tsInputMethodIconFileKey</key>
	<string>main.tiff</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSExceptionDomains</key>
		<dict>
			<key>100.78.215.127</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
				<key>NSIncludesSubdomains</key>
				<false/>
			</dict>
		</dict>
	</dict>
</dict>
</plist>
PLIST

# Write source files
mkdir -p /tmp/${APP_NAME}_src
cat > /tmp/${APP_NAME}_src/AppDelegate.swift << 'SWIFT'
import Cocoa
import InputMethodKit

@objc(DriMacApplication)
class DriMacApplication: NSApplication {
    private let appDelegate = AppDelegate()
    override init() { super.init(); self.delegate = appDelegate }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let connName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        server = IMKServer(name: connName, bundleIdentifier: Bundle.main.bundleIdentifier)
        NSLog("DriMacIME: server initialized")
    }
}
SWIFT

cat > /tmp/${APP_NAME}_src/DriMacInputController.swift << 'SWIFT'
@preconcurrency import Cocoa
@preconcurrency import InputMethodKit

extension IMKInputController {
    nonisolated fileprivate func wrap(_ object: Any?) -> UInt? {
        guard let object = object as? AnyObject else { return nil }
        return UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
    }
    nonisolated fileprivate func unwrap(_ addr: UInt?) -> Any? {
        guard let addr = addr, let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    }
}

@objc(DriMacInputController)
nonisolated public final class DriMacInputController: IMKInputController, @unchecked Sendable {
    private var phrases: [String] = []
    private var current: String = ""
    private let inferenceURL = URL(string: "http://100.78.215.127:8000/v1/chat/completions")!
    private let session: URLSession = { let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 3.0; c.timeoutIntervalForResource = 5.0; return URLSession(configuration: c) }()
    private var converting = false
    private var conversionTask: Task<Void, Never>?

    private var fullText: String {
        if current.isEmpty { return phrases.joined(separator: " ") }
        return (phrases + [current]).joined(separator: " ")
    }

    @objc(deactivateServer:)
    nonisolated override public func deactivateServer(_ sender: Any!) {
        conversionTask?.cancel(); conversionTask = nil; phrases = []; current = ""; converting = false
        super.deactivateServer(sender)
    }

    @objc(handleEvent:client:)
    nonisolated override public func handle(_ event: NSEvent?, client sender: Any?) -> Bool {
        guard let event = event, event.type == .keyDown else { return false }
        if event.modifierFlags.contains(.command) { return false }
        guard let chars = event.characters else { return false }
        let isShift = event.modifierFlags.contains(.shift)
        let senderRef = wrap(sender)
        if Thread.isMainThread { return handleOnMain(chars: chars, keyCode: event.keyCode, isShift: isShift, client: unwrap(senderRef) as? IMKTextInput) }
        return DispatchQueue.main.sync { self.handleOnMain(chars: chars, keyCode: event.keyCode, isShift: isShift, client: unwrap(senderRef) as? IMKTextInput) }
    }

    private func handleOnMain(chars: String, keyCode: UInt16, isShift: Bool, client: IMKTextInput?) -> Bool {
        guard let client = client else { return false }
        if converting { return true }
        if keyCode == 0x33 {
            if !current.isEmpty { current.removeLast(); updateMarked(client: client); return true }
            else if !phrases.isEmpty { current = phrases.removeLast(); updateMarked(client: client); return true }
            return false
        }
        if keyCode == 0x35 { phrases = []; current = ""; let a = NSAttributedString(string: ""); client.setMarkedText(a, selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); return true }
        if chars == " " {
            if !current.isEmpty { phrases.append(current); current = ""; updateMarked(client: client); return true }
            return false
        }
        if keyCode == 0x24 {
            if !fullText.isEmpty { doConvert(client: client, mode: isShift ? .toEnglish : .toJapanese) }
            return true
        }
        if chars == "\t" {
            if !fullText.isEmpty { commitAsIs(client: client) }
            return true
        }
        let accepted = CharacterSet.lowercaseLetters.union(.uppercaseLetters).union(CharacterSet(charactersIn: " ,.!?'-"))
        guard chars.rangeOfCharacter(from: accepted.inverted) == nil else {
            if !fullText.isEmpty { doConvert(client: client, mode: .toJapanese) }
            return false
        }
        current += chars.lowercased(); updateMarked(client: client); return true
    }

    private func updateMarked(client: IMKTextInput) {
        let text = fullText; let attr = NSAttributedString(string: text)
        client.setMarkedText(attr, selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private enum ConvertMode { case toJapanese, toEnglish }

    @objc(inputText:client:)
    nonisolated override public func inputText(_ string: String!, client sender: Any!) -> Bool { return false }

    private func commitAsIs(client: IMKTextInput) {
        conversionTask?.cancel(); conversionTask = nil
        let text = fullText; phrases = []; current = ""; converting = false
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func doConvert(client: IMKTextInput, mode: ConvertMode) {
        conversionTask?.cancel(); conversionTask = nil
        let text = fullText; phrases = []; current = ""; converting = true
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        conversionTask = Task { [weak self] in
            guard let self = self else { return }
            let result: String
            switch mode {
            case .toJapanese: result = await self.convertRomaji(text)
            case .toEnglish: let jp = await self.convertRomaji(text); guard !Task.isCancelled else { return }; result = await self.translateToEnglish(jp)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { self.converting = false; client.insertText(result, replacementRange: NSRange(location: NSNotFound, length: NSNotFound)) }
        }
    }

    private func convertRomaji(_ romaji: String) async -> String {
        let prompt = "Convert the following romaji text to natural Japanese. Fix any typos, missing letters, repeated words, and make it natural. Output ONLY the converted Japanese text. No explanation. No quotes."
        let body: [String: Any] = ["model": "spark-local", "messages": [["role": "system", "content": prompt], ["role": "user", "content": romaji]], "max_tokens": 60, "temperature": 0.1]
        return await callLLM(body: body, fallback: romaji)
    }

    private func translateToEnglish(_ japanese: String) async -> String {
        let prompt = "Translate the following Japanese text to natural English. Output ONLY the English translation. No explanation. No quotes."
        let body: [String: Any] = ["model": "spark-local", "messages": [["role": "system", "content": prompt], ["role": "user", "content": japanese]], "max_tokens": 60, "temperature": 0.1]
        return await callLLM(body: body, fallback: japanese)
    }

    private func callLLM(body: [String: Any], fallback: String) async -> String {
        var req = URLRequest(url: inferenceURL); req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await session.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else { return fallback }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let first = choices.first,
               let msg = first["message"] as? [String: Any], let content = msg["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch { NSLog("DriMacIME error: \(error)") }
        return fallback
    }
}
SWIFT

# Compile
swiftc \
  -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -framework Cocoa \
  -framework InputMethodKit \
  -o "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
  /tmp/${APP_NAME}_src/AppDelegate.swift \
  /tmp/${APP_NAME}_src/DriMacInputController.swift

echo ""
echo "=== Build successful! ==="
echo ""
echo "To install, run:"
echo "  sudo cp -r \"$BUILD_DIR/$APP_NAME.app\" /Library/Input\\ Methods/"
echo "  sudo chmod -R 755 \"/Library/Input Methods/$APP_NAME.app\""
echo ""
echo "Then: System Settings > Keyboard > Input Sources > Add 'DriMac'"
