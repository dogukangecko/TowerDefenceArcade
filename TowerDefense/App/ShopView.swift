import SwiftUI

/// Menüden erişilen Mağaza: katalog item'ları kalıcı Hazine ile satın alınır.
/// Katalog CatalogClient'tan (canlı → önbellek → bundle); sahiplik tek seferliktir.
struct ShopView: View {
    let onClose: () -> Void
    @EnvironmentObject private var client: CatalogClient

    /// Hazine ve sahiplik yerel kopyaları — satın alımda rozet/kartlar canlı güncellenir.
    @State private var treasury = Persistence.treasury
    @State private var owned = Persistence.ownedItems
    /// Oyuncunun kapattığı bonuslar (zorluk tercihi) — kart üstünden açılıp kapanır.
    @State private var disabled = Persistence.disabledItems
    /// Kuşanılı görünümler (assetKey) — KUŞAN/KUŞANILDI kartları canlı güncellenir.
    @State private var equippedSkin = Persistence.equippedSkin
    @State private var equippedTheme = Persistence.equippedTheme
    /// Obsidyen ödülü (E2): kilit + Kâbus zafer sayısı — mağaza açılırken okunur
    /// (mağazadayken değişemez; katalog/satın alma akışından tamamen bağımsız).
    private let obsidyenUnlocked = Persistence.obsidyenUnlocked
    private let kabusWinCount = Persistence.kabusWinCount
    /// Başarılı satın alımda pulse atan kartın id'si.
    @State private var pulsingID: String?
    /// Başarısız denemede sarsılan kartın id'si + animasyon tetiği.
    @State private var shakingID: String?
    @State private var shakeCount = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.059, green: 0.078, blue: 0.047), Theme.panel],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("MAĞAZA")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.accent)

                    // Hazine rozeti + katalog sürümü + Yenile.
                    HStack(spacing: 14) {
                        Text("🪙 \(treasury)")
                            .font(.system(.title3, design: .rounded).bold())
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.bgDark.opacity(0.6)))
                            .overlay(Capsule().strokeBorder(Theme.outline.opacity(0.7), lineWidth: 1))
                        Text("v\(client.catalog.version)")
                            .font(.system(.footnote, design: .rounded).bold())
                            .foregroundStyle(Theme.textSecondary)
                        if client.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.accent)
                        } else {
                            Button {
                                Task { await client.refresh() }
                            } label: {
                                Label("Yenile", systemImage: "arrow.clockwise")
                                    .font(.system(.callout, design: .rounded).bold())
                            }
                            .buttonStyle(CommandButtonStyle())
                        }
                    }

                    // Kâbus ödül kartı — katalog ürünlerinin ÜSTÜNE sabitlenir;
                    // mağaza ürünü DEĞİL (satın alınamaz, sahiplik = kilit durumu).
                    ObsidianRewardCard(unlocked: obsidyenUnlocked,
                                       winCount: kabusWinCount,
                                       equipped: equippedSkin == "obsidyen",
                                       onEquip: { equipObsidian() })

                    if client.catalog.items.isEmpty {
                        Text("Katalog boş — bağlantıyı kontrol edip Yenile'ye bas.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 30)
                    }

                    ForEach(client.catalog.items) { item in
                        ShopItemCard(item: item,
                                     ownedItem: owned.contains(item.id),
                                     enabled: !disabled.contains(item.id),
                                     equipped: isEquipped(item),
                                     affordable: treasury >= item.priceGold,
                                     onBuy: { buy(item) },
                                     onToggle: { toggle(item) },
                                     onEquip: { equip(item) })
                            .scaleEffect(pulsingID == item.id ? 1.05 : 1.0)
                            .modifier(ShakeEffect(
                                animatableData: CGFloat(shakingID == item.id ? shakeCount : 0)))
                    }

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

    private func buy(_ item: CatalogItem) {
        if Persistence.purchase(item) {
            SoundPlayer.shared.play("coin")
            treasury = Persistence.treasury
            owned = Persistence.ownedItems
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                pulsingID = item.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if pulsingID == item.id { pulsingID = nil }
                }
            }
        } else {
            // Yetersiz Hazine (düğme normalde kapalı ama yarış olasılığına karşı) → sarsıntı.
            shakingID = item.id
            withAnimation(.linear(duration: 0.35)) { shakeCount += 1 }
        }
    }

    /// Sahip olunan bonusu aç/kapat — kapatmak zorluğu artırmak isteyen oyuncunun tercihi.
    private func toggle(_ item: CatalogItem) {
        Persistence.toggleItemEnabled(item.id)
        withAnimation(.spring(duration: 0.25)) {
            disabled = Persistence.disabledItems
        }
        SoundPlayer.shared.play("click")
    }

    // MARK: - Kuşanma (skin / tema)

    private func isEquipped(_ item: CatalogItem) -> Bool {
        guard let key = item.assetKey else { return false }
        switch item.kind {
        case "skin": return equippedSkin == key
        case "theme": return equippedTheme == key
        default: return false
        }
    }

    /// KUŞAN: seti/temayı giy; kuşanılıyken tekrar basmak çıkarır (nil = orijinal).
    private func equip(_ item: CatalogItem) {
        guard let key = item.assetKey else { return }
        withAnimation(.spring(duration: 0.25)) {
            switch item.kind {
            case "skin":
                Persistence.equippedSkin = (Persistence.equippedSkin == key) ? nil : key
                equippedSkin = Persistence.equippedSkin
            case "theme":
                Persistence.equippedTheme = (Persistence.equippedTheme == key) ? nil : key
                equippedTheme = Persistence.equippedTheme
            default:
                break
            }
        }
        SoundPlayer.shared.play("click")
    }

    /// Obsidyen kuşanması — katalog ürünlerinden bağımsız: kilit obsidyenUnlocked,
    /// görünüm anahtarı sabit "obsidyen" (TextureBank skin_obsidyen_* öneki).
    /// Kuşanılıyken tekrar basmak çıkarır (nil = orijinal görünüm).
    private func equipObsidian() {
        withAnimation(.spring(duration: 0.25)) {
            Persistence.equippedSkin =
                (Persistence.equippedSkin == "obsidyen") ? nil : "obsidyen"
            equippedSkin = Persistence.equippedSkin
        }
        SoundPlayer.shared.play("click")
    }
}

