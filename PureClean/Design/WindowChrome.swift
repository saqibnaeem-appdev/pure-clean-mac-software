import SwiftUI
import AppKit

/// Native blur material behind window content.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Captures the hosting NSWindow so the app can manage activation policy
/// (Dock icon appears while the dashboard is open, disappears when it
/// closes and PureClean retreats to the menu bar).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Slowly drifting gradient glow behind the whole window — depth without
/// heavy rendering. Runs a single 18 s ease loop.
struct AuroraBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.blue.opacity(0.20), .clear],
                                     center: .center, startRadius: 0, endRadius: 280))
                .frame(width: 560, height: 560)
                .offset(x: animate ? -180 : -120, y: animate ? -220 : -280)
                .blur(radius: 60)
            Circle()
                .fill(RadialGradient(colors: [.purple.opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
                .offset(x: animate ? 260 : 200, y: animate ? 180 : 240)
                .blur(radius: 70)
            Circle()
                .fill(RadialGradient(colors: [.pink.opacity(0.10), .clear],
                                     center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: animate ? 60 : 120, y: animate ? -60 : 20)
                .blur(radius: 80)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
