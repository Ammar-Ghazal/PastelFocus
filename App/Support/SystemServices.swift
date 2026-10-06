import AppKit
import Carbon.HIToolbox
import CoreServices
import SwiftUI
import UserNotifications

/// FSEvents watcher on several folders; calls back on the main queue, coalesced to `latency`.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void

    init(paths: [String], latency: TimeInterval = 0.3, callback: @escaping () -> Void) {
        self.callback = callback
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().callback()
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

@MainActor
final class PanelController {
    private(set) var panels: [String: DesktopPanel] = [:]

    func show<Content: View>(_ name: String, size: CGSize, origin: CGPoint, floating: Bool, @ViewBuilder content: () -> Content) {
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
        let host = FirstMouseHostingView(rootView: content())
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setFrameAutosaveName("PastelFocus.\(name)")
        panel.setContentSize(size) // a remembered frame keeps its position, never an outdated size
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
