/// E4 — Mutatörler: gönüllü zorluk anahtarları. Yalnız Sefer'de, o seviye + o
/// kademe daha önce KAZANILMIŞSA seçilebilir (UI kuralı); motor hangi kipte
/// olursa olsun verilen listeyi uygular. Ödülü Hazine çarpanıdır: kademe
/// çarpanıyla ÇARPILIR, toplam ×4 ile sınırlanır (treasuryMultiplier(difficulty:mutators:)).
/// rawValue kalıcı kayıt/argümanlarda kullanılabilir — DEĞİŞTİRME.
public enum Mutator: String, CaseIterable, Sendable, Codable {
    case hizliDusmanlar, camKuleler, ucKule, altinKitligi, demirIrade

    // MARK: - Sunum

    public var label: String {
        switch self {
        case .hizliDusmanlar: "Hızlı Düşmanlar"
        case .camKuleler: "Cam Kuleler"
        case .ucKule: "Üç Kule"
        case .altinKitligi: "Altın Kıtlığı"
        case .demirIrade: "Demir İrade"
        }
    }

    public var desc: String {
        switch self {
        case .hizliDusmanlar: "Düşmanlar %30 daha hızlı"
        case .camKuleler: "Kuleler yükseltilemez"
        case .ucKule: "Yalnız Arbalet, Şok ve Dikenatar"
        case .altinKitligi: "Düşman ödülleri %30 kırpılır"
        case .demirIrade: "Tam 1 can — sızıntı yok"
        }
    }

    public var icon: String {
        switch self {
        case .hizliDusmanlar: "💨"
        case .camKuleler: "🔮"
        case .ucKule: "🎯"
        case .altinKitligi: "🪙"
        case .demirIrade: "⚖️"
        }
    }

    // MARK: - Hazine ödülü

    public var treasuryMultiplier: Double {
        switch self {
        case .hizliDusmanlar, .camKuleler, .ucKule: 1.5
        case .altinKitligi, .demirIrade: 2.0
        }
    }

    /// Birleşik Hazine çarpanı: kademe çarpanı × tüm mutatör çarpanlarının
    /// çarpımı, ÜST SINIR ×4 (örn. Kâbus ×3 × Demir İrade ×2 = 6 → 4).
    public static func treasuryMultiplier(difficulty: Difficulty,
                                          mutators: [Mutator]) -> Double {
        min(4.0, mutators.reduce(difficulty.treasuryMultiplier) {
            $0 * $1.treasuryMultiplier
        })
    }

    // MARK: - Oyun kuralı parametreleri (motor okur)

    /// Düşman hızına doğuşta uygulanan çarpan (1.0 = etkisiz).
    public var speedMultiplier: Double {
        self == .hizliDusmanlar ? 1.3 : 1.0
    }

    /// true → upgradeTower her zaman .mutatorForbidden döner.
    public var upgradesDisabled: Bool {
        self == .camKuleler
    }

    /// Dolu ise buildTower yalnız bu türleri kabul eder; nil = filtre yok.
    public var allowedKinds: [TowerKind]? {
        self == .ucKule ? [.machineGun, .shock, .dart] : nil
    }

    /// Düşman ödülüne çarpan (yuvarlanır, taban 1); 1.0 = etkisiz.
    public var bountyMultiplier: Double {
        self == .altinKitligi ? 0.7 : 1.0
    }

    /// Dolu ise tur canını AYNEN bu değere sabitler — kademe canı VE mağaza
    /// extraLives yok sayılır (Demir İrade kimliği: tam 1 can).
    public var livesOverride: Int? {
        self == .demirIrade ? 1 : nil
    }
}
