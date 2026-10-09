import AppKit
import Carbon.HIToolbox
import CoreServices
import SwiftUI
import UserNotifications

/// FSEvents watcher on several folders; calls back on the main queue, coalesced to `latency`.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void

    /// Calls back on the main queue with the paths that changed. `latency` is how long FSEvents
    /// gathers events before delivering them; NoDefer delivers the first one straight away.
    init(paths: [String], latency: TimeInterval = 0.1, callback: @escaping ([String]) -> Void) {
        self.callback = callback
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, _, _ in
            guard let info else { return }
            let list = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]) ?? []
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().callback(Array(list.prefix(count)))
        }, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}

/// Global shortcuts without Accessibility permission (Carbon hot keys): ⌥⌘F start/pause, ⌥⌘. stop.
final class HotKeys {
    private var refs: [EventHotKeyRef?] = []
    private static var handlers: [UInt32: () -> Void] = [:]

    init(startPause: @escaping () -> Void, stop: @escaping () -> Void) {
        Self.handlers = [1: startPause, 2: stop]
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKeys.handlers[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
        register(kVK_ANSI_F, id: 1)
        register(kVK_ANSI_Period, id: 2)
    }

    private func register(_ key: Int, id: UInt32) {
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(cmdKey | optionKey), EventHotKeyID(signature: OSType(0x5046_4F43), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    deinit { refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } } }
}

/// End-of-session alerts with "Mark task done" and "Start rest" actions.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let category = "pastelfocus.session"
    var onAction: ((String, [AnyHashable: Any]) -> Void)?

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "markDone", title: "Mark task done")
        let rest = UNNotificationAction(identifier: "startRest", title: "Start rest")
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [done, rest], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Books the alert with the system so it fires on time even if the app is throttled.
    func schedule(id: String, title: String, body: String, at date: Date, info: [String: String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = info
        let interval = max(1, date.timeIntervalSinceNow)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    func cancel(id: String) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        DispatchQueue.main.async { self.onAction?(action, info) }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

/// A borderless glass panel on the desktop. Non-activating, but can take keyboard focus for quick add.
final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A non-activating panel never becomes key on its own, so AppKit swallowed the first click on
    /// views inside scroll views (checkboxes, menus). Take key status on every mouse-down instead.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}

/// Hosting view that accepts the click that brings the panel forward.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Drag area for borderless panels: SwiftUI content covers the whole window, so
/// `isMovableByWindowBackground` never sees a background click. Put this behind headers and padding.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Grab strip along a panel's bottom edge: drag to change the height, keeping the top edge where it is.
/// Borderless panels get no resize edges from macOS, so this does it by hand.
struct PanelResizeHandle: NSViewRepresentable {
    final class HandleView: NSView {
        private var startMouseY: CGFloat = 0
        private var startFrame: NSRect = .zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false } // resize, don't move
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }

        override func mouseDown(with event: NSEvent) {
            startMouseY = NSEvent.mouseLocation.y
            startFrame = window?.frame ?? .zero
        }

        override func mouseUp(with event: NSEvent) {
            // Remember the height the user chose (see `PanelController.savedHeight`).
            guard let w = window, let name = w.identifier?.rawValue else { return }
            UserDefaults.standard.set(Double(w.frame.height), forKey: PanelController.heightKey(name))
        }

        override func mouseDragged(with event: NSEvent) {
            guard let w = window else { return }
            let wanted = startFrame.height + (startMouseY - NSEvent.mouseLocation.y) // dragging down makes it taller
            let height = min(w.contentMaxSize.height, max(w.contentMinSize.height, wanted.rounded()))
            var f = startFrame
            f.origin.y = startFrame.maxY - height
            f.size.height = height
            w.setFrame(f, display: true)
        }
    }

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}
}

@MainActor
final class PanelController {
    private(set) var panels: [String: DesktopPanel] = [:]

    /// macOS restores only the position of a remembered frame for windows that aren't `.resizable`
    /// (these borderless panels), so a user-chosen height is stored separately.
    static func heightKey(_ name: String) -> String { "PastelFocus.\(name).height" }
    static func savedHeight(_ name: String) -> CGFloat? {
        let h = UserDefaults.standard.double(forKey: heightKey(name))
        return h > 0 ? CGFloat(h) : nil
    }

    /// `heightRange`: lets the user drag the panel's height within the range (see `PanelResizeHandle`);
    /// the height they chose is remembered. Without it the panel always has `size`.
    func show<Content: View>(_ name: String, size: CGSize, origin: CGPoint, floating: Bool, heightRange: ClosedRange<CGFloat>? = nil,
                             @ViewBuilder content: () -> Content) {
        if let p = panels[name] { p.orderFrontRegardless(); apply(floating: floating, to: p); return }
        let panel = DesktopPanel(contentRect: NSRect(origin: origin, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Panels are mouse-first: with macOS keyboard navigation on, a clicked button would otherwise
        // keep a focus ring until focus moved elsewhere.
        let host = FirstMouseHostingView(rootView: content().focusEffectDisabled())
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.identifier = NSUserInterfaceItemIdentifier(name)
        panel.setFrameAutosaveName("PastelFocus.\(name)")
        if let range = heightRange {
            // Apply the remembered height (clamped), keeping the top edge: macOS restores the remembered
            // frame top-anchored at the default height, so this lands exactly where it was left.
            host.sizingOptions = []
            panel.contentMinSize = CGSize(width: size.width, height: range.lowerBound)
            panel.contentMaxSize = CGSize(width: size.width, height: range.upperBound)
            var frame = panel.frame
            let height = min(range.upperBound, max(range.lowerBound, Self.savedHeight(name) ?? size.height))
            frame.origin.y += frame.height - height
            frame.size = CGSize(width: size.width, height: height)
            panel.setFrame(frame, display: false)
        } else {
            panel.setContentSize(size) // a remembered frame keeps its position, never an outdated size
        }
        apply(floating: floating, to: panel)
        panel.orderFrontRegardless()
        panels[name] = panel
    }

    func hide(_ name: String) { panels[name]?.orderOut(nil) }

    /// Closes every panel so the next `show` rebuilds it (used when the theme changes).
    func resetAll() {
        panels.values.forEach { $0.close() }
        panels = [:]
    }

    func setFloating(_ floating: Bool) { panels.values.forEach { apply(floating: floating, to: $0) } }

    private func apply(floating: Bool, to p: NSPanel) {
        p.level = floating ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    var isAnyVisible: Bool { panels.values.contains { $0.isVisible && $0.occlusionState.contains(.visible) } }
    func isVisible(_ name: String) -> Bool { panels[name].map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false }
}
