import Cocoa
import SwiftUI

// MARK: - Window Controller
class DictionaryController: NSWindowController {
    convenience init() {
        let hosting = NSHostingView(rootView: DictionaryPanel())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "OneByte ユーザー辞書"
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

// MARK: - Dictionary Panel
struct DictionaryPanel: View {
    @State private var entries: [(key: String, value: String)] = []
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ユーザー辞書").font(.title2).bold()

            // Add form
            HStack {
                TextField("ローマ字", text: $newKey)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).frame(width: 140)
                Text("→")
                TextField("変換結果", text: $newValue)
                    .textFieldStyle(.roundedBorder).frame(width: 140)
                Button("追加") { addEntry() }
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }

            // List
            List {
                ForEach(entries.indices, id: \.self) { i in
                    let entry = entries[i]
                    HStack {
                        Text(entry.key).font(.system(.body, design: .monospaced)).frame(width: 140, alignment: .leading)
                        Text("→").foregroundColor(.secondary)
                        Text(entry.value)
                        Spacer()
                        Button("削除", role: .destructive) { deleteEntry(key: entry.key) }
                            .buttonStyle(.borderless).foregroundColor(.red)
                    }
                }
            }
            .listStyle(.plain)

            HStack {
                Text("\(entries.count) 件").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("JSONファイルを開く") { openFile() }
                    .buttonStyle(.bordered).controlSize(.small)
                if !statusMessage.isEmpty { Text(statusMessage).font(.caption).foregroundColor(.secondary) }
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .onAppear { reload() }
    }

    private func reload() {
        let dict = UserDictionary()
        entries = dict.allEntries
    }

    private func addEntry() {
        let k = newKey.trimmingCharacters(in: .whitespaces)
        let v = newValue.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty, !v.isEmpty else { return }
        var dict = UserDictionary()
        dict.set(key: k, value: v)
        newKey = ""; newValue = ""
        statusMessage = "追加しました"
        reload()
    }

    private func deleteEntry(key: String) {
        var dict = UserDictionary()
        dict.remove(key: key)
        statusMessage = "削除しました"
        reload()
    }

    private func openFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".onebyte/user_dict.json")
        NSWorkspace.shared.open(url)
    }
}
