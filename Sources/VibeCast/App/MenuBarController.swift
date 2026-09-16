import AppKit
import Combine
import SwiftUI

// AppKit owns presentation lifetime; SwiftUI still owns all content and app state.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let store: VibeCastStore
    let statusItem: NSStatusItem
    let popover = NSPopover()
    let playerPresentation = PlayerPresentation()
    private(set) var playerWindow: NSWindow?
    private(set) var anchorWindow: NSPanel?
    private var hosting: NSHostingController<MenuBarRootView>!
    private var playerHeight: CGFloat = 462
    private var lastPlayerFrame: NSRect?
    private(set) var settingsWindow: NSWindow?
    private var pendingPopoverHeight: CGFloat?
    private var resizeScheduled = false
    private var interactionMonitor: Any?
    private var presentationObserver: AnyCancellable?
    private var adjustingWindow = false
    private var lastPopoverAnchor: NSRect?
    private var outsideClickMonitor: Any?
    private var popoverEventMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?

    var isMonitoringPopoverDismissal: Bool { popoverEventMonitor != nil && outsideClickMonitor != nil }

    init(store: VibeCastStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = ResourceImage.menuBarSymbol
            button.imagePosition = .imageOnly
            button.toolTip = "VibeCast"
            button.setAccessibilityLabel("VibeCast")
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: .leftMouseDown)
        }
        // The stable fullscreen anchor is not the status button. Own dismissal
        // so AppKit cannot close on mouse-down and reopen on the button action.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        hosting = NSHostingController(rootView:
            MenuBarRootView(store: store,
                            resize: { [weak self] height in self?.resizePopover(height) },
                            openSettings: { [weak self] in self?.showSettings() },
                            presentation: playerPresentation,
                            toggleWindow: { [weak self] in self?.togglePlayerWindow() }))
        // The measured SwiftUI height drives NSPopover; automatic hosting constraints
        // must not independently resize its window during the same layout pass.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 400, height: 462)
        playerPresentation.windowHeight = popover.contentSize.height
        presentationObserver = playerPresentation.$panel
            .combineLatest(playerPresentation.$lyricsFocused, playerPresentation.$advanced)
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.resizePopover(self.playerHeight)
            }
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            if let self, let window = self.hosting.view.window,
               (self.popover.isShown || self.playerPresentation.isDetached), event.window === window {
                self.store.noteInteraction()
            }
            return event
        }
        installMenus()
    }

    private func resizePopover(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        pendingPopoverHeight = ceil(height)
        guard !resizeScheduled else { return }
        resizeScheduled = true
        // Leave SwiftUI's layout transaction before resizing the native popover.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            guard let height = self.pendingPopoverHeight else { return }
            self.pendingPopoverHeight = nil
            self.playerHeight = height
            if self.playerPresentation.isDetached, let window = self.playerWindow {
                self.resizePlayerWindow(window, naturalHeight: height)
                return
            }
            guard abs(self.popover.contentSize.height - height) > 1 else {
                self.playerPresentation.windowHeight = self.popover.contentSize.height
                return
            }
            let window = self.popover.isShown ? self.popover.contentViewController?.view.window : nil
            let previousFrame = window?.frame
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self.popover.contentSize = NSSize(width: 400, height: height)
                // Preserve the position chosen when shown. Resetting positioningRect
                // during a height change makes AppKit choose a new horizontal origin.
                if let window, let previousFrame {
                    window.setFrameOrigin(NSPoint(x: previousFrame.minX, y: previousFrame.maxY - window.frame.height))
                }
                // Like the detached player, publish the allocated height only
                // after AppKit has resized and positioned the native surface.
                self.playerPresentation.windowHeight = height
                self.popover.contentViewController?.view.layoutSubtreeIfNeeded()
            }
        }
    }

    // A revealed fullscreen menu bar can move its status-item windows offscreen.
    // Anchor to a snapshot of the click position, not that moving system window.
    func showPopover(anchoredAt rect: NSRect) {
        guard !playerPresentation.isDetached else { return }
        lastPopoverAnchor = rect
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        updateMaximumHeight(on: screen)
        if anchorWindow == nil {
            let anchor = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            anchor.backgroundColor = .clear
            anchor.isOpaque = false
            anchor.hasShadow = false
            anchor.ignoresMouseEvents = true
            anchor.hidesOnDeactivate = false
            anchor.level = .statusBar
            anchor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            anchor.contentView = NSView(frame: NSRect(origin: .zero, size: rect.size))
            anchorWindow = anchor
        }
        guard let anchor = anchorWindow, let view = anchor.contentView else { return }
        anchor.setFrame(rect, display: false)
        anchor.orderFrontRegardless()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        if popover.isShown { startPopoverDismissalMonitoring() }
    }

    func popoverDidClose(_ notification: Notification) {
        stopPopoverDismissalMonitoring()
        anchorWindow?.orderOut(nil)
    }

    private func startPopoverDismissalMonitoring() {
        stopPopoverDismissalMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        popoverEventMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            guard let self else { return event }
            return self.handlePopoverEvent(event)
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.dismissPopoverForExternalInteraction()
        }
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPopoverForExternalInteraction() }
        }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPopoverForExternalInteraction() }
        }
    }

    func handlePopoverEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown, !playerPresentation.isDetached else { return event }
        if event.type == .keyDown {
            if event.keyCode == 53 {
                popover.performClose(nil)
                return nil
            }
            return event
        }
        // The status button owns its toggle. Never close here and then deliver
        // the same click to a button that would reopen the popover.
        if event.type == .leftMouseDown, let buttonWindow = statusItem.button?.window,
           event.window === buttonWindow { return event }
        let contentWindow = popover.contentViewController?.view.window
        var target = event.window
        while let window = target {
            if window === contentWindow { return event }
            target = window.parent
        }
        dismissPopoverForExternalInteraction()
        return event
    }

    func dismissPopoverForExternalInteraction() {
        guard popover.isShown, !playerPresentation.isDetached else { return }
        popover.performClose(nil)
    }

    private func stopPopoverDismissalMonitoring() {
        if let popoverEventMonitor { NSEvent.removeMonitor(popoverEventMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        if let spaceChangeObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver) }
        popoverEventMonitor = nil
        outsideClickMonitor = nil
        deactivateObserver = nil
        spaceChangeObserver = nil
    }

    @objc func togglePopover() {
        if playerPresentation.isDetached { bringPlayerForward(); return }
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard NSScreen.screens.contains(where: { $0.frame.intersects(anchor) }) else { return }
        store.returnToSuggestionsIfIdle()
        store.noteInteraction()
        NSApp.activate(ignoringOtherApps: true)
        showPopover(anchoredAt: anchor)
        popover.contentViewController?.view.window?.makeKey()
    }

    func togglePlayerWindow() {
        if playerPresentation.isDetached { returnToMenuBar() } else { detachPlayer() }
    }

    private func detachPlayer() {
        let source = hosting.view.window
        let screen = source?.screen ?? NSScreen.main
        let sourceFrame = source?.frame
        popover.performClose(nil)
        anchorWindow?.orderOut(nil)
        popover.contentViewController = nil
        if playerWindow == nil {
            let window = PlayerWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: playerHeight),
                                      styleMask: [.borderless, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "VibeCast"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .normal
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.onClose = { [weak self] in self?.returnToMenuBar() }
            window.delegate = self
            playerWindow = window
        }
        guard let window = playerWindow else { return }
        playerPresentation.resetWindowSize()
        window.contentViewController = hosting
        playerPresentation.isDetached = true
        updateMaximumHeight(on: screen)
        let height = playerPresentation.desiredHeight(natural: playerHeight)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let origin = lastPlayerFrame?.origin ?? sourceFrame.map { NSPoint(x: $0.midX - 200, y: $0.maxY - playerHeight - 12) }
            ?? NSPoint(x: visible.midX - 200, y: visible.midY - playerHeight / 2)
        adjustingWindow = true
        window.minSize = NSSize(width: 400, height: min(PlayerPresentation.minimumHeight, playerPresentation.maximumHeight))
        window.maxSize = NSSize(width: 400, height: playerPresentation.maximumHeight)
        window.setFrame(Self.constrainedFrame(NSRect(origin: origin, size: NSSize(width: 400, height: height)), to: screen),
                        display: false)
        adjustingWindow = false
        resizePlayerWindow(window, naturalHeight: playerHeight)
        bringPlayerForward()
    }

    @objc func returnToMenuBar() {
        guard playerPresentation.isDetached, let window = playerWindow else { return }
        lastPlayerFrame = window.frame
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderOut(nil)
        window.contentViewController = nil
        playerPresentation.isDetached = false
        playerPresentation.resetWindowSize()
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 400, height: playerHeight)
        playerPresentation.windowHeight = popover.contentSize.height
        // Snapshot the current status item before activation. In fullscreen its
        // window may already be hidden; the last visible anchor remains valid.
        let current = statusItem.button.flatMap { button in
            button.window?.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let anchor = [current, lastPopoverAnchor].compactMap { $0 }.first { rect in
            NSScreen.screens.contains { $0.frame.intersects(rect) }
        }
        if let anchor {
            NSApp.activate(ignoringOtherApps: true)
            showPopover(anchoredAt: anchor)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func bringPlayerForward() {
        guard let window = playerWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        store.noteInteraction()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === playerWindow else { return }
        updateMaximumHeight(on: window.screen)
        resizePopover(playerHeight)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === playerWindow else { return frameSize }
        // Hosting can reset NSWindow's min/max sizes during layout. The delegate
        // remains authoritative for user resizing, independent of those hints.
        let height = playerPresentation.isHeightLocked ? sender.frame.height :
            min(max(frameSize.height, PlayerPresentation.minimumHeight), playerPresentation.maximumHeight)
        return NSSize(width: 400, height: height)
    }

    func windowDidResize(_ notification: Notification) {
        guard !adjustingWindow, playerPresentation.isDetached,
              let window = notification.object as? NSWindow, window === playerWindow else { return }
        playerPresentation.recordResize(window.frame.height)
    }

    private func resizePlayerWindow(_ window: NSWindow, naturalHeight: CGFloat) {
        guard !window.inLiveResize else { return }
        let height = playerPresentation.desiredHeight(natural: naturalHeight)
        let locked = playerPresentation.isHeightLocked
        adjustingWindow = true
        if locked { window.styleMask.remove(.resizable) }
        else { window.styleMask.insert(.resizable) }
        // Release old limits before applying the next mode's frame, then lock
        // reading panels to that frame. Programmatic layout never becomes a user size.
        window.minSize = NSSize(width: 400, height: min(PlayerPresentation.minimumHeight, playerPresentation.maximumHeight))
        window.maxSize = NSSize(width: 400, height: playerPresentation.maximumHeight)
        let frame = window.frame
        let desired = NSRect(x: frame.minX, y: frame.maxY - height, width: 400, height: height)
        if abs(frame.height - height) > 0.5 || frame.width != 400 {
            window.setFrame(Self.constrainedFrame(desired, to: window.screen ?? NSScreen.main), display: true, animate: false)
        }
        if locked {
            window.minSize = NSSize(width: 400, height: height)
            window.maxSize = window.minSize
        }
        playerPresentation.windowHeight = height
        adjustingWindow = false
    }

    private func updateMaximumHeight(on screen: NSScreen?) {
        let available = max(320, (screen?.visibleFrame.height ?? 720) - 40)
        playerPresentation.maximumHeight = playerPresentation.isDetached ? available : min(680, available)
    }

    static func constrainedFrame(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        result.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        return result
    }

    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                                  styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.title = "VibeCast Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView:
                SettingsView(store: store, settings: store.settings, close: { [weak window] in window?.close() }))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func close() {
        stopPopoverDismissalMonitoring()
        presentationObserver = nil
        if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
        interactionMonitor = nil
        pendingPopoverHeight = nil
        popover.performClose(nil)
        anchorWindow?.orderOut(nil)
        playerWindow?.orderOut(nil)
        playerWindow?.contentViewController = nil
        settingsWindow?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func installMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let settings = appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit VibeCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        main.addItem(edit)
        edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                      ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
    }
}

private final class PlayerWindow: NSWindow {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { onClose?() }
    override func close() { onClose?() }
}

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }
    override func cancelOperation(_ sender: Any?) { close() }
}

// Only the title region is draggable, never fields, toggles, or buttons.
struct SettingsDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
