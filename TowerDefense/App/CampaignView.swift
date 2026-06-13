import GameCore
import SwiftUI

/// Sefer ekranı: 50 üretilmiş seviyenin kart ızgarası. Kilit ilerlemesi ve
/// yıldızlar Persistence'tan; kart meta verisi (ad + nehir rozeti) dalga
/// üretimini atlayan hafif LevelGenerator.meta(50) listesinden gelir.
struct CampaignView: View {
    let onPlay: (Int, Difficulty, [Mutator]) -> Void
    let onClose: () -> Void

    /// meta(50) deterministik ve saf — bir kez üretilip süreç boyunca paylaşılır.
    private static let levels = LevelGenerator.meta(50)

    /// Görünüm her kuruluşta taze okur (galibiyet sonrası dönüşte kilit açılmış olur).
    private let unlockedLevel = Persistence.unlockedLevel

    /// Zorluk paneli açık olan seviye; nil = panel kapalı. Karta basınca açılır,
    /// seçim/dışına dokunma/X kapatır — seçim onPlay(level, difficulty)'ye gider.
    @State private var pickerLevel: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        ZStack {
            Theme.bgDark.ignoresSafeArea()
            VStack(spacing: 12) {
                ZStack {
                    Text("SEFER")
                        .font(.system(size: 34, weight: .black, design: .serif))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                    HStack {
                        Button(action: onClose) {
                            Label("Geri", systemImage: "chevron.left")
                                .font(.system(.callout, design: .rounded).bold())
                        }
                        .buttonStyle(CommandButtonStyle())
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Self.levels, id: \.id) { meta in
                            LevelCard(id: meta.id,
                                      name: meta.name,
                                      hasRiver: meta.hasRiver,
                                      stars: Persistence.stars(level: meta.id),
                                      wonDifficulties: Self.wonDifficulties(level: meta.id),
                                      locked: meta.id > unlockedLevel,
                                      onPlay: { pickerLevel = meta.id })
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            // Zorluk seçimi: açık seviye kartına basınca beliren mini panel.
            if let level = pickerLevel,
               let meta = Self.levels.first(where: { $0.id == level }) {
                DifficultyPickerOverlay(
                    level: level,
                    name: meta.name,
                    onPick: { difficulty, mutators in
                        pickerLevel = nil
                        onPlay(level, difficulty, mutators)
                    },
                    onClose: { pickerLevel = nil })
            }
        }
    }

    /// Bu seviyede kazanılmış kademeler (kart pip'leri + panel ✓ işaretleri için).
    static func wonDifficulties(level: Int) -> Set<Difficulty> {
        Set(Difficulty.allCases.filter { Persistence.seferWon(level: level, difficulty: $0) })
    }
}

/// Kademeye özgü vurgu rengi — kart pip'leri, panel satırları ve ResultOverlay
/// kapsülü aynı paleti paylaşır (normal→yeşil, zor→amber, cokZor→turuncu, kabus→mor).
extension Difficulty {
    var tint: Color {
        switch self {
        case .normal: Color(red: 0.36, green: 0.65, blue: 0.32)   // yeşil
        case .zor: Theme.accent                                    // amber
        case .cokZor: Color(red: 0.89, green: 0.45, blue: 0.18)   // turuncu
        case .kabus: Color(red: 0.62, green: 0.38, blue: 0.85)    // mor
        }
    }

    /// "14 ❤️ · ×1.5 🪙" — can + Hazine çarpanı özeti (panel satır altyazısı).
    var summaryText: String {
        "\(startingLives) ❤️ · ×\(Self.trimmed(treasuryMultiplier)) 🪙"
    }

    fileprivate static func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }
}

/// Zorluk seçim paneli: karartılmış zemin (dışına dokunma kapatır) üstünde
/// commandPanel parşömeni — seviye adı, X, 4 kademe satırı ve Başlat. Kâbus,
/// o seviyede diğer üç kademe kazanılmadan kilitlidir. E4: satıra dokunmak
/// SEÇER (hemen oynatmaz); seçili kademenin hemen altında, o seviye+kademe
/// daha önce kazanıldıysa açılır "Mutatörler" bölümü belirir; Başlat seçimle
/// oynatır. Panel altında birleşik Hazine çarpanı önizlemesi durur.
private struct DifficultyPickerOverlay: View {
    let level: Int
    let name: String
    let onPick: (Difficulty, [Mutator]) -> Void
    let onClose: () -> Void

