import AppKit
import SwiftUI
import QuartzCore

struct TableScrollRequest: Equatable {
    let id = UUID()
    let row: Int
    let animated: Bool
}

/// Adds native row positioning to SwiftUI's Table while retaining its selection,
/// column sorting, accessibility and keyboard behavior.
struct TablePositionBridge: NSViewRepresentable {
    let request: TableScrollRequest?
    func makeNSView(context: Context) -> PositionView { PositionView() }
    func updateNSView(_ view: PositionView, context: Context) {
        guard let request, view.lastRequest != request.id else { return }
        view.lastRequest = request.id
        view.position(request)
    }
    @MainActor final class PositionView: NSView {
        var lastRequest: UUID?
        func position(_ request: TableScrollRequest) {
            Task { @MainActor [weak self] in
                // Let SwiftUI commit the new alphabetical row order first.
                await Task.yield()
                guard let self, self.lastRequest == request.id else { return }
                let row = request.row
                var ancestor = self.superview
                while let container = ancestor {
                    if let table = self.findTable(in: container), row >= 0, row < table.numberOfRows {
                        table.layoutSubtreeIfNeeded()
                        guard let scroll = table.enclosingScrollView else { return }
                        let clip = scroll.contentView
                        let start = clip.bounds.origin
                        // Ask AppKit to calculate a valid endpoint for the real
                        // row geometry, including variable heights and the header.
                        table.scrollRowToVisible(row)
                        let endpoint = clip.bounds.origin
                        if request.animated && start != endpoint {
                            clip.scroll(to: start)
                            NSAnimationContext.runAnimationGroup({ context in
                                context.duration = 0.18
                                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                                clip.animator().setBoundsOrigin(endpoint)
                            }, completionHandler: nil)
                        }
                        scroll.reflectScrolledClipView(clip)
                        return
                    }
                    ancestor = container.superview
                }
            }
        }
        private func findTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for child in view.subviews {
                if let table = findTable(in: child) { return table }
            }
            return nil
        }
    }
}
