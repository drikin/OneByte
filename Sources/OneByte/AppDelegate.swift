import Cocoa
import InputMethodKit

@objc(OneByteApplication)
@main
final class OneByteApplication: NSApplication, NSApplicationDelegate {
    var server: IMKServer!
    var preferencesController: PreferencesController?

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
        NSLog("OneByte: server initialized")
    }

    @objc func showPreferences(_ sender: Any?) {
        preferencesController?.showWindow(sender)
    }
}