    @State private var selected: Difficulty = .normal
    /// Açılır bölüm durumu; kapalı başlar (panel sade kalır).
    @State private var mutatorsExpanded = false
    /// İşaretlenen mutatörler — kademe değişse de hatırlanır; Başlat yalnız
    /// bölüm GÖRÜNÜRKEN (kazanılmış kademe) uygular.
    @State private var chosen: Set<Mutator> = []

    private var won: Set<Difficulty> { CampaignView.wonDifficulties(level: level) }
    /// Kâbus ön koşulu: normal + zor + cokZor üçü de BU seviyede kazanılmış olmalı.
    private var kabusUnlocked: Bool {
        won.isSuperset(of: [.normal, .zor, .cokZor])
    }

    /// Mutatör kapısı: O SEVİYE + O KADEME daha önce kazanılmış olmalı
    /// (Persistence.seferWon) — körlemesine ×4 Hazine kasması yok.
    private var mutatorsAvailable: Bool { won.contains(selected) }

    /// Başlat'a giden etkin liste: kapı kapalıysa boş; sabit enum sırasında.
    private var activeMutators: [Mutator] {
        mutatorsAvailable ? Mutator.allCases.filter(chosen.contains) : []
    }

    private var totalMultiplierText: String {
        Difficulty.trimmed(Mutator.treasuryMultiplier(difficulty: selected,
                                                      mutators: activeMutators))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                ZStack {
                    Text("Seviye \(level) — \(name)")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(Theme.inkPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 30)
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kapat")
                    }
                }
                Text("Zorluk seç")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(Theme.inkSecondary)
                    .tracking(2)
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    DifficultyRow(difficulty: difficulty,
                                  won: won.contains(difficulty),
                                  locked: difficulty == .kabus && !kabusUnlocked,
                                  isSelected: difficulty == selected,
                                  onSelect: { selected = difficulty })
                    // Mutatör bölümü SEÇİLİ satırın hemen altında — yalnız kapı açıkken.
                    if difficulty == selected && mutatorsAvailable {
                        MutatorSection(expanded: $mutatorsExpanded, chosen: $chosen)
                    }
                }
                // Birleşik Hazine çarpanı önizlemesi + Başlat.
                HStack {
                    Text("Toplam: ×\(totalMultiplierText) 🪙")
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(Theme.inkAccent)
                        .accessibilityLabel("Toplam Hazine çarpanı \(totalMultiplierText)")
                    Spacer()
                    Button(action: { onPick(selected, activeMutators) }) {
                        Label("Başlat", systemImage: "play.fill")
                            .font(.system(.body, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle(prominent: true))
                    .accessibilityLabel("\(selected.label) zorlukta başlat"
                        + (activeMutators.isEmpty ? ""
                           : ", mutatörler: "
                             + activeMutators.map(\.label).joined(separator: ", ")))
                }
                .padding(.top, 4)
            }
            .padding(18)
            .frame(maxWidth: 380)
            .commandPanel()
            .padding(40)
        }
    }
}

/// Açılır "Mutatörler" bölümü: başlık satırı (chevron + seçim sayısı) ve
/// açıkken beş toggle satırı (ikon + ad + açıklama + ×N rozeti).
private struct MutatorSection: View {
    @Binding var expanded: Bool
    @Binding var chosen: Set<Mutator>

