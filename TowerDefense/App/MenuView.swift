import GameCore
import SwiftUI

struct MenuView: View {
    let onCampaign: () -> Void
    /// Günlük Meydan Okuma (E3): bugünün tohumlu seviyesi — gün başına tek deneme.
    let onDaily: () -> Void
    /// Sonsuz Mod: seçili arenada üstel dalga üreteciyle, galibiyetsiz rekor avı.
    let onEndless: () -> Void
    let onShop: () -> Void
    /// Başarımlar vitrini (E5): 11 yerel başarımın kazanım durumu.
    let onAchievements: () -> Void
    let onHowTo: () -> Void
    /// Hakkında ekranı (K1): GitHub bağlantısı + emeği geçenler.
    let onCredits: () -> Void
    @State private var kenBurns = false
    /// Bugünün günlük seviye adı + durumu — üretim hafif ama menü gövdesinde her
    /// yeniden çizimde koşmasın diye onAppear'da bir kez hesaplanıp saklanır.
    @State private var dailyName = ""
    @State private var dailyState: (attempted: Bool, won: Bool, wave: Int) = (false, false, 0)
    @AppStorage("selectedMap") private var selectedMap = Persistence.classicMapName

    var body: some View {
        ZStack {
            // Spire kompozisyonu arka plan + yavaş Ken Burns kaydırması.
            GeometryReader { geo in
                bundleImage("menu_bg")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.06 : 1.0)
                    .clipped()
            }
            .ignoresSafeArea()
            .onAppear {
                SoundPlayer.shared.playMusic("music_menu")
                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                    kenBurns = true
                }
            }
            LinearGradient(colors: [.clear, Theme.bgDark.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                // Oyunun arması: uygulama logosu — yuvarlatılmış rozet + amber parıltı.
                bundleImage("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 52))
                    .overlay(RoundedRectangle(cornerRadius: 52)
                        .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.5))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 22, y: 6)
                    .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
                Text("Kulelerini kur, üssünü dalgalara karşı savun")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                // Ana mod: 50 seviyelik Sefer — belirgin amber düğme.
                Button(action: onCampaign) {
                    Label("Sefer", systemImage: "map.fill")
                        .font(.system(.title2, design: .rounded).bold())
                        .padding(.horizontal, 30)
                        .padding(.vertical, 6)
                }
                .buttonStyle(CommandButtonStyle(prominent: true))
                // Günlük Meydan Okuma kartı: bugünün adı + durum; tek deneme.
                DailyCard(name: dailyName, state: dailyState, onPlay: onDaily)
                    .onAppear {
                        let c = Calendar.current.dateComponents([.year, .month, .day],
                                                                from: Date())
                        guard let y = c.year, let m = c.month, let d = c.day else { return }
                        dailyName = LevelGenerator.daily(year: y, month: m, day: d).name
                        dailyState = Persistence.dailyState(
                            Persistence.dailyKey(year: y, month: m, day: d))
                    }
                // Sonsuz Mod bölümü: el yapımı arenalar (eski Serbest Oyun
                // haritaları) + "∞ Başla". Arena seçimi @AppStorage selectedMap'te.
                VStack(spacing: 10) {
                    Text("SONSUZ MOD")
                        .font(.system(.caption, design: .rounded).bold())
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(2)
                    // Arena seçimi: seçilen kart amber vurgulu; Başla seçili arenayla.
                    HStack(spacing: 12) {
                        ForEach(Maps.all.map { $0.name }, id: \.self) { name in
                            MapCard(name: name,
                                    isSelected: selectedMap == name,
                                    bestWave: Persistence.bestEndlessWave(mapName: name),
                                    onSelect: { selectedMap = name })
                        }
                        Button(action: onEndless) {
                            Label("Başla", systemImage: "infinity")
                                .font(.system(.title3, design: .rounded).bold())
                        }
                        .buttonStyle(CommandButtonStyle())
                        .accessibilityLabel("Sonsuz Mod Başla")
                    }
                }
                HStack(spacing: 14) {
                    Button(action: onShop) {
                        Label("Mağaza", systemImage: "cart")
                            .font(.system(.title3, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle())
                    Button(action: onAchievements) {
                        Label("Başarımlar", systemImage: "trophy")
                            .font(.system(.title3, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle())
                    Button(action: onHowTo) {
                        Label("Nasıl Oynanır", systemImage: "questionmark.circle")
                            .font(.system(.title3, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle())
                    // Hakkında (K1): ikincil, küçük — satırı sıkıştırmasın.
                    Button(action: onCredits) {
                        Label("Hakkında", systemImage: "info.circle")
                            .font(.system(.callout, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle())
                }
            }
        }
    }
}

/// Günlük Meydan Okuma kartı (E3): bugünün üretilmiş adı + durum. Oynanmadıysa
/// amber kenarlı "Oyna" düğmesi; denendiyse sonuç satırı + "Yarın yenisi" (kilit).
private struct DailyCard: View {
    let name: String
    let state: (attempted: Bool, won: Bool, wave: Int)
    let onPlay: () -> Void

    private var statusText: String {
        state.won ? "✓ Kazandın (Dalga \(state.wave)) · Yarın yenisi"
                  : "✗ Dalga \(state.wave)'de düştün · Yarın yenisi"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("📅 Günlük Meydan Okuma")
                    .font(.system(.callout, design: .rounded).bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(state.attempted ? statusText : "\(name) · ×2 Hazine")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(state.attempted && state.won
                                     ? Theme.accent : Theme.textSecondary)
            }
            if !state.attempted {
                Button(action: onPlay) {
                    Label("Oyna", systemImage: "play.fill")
                        .font(.system(.callout, design: .rounded).bold())
                }
                .buttonStyle(CommandButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(colors: [Theme.panelTop, Theme.panel],
                                 startPoint: .top, endPoint: .bottom)
                .opacity(state.attempted ? 0.55 : 1)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(state.attempted ? Theme.outline.opacity(0.7) : Theme.accent,
                          lineWidth: state.attempted ? 1 : 2))
        .shadow(color: state.attempted ? .clear : Theme.accent.opacity(0.3),
                radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Günlük Meydan Okuma: "
            + (state.attempted ? statusText : "\(name), oynanabilir"))
    }
}

/// Sonsuz arena kartı: arena adı + arenaya özel sonsuz rekoru (bestEndlessWave);
/// seçili olan amber çerçeveli.
private struct MapCard: View {
    let name: String
    let isSelected: Bool
    let bestWave: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                Text(name)
                    .font(.system(.callout, design: .rounded).bold())
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Text(bestWave > 0 ? "En iyi: Dalga \(bestWave)" : "Henüz oynanmadı")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: isSelected ? [Theme.panelTop, Theme.panel]
                                       : [Theme.panel.opacity(0.6), Theme.bgDark.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Theme.accent : Theme.outline.opacity(0.7),
                              lineWidth: isSelected ? 2 : 1))
            .shadow(color: isSelected ? Theme.accent.opacity(0.35) : .clear,
                    radius: 8, y: 2)
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(duration: 0.25), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct ResultOverlay: View {
    let won: Bool
    let killCount: Int
    let reachedWave: Int
    let totalWaves: Int
    /// Sonsuz rekoru (bestEndlessWave) — yalnız isEndless'ta gösterilir.
    let bestWave: Int
    /// Bu oyunda kazanılan kalıcı Hazine; nil ise satır gösterilmez.
    let treasuryEarned: Int?
    /// Sefer yıldızları (0–3); nil = Sonsuz/Günlük → yıldız satırı gösterilmez.
    let stars: Int?
    /// Sefer kademesi; nil = Sonsuz/Günlük → zorluk kapsülü gösterilmez.
    let difficulty: Difficulty?
    /// Aktif mutatörler (E4) — zorluk kapsülünün yanında küçük emoji dizisi;
    /// boşsa hiçbir şey gösterilmez (Sonsuz/Günlük hep boş).
    let mutators: [Mutator]
    /// Sonsuz Mod: galibiyet yok — başlık ulaşılan dalgayı kutlar, "En iyi"
    /// satırı sonsuz rekorunu (bestWave parametresiyle gelir) gösterir.
    let isEndless: Bool
    /// Günlük Meydan Okuma (E3): alt satır "Günlük Meydan Okuma · ×2 Hazine"
    /// görünür, "Tekrar Oyna" GİZLENİR (gün başına tek deneme) ve harita-rekoru
    /// satırı atlanır (günlük seviyenin kalıcı harita rekoru yok).
    let isDaily: Bool
    /// Bu oyunda YENİ kazanılan başarımlar (E5) — panelin üstünde altın kapsül
    /// şeridi; birden çoksa dikey liste. Boşsa hiçbir şey gösterilmez.
    let achievements: [Achievement]
    let onRestart: () -> Void
    let onExit: () -> Void
    /// Sefer galibiyetinde "Sıradaki Seviye" (son seviyede/diğer kiplerde nil).
    let onNext: (() -> Void)?

    /// Kâbus galibiyeti özel kutlama başlığı alır; Sonsuz'da kayıp bile rekor
    /// kutlamasıdır; diğer her şey eskisi gibi.
    private var title: String {
        if isEndless { return "SONSUZ BİTTİ ⚔️" }
        if won {
            return difficulty == .kabus ? "KÂBUS BİTTİ! 💀🔥" : "KAZANDIN! 🎉"
        }
        return "ÜS DÜŞTÜ 💥"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 20) {
                // Yeni başarımlar (E5): en üstte altın kapsüller — katalog sırasında.
                if !achievements.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(achievements) { a in
                            Text("🏆 Başarım: \(a.title)")
                                .font(.system(.callout, design: .rounded).bold())
                                .foregroundStyle(Theme.bgDark)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Theme.accent))
                                .overlay(Capsule().strokeBorder(
                                    Theme.bgDark.opacity(0.25), lineWidth: 1))
                                .accessibilityLabel("Yeni başarım: \(a.title)")
                        }
                    }
                }
                // commandPanel parşömeni açık renkli — panel içi metinler koyu (ink*).
                Text(title)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    // Sonsuz'da kayıp da kutlamadır (rekor avı) — altın başlık.
                    .foregroundStyle(won || isEndless ? Theme.inkAccent : Theme.danger)
                if isDaily {
                    Text("Günlük Meydan Okuma · ×2 Hazine")
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(Theme.inkSecondary)
                }
                if let difficulty {
                    HStack(spacing: 8) {
                        // Sefer kademe kapsülü: kademe renginde dolgu, koyu metin.
                        Text(difficulty.label)
                            .font(.system(.callout, design: .rounded).bold())
                            .foregroundStyle(Theme.bgDark)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(difficulty.tint))
                            .overlay(Capsule().strokeBorder(
                                Theme.bgDark.opacity(0.25), lineWidth: 1))
                            .accessibilityLabel("Zorluk: \(difficulty.label)")
                        // Aktif mutatör ikonları (E4) — sabit enum sırasında.
                        if !mutators.isEmpty {
                            Text(Mutator.allCases.filter(mutators.contains)
                                .map(\.icon).joined(separator: " "))
                                .font(.system(size: 15))
                                .accessibilityLabel("Mutatörler: "
                                    + mutators.map(\.label).joined(separator: ", "))
                        }
                    }
                }
                if let stars {
                    // Sefer yıldızları: dolu altın ★ + eskitilmiş boş ☆.
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            Text(i < stars ? "★" : "☆")
                                .font(.system(size: 42))
                                .foregroundStyle(i < stars ? Theme.inkAccent
                                                           : Theme.inkSecondary.opacity(0.6))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stars) yıldız")
                }
                VStack(spacing: 6) {
                    Text("Öldürülen düşman: \(killCount)")
                    // Sonsuz'da hedef dalga yok: "/total" payda gösterilmez.
                    Text(isEndless ? "Ulaşılan dalga: \(reachedWave)"
                                   : "Ulaşılan dalga: \(reachedWave)/\(totalWaves)")
                    if let earned = treasuryEarned {
                        Text("+\(earned) Hazine 🪙")
                            .foregroundStyle(Theme.inkAccent)
                    }
                    if isEndless {
                        // Sonsuzda galibiyet kavramı yok — yalnız rekor dalga.
                        Text("En iyi: Dalga \(bestWave)")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Theme.inkPrimary)
                HStack(spacing: 16) {
                    if let onNext {
                        Button(action: onNext) {
                            Label("Sıradaki Seviye", systemImage: "arrow.right")
                                .font(.system(.title3, design: .rounded).bold())
                        }
                        .buttonStyle(CommandButtonStyle(prominent: true))
                    }
                    // Günlükte "Tekrar Oyna" YOK: gün başına tek deneme.
                    if !isDaily {
                        Button(action: onRestart) {
                            Label("Tekrar Oyna", systemImage: "arrow.counterclockwise")
                                .font(.system(.title3, design: .rounded).bold())
                        }
                        .buttonStyle(CommandButtonStyle(prominent: onNext == nil))
                    }
                    Button(action: onExit) {
                        Label("Ana Menü", systemImage: "house")
                            .font(.system(.title3, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle())
                }
            }
            .padding(30)
            .commandPanel()
            .padding(40)
        }
    }
}
