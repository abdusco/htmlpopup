import Cocoa
import WebKit

func logError(_ message: String) {
    fputs("ERROR: \(message)\n", stderr)
}

func logFatalError(_ message: String) -> Never {
    NSApplication.shared.terminate(nil)
    fatalError("FATAL: \(message)")
}

func readStdin() -> String {
    var input = ""
    while let line = readLine() {
        input += line + "\n"
    }
    return input
}

struct Options {
    var html: String = ""
    var url: URL? = nil
    var title: String = ""
    var width: CGFloat = 800
    var height: CGFloat = 600
    var env: [String: Any] = [:] // Default empty dictionary
    var staticDirectory: String? = nil
}

var currentVersion = "dev" // Default version, will be overridden by build system

func printUsage() {
    fputs("""
Usage: htmlpopup [OPTIONS] content

Arguments:
  content
    HTML content string, path to an HTML file, a URL, or a directory.
    Use '-' to read HTML from stdin.
    If a directory is provided, it will serve 'index.html' from that directory
    or generate a directory listing if 'index.html' is not found.

Options:
  --title <title>         Set the window title (default: <empty>).
  --width <width>         Set the window width (default: 800)
  --height <height>       Set the window height (default: 600)
  --env <json_object>     Provide a JSON object to be injected as window.env in the web view.
  --env.<key> <value>     Provide individual key-value pairs to be injected as window.env. Values are parsed as JSON if possible, otherwise as strings.
  --version               Print the version of htmlpopup.
  --help                  Print this help message.
""", stderr)
}


struct ArgumentError: Error {
    let message: String
}

func parseArguments() throws -> Options {
    var options = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var envArgs: [String: Any] = [:]

    // First pass: Check for --version or --help flag
    if args.contains("--version") {
        print("htmlpopup version: \(currentVersion)")
        exit(0)
    }
    if args.contains("--help") {
        printUsage()
        exit(0)
    }

    var argIterator = args.makeIterator()
    while let arg = argIterator.next() {
        if arg.hasPrefix("--") {
            if arg.hasPrefix("--env.") {
                // Handle --env.KEY
                let key = String(arg.dropFirst(6))
                guard let valueString = argIterator.next() else {
                    throw ArgumentError(message: "Missing value for \(arg)")
                }
                if let data = valueString.data(using: .utf8),
                   let jsonValue = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) {
                    envArgs[key] = jsonValue
                } else {
                    envArgs[key] = valueString
                }
            } else {
                guard let value = argIterator.next() else {
                    throw ArgumentError(message: "Missing value for \(arg)")
                }
                switch arg {
                case "--title":
                    options.title = value
                case "--width":
                    if let width = Double(value) {
                        options.width = CGFloat(width)
                    } else {
                        throw ArgumentError(message: "Invalid width value: \(value)")
                    }
                case "--height":
                    if let height = Double(value) {
                        options.height = CGFloat(height)
                    } else {
                        throw ArgumentError(message: "Invalid height value: \(value)")
                    }
                case "--env":
                    if let data = value.data(using: .utf8) {
                        let json = try? JSONSerialization.jsonObject(with: data)
                        if let dict = json as? [String: Any] {
                            options.env = dict // This will be merged with envArgs later
                        } else {
                            throw ArgumentError(message: "The JSON string for --env must be an object/dictionary: \(value)")
                        }
                    } else {
                        throw ArgumentError(message: "Invalid JSON string for --env: \(value)")
                    }
                default:
                    throw ArgumentError(message: "Unknown option: \(arg)")
                }
            }
        } else {
            // It's not a flag, so it must be the content argument
            if options.html.isEmpty && options.url == nil && options.staticDirectory == nil {
                let contentArg = arg
                if contentArg == "-" {
                    options.html = readStdin()
                } else if (try? FileManager.default.attributesOfItem(atPath: contentArg)[.type] as? FileAttributeType) == .typeDirectory {
                    let indexPath = (contentArg as NSString).appendingPathComponent("index.html")
                    if FileManager.default.fileExists(atPath: indexPath) {
                        options.staticDirectory = contentArg
                    } else {
                        throw ArgumentError(message: "The static directory does not contain an index.html file: \(contentArg)")
                    }
                } else if FileManager.default.fileExists(atPath: contentArg) {
                    do {
                        options.html = try String(contentsOfFile: contentArg, encoding: .utf8)
                    } catch {
                        throw ArgumentError(message: "Error reading file: \(error)")
                    }
                } else if let url = URL(string: contentArg), let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                    options.url = url
                } else {
                    options.html = contentArg
                }
            } else {
                throw ArgumentError(message: "Unexpected argument: \(arg)")
            }
        }
    }

    // Merge envArgs into env, prioritizing envArgs
    options.env = options.env.merging(envArgs) { (_, new) in new }

    // Ensure content argument was provided
    guard !(options.html.isEmpty && options.url == nil && options.staticDirectory == nil) else {
        throw ArgumentError(message: "Missing content argument")
    }
    
    return options
}


