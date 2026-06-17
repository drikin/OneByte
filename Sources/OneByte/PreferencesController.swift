import Cocoa
import SwiftUI

// MARK: - Window Controller
class PreferencesController: NSWindowController {
    convenience init() {
        let hosting = NSHostingView(rootView: PreferencesPanel())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "OneByte 設定"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI Preferences Panel
struct PreferencesPanel: View {
    @AppStorage("OneByteEndpoint") var endpoint = "http://100.78.215.127:8000/v1/chat/completions"
    @AppStorage("OneByteAPIKey") var apiKey = ""
    @AppStorage("OneByteModel") var model = "spark-local"

    @State private var statusText = ""
    @State private var statusColor: Color = .gray
    @State private var testing = false

    private let presets: [(String, String, String, String)] = [
        ("Spark2 vLLM", "http://100.78.215.127:8000/v1/chat/completions", "", "spark-local"),
        ("DriMac Gemma4", "http://100.100.36.4:8081/v1/chat/completions", "", "gemma4"),
        ("OpenAI GPT-4o-mini", "https://api.openai.com/v1/chat/completions", "", "gpt-4o-mini"),
        ("Ollama ローカル", "http://localhost:11434/v1/chat/completions", "", "gemma3"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OneByte 設定").font(.title2).bold()

            Group {
                Text("API Endpoint").font(.caption).foregroundColor(.secondary)
                TextField("https://api.openai.com/v1/chat/completions", text: $endpoint)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                Text("API Key").font(.caption).foregroundColor(.secondary)
                SecureField("sk-...（空欄の場合は認証なしで送信）", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Model").font(.caption).foregroundColor(.secondary)
                TextField("gpt-4o-mini", text: $model)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("プリセット:").font(.caption).foregroundColor(.secondary)
                ForEach(presets, id: \.0) { preset in
                    Button(preset.0) { endpoint = preset.1; apiKey = preset.2; model = preset.3 }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }

            Divider()
            HStack {
                Button("接続テスト") { testConnection() }.disabled(testing)
                if testing { ProgressView().scaleEffect(0.7) }
                Spacer()
                Button("閉じる") {
                    UserDefaults.standard.synchronize()
                    window?.close()
                }
                .keyboardShortcut(.cancelAction)
            }

            if !statusText.isEmpty {
                Text(statusText).foregroundColor(statusColor).font(.caption)
            }

            Text("変更後はOneByteを再起動するか、ログアウト/ログインしてください。")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 500, height: 400)
    }

    private var window: NSWindow? { NSApp.keyWindow }

    private func testConnection() {
        testing = true; statusText = "テスト中..."; statusColor = .gray
        Task {
            let url = URL(string: endpoint)!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": "Say 'OK'"]], "max_tokens": 5, "temperature": 0.1]
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let config = URLSessionConfiguration.default; config.timeoutIntervalForRequest = 5.0
                let (data, resp) = try await URLSession(configuration: config).data(for: req)
                guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    await MainActor.run { statusText = "エラー: HTTP \(code)"; statusColor = .red; testing = false }; return
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]], let first = choices.first,
                   let msg = first["message"] as? [String: Any], let content = msg["content"] as? String {
                    await MainActor.run { statusText = "✅ 接続OK: \(content.trimmingCharacters(in: .whitespacesAndNewlines))"; statusColor = .green; testing = false }
                }
            } catch {
                await MainActor.run { statusText = "❌ エラー: \(error.localizedDescription)"; statusColor = .red; testing = false }
            }
        }
    }
}
