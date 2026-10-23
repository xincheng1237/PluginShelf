import SwiftUI
import AppKit

struct AlphabetIndexButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Feedback(configuration: configuration)
    }
    private struct Feedback: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false
        private var keyboard: Bool { NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp }
        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(!enabled ? 0 : configuration.isPressed ? 0.22 : hovered ? 0.1 : 0))
                        .padding(.horizontal, 3)
                }
                .scaleEffect(enabled && configuration.isPressed && !reduceMotion && !keyboard ? 0.97 : 1)
                .onHover { hovered = $0 }
                .animation(keyboard ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.125), value: hovered)
                .animation(keyboard ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.1), value: configuration.isPressed)
        }
    }
}
