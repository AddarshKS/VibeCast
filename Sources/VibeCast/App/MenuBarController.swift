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
    private var playerHeight: CGFloat = 420
    private var lastPlayerFrame: NSRect?
    private(set) var settingsWindow: NSWindow?
    private var pendingPopoverHeight: CGFloat?
    private var resizeScheduled = false
    private var interactionMonitor: Any?
    private var subscriptionObserver: AnyCancellable?
    private weak var statusMenu: NSMenu?
    private var adjustingWindow = false
    private var lastPopoverAnchor: NSRect?
    private var popoverSessionID: UUID?
    private var outsideClickMonitor: Any?
    private var popoverEventMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var settingsActivationObserver: NSObjectProtocol?
    private var settingsNeedsActivation = false
    private var spaceChangeObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?
    private(set) var expandedSession: StatusItemExpandedSession?

    var isMonitoringPopoverDismissal: Bool { popoverEventMonitor != nil && outsideClickMonitor != nil }

    init(store: VibeCastStore, usesNativeStatusTracking: Bool = true) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = ResourceImage.menuBarSymbol
            button.imagePosition = .imageOnly
            button.toolTip = "VibeCast"
            button.setAccessibilityLabel("VibeCast")
        }
        // The stable fullscreen anchor is not the status button. Own dismissal
        // so AppKit cannot close on mouse-down and reopen on the button action.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        hosting = NSHostingController(rootView:
            MenuBarRootView(store: store,
                            resize: { [weak self] height in self?.resizePopover(height) },
                            presentation: playerPresentation,
                            toggleWindow: { [weak self] in self?.togglePlayerWindow() }))
        // The measured SwiftUI height drives NSPopover; automatic hosting constraints
        // must not independently resize its window during the same layout pass.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: PlayerPresentation.width, height: playerHeight)
        playerPresentation.windowHeight = popover.contentSize.height
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            if let self, self.isStatusItemClick(event) {
                StatusItemExpandedSession.log.debug("local event=\(event.type.rawValue) time=\(event.timestamp) shown=\(self.popover.isShown)")
            }
            if let self, self.expandedSession != nil, self.isStatusItemClick(event),
               event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                self.showStatusMenu()
                return nil
            }
            if let self, let window = self.hosting.view.window,
               (self.popover.isShown || self.playerPresentation.isDetached), event.window === window {
                self.store.noteInteraction()
            }
            return event
        }
        installMenus()
        settingsActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusSettingsIfPending() }
        }
        subscriptionObserver = store.chatGPT.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateSubscriptionMenuItem() }
        }
        if usesNativeStatusTracking { installExpandedInterfaceSession() }
        if expandedSession == nil {
            statusItem.button?.target = self
            statusItem.button?.action = #selector(statusItemClicked)
            statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }

    private func installExpandedInterfaceSession() {
        let session = StatusItemExpandedSession()
        session.onBegin = { [weak self] in
            guard let self else { return }
            if let event = NSApp.currentEvent,
               event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                self.showStatusMenu()
                return
            }
            if self.playerPresentation.isDetached {
                self.expandedSession?.cancel()
                self.bringPlayerForward()
            } else {
                self.togglePopover()
                if !self.popover.isShown { self.expandedSession?.cancel() }
            }
        }
        session.onEnd = { [weak self] in self?.popover.performClose(nil) }
        guard session.install(on: statusItem) else { return }
        // AppKit owns opening/menu tracking; our monitors handle repeated clicks.
        // Assigning a menu disables expanded sessions, so contextual clicks stay separate.
        expandedSession = session
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
                self.popover.contentSize = NSSize(width: PlayerPresentation.width, height: height)
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
        popoverSessionID = UUID()
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
        // The native popover is a nonactivating panel. Controls can receive the
        // first click without activating VibeCast; text editing can still take key focus.
        if let panel = hosting.view.window as? NSPanel {
            panel.becomesKeyOnlyIfNeeded = true
            panel.acceptsMouseMovedEvents = true
        }
        if popover.isShown { startPopoverDismissalMonitoring() }
    }

    func popoverDidClose(_ notification: Notification) {
        popoverSessionID = nil
        stopPopoverDismissalMonitoring()
        anchorWindow?.orderOut(nil)
        expandedSession?.cancel()
    }

    private func startPopoverDismissalMonitoring() {
        stopPopoverDismissalMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        popoverEventMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            guard let self else { return event }
            return self.handlePopoverEvent(event)
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] event in
            self?.handleGlobalPopoverClick(event)
        }
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleApplicationDeactivation() }
        }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPopoverForExternalInteraction() }
        }
        // A nonactivating dropdown cannot rely on our app resigning active
        // when the user switches from one other application to another.
        let originalApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.processIdentifier != originalApplicationPID else { return }
            MainActor.assumeIsolated {
                self?.dismissPopoverForExternalInteraction()
            }
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
        if isStatusItemClick(event) {
            // Native tracking does not necessarily end on a repeated icon click.
            // Consume local dismissal so this same event cannot open it again.
            return closeExpandedPopoverForStatusClick(event) ? nil : event
        }
        let contentWindow = popover.contentViewController?.view.window
        var target = event.window
        while let window = target {
            if window === contentWindow { return event }
            target = window.parent
        }
        dismissPopoverForExternalInteraction()
        return event
    }

    private var statusButtonScreenRect: NSRect? {
        if let button = statusItem.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return rect }
        }
        // The fullscreen menu bar can hide its native status window while the
        // popover remains anchored to the last visible icon location.
        return popover.isShown ? lastPopoverAnchor : nil
    }

    private func isStatusItemClick(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown || event.type == .rightMouseDown else { return false }
        if let window = statusItem.button?.window, event.window === window { return true }
        // Forwarded status clicks may have no window or a different native window.
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        return statusButtonScreenRect?.contains(point) == true
    }

    func handleGlobalPopoverClick(_ event: NSEvent) {
        if isStatusItemClick(event) {
            StatusItemExpandedSession.log.debug("global event=\(event.type.rawValue) time=\(event.timestamp) shown=\(self.popover.isShown)")
            _ = closeExpandedPopoverForStatusClick(event)
            return
        }
        dismissPopoverForExternalInteraction()
    }

    // The caller has hit-tested the status item. Legacy target/action still owns
    // its toggle; right/Control-click still belongs to the contextual menu.
    private func closeExpandedPopoverForStatusClick(_ event: NSEvent) -> Bool {
        guard expandedSession != nil, popover.isShown, !playerPresentation.isDetached,
              event.type == .leftMouseDown, !event.modifierFlags.contains(.control) else { return false }
        StatusItemExpandedSession.log.notice("Closing dropdown from repeated status-icon click")
        popover.performClose(nil) // popoverDidClose cancels native menu tracking.
        return true
    }

    func handleApplicationDeactivation(mouseLocation: NSPoint = NSEvent.mouseLocation,
                                       pressedMouseButtons: Int = NSEvent.pressedMouseButtons) {
        guard popover.isShown, !playerPresentation.isDetached, let sessionID = popoverSessionID else { return }
        // Status-item tracking can resign activation before delivering its action.
        // That physical click belongs to the button, not the outside-click closer.
        if pressedMouseButtons & 0b11 != 0, statusButtonScreenRect?.contains(mouseLocation) == true { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popoverSessionID == sessionID else { return }
            self.dismissPopoverForExternalInteraction()
        }
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
        if let workspaceActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver) }
        popoverEventMonitor = nil
        outsideClickMonitor = nil
        deactivateObserver = nil
        spaceChangeObserver = nil
        workspaceActivationObserver = nil
    }

    @objc func togglePopover() {
        if playerPresentation.isDetached { bringPlayerForward(); return }
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard NSScreen.screens.contains(where: { $0.frame.intersects(anchor) }) else { return }
        store.returnToSuggestionsIfIdle()
        store.noteInteraction()
        showPopover(anchoredAt: anchor)
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            showStatusMenu()
        } else { togglePopover() }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        popover.performClose(nil)
        expandedSession?.cancel()
        button.highlight(true)
        defer { button.highlight(false) }
        makeStatusMenu().popUp(positioning: nil, at: Self.statusMenuOrigin(below: anchor), in: nil)
    }

    // Screen coordinates avoid the status button's flipped local coordinate system.
    static func statusMenuOrigin(below anchor: NSRect) -> NSPoint {
        NSPoint(x: anchor.minX, y: anchor.minY - 6)
    }

    // Build on opening so connection indicators and the view checkmark are current.
    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, symbol, action) in [
            ("Advance Mode View", "terminal", #selector(toggleAdvancedView)),
            ("Settings", "slider.horizontal.3", #selector(showSettings)),
            ("Quit VibeCast", "power", #selector(quitVibeCast)),
            ("Contact Us!", "envelope", #selector(contactUs))
        ] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        menu.items.first?.state = playerPresentation.advanced ? .on : .off
        menu.addItem(.separator())
        menu.addItem(connectionItem("Spotify", connected: store.authState.isLoggedIn))
        if store.settings.aiProvider == .chatGPT {
            let item = NSMenuItem()
            item.identifier = NSUserInterfaceItemIdentifier("openai-status")
            menu.addItem(item)
        }
        statusMenu = menu
        updateSubscriptionMenuItem()
        return menu
    }

    private func updateSubscriptionMenuItem() {
        guard let item = statusMenu?.items.first(where: { $0.identifier?.rawValue == "openai-status" }) else { return }
        let session = store.chatGPT
        let connected: Bool? = session.account != nil ? true : (session.hasCheckedAccount ? false : nil)
        let replacement = connectionItem("OpenAI", connected: connected)
        item.title = connected == nil && session.error != nil ? "OpenAI Connection Unavailable" : replacement.title
        item.image = replacement.image
        item.isEnabled = false
    }

    private func connectionItem(_ service: String, connected: Bool?) -> NSMenuItem {
        let status = connected.map { $0 ? "Connected" : "Disconnected" } ?? "Checking Connection"
        let item = NSMenuItem(title: "\(service) \(status)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { _ in
            (connected.map { $0 ? NSColor.systemGreen : NSColor.systemRed } ?? NSColor.secondaryLabelColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 8, height: 8)).fill()
            return true
        }
        return item
    }

    @objc func toggleAdvancedView() {
        playerPresentation.toggleAdvanced()
        if playerPresentation.isDetached { bringPlayerForward() }
        else if !popover.isShown { togglePopover() }
    }

    static let contactURL = URL(string: "mailto:addarshshrivastava@gmail.com")!
    @objc private func contactUs() { NSWorkspace.shared.open(Self.contactURL) }
    @objc private func quitVibeCast() { NSApp.terminate(nil) }

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
            let window = PlayerWindow(contentRect: NSRect(x: 0, y: 0, width: PlayerPresentation.width, height: playerHeight),
                                      styleMask: [.borderless, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "VibeCast"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .normal
            // Keep the player on its own Space. Activation should visit that
            // window, not carry it onto the user's current desktop/fullscreen app.
            window.collectionBehavior = [.managed, .participatesInCycle]
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
        let origin = lastPlayerFrame?.origin ?? sourceFrame.map { NSPoint(x: $0.midX - PlayerPresentation.width / 2, y: $0.maxY - height - 12) }
            ?? NSPoint(x: visible.midX - PlayerPresentation.width / 2, y: visible.midY - height / 2)
        adjustingWindow = true
        window.minSize = NSSize(width: PlayerPresentation.width, height: 1)
        window.maxSize = NSSize(width: PlayerPresentation.width, height: playerPresentation.maximumHeight)
        window.setFrame(Self.constrainedFrame(NSRect(origin: origin, size: NSSize(width: PlayerPresentation.width, height: height)), to: screen),
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
        popover.contentSize = NSSize(width: PlayerPresentation.width, height: playerHeight)
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
            showPopover(anchoredAt: anchor)
        }
    }

    private func bringPlayerForward() {
        guard let window = playerWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        return NSSize(width: PlayerPresentation.width, height: height)
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
        // non-resizable panels to that frame. Programmatic layout never becomes a user size.
        window.minSize = NSSize(width: PlayerPresentation.width, height: locked ? 1 : min(PlayerPresentation.minimumHeight, playerPresentation.maximumHeight))
        window.maxSize = NSSize(width: PlayerPresentation.width, height: playerPresentation.maximumHeight)
        let frame = window.frame
        let desired = NSRect(x: frame.minX, y: frame.maxY - height, width: PlayerPresentation.width, height: height)
        if abs(frame.height - height) > 0.5 || frame.width != PlayerPresentation.width {
            window.setFrame(Self.constrainedFrame(desired, to: window.screen ?? NSScreen.main), display: true, animate: false)
        }
        if locked {
            window.minSize = NSSize(width: PlayerPresentation.width, height: height)
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
            window.contentView = FirstClickHostingView(rootView:
                SettingsView(store: store, settings: store.settings, close: { [weak window] in window?.close() }))
            window.center()
            settingsWindow = window
        }
        settingsNeedsActivation = true
        settingsWindow?.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusSettingsIfPending()
        // A status menu can restore its former key window when tracking ends.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.settingsWindow, window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if window.isKeyWindow { self?.settingsNeedsActivation = false }
        }
    }

    private func focusSettingsIfPending() {
        guard settingsNeedsActivation, let window = settingsWindow else { return }
        guard window.isVisible else { settingsNeedsActivation = false; return }
        window.makeKeyAndOrderFront(nil)
        if window.isKeyWindow { settingsNeedsActivation = false }
    }

    func close() {
        expandedSession?.uninstall()
        expandedSession = nil
        popoverSessionID = nil
        stopPopoverDismissalMonitoring()
        subscriptionObserver = nil
        if let settingsActivationObserver { NotificationCenter.default.removeObserver(settingsActivationObserver) }
        settingsActivationObserver = nil
        settingsNeedsActivation = false
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

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
