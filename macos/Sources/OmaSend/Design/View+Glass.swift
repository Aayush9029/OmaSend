import SwiftUI

extension View {
    @ViewBuilder
    func omaGlass(cornerRadius: CGFloat) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            omaLegacyGlass(cornerRadius: cornerRadius)
        }
#else
        omaLegacyGlass(cornerRadius: cornerRadius)
#endif
    }

    @ViewBuilder
    func omaGlassButtons() -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) { buttonStyle(.glass) }
        else { buttonStyle(.bordered) }
#else
        buttonStyle(.bordered)
#endif
    }

    private func omaLegacyGlass(cornerRadius: CGFloat) -> some View {
        background {
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}
