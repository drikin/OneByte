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

@objc(OneByteInputController)
nonisolated public final class OneByteInputController: IMKInputController, @unchecked Sendable {
    private var phrases: [String] = []
    private var current: String = ""
    private let inferenceURL = URL(string: "http://100.78.215.127:8000/v1/chat/completions")!
    private let session: URLSession = { let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 3.0; c.timeoutIntervalForResource = 5.0; return URLSession(configuration: c) }()
    private var converting = false
    private var conversionTask: Task<Void, Never>?
    private var isActive = false
    private let maxPhrases = 20
    private let maxCurrentLen = 200

    private var fullText: String {
        if current.isEmpty { return phrases.joined(separator: " ") }
        return (phrases + [current]).joined(separator: " ")
    }

    private var capslockOn = false

    @objc(deactivateServer:)
    nonisolated override public func deactivateServer(_ sender: Any!) {
        conversionTask?.cancel(); conversionTask = nil; phrases = []; current = ""; converting = false
        super.deactivateServer(sender)
    }

    @objc(handleEvent:client:)
    nonisolated override public func handle(_ event: NSEvent?, client sender: Any?) -> Bool {
        guard let event = event else { return false }

        // Track CapsLock state via flagsChanged events
        if event.type == .flagsChanged {
            capslockOn = event.modifierFlags.contains(.capsLock)
            return false  // Don't consume — let system handle CapsLock normally
        }

        guard event.type == .keyDown else { return false }
        if event.modifierFlags.contains(.command) { return false }

        // CapsLock ON = direct input mode
        if capslockOn {
            if !fullText.isEmpty, let client = unwrap(wrap(sender)) as? IMKTextInput { commitAsIs(client: client) }
            return false
        }

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
            if !current.isEmpty {
                if phrases.count >= maxPhrases { phrases.removeFirst() }
                phrases.append(current); current = ""; updateMarked(client: client); return true
            }
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
        current += chars.lowercased()
        if current.count > maxCurrentLen { current = String(current.suffix(maxCurrentLen)) }
        updateMarked(client: client); return true
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
        } catch { NSLog("OneByte error: \(error)") }
        return fallback
    }
}
