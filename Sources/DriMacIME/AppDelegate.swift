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
