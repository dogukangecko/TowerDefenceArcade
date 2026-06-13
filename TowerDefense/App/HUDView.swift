import GameCore
import SwiftUI

struct HUDView: View {
    @ObservedObject var session: GameSession
    @State private var pulse = false

    var body: some View {
        VStack {
            if session.phase == .building || session.phase == .waveActive {
                topBar
            }
            wavePreview
            tutorialHint
            Spacer()
            bottomPanel
        }
        .padding(12)
    }

    /// Dalga sayacı: sonlu kipte "n/10", Sonsuz'da hedef yok — "Dalga n"
    /// (başlamadan önce yalnız ∞ simgesi).
    private var waveCounterText: String {
        if session.isEndless {
            return session.waveNumber == 0 ? "∞" : "Dalga \(session.waveNumber)"
        }
        return session.waveNumber == 0 ? "–/\(session.totalWaves)"
                                       : "\(session.waveNumber)/\(session.totalWaves)"
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            StatCapsule(icon: "dollarsign.circle.fill", value: "\(session.gold)", tint: Theme.accent)
            StatCapsule(icon: "heart.fill", value: "\(session.lives)", tint: Theme.danger)
            StatCapsule(icon: "water.waves", value: waveCounterText, tint: .cyan)
            Spacer()
            if session.phase == .building {
                Button {
                    session.startWave()
                } label: {
                    Label(session.waveNumber == 0 ? "Dalgayı Başlat" : "Sonraki Dalga",
                          systemImage: "play.fill")
                        .font(.system(.body, design: .rounded).bold())
                }
                .buttonStyle(CommandButtonStyle(prominent: true))
                .disabled(session.isPaused)
            }
            // Otomatik dalga anahtarı: dalga sürerken de görünür — oyuncu ortada fikrini
            // değiştirebilsin diye hız/ses düğmelerinin yanında kalıcı durur.
            Button {
                session.autoWave.toggle()
            } label: {
                Image(systemName: "repeat")
            }
            .buttonStyle(CommandButtonStyle(prominent: session.autoWave))
            .accessibilityLabel("Otomatik dalga")
            Button {
                session.toggleSpeed()
            } label: {
                Text("\(Int(session.gameSpeed))x")
                    .font(.system(.body, design: .rounded).bold())
                    .frame(width: 26)
            }
            .buttonStyle(CommandButtonStyle())
            .accessibilityLabel("Oyun hızı")
            Button {
                session.toggleMute()
            } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(CommandButtonStyle())
            .accessibilityLabel(session.isMuted ? "Sesi Aç" : "Sesi Kapat")
            Button {
                session.isPaused.toggle()
            } label: {
                Image(systemName: session.isPaused ? "play.circle" : "pause.circle")
            }
            .buttonStyle(CommandButtonStyle())
            .accessibilityLabel(session.isPaused ? "Devam Et" : "Duraklat")
        }
        .commandPanel()
    }

    @ViewBuilder
    private var wavePreview: some View {
        if session.phase == .building, let summary = session.upcomingWaveSummary {
            Label("Sıradaki: \(summary)", systemImage: "list.bullet")
                .font(.system(.callout, design: .rounded).bold())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.bgDark.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Theme.outline.opacity(0.5), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var tutorialHint: some View {
        if session.phase == .building, session.tutorialStep != .done {
            Text(session.tutorialStep == .buildTower
                 ? "🏗 Boş bir çim karesine dokun ve ilk kuleni kur"
                 : "▶ Hazırsan sağ üstten Dalgayı Başlat")
                .font(.system(.callout, design: .rounded).bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.bgDark.opacity(0.75)))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.9), lineWidth: 1.5))
                .opacity(pulse ? 1.0 : 0.7)
                .padding(.top, 6)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if session.buildTile != nil {
            buildMenu
        } else if let tower = session.selectedTower {
            towerPanel(tower)
        }
    }

    private var buildMenu: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(TowerKind.allCases, id: \.self) { kind in
                        Button {
                            // İki dokunuşlu inşa: ilk dokunuş menzil önizlemesi,
                            // aynı karta ikinci dokunuş inşa eder; farklı kart önizlemeyi değiştirir.
                            if session.previewKind == kind {
                                session.build(kind)
                                session.previewKind = nil
                            } else {
                                session.previewKind = kind
                            }
                        } label: {
                            VStack(spacing: 4) {
                                bundleImage(AssetName.portrait(kind))
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(height: 44)
                                Text(Self.name(of: kind))
                                    .font(.system(.callout, design: .rounded).bold())
                                    .foregroundStyle(Theme.textPrimary)
                                HStack(spacing: 3) {
                                    Image(systemName: "dollarsign.circle")
                                    // Gerçek fiyat motordan: kademe zammı (Çok Zor/Kâbus) dahil.
                                    Text("\(session.engine.cost(of: kind))")
                                }
                                .font(.system(.caption, design: .rounded).bold())
                                .foregroundStyle(Theme.accent)
                            }
                            .frame(width: 78)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(CommandButtonStyle())
                        // Sürükle-bırak inşa: minimumDistance 8 → düz dokunuş Button'a kalır
                        // (iki-dokunuş akışı bozulmaz), kart haritaya çekilince hayalet doğar.
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                                .onChanged { value in
                                    if session.dragKind != kind { session.dragKind = kind }
                                    session.dragViewPoint = value.location
                                }
                                .onEnded { _ in session.commitDrag() }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.accent,
                                        lineWidth: session.previewKind == kind ? 2.5 : 0)
                        )
                        .disabled(session.gold < session.engine.cost(of: kind))
                    }
                }
            }
            .frame(maxWidth: 700)
            Button("Kapat") { session.buildTile = nil }
                .buttonStyle(CommandButtonStyle())
        }
        .commandPanel()
    }

    private func towerPanel(_ tower: Tower) -> some View {
        HStack(spacing: 12) {
            bundleImage(AssetName.portrait(tower.kind))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(height: 32)
            // commandPanel parşömeni açık renkli — panel üstü düz metinler koyu mürekkep.
            Text("\(Self.name(of: tower.kind))  Sv. \(tower.level)")
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(Theme.inkPrimary)
            if tower.canUpgrade {
                Button {
                    session.upgradeSelected()
                } label: {
                    Label("Yükselt (\(session.engine.upgradeCost(of: tower.kind, toLevel: tower.level + 1)))",
                          systemImage: "arrow.up.circle.fill")
                        .font(.system(.body, design: .rounded).bold())
                }
                .buttonStyle(CommandButtonStyle(prominent: true))
                .disabled(session.gold < session.engine.upgradeCost(of: tower.kind, toLevel: tower.level + 1))
            } else {
                Text("MAKS")
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(Theme.inkAccent)
            }
            Button {
                session.cycleTargeting()
            } label: {
                Text("🎯 \(Self.modeName(tower.targetingMode))")
                    .font(.system(.body, design: .rounded).bold())
            }
            .buttonStyle(CommandButtonStyle())
            Button {
                session.sellSelected()
            } label: {
                let refund = Int((Double(tower.invested) * Balance.sellRefundRate).rounded())
                Label("Sat (+\(refund))", systemImage: "trash")
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(CommandButtonStyle())
            Button("Kapat") { session.selectedTowerID = nil }
                .buttonStyle(CommandButtonStyle())
        }
        .commandPanel()
    }

    private static func modeName(_ mode: TargetingMode) -> String {
        switch mode {
        case .first: "İlk"
        case .strongest: "Güçlü"
        case .nearest: "Yakın"
        }
    }

    private static func name(of kind: TowerKind) -> String {
        switch kind {
        case .machineGun: "Arbalet"
        case .rocket: "Mancınık"
        case .sniper: "Burç Yayı"
        case .crystal: "Kristal"
        case .shock: "Şok"
        case .orb: "Orb"
        case .dart: "Dikenatar"
        case .solar: "Güneş Kulesi"
        }
    }
}
