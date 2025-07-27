import Cocoa
import WebKit

struct Options {
    var html: String = ""
    var url: URL? = nil
    var title: String = ""
    var width: CGFloat = 800
    var height: CGFloat = 600
    var env: [String: Any] = [:] // Default empty dictionary
    var staticDirectory: String? = nil
}

func readStdin() -> String {
    var input = ""
    while let line = readLine() {
        input += line + "\n"
    }
    return input
}

var currentVersion = "dev" // Default version, will be overridden by build system

func printUsage() {
    print("""
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
  --env <json_string>     Provide a JSON string to be injected as window.env in the web view.
  --env.<key> <value>     Provide individual key-value pairs to be injected as window.env. Values are parsed as JSON if possible, otherwise as strings.
  --version               Print the version of htmlpopup.
  --help                  Print this help message.
""")
}

func parseArguments() -> Options? {
    var options = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var envArgs: [String: Any] = [:]
    var i = 0

    // First pass: Check for --version or --help flag
    if args.contains("--version") {
        print("htmlpopup version: \(currentVersion)")
        return nil
    }
    if args.contains("--help") {
        printUsage()
        return nil
    }

    // Second pass: Parse all flags and the content argument
    while i < args.count {
        let arg = args[i]

        if arg.hasPrefix("--") {
            // It's a flag
            if arg.hasPrefix("--env.") {
                // Handle --env.KEY
                let key = String(arg.dropFirst(6))
                i += 1
                guard i < args.count else {
                    print("Missing value for \(arg)")
                    printUsage()
                    return nil
                }
                let valueString = args[i]

                if let data = valueString.data(using: .utf8),
                   let jsonValue = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) {
                    envArgs[key] = jsonValue
                } else {
                    envArgs[key] = valueString
                }
            } else {
                // Handle other flags like --title, --width, --height, --env
                i += 1
                guard i < args.count else {
                    print("Missing value for \(arg)")
                    printUsage()
                    return nil
                }
                let value = args[i]

                switch arg {
                case "--title":
                    options.title = value
                case "--width":
                    if let width = Double(value) {
                        options.width = CGFloat(width)
                    } else {
                        print("Invalid width value: \(value)")
                        printUsage()
                        return nil
                    }
                case "--height":
                    if let height = Double(value) {
                        options.height = CGFloat(height)
                    } else {
                        print("Invalid height value: \(value)")
                        printUsage()
                        return nil
                    }
                case "--env":
                    if let data = value.data(using: .utf8),
                       let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        options.env = jsonObject // This will be merged with envArgs later
                    } else {
                        print("Invalid JSON string for --env")
                        printUsage()
                        return nil
                    }
                default:
                    print("Unknown option: \(arg)")
                    printUsage()
                    return nil
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
                        print("The static directory does not contain an index.html file.")
                        return nil
                    }
                } else if FileManager.default.fileExists(atPath: contentArg) {
                    do {
                        options.html = try String(contentsOfFile: contentArg, encoding: .utf8)
                    } catch {
                        print("Error reading file: \(error)")
                        return nil
                    }
                } else if let url = URL(string: contentArg) {
                    options.url = url
                } else {
                    options.html = contentArg
                }
            } else {
                // Content argument already set, this is an unexpected argument
                print("Unexpected argument: \(arg)")
                printUsage()
                return nil
            }
        }
        i += 1
    }

    // Merge envArgs into options.env, prioritizing envArgs
    options.env = options.env.merging(envArgs) { (current, new) in new }

    // Ensure content argument was provided
    guard !(options.html.isEmpty && options.url == nil && options.staticDirectory == nil) else {
        print("Missing content argument")
        printUsage()
        return nil
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        // Create the menu bar
        let menuBar = NSMenu()
        NSApp.mainMenu = menuBar
        
        // File menu
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
        
        // View menu
        let viewMenuItem = NSMenuItem()
        menuBar.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        

        // Add Edit menu
        let editMenuItem = NSMenuItem()
        menuBar.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        
        guard let options = parseArguments() else {
            NSApplication.shared.terminate(nil)
            return
        }

        windowController = WindowController(
            width: options.width,
            height: options.height,
            title: options.title
        )

        // Crucial fix:  Create the WKWebView *before* the windowController
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
    
        webView = WKWebView(frame: windowController!.window!.contentView!.bounds, configuration: config)
        webView?.autoresizingMask = [.width, .height]
        webView?.navigationDelegate = self

        if #available(macOS 10.14, *) {
            webView?.setValue(false, forKey: "drawsBackground")
        }
        
        if let staticDir = options.staticDirectory {
            let dirURL = URL(fileURLWithPath: staticDir, isDirectory: true)
            let indexURL = dirURL.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: indexURL.path) {
                webView?.loadFileURL(indexURL, allowingReadAccessTo: dirURL)
            } else {
                print("The static directory does not contain an index.html file.")
                NSApplication.shared.terminate(nil)
                return
            }
        } else if let url = options.url {
            webView?.load(URLRequest(url: url))
        } else if !options.html.isEmpty {
            webView?.loadHTMLString(options.html, baseURL: nil)
        } else {
            print("No content to load.")
            return
        }

        // Add the WKWebView to the contentView
        windowController!.window!.contentView?.addSubview(webView!)

        windowController!.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController!.window!.makeKey()
        windowController!.window!.orderFront(nil)
    }

    func webView(_ webView: WKWebView, 
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        if let url = navigationAction.request.url {
            // Check if the URL scheme is different from http/https
            if let scheme = url.scheme?.lowercased(),
            scheme != "http" && scheme != "https" && scheme != "about" && scheme != "file" {
                
                // Handle external protocol
                if !NSWorkspace.shared.open(url) {
                    print("Failed to open URL: \(url)")
                }
                
                // Cancel the navigation in WebView
                decisionHandler(.cancel)
                return
            }
        }
        
        // Allow normal http/https navigation
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
                    print("Unknown action: \(messageBody["action"] ?? "")")
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()