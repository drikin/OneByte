import Cocoa
import SwiftUI

// MARK: - Window Controller
class PreferencesController: NSWindowController {
    convenience init() {
        let hosting = NSHostingView(rootView: PreferencesPanel())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
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
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            LLMSettingsView().tabItem { Label("LLM設定", systemImage: "network") }.tag(0)
            DictionaryView().tabItem { Label("ユーザー辞書", systemImage: "book") }.tag(1)
        }
        .padding(20)
        .frame(width: 520, height: 460)
    }
}

// MARK: - LLM Settings Tab
struct LLMSettingsView: View {
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
            }

            if !statusText.isEmpty {
                Text(statusText).foregroundColor(statusColor).font(.caption)
            }
        }
    }

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

// MARK: - User Dictionary Tab
struct DictionaryView: View {
    @State private var entries: [(key: String, value: String)] = []
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var searchText = ""
    @State private var statusMessage = ""

    private var filteredEntries: [(key: String, value: String)] {
        if searchText.isEmpty { return entries }
        return entries.filter { $0.key.localizedCaseInsensitiveContains(searchText) || $0.value.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Add form
            HStack {
                TextField("ローマ字（キー）", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 160)
                Text("→")
                TextField("変換結果", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("追加") { addEntry() }
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("検索...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            // Entry list
            List {
                ForEach(filteredEntries.indices, id: \.self) { i in
                    let entry = filteredEntries[i]
                    HStack {
                        Text(entry.key).font(.system(.body, design: .monospaced)).frame(width: 150, alignment: .leading)
                        Text("→").foregroundColor(.secondary)
                        Text(entry.value).frame(alignment: .leading)
                        Spacer()
                        Button("削除", role: .destructive) {
                            deleteEntry(key: entry.key)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
            }
            .listStyle(.plain)

            // Status & count
            HStack {
                Text("\(entries.count) 件登録").font(.caption).foregroundColor(.secondary)
                Spacer()
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        let dict = UserDictionary()
        entries = dict.allEntries
    }

    private func addEntry() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        let value = newValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else { return }

        var dict = UserDictionary()
        dict.set(key: key, value: value)
        newKey = ""; newValue = ""
        statusMessage = "「\(key)」→「\(value)」を追加しました"
        reload()
    }

    private func deleteEntry(key: String) {
        var dict = UserDictionary()
        dict.remove(key: key)
        statusMessage = "「\(key)」を削除しました"
        reload()
    }
}
