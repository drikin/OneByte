import Cocoa
import InputMethodKit

@objc(OneByteApplication)
@main
final class OneByteApplication: NSApplication, NSApplicationDelegate {
    var server: IMKServer!
    var preferencesController: PreferencesController?
    var dictionaryController: DictionaryController?
    var statusItem: NSStatusItem!

    override init() {
        super.init()
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let connName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        server = IMKServer(name: connName, bundleIdentifier: Bundle.main.bundleIdentifier)
        preferencesController = PreferencesController()
        dictionaryController = DictionaryController()

        // NSStatusItem with popover menu (macOS 26 compatible — no IMK menu dependency)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "一"
            button.action = #selector(showStatusMenu(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        NSLog("OneByte: server initialized")
    }

    @objc func showStatusMenu(_ sender: Any?) {
        let menu = NSMenu(title: "OneByte")
        menu.addItem(NSMenuItem(title: "設定...", action: #selector(showPreferences(_:)), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "辞書管理...", action: #selector(showDictionary(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let direct = NSMenuItem(title: "直接入力モード", action: nil, keyEquivalent: "")
        direct.isEnabled = false
        menu.addItem(direct)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so it shows fresh each time
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }

    @objc func showPreferences(_ sender: Any?) {
        preferencesController?.showWindow(sender)
    }

    @objc func showDictionary(_ sender: Any?) {
        dictionaryController?.showWindow(sender)
    }
}
