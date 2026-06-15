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
    // ── Buffer ──
    private var phrases: [String] = []
    private var current: String = ""
    private let maxPhrases = 20
    private let maxCurrentLen = 200
    private var converting = false
    private var conversionTask: Task<Void, Never>?
    private var directMode = false
    private var conversionSeq = 0

    // ── LLM config ──
    private let session: URLSession = { let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 3.0; c.timeoutIntervalForResource = 5.0; return URLSession(configuration: c) }()
    private var inferenceURL: URL {
        if let saved = UserDefaults.standard.string(forKey: "OneByteEndpoint"),
           let url = URL(string: saved) { return url }
        return URL(string: "http://100.78.215.127:8000/v1/chat/completions")!
    }
    private var apiKey: String { UserDefaults.standard.string(forKey: "OneByteAPIKey") ?? "" }
    private var modelName: String { UserDefaults.standard.string(forKey: "OneByteModel") ?? "spark-local" }

    // ── Conversion history ──
    private var conversionHistory: [String] = []
    private let maxHistory = 5

    private var fullText: String {
        if current.isEmpty { return phrases.joined(separator: " ") }
        return (phrases + [current]).joined(separator: " ")
    }

    // ── Menu ──
    override public func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "設定...", action: #selector(showPreferencesFromMenu), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "直接入力モード", action: #selector(toggleDirectModeFromMenu), keyEquivalent: "j"))
        return menu
    }
    @objc private func showPreferencesFromMenu() { (NSApp as? OneByteApplication)?.showPreferences(nil) }
    @objc private func toggleDirectModeFromMenu() {
        directMode.toggle()
        if let item = menu()?.item(at: 1) { item.state = directMode ? .on : .off }
    }

    // ── Lifecycle ──
    @objc(deactivateServer:)
    nonisolated override public func deactivateServer(_ sender: Any!) {
        conversionTask?.cancel(); conversionTask = nil
        phrases = []; current = ""; converting = false; conversionHistory = []
        super.deactivateServer(sender)
    }

    // ── handleEvent ──
    @objc(handleEvent:client:)
    nonisolated override public func handle(_ event: NSEvent?, client sender: Any?) -> Bool {
        guard let event = event, event.type == .keyDown else { return false }

        if event.modifierFlags.contains(.control) && event.keyCode == 0x26 {
            directMode.toggle()
            if directMode, let client = unwrap(wrap(sender)) as? IMKTextInput {
                if !fullText.isEmpty { commitAsIs(client: client) }
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            return true
        }
        if event.modifierFlags.contains(.command) { return false }
        if directMode { return false }

        guard let chars = event.characters else { return false }
        let isShift = event.modifierFlags.contains(.shift)

        if Thread.isMainThread {
            return handleOnMain(chars: chars, keyCode: event.keyCode, isShift: isShift, client: unwrap(wrap(sender)) as? IMKTextInput)
        }
        return DispatchQueue.main.sync {
            self.handleOnMain(chars: chars, keyCode: event.keyCode, isShift: isShift, client: unwrap(wrap(sender)) as? IMKTextInput)
        }
    }

    // ── Key handler ──
    private func handleOnMain(chars: String, keyCode: UInt16, isShift: Bool, client: IMKTextInput?) -> Bool {
        guard let client = client else { return false }

        if keyCode == 0x33 {
            if !current.isEmpty { current.removeLast(); updateMarked(client: client); return true }
            else if !phrases.isEmpty { current = phrases.removeLast(); updateMarked(client: client); return true }
            return false
        }
        if keyCode == 0x35 { phrases = []; current = ""; client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); return true }
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
        let accepted = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ,.!?\"'-:;@#$%^&*()_+=[]{}|\\/~`<>　１２３４５６７８９０ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ”！＃＄％＆＇（）＊＋，−．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～")
        guard chars.rangeOfCharacter(from: accepted.inverted) == nil else {
            if !fullText.isEmpty { doConvert(client: client, mode: .toJapanese) }
            return false
        }
        current += chars
        if current.count > maxCurrentLen { current = String(current.suffix(maxCurrentLen)) }
        updateMarked(client: client); return true
    }

    private func updateMarked(client: IMKTextInput) {
        let text = fullText
        client.setMarkedText(NSAttributedString(string: text), selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private enum ConvertMode { case toJapanese, toEnglish }

    @objc(inputText:client:)
    nonisolated override public func inputText(_ string: String!, client sender: Any!) -> Bool { return false }

    // ── Conversion (race-condition-safe) ──
    private func doConvert(client: IMKTextInput, mode: ConvertMode) {
        if converting { return }
        let text = fullText
        let context = conversionHistory.suffix(3).joined(separator: "\n")
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        phrases = []; current = ""; converting = true
        conversionSeq += 1
        let mySeq = conversionSeq
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

        conversionTask?.cancel()
        conversionTask = Task { [weak self] in
            guard let self = self else { return }
            let isProperNoun = text.unicodeScalars.first.map { CharacterSet.uppercaseLetters.contains($0) } ?? false
            let result: String
            switch mode {
            case .toJapanese: result = await self.convertRomaji(text, context: context, appName: appName, isProperNoun: isProperNoun)
            case .toEnglish: let jp = await self.convertRomaji(text, context: context, appName: appName, isProperNoun: isProperNoun); guard !Task.isCancelled else { return }; result = await self.translateToEnglish(jp)
            }
            guard !Task.isCancelled, mySeq == self.conversionSeq else { return }
            await MainActor.run {
                self.converting = false
                if result == text {
                    self.conversionFailed(client: client, original: text, failedSeq: mySeq)
                } else {
                    self.conversionHistory.append(result)
                    if self.conversionHistory.count > self.maxHistory { self.conversionHistory.removeFirst() }
                    client.insertText(result, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                }
            }
        }
    }

    // ── Error visualization with seq guard ──
    private func conversionFailed(client: IMKTextInput, original: String, failedSeq: Int) {
        let warning = NSAttributedString(string: "⚠️ \(original)", attributes: [
            .foregroundColor: NSColor.red,
            .backgroundColor: NSColor.yellow.withAlphaComponent(0.3)
        ])
        client.setMarkedText(warning, selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self = self, failedSeq == self.conversionSeq, !self.converting else { return }
            await MainActor.run { client.insertText(original, replacementRange: NSRange(location: NSNotFound, length: NSNotFound)) }
        }
    }

    // ── LLM calls ──
    private func convertRomaji(_ romaji: String, context: String, appName: String, isProperNoun: Bool) async -> String {
        var systemPrompt: String
        if isProperNoun {
            systemPrompt = "This text appears to be a proper noun (name, brand, etc.) written in romaji. " +
                "If it's a known Japanese name/brand, convert it to the correct Japanese form. " +
                "If it's a foreign name, keep it as-is or convert to katakana reading if appropriate. " +
                "Output ONLY the converted text. No explanation."
        } else if romaji.utf16.count < 5 {
            systemPrompt = "Convert this short romaji word to natural Japanese. " +
                "Choose the most common/standard Japanese form. Output ONLY the Japanese word."
        } else {
            systemPrompt = "Convert the following romaji text to natural Japanese. " +
                "Fix any typos, missing letters, repeated words, and make it natural. " +
                "Output ONLY the converted Japanese text. No explanation. No quotes."
        }
        if !appName.isEmpty { systemPrompt += "\n\nActive application: \(appName). Adapt vocabulary accordingly." }
        if !context.isEmpty { systemPrompt += "\n\nRecent conversions for style reference:\n\(context)" }
        let body: [String: Any] = ["model": modelName, "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": romaji]], "max_tokens": 60, "temperature": 0.1]
        return await callLLM(body: body, fallback: romaji)
    }

    private func translateToEnglish(_ japanese: String) async -> String {
        let prompt = "Translate the following Japanese text to natural English. Output ONLY the English translation. No explanation. No quotes."
        let body: [String: Any] = ["model": modelName, "messages": [["role": "system", "content": prompt], ["role": "user", "content": japanese]], "max_tokens": 60, "temperature": 0.1]
        return await callLLM(body: body, fallback: japanese)
    }

    private func commitAsIs(client: IMKTextInput) {
        conversionTask?.cancel(); conversionTask = nil
        let text = fullText; phrases = []; current = ""; converting = false
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func callLLM(body: [String: Any], fallback: String) async -> String {
        var req = URLRequest(url: inferenceURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
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
