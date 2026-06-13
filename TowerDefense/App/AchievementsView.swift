import GameCore
import SwiftUI

/// Başarımlar vitrini (E5): 11 yerel başarımın grid'i. Kazanılan amber kenarlı
/// ve renkli; kazanılmayan gri (ikon soluk) ama AÇIKLAMA GÖRÜNÜR — koşul
/// bilinince ilerleme motive eder (gizli başarım yok).
struct AchievementsView: View {
    let onClose: () -> Void
    @State private var achieved: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    var body: some View {
        ZStack {
            Theme.bgDark.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Text("🏆 Başarımlar")
                        .font(.system(.largeTitle, design: .rounded).bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(achieved.count)/\(AchievementEngine.all.count)")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.panel))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6),
                                                        lineWidth: 1))
                    Spacer()
                    Button(action: onClose) {
                        Label("Kapat", systemImage: "xmark")
                            .font(.system(.title3, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle())
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(AchievementEngine.all) { a in
                            AchievementCard(achievement: a,
                                            earned: achieved.contains(a.id))
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .padding(24)
        }
        .onAppear {
            // Pasif değerlendirme: sayaç bazlı başarımlar (zengin/katliam/
            // dalga-ustasi/mudavim/fatih/obsidyen) oyun SONU dışında da dolabilir
            // (örn. Hazine harcanmadan biriktiyse) — vitrin açılışında kalıcı
            // sayaçlarla won=false bağlamı değerlendirilir; galibiyet bazlılar
            // won=false olduğundan asla yanlışlıkla düşmez.
            // mode burada önemsiz (won=false; sayaç kuralları kipe bakmaz) —
            // .endless yer tutucudur (uygulamada serbest oyun kipi artık yok).
            let ctx = AchievementContext(
                won: false, leaks: 1, towerKindsUsed: [], towersBuilt: 0,
                difficulty: .normal, mode: .endless, reachedWave: 0,
                normalPlusWinLevels: Persistence.normalPlusWinLevels,
                kabusWinLevels: Persistence.kabusWinCount,
                treasury: Persistence.treasury,
                totalKills: Persistence.totalKills,
                dailyWins: Persistence.dailyWinCount,
                bestEndlessWave: Persistence.bestEndlessWaveOverall)
            let passive = AchievementEngine.evaluate(ctx,
                                                     already: Persistence.achievedIDs)
            Persistence.recordAchievements(passive.map(\.id))
            achieved = Persistence.achievedIDs
        }
    }
}

/// Tek başarım kartı: ikon + başlık + açıklama. Kazanılmamışta ikon desatüre
/// (opacity 0.35) ve metinler soluk; kazanılanda amber kenar + parıltı.
private struct AchievementCard: View {
    let achievement: Achievement
    let earned: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(achievement.icon)
                .font(.system(size: 34))
                .opacity(earned ? 1 : 0.35)
                .saturation(earned ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.title)
                    .font(.system(.callout, design: .rounded).bold())
                    .foregroundStyle(earned ? Theme.textPrimary
                                            : Theme.textSecondary)
                Text(achievement.desc)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary
                        .opacity(earned ? 1 : 0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(
                colors: earned ? [Theme.panelTop, Theme.panel]
                               : [Theme.panel.opacity(0.5), Theme.bgDark.opacity(0.5)],
                startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(earned ? Theme.accent : Theme.outline.opacity(0.6),
                          lineWidth: earned ? 2 : 1))
        .shadow(color: earned ? Theme.accent.opacity(0.3) : .clear, radius: 7, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title): \(achievement.desc), "
            + (earned ? "kazanıldı" : "kazanılmadı"))
    }
}
