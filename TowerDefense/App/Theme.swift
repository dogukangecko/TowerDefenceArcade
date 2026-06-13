import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Orta çağ ahşap/taş teması — paylaşılan renkler.
enum Theme {
    static let bgDark = Color(red: 0.102, green: 0.078, blue: 0.047)     // #1A140C koyu meşe
    static let panel = Color(red: 0.165, green: 0.125, blue: 0.078)      // #2A2014
    static let panelTop = Color(red: 0.204, green: 0.161, blue: 0.102)   // #34291A
    static let accent = Color(red: 0.910, green: 0.639, blue: 0.239)     // #E8A33D amber
    static let danger = Color(red: 0.788, green: 0.310, blue: 0.220)     // #C94F38
    static let outline = Color(red: 0.361, green: 0.290, blue: 0.180)    // #5C4A2E
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)

    // ui_panel parşömeni AÇIK renkli — üzerine konan metin bu koyu "mürekkep"
    // tonlarını kullanmalı (ShopView kartlarıyla aynı seçimler).
    static let inkPrimary = bgDark
    static let inkSecondary = bgDark.opacity(0.65)
    static let inkAccent = Color(red: 0.62, green: 0.38, blue: 0.05)  // koyu amber
}

/// Bundle'daki PNG'yi SwiftUI Image olarak yükler (xcassets dışı kaynaklar).
/// Kule/silah/portre adları TextureBank ile AYNI skin çözümünden geçer —
/// kuşanılı set varsa portreler HUD/HowTo/Mağaza'da da skinli görünür.
func bundleImage(_ rawName: String) -> Image {
    let name = TextureBank.skinResolved(rawName)
    guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
        assertionFailure("UI görseli eksik: \(name).png")
        return Image(systemName: "questionmark.square")
    }
    #if os(macOS)
    return Image(nsImage: NSImage(contentsOf: url) ?? NSImage())
    #else
    return Image(uiImage: UIImage(contentsOfFile: url.path) ?? UIImage())
    #endif
}

/// 9-slice panel arka planı (UI Pack Adventure).
struct NineSlice: View {
    let name: String
    var body: some View {
        bundleImage(name)
            .resizable(capInsets: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
                       resizingMode: .stretch)
    }
}

/// Cilalı komuta düğmesi: belirginlerde amber degrade + parıltı, normallerde koyu
/// meşe degrade + amber kenarlık. Basılınca hafif küçülür ve aydınlanır.
struct CommandButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    private var fill: LinearGradient {
        prominent
            ? LinearGradient(colors: [Color(red: 0.96, green: 0.72, blue: 0.30),
                                      Color(red: 0.78, green: 0.50, blue: 0.13)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Theme.panelTop, Theme.panel],
                             startPoint: .top, endPoint: .bottom)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Theme.bgDark : Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(prominent ? Color.white.opacity(0.55)
                                            : Theme.accent.opacity(0.45),
                                  lineWidth: 1.2)
            )
            .shadow(color: prominent ? Theme.accent.opacity(0.45) : .black.opacity(0.35),
                    radius: prominent ? 9 : 5, y: 3)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Komuta paneli zemini: degrade + ince kenarlık + gölge.
struct CommandPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(NineSlice(name: "ui_panel").opacity(0.96))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

extension View {
    func commandPanel() -> some View { modifier(CommandPanel()) }
}

/// HUD üst barındaki ikonlu değer kapsülü.
struct StatCapsule: View {
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).foregroundStyle(Theme.textPrimary)
        }
        .font(.system(.title3, design: .rounded).bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.bgDark.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Theme.outline.opacity(0.7), lineWidth: 1))
    }
}