    var body: some View {
        VStack(spacing: 6) {
            Button(action: { withAnimation(.spring(duration: 0.25)) { expanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("Mutatörler")
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(Theme.inkPrimary)
                    if !chosen.isEmpty {
                        Text(Mutator.allCases.filter(chosen.contains)
                            .map(\.icon).joined())
                            .font(.system(size: 13))
                    }
                    Spacer()
                    Text("gönüllü zorluk — daha çok Hazine")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mutatörler bölümü, \(chosen.count) seçili, "
                + (expanded ? "açık" : "kapalı"))
            if expanded {
                ForEach(Mutator.allCases, id: \.self) { mutator in
                    MutatorToggleRow(mutator: mutator,
                                     isOn: chosen.contains(mutator),
                                     onToggle: {
                        if chosen.contains(mutator) {
                            chosen.remove(mutator)
                        } else {
                            chosen.insert(mutator)
                        }
                    })
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color.black.opacity(0.06)))
        .padding(.leading, 14)   // seçili kademe satırının "altı" hissi — hafif içerlek
    }
}

/// Tek mutatör toggle satırı: ikon + ad + açıklama + Hazine rozeti; işaretliyse
/// dolgulu onay kutusu ve vurgulu çerçeve.
private struct MutatorToggleRow: View {
    let mutator: Mutator
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isOn ? Theme.inkAccent : Theme.inkSecondary)
                Text(mutator.icon).font(.system(size: 15))
                VStack(alignment: .leading, spacing: 1) {
                    Text(mutator.label)
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(Theme.inkPrimary)
                    Text(mutator.desc)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Text("×\(Difficulty.trimmed(mutator.treasuryMultiplier))")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(Theme.inkAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.inkAccent.opacity(0.14)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isOn ? Theme.inkAccent.opacity(0.10) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isOn ? Theme.inkAccent.opacity(0.5)
                                   : Color.black.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mutator.label): \(mutator.desc), "
            + "Hazine çarpanı \(mutator.treasuryMultiplier)"
            + (isOn ? ", seçili" : ""))
    }
}

/// Tek kademe satırı: renk noktası + etiket (+✓ kazanıldıysa) + can/ödül özeti.
/// E4: dokunmak SEÇER (Başlat oynatır); seçili satır kalın çerçeve + dolgun
/// zemin alır. Kilitliyse 🔒 + gri + tıklanamaz; altyazı ön koşulu söyler.
private struct DifficultyRow: View {
    let difficulty: Difficulty
    let won: Bool
    let locked: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(locked ? Color.gray.opacity(0.5) : difficulty.tint)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(difficulty.label)
                            .font(.system(.body, design: .rounded).bold())
                            .foregroundStyle(locked ? Theme.inkSecondary : Theme.inkPrimary)
                        if difficulty == .kabus { Text("💀").font(.system(size: 13)) }
                        if won {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(difficulty.tint)
                        }
                    }
                    Text(locked ? "Önce diğer üç zorluğu tamamla" : difficulty.summaryText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(locked ? Color.black.opacity(0.08)
                             : difficulty.tint.opacity(isSelected ? 0.26 : 0.14)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(locked ? Color.black.opacity(0.15)
                                     : difficulty.tint.opacity(isSelected ? 1.0 : 0.6),
                              lineWidth: isSelected ? 2 : 1.2))
            .opacity(locked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(locked
            ? "\(difficulty.label) kilitli — önce diğer üç zorluğu tamamla"
            : "\(difficulty.label): \(difficulty.startingLives) can, "
              + "Hazine çarpanı \(difficulty.treasuryMultiplier)"
              + (won ? ", kazanıldı" : "")
              + (isSelected ? ", seçili" : ""))
    }
}

/// Tek seviye kartı: büyük numara + üretilmiş ad + yıldızlar; nehirli haritada 💧.
/// Kilitliyse gri, kilit ikonu ve tıklanamaz.
private struct LevelCard: View {
    let id: Int
    let name: String
    let hasRiver: Bool
    let stars: Int
    /// Bu seviyede kazanılmış kademeler — yıldız altı pip rozetleri; boşsa satır gizli.
    let wonDifficulties: Set<Difficulty>
    let locked: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text("\(id)")
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundStyle(locked ? Theme.textSecondary : Theme.textPrimary)
                    if hasRiver {
                        Text("💧").font(.system(size: 12))
                    }
                }
                Text(name)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(starText)
                    .font(.system(size: 13))
                    .foregroundStyle(stars > 0 ? Theme.accent : Theme.textSecondary.opacity(0.6))
                // Kademe rozetleri: 4 pip — kazanılan kademe kendi renginde dolu,
                // kazanılmayan soluk halka. Hiç kazanım yoksa satır tamamen gizli.
                if !wonDifficulties.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Difficulty.allCases, id: \.self) { difficulty in
                            Circle()
                                .fill(wonDifficulties.contains(difficulty)
                                      ? difficulty.tint
                                      : Color.white.opacity(0.12))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: locked ? [Theme.panel.opacity(0.35), Theme.bgDark.opacity(0.5)]
                                   : [Theme.panelTop, Theme.panel],
                    startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(locked ? Theme.outline.opacity(0.4)
                                     : Theme.accent.opacity(0.5),
                              lineWidth: 1))
            .opacity(locked ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(locked ? "Seviye \(id) kilitli"
                                   : "Seviye \(id): \(name), \(stars) yıldız")
    }

    /// ★ dolu / ☆ boş — Text yeterli, ikon yükü yok.
    private var starText: String {
        String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars)
    }
}
