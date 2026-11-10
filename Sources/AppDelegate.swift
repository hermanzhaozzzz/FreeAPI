import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "local.freeapi").count > 1 {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePopover()

        model.onOpenWindow = { [weak self] id in
            self?.showMainWindow(select: id)
        }
        model.start()
        observeModel()
        installSignalHandler()

        if model.backends.isEmpty || model.didMigrate
            || ProcessInfo.processInfo.environment["FREEAPI_SHOW_WINDOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showMainWindow()
            }
        }

        if ProcessInfo.processInfo.environment["FREEAPI_SHOW_POPOVER"] == "1",
           let button = statusItem?.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, let popover = self.popover else { return }
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }

        if let error = model.startupError {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let alert = NSAlert()
                alert.messageText = "FreeAPI 配置无法读取"
                alert.informativeText = "\(error)\n\n\(ConfigurationStore.fileURL.path)"
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.shutdown()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "link", accessibilityDescription: "FreeAPI")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        updateStatusItem()
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let color: NSColor
        switch model.overallState {
        case .connected: color = .systemGreen
        case .connecting, .degraded: color = .systemOrange
        case .error: color = .systemRed
        case .off: color = .tertiaryLabelColor
        }
        button.attributedTitle = NSAttributedString(
            string: " ●",
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                .baselineOffset: 1
            ]
        )
        button.toolTip = "FreeAPI · \(model.overallState.label)"
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开主窗口", action: #selector(openMainFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 FreeAPI", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openMainFromMenu() {
        showMainWindow(select: model.selectedID)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    // MARK: - Popover

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: MenuBarView.width,
            height: MenuBarView.preferredHeight(rowCount: model.backends.count)
        )
        popover.contentViewController = NSHostingController(rootView: MenuBarView(
            model: model,
            close: { [weak popover] in popover?.performClose(nil) },
            quit: { NSApp.terminate(nil) }
        ))
        self.popover = popover
    }

    private func observeModel() {
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshChrome()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshChrome() {
        updateStatusItem()
        guard let popover else { return }
        let height = MenuBarView.preferredHeight(rowCount: model.backends.count)
        if abs(popover.contentSize.height - height) > 0.5 {
            popover.contentSize = NSSize(width: MenuBarView.width, height: height)
        }
    }

    // MARK: - Main window

    private func showMainWindow(select id: UUID? = nil) {
        if let id { model.selectedID = id }

        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "FreeAPI"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.minSize = NSSize(width: 920, height: 640)
            window.isReleasedWhenClosed = false

            let hosting = NSHostingView(rootView: MainWindowView(model: model))
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting

            if !window.setFrameUsingName("FreeAPIMainWindow") {
                window.center()
            }
            _ = window.setFrameAutosaveName("FreeAPIMainWindow")
            mainWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        appItem.title = "FreeAPI"
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let about = NSMenuItem(
            title: "关于 FreeAPI",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 FreeAPI", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        editItem.title = "编辑"
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        windowItem.title = "窗口"
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "关闭",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Signals

    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSignal = source
    }
}
