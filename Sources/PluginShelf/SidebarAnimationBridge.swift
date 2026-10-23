import PluginShelfCore
import AppKit
import SwiftUI
import QuartzCore

/// Uses this window's native sidebar item instead of snapping column visibility.
@MainActor
final class SidebarAnimationController: NSObject {
    weak var anchor: NSView?
    private var accessory: NSTitlebarAccessoryViewController?
    private weak var accessoryWindow: NSWindow?
    private var onToggle: (@MainActor (Bool) -> Void)?
    private let button = NSButton()

    func updateButton(visible: Bool, onToggle: @escaping @MainActor (Bool) -> Void) {
        self.onToggle = onToggle
        button.state = visible ? .on : .off
        button.setAccessibilityLabel(L("边栏"))
        button.toolTip = visible ? L("隐藏边栏") : L("显示边栏")
        button.setAccessibilityValue(visible ? 1 : 0)
        button.setAccessibilityHelp(visible ? L("隐藏边栏，当前已展开") : L("显示边栏，当前已收起"))
        attachButtonIfNeeded()
    }

    func attachButtonIfNeeded() {
        guard let window = anchor?.window, accessoryWindow !== window else { return }
        removeButton()
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 44, height: 38))
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .texturedRounded
        button.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: L("边栏"))
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(toggleSidebar(_:))
        button.setAccessibilityLabel(L("边栏"))
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
        self.accessory = accessory
        accessoryWindow = window
    }

    func removeButton() {
        if let accessory, let window = accessoryWindow,
           let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
        accessory = nil
        accessoryWindow = nil
    }

    func detach() {
        removeButton()
        onToggle = nil
        anchor = nil
    }

    @objc private func toggleSidebar(_ sender: NSButton) { onToggle?(sender.state == .on) }

    private(set) var isAnimating = false
    private struct Request {
        let visible: Bool
        let animated: Bool
        let onSettled: @MainActor (Bool) -> Void
    }
    private var pending: Request?

    func setVisible(_ visible: Bool, animated: Bool, onSettled: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard let split = splitController, let item = split.splitViewItems.first(where: { $0.behavior == .sidebar }) else { return false }
        // Reversing the native animator mid-flight snaps to an endpoint. Keep
        // the current 220 ms transition smooth and coalesce subsequent clicks.
        pending = Request(visible: visible, animated: animated, onSettled: onSettled)
        if !isAnimating { runPending(in: split, item: item) }
        return true
    }

    private func runPending(in split: NSSplitViewController, item: NSSplitViewItem) {
        guard let request = pending else { return }
        pending = nil
        guard item.isCollapsed == request.visible else {
            request.onSettled(!item.isCollapsed)
            return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = request.animated ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            if request.animated { item.animator().isCollapsed = !request.visible }
            else { item.isCollapsed = !request.visible }
        }, completionHandler: { [weak self, weak split, weak item] in
            Task { @MainActor [weak self, weak split, weak item] in
                guard let self else { return }
                self.isAnimating = false
                guard let split, let item else { self.pending = nil; return }
                if self.pending != nil { self.runPending(in: split, item: item) }
                else { request.onSettled(!item.isCollapsed) }
            }
        })
    }

    private var splitController: NSSplitViewController? {
        var responder: NSResponder? = anchor
        while let current = responder {
            if let split = current as? NSSplitViewController,
               split.splitViewItems.contains(where: { $0.behavior == .sidebar }) { return split }
            responder = current.nextResponder
        }
        return nil
    }
}

struct SidebarAnimationBridge: NSViewRepresentable {
    let controller: SidebarAnimationController
    let visible: Bool
    let onToggle: @MainActor (Bool) -> Void

    final class Anchor: NSView {
        weak var controller: SidebarAnimationController?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            controller?.anchor = self
            controller?.attachButtonIfNeeded()
        }
    }

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.controller = controller
        controller.anchor = view
        controller.updateButton(visible: visible, onToggle: onToggle)
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) {
        controller.anchor = view
        controller.updateButton(visible: visible, onToggle: onToggle)
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.controller?.detach()
    }
}
