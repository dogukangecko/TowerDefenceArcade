import SwiftUI

/// Menüden erişilen "Hakkında" ekranı (K1): sürüm, GitHub kaynak bağlantısı ve
/// CC0 varlık sahiplerine atıf. HowToPlayView'in görsel dilinde — parşömen
/// commandPanel + ink mürekkep tonları, ScrollView.
struct CreditsView: View {
    let onClose: () -> Void

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.059, green: 0.078, blue: 0.047), Theme.panel],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("HAKKINDA")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.accent)

                    // Üst blok: logo + ad + sürüm + kısa tanıtım — parşömen panelde.
                    VStack(spacing: 8) {
                        bundleImage("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Theme.inkAccent.opacity(0.5), lineWidth: 1))
                        Text("Tower Defence")
                            .font(.system(.title2, design: .rounded).bold())
                            .foregroundStyle(Theme.inkPrimary)
                        Text("Sürüm \(version)")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("SwiftUI + SpriteKit ile geliştirildi; oyun mantığı açık kaynak.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Theme.inkPrimary)
                            .multilineTextAlignment(.center)
                        // SwiftUI Link: macOS ve iOS'ta varsayılan tarayıcıyı açar.
                        Link(destination: URL(string:
                            "https://github.com/dogukangecko/TowerDefenceArcade")!) {
                            Label("GitHub'da Kaynak Kodu", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.system(.title3, design: .rounded).bold())
                        }
                        .buttonStyle(CommandButtonStyle(prominent: true))
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: 560)
                    .commandPanel()

                    // Krediler: ad + katkı + kendi sayfasına Link — hepsi CC0.
                    VStack(spacing: 12) {
                        Text("EMEĞİ GEÇENLER")
                            .font(.system(.headline, design: .rounded).bold())
                            .foregroundStyle(Theme.inkAccent)
                            .tracking(2)
                        creditRow(name: "Foozle",
                                  contribution: "Spire pixel-art serisi: kuleler, düşmanlar, "
                                    + "zeminler, efektler (CC0)",
                                  url: "https://foozlecc.itch.io/")
                        creditRow(name: "Kenney",
                                  contribution: "UI paketi ve ses efektleri (CC0)",
                                  url: "https://kenney.nl")
                        creditRow(name: "RandomMind",
                                  contribution: "Müzikler: The Old Tower Inn, Medieval: "
                                    + "Market Day, Medieval: Battle (CC0)",
                                  url: "https://opengameart.org/users/randommind")
                        // Ambiyans sesleri: kompakt alt liste — her ad kendi
                        // OpenGameArt sayfasına linkli (bkz. CREDITS.md).
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ambiyans sesleri (CC0)")
                                .font(.system(.callout, design: .rounded).bold())
                                .foregroundStyle(Theme.inkPrimary)
                            ambientRow(name: "TinyWorlds", what: "orman ambiyansı",
                                       url: "https://opengameart.org/content/forest-ambience")
                            ambientRow(name: "Wolfgang_", what: "cırcır böcekleri",
                                       url: "https://opengameart.org/content/crickets-ambient-noise-loopable")
                            ambientRow(name: "JaggedStone", what: "zindan ambiyansı",
                                       url: "https://opengameart.org/content/loopable-dungeon-ambience")
                            ambientRow(name: "LokiF", what: "bataklık ambiyansı",
                                       url: "https://opengameart.org/content/swamp-environment-audio")
                        }
                        .frame(maxWidth: 480, alignment: .leading)
                    }
                    .frame(maxWidth: 560)
                    .commandPanel()

                    Text("Tüm sanat ve ses varlıkları CC0 (kamu malı) lisanslıdır. Teşekkürler! 🙏")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button(action: onClose) {
                        Text("Kapat")
                            .font(.system(.title3, design: .rounded).bold())
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(CommandButtonStyle(prominent: true))
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Tek katkıcı satırı: ad + katkı metni, sağda kaynağa giden link ikonu.
    private func creditRow(name: String, contribution: String, url: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.callout, design: .rounded).bold())
                    .foregroundStyle(Theme.inkPrimary)
                Text(contribution)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Link(destination: URL(string: url)!) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.inkAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name) sayfasını aç")
        }
        .frame(maxWidth: 480)
    }

    /// Kompakt ambiyans satırı: "• Ad — katkı" + link ikonu.
    private func ambientRow(name: String, what: String, url: String) -> some View {
        HStack(spacing: 8) {
            Text("• \(name) — \(what)")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
            Link(destination: URL(string: url)!) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name) sayfasını aç")
        }
    }
}