class WindowController: NSWindowController, NSWindowDelegate {
    private var pinButton: NSButton!
    public var isPinned: Bool {
        get {
            return window?.level == .floating
        }
        set {
            window?.level = newValue ? .floating : .normal
            updatePinButtonImage()
        }
    }
    
    init(width: CGFloat, height: CGFloat, title: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = title
        window.level = .floating  // Window starts as floating
        window.center()
        
        window.appearance = NSAppearance(named: .aqua)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        window.delegate = self
        
        setupPinButton()
        setupKeyEventMonitor()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var keyEventMonitor: Any?
    
    private func setupPinButton() {
        guard let window = self.window else { return }
        
        pinButton = NSButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        pinButton.bezelStyle = .texturedRounded
        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.state = isPinned ? .on : .off  // Set initial state based on window level
        updatePinButtonImage()  // Set initial image
        pinButton.toolTip = "Keep window floating on top"
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        
        // Position the button in the titlebar
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.addSubview(pinButton)
            
            if let closeButton = window.standardWindowButton(.closeButton) {
                let margin: CGFloat = 6
                let pinButtonX = titlebarView.frame.width - pinButton.frame.width - margin
                let pinButtonY = closeButton.frame.minY
                
                pinButton.frame.origin = CGPoint(x: pinButtonX, y: pinButtonY)
                pinButton.autoresizingMask = [.minXMargin]
            }
        }
    }
    
