import Cocoa
import InputMethodKit

@objc(OneByteApplication)
@main
final class OneByteApplication: NSApplication, NSApplicationDelegate {
    var server: IMKServer!
    var candidatesWindow: IMKCandidates!
    var preferencesController: PreferencesController?
    var dictionaryController: DictionaryController?

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
        // Process-global candidate window (one per process, not per controller)
        candidatesWindow = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
        // Route all key events to controller first, then let window handle remainder
        candidatesWindow.setAttributes([IMKCandidatesSendServerKeyEventFirst: true])
        preferencesController = PreferencesController()
        dictionaryController = DictionaryController()
        NSLog("OneByte: server initialized")
    }

    @objc func showPreferences(_ sender: Any?) {
        preferencesController?.showWindow(sender)
    }

    @objc func showDictionary(_ sender: Any?) {
        dictionaryController?.showWindow(sender)
    }
}
