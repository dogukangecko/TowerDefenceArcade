import GameCore
import SwiftUI

/// Menüden erişilen "Nasıl Oynanır" ekranı — güncel kipleri anlatır:
/// Sefer (zorluk + yıldız), Günlük, Sonsuz, kule yönetimi, Mağaza, mutatörler.
struct HowToPlayView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.059, green: 0.078, blue: 0.047), Theme.panel],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("NASIL OYNANIR")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.accent)

                    // commandPanel parşömeni açık renkli — panel içi metinler koyu (ink*).
                    section("🎯 Amaç",
                            "Düşmanlar yol boyunca üssüne yürür; kulelerini yol kenarına kur ve "
                            + "tüm dalgaları atlat. Her sızan düşman can götürür (boss daha çok) — "
                            + "canın biterse üs düşer.")

                    section("🗺️ Sefer",
                            "50 seviyelik ana yolculuk: her zafer sıradaki seviyenin kilidini açar, "
                            + "kalan canına göre 1–3 yıldız kazanırsın. Dört zorluk kademesi var — "
                            + "Normal, Zor, Çok Zor ve Kâbus; kademe yükseldikçe canın azalır ama "
                            + "Hazine ödülü katlanır (×3'e dek). Kâbus, o seviyeyi diğer üç kademede "
                            + "kazanınca açılır.")

                    section("📅 Günlük Meydan Okuma",
                            "Her gün herkese aynı, o güne özel üretilmiş tek seviye. Gün başına "
                            + "TEK deneme hakkın var — kazan ya da kaybet, Hazine ödülü ×2 işler.")

                    section("♾️ Sonsuz Mod",
                            "İki arenadan birini seç; dalgalar bitmez, her 10. dalgada boss gelir "
                            + "ve düşmanlar giderek güçlenir. Amaç tek: rekor dalgaya ulaşmak — "
                            + "arenanın en iyisi menü kartında yazar.")

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            towerCard(kind: .machineGun, role: "Hızlı ateş, ucuz başlangıç")
                            towerCard(kind: .rocket, role: "Alan hasarı, kalabalık kontrolü")
                            towerCard(kind: .sniper, role: "Uzun menzil, ağır hasar")
                            towerCard(kind: .dart, role: "Hızlı dikenler, orta menzil")
                        }
                        HStack(spacing: 12) {
                            towerCard(kind: .crystal, role: "Tek hedefe çok yüksek hasar")
                            towerCard(kind: .shock, role: "Çok hızlı, kısa menzil")
                            towerCard(kind: .orb, role: "Orta alan hasarı")
                            towerCard(kind: .solar, role: "Pahalı; geniş alana güneş patlaması")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        tip("Dalgalar arası inşa süresi sınırsız — aceleye gerek yok")
                        tip("Kule kurmak için boş kareye dokun ya da karttan sürükle-bırak")
                        tip("Kuleler 2 kez yükseltilir, %70 iadeyle satılır")
                        tip("Hedefleme modu kule panelinden değişir: İlk / Güçlü / Yakın")
                        tip("Sıradaki dalganın içeriği üst şeritte yazar")
                        tip("Hız düğmesiyle savaşı 2x ve 3x'e çıkarabilirsin")
                        tip("Boss dalgalarında Burç Yayı ve Kristal bulundur!")
                    }
                    .commandPanel()

                    section("🪙 Mağaza",
                            "Her oyunun sonunda kalıcı Hazine kazanırsın. Mağazadan tur başı "
                            + "bonuslar (başlangıç altını, ekstra can, hasar/menzil artışı…) ve "
                            + "kule görünümleri/harita temaları alınır; bonuslar istenirse "
                            + "kapatılabilir.")

                    section("🎲 Mutatörler",
                            "Kazandığın Sefer seviyelerinde gönüllü zorluk anahtarları: hızlı "
                            + "düşmanlar, yükseltme yasağı, tek can gibi kurallar ekler — karşılığında "
                            + "Hazine çarpanını büyütür (toplamda ×4'e dek).")

                    section("🏆 Başarımlar",
                            "Zaferler, rekorlar ve koleksiyon hedefleri menüdeki Başarımlar "
                            + "vitrininde birikir.")

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

    /// Parşömen panelinde başlık + gövde — tüm kip bölümleri aynı kalıptan.
    private func section(_ title: String, _ body: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(.headline, design: .rounded).bold())
                .foregroundStyle(Theme.inkAccent)
            Text(body)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.inkPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 560)
        .commandPanel()
    }

    private func towerCard(kind: TowerKind, role: String) -> some View {
        VStack(spacing: 6) {
            bundleImage(AssetName.portrait(kind))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(height: 44)
            Text(towerName(kind))
                .font(.system(.callout, design: .rounded).bold())
                .foregroundStyle(Theme.inkPrimary)
            Text(role)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Label("\(Balance.cost(of: kind))", systemImage: "dollarsign.circle")
                .font(.system(.caption, design: .rounded).bold())
                .foregroundStyle(Theme.inkAccent)
        }
        .frame(width: 150)
        .commandPanel()
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(Theme.inkPrimary)
    }

    private func towerName(_ kind: TowerKind) -> String {
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