    private func updatePinButtonImage() {
        let imageName = isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: isPinned ? "Unpin Window" : "Pin Window")
    }
    
    @objc private func togglePin() {
        isPinned.toggle()
    }
    
    // Set up a local key event monitor that will detect ESC key presses
    private func setupKeyEventMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                // Unfloat the window and move it to background
                self?.isPinned = false
                self?.window?.orderBack(nil)
                return nil // Consume the event
            }
            return event // Pass other events through
        }
    }
    
    deinit {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var windowController: WindowController?
    var webView: WKWebView?
    var closeString: String?
    let options: Options

    init(options: Options) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        setupMenuBar()
        setupWindowAndWebView()
    }

    private func setupMenuBar() {
        let menuBar = NSMenu()
        NSApplication.shared.mainMenu = menuBar

        let fileMenuItem = NSMenuItem()
        menuBar.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(NSMenuItem(title: "Close Window", 
                                    action: #selector(NSWindow.performClose(_:)), 
                                    keyEquivalent: "w"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Quit", 
                                    action: #selector(NSApplication.terminate(_:)), 
                                    keyEquivalent: "q"))

        let editMenuItem = NSMenuItem()
        menuBar.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(NSMenuItem(title: "Undo", 
                                    action: Selector(("undo:")), 
                                    keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", 
                                    action: Selector(("redo:")), 
                                    keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", 
                                    action: #selector(NSText.cut(_:)), 
                                    keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", 
                                    action: #selector(NSText.copy(_:)), 
                                    keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", 
                                    action: #selector(NSText.paste(_:)), 
                                    keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", 
                                    action: #selector(NSText.selectAll(_:)), 
                                    keyEquivalent: "a"))
    }

    private func setupWindowAndWebView() {
        windowController = WindowController(
            width: options.width,
            height: options.height,
            title: options.title
        )

        let userContentController = WKUserContentController()
        userContentController.add(self, name: "app")
        setupUserScripts(userContentController: userContentController, env: options.env)
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        if #available(macOS 11.0, *) {
            config.limitsNavigationsToAppBoundDomains = false
        }

        guard let contentView = windowController?.window?.contentView else {
            logFatalError("Window contentView is nil.")
        }

        webView = WKWebView(frame: contentView.bounds, configuration: config)
        guard let webView = webView else {
            logFatalError("Failed to create WKWebView.")
        }
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self

        if #available(macOS 10.14, *) {
            webView.setValue(false, forKey: "drawsBackground")
        }

        if let staticDir = options.staticDirectory {
            let dirURL = URL(fileURLWithPath: staticDir, isDirectory: true)
            let indexURL = dirURL.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: indexURL.path) {
                webView.loadFileURL(indexURL, allowingReadAccessTo: dirURL)
            } else {
                logFatalError("The static directory does not contain an index.html file.")
            }
        } else if let url = options.url {
            webView.load(URLRequest(url: url))
        } else if !options.html.isEmpty {
            webView.loadHTMLString(options.html, baseURL: nil)
        } else {
            logFatalError("No content to load.")
        }

        contentView.addSubview(webView)

        windowController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, 
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            // Allow only http, https, about, and file schemes in the webview
            if let scheme = url.scheme?.lowercased(),
                scheme != "http" && scheme != "https" && scheme != "about" && scheme != "file" {
                // Handle external protocol
                if !NSWorkspace.shared.open(url) {
                    logError("Failed to open URL: \(url)")
                }
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func setupUserScripts(userContentController: WKUserContentController, env: [String: Any] = [:]) {
        // Convert the dictionary to a JSON string
        var envJsonString = "{}"
        if let jsonData = try? JSONSerialization.data(withJSONObject: env, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            envJsonString = jsonString
        }

        // First inject ENV
        let envScript = WKUserScript(
            source: "window.env = \(envJsonString);",
            injectionTime: .atDocumentStart,
    forMainFrameOnly: true
)
        
        // Then inject app API
        let appScript = WKUserScript(
            source: """
            window.app = {
                finish: function(message) {
                    window.webkit.messageHandlers.app.postMessage({ action: "finish", message: message }); 
                },
                setSize: function(width, height) {
                    window.webkit.messageHandlers.app.postMessage({ action: "setSize", width: width, height: height }); 
                },
                setFullscreen: function(enabled) {
                    window.webkit.messageHandlers.app.postMessage({ action: "setFullscreen", enabled: enabled }); 
                },
                setFloating: function(enabled) {
                    window.webkit.messageHandlers.app.postMessage({ action: "setFloating", enabled: enabled }); 
                },
                selectFolder: function() {
                    return new Promise((resolve, reject) => {
                        const callbackId = 'callback_' + Math.random().toString(36).substr(2, 9);
                        window[callbackId] = {
                            resolve: resolve,
                            reject: reject
                        };
                        window.webkit.messageHandlers.app.postMessage({ 
                            action: "selectFolder",
                            callbackId: callbackId
                        });
                    });
                }
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        
        userContentController.addUserScript(envScript)
        userContentController.addUserScript(appScript)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "app" {
            if let messageBody = message.body as? [String: Any] {
                switch messageBody["action"] as? String {
                case "finish":
                    appFinish(messageBody["message"] as? String ?? "")
                case "setSize":
                    if let width = messageBody["width"] as? CGFloat, let height = messageBody["height"] as? CGFloat {
                        appSetSize(width, height)
                    }
                case "setFullscreen":
                    appSetFullscreen(messageBody["enabled"] as? Bool ?? false)
                case "setFloating":
                    appSetFloating(messageBody["enabled"] as? Bool ?? false)
                case "selectFolder":
                    if let callbackId = messageBody["callbackId"] as? String {
                        appSelectFolder(callbackId: callbackId)
                    }
                default:
                    logError("Unknown action: \(messageBody["action"] ?? "")")
                }
            }
        }
    }

    func appSelectFolder(callbackId: String) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.level = .floating + 1
        
        openPanel.begin { [weak self] response in
            guard let webView = self?.webView else { return }
            
            if response == .OK {
                if let url = openPanel.url {
                    let path = url.path
                    let jsCallback = """
                        {
                            const callback = window['\(callbackId)'];
                            callback.resolve('\(path)');
                            delete window['\(callbackId)'];
                        }
                    """
                    webView.evaluateJavaScript(jsCallback)
                }
            } else {
                let jsCallback = """
                    {
                        const callback = window['\(callbackId)'];
                        callback.reject('Folder selection cancelled');
                        delete window['\(callbackId)'];
                    }
                """
                webView.evaluateJavaScript(jsCallback)
            }
        }
    }


    func applicationWillTerminate(_ aNotification: Notification) {
        if let closeMessage = closeString {
            print(closeMessage)
        }
    }

    // JavaScript binding function
    func appFinish(_ message: String) {
        closeString = message
        NSApplication.shared.terminate(nil)
    }

    func appSetSize(_ width: CGFloat, _ height: CGFloat) {
        guard let window = windowController?.window else { return }
        window.setContentSize(NSSize(width: width, height: height))
    }

    func appSetFullscreen(_ enabled: Bool) {
        guard let window = windowController?.window else { return }
        window.toggleFullScreen(nil)
    }

    func appSetFloating(_ enabled: Bool) {
        windowController?.isPinned.toggle()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    private func generateDirectoryListing(for directory: URL) -> String {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            var html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Directory Listing</title>
                <style>
                    body { font-family: -apple-system, sans-serif; padding: 20px; }
                    h1 { color: #333; }
                    ul { list-style: none; padding: 0; }
                    li { padding: 5px 0; }
                    a { color: #0066cc; text-decoration: none; }
                    a:hover { text-decoration: underline; }
                </style>
            </head>
            <body>
                <h1>Directory Listing</h1>
                <ul>
            """
            
            for item in contents {
                let name = item.lastPathComponent
                html += "<li><a href=\"\(name)\">\(name)</a></li>\n"
            }
            
            html += """
                </ul>
            </body>
            </html>
            """
            return html
        } catch {
            return "<html><body><h1>Error reading directory</h1></body></html>"
        }
    }
}

extension WKWebView {
    func toggleInspector(_ sender: Any?) {
        guard responds(to: Selector(("_inspector"))) else { return }
        
        let inspector = value(forKey: "_inspector") as AnyObject
        let selector = Selector(("show:"))
        if inspector.responds(to: selector) {
            _ = inspector.perform(selector, with: nil as Any?)
        }
    }
}

// Parse and validate arguments before launching the app
do {
    let options = try parseArguments()
    let app = NSApplication.shared
    let delegate = AppDelegate(options: options)
    app.delegate = delegate
    app.run()
} catch let error as ArgumentError {
    logError(error.message)
    printUsage()
    exit(1)
}