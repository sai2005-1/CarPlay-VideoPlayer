import SwiftUI
import UIKit

enum AppPalette {
    static let ink = Color(.sRGB, red: 0.035, green: 0.075, blue: 0.145, opacity: 1)
    static let ocean = Color(.sRGB, red: 0.055, green: 0.29, blue: 0.53, opacity: 1)
    static let cyan = Color(.sRGB, red: 0.16, green: 0.82, blue: 0.83, opacity: 1)
    static let blue = Color(.sRGB, red: 0.24, green: 0.47, blue: 0.98, opacity: 1)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let gradient = LinearGradient(
        colors: [ink, ocean, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct BrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppPalette.cyan, AppPalette.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "car.side.fill")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .offset(y: size * 0.14)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.25, weight: .black))
                .foregroundStyle(AppPalette.ink)
                .padding(size * 0.13)
                .background(.white, in: RoundedRectangle(cornerRadius: size * 0.13))
                .offset(y: -size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("CarPlay Video")
    }
}

struct AppGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content, shape: shape)
        }
        #else
        fallback(content, shape: shape)
        #endif
    }

    private func fallback<Content: View>(
        _ content: Content,
        shape: RoundedRectangle
    ) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
    }
}

extension View {
    func appGlassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(AppGlassCard(cornerRadius: cornerRadius))
    }
}