/// Kâbus ödül kartı (E2): siyah-mor degrade, 💀 — satın alınamaz, 50 Kâbus
/// zaferiyle açılır. Kilitliyken ilerleme çubuğu (n/50), açıkken KUŞAN/KUŞANILDI.
private struct ObsidianRewardCard: View {
    let unlocked: Bool
    let winCount: Int
    let equipped: Bool
    let onEquip: () -> Void

    /// Kart vurgu moru — degrade kenarı, ilerleme dolgusu ve rozet aynı tonu paylaşır.
    private let purple = Color(red: 0.56, green: 0.27, blue: 0.86)

    var body: some View {
        HStack(spacing: 14) {
            Text("💀")
                .font(.system(size: 44))
                .frame(width: 64)
                .saturation(unlocked ? 1 : 0.4)
            // Kart zemini KOYU (siyah-mor) — metinler açık tonlarda kalmalı
            // (katalog kartlarının parşömen/ink düzeninin tersi).
            VStack(alignment: .leading, spacing: 3) {
                Text("Obsidyen Seti")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.white)
                Text("50 Kâbus zaferinin ödülü")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                if unlocked {
                    Text("Görünüm seti")
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(purple.opacity(0.95))
                } else {
                    // İlerleme çubuğu: mor dolgu, n/50.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(purple)
                                .frame(width: max(
                                    0, geo.size.width * CGFloat(winCount) / 50))
                        }
                    }
                    .frame(height: 8)
                    .padding(.top, 5)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                if unlocked {
                    Button(action: onEquip) {
                        HStack(spacing: 6) {
                            Image(systemName: equipped ? "person.fill.checkmark" : "tshirt")
                            Text(equipped ? "KUŞANILDI" : "KUŞAN")
                        }
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(equipped ? Theme.bgDark : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(
                            equipped ? Theme.accent : purple.opacity(0.35)))
                        .overlay(Capsule().strokeBorder(
                            equipped ? Color.white.opacity(0.5)
                                     : purple.opacity(0.8), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(equipped ? "Çıkar (orijinal görünüme dön)" : "Bu görünümü kuşan")
                    Text(equipped ? "Kuşanıldı" : "Açıldı")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(winCount)/50")
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 620)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [Color(red: 0.13, green: 0.05, blue: 0.21),
                             Color(red: 0.03, green: 0.02, blue: 0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(purple.opacity(unlocked ? 0.8 : 0.45), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            Text("ÖDÜL")
                .font(.system(.caption2, design: .rounded).bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(purple))
                .offset(x: -14, y: -8)
        }
        .shadow(color: purple.opacity(0.25), radius: 8, y: 2)
    }
}

/// Tek mağaza kartı: ikon, ad/açıklama/etki, fiyat ve Satın Al / SAHİPSİN durumu.
private struct ShopItemCard: View {
    let item: CatalogItem
    let ownedItem: Bool
    /// Sahip olunan bonus şu an açık mı (kapalıysa yeni oyunlara uygulanmaz).
    let enabled: Bool
    /// Skin/tema kartı: şu an kuşanılı mı (Persistence.equippedSkin/Theme == assetKey).
    let equipped: Bool
    let affordable: Bool
    let onBuy: () -> Void
    let onToggle: () -> Void
    let onEquip: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(item.icon)
                .font(.system(size: 44))
                .frame(width: 64)
            // ui_panel parşömeni AÇIK renkli — kart metinleri koyu tonlarda kalmalı.
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(Theme.inkPrimary)
                Text(item.desc)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                Text(effectLabel)
                    .font(.system(.callout, design: .rounded).bold())
                    .foregroundStyle(Theme.inkAccent)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Text("🪙 \(item.priceGold)")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(Theme.inkPrimary)
                if ownedItem, item.kind != "item" {
                    // Skin/tema: KUŞAN giyer; kuşanılıyken basmak çıkarır (orijinale döner).
                    Button(action: onEquip) {
                        HStack(spacing: 6) {
                            Image(systemName: equipped ? "person.fill.checkmark" : "tshirt")
                            Text(equipped ? "KUŞANILDI" : "KUŞAN")
                        }
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(equipped ? Theme.bgDark : Theme.inkAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(
                            equipped ? Theme.accent : Color.black.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(
                            equipped ? Color.white.opacity(0.5)
                                     : Theme.inkAccent.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(equipped ? "Çıkar (orijinal görünüme dön)" : "Bu görünümü kuşan")
                    Text(equipped ? "Kuşanıldı" : "Sahipsin")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                } else if ownedItem {
                    // Aç/kapa: kapatınca bonus yeni oyunlara uygulanmaz (zorluk tercihi).
                    Button(action: onToggle) {
                        HStack(spacing: 6) {
                            Image(systemName: enabled ? "checkmark.circle.fill" : "slash.circle")
                            Text(enabled ? "AKTİF" : "KAPALI")
                        }
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundStyle(enabled ? Color(red: 0.16, green: 0.45, blue: 0.18)
                                                 : Theme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(
                            enabled ? Color.green.opacity(0.15) : Color.black.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(
                            enabled ? Color(red: 0.16, green: 0.45, blue: 0.18).opacity(0.6)
                                    : Theme.inkSecondary.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(enabled ? "Bonusu kapat (zorluğu artır)" : "Bonusu tekrar aç")
                    Text(enabled ? "Sahipsin" : "Kapalı — uygulanmıyor")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Button(action: onBuy) {
                        Text("Satın Al")
                            .font(.system(.callout, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle(prominent: true))
                    .disabled(!affordable)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 620)
        .background(NineSlice(name: "ui_panel").opacity(0.96))
        .overlay(alignment: .topTrailing) {
            if item.premium {
                Text("PREMIUM")
                    .font(.system(.caption2, design: .rounded).bold())
                    .foregroundStyle(Theme.bgDark)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent))
                    .offset(x: -14, y: -8)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    /// Etki etiketi: startGold→"+N başlangıç altını", towerDamage→"+%N kule hasarı",
    /// extraLives→"+N can"; skin/tema kartları tür etiketi gösterir;
    /// bilinmeyen type fiyat-etiketinde gizlenir (ileri uyumluluk).
    private var effectLabel: String {
        switch item.kind {
        case "skin": return "Görünüm seti"
        case "theme": return "Harita teması"
        default: break
        }
        return switch item.effect.type {
        case "startGold": "+\(Int(item.effect.value)) başlangıç altını"
        case "towerDamage": "+%\(Int((item.effect.value * 100).rounded())) kule hasarı"
        case "extraLives": "+\(Int(item.effect.value)) can"
        default: ""
        }
    }
}

/// Yatay sarsıntı — başarısız satın alma geri bildirimi.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 6
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * shakesPerUnit * 2), y: 0))
    }
}
