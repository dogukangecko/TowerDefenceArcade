/// ÜRETİLMİŞ DOSYA — elle düzenlemeyin.
/// Üretici: `swift run -c release BalanceLab ayar` (v3 — H1b).
/// dByLevel: kompozisyon kaynağı (formül D değerleri; üreteç bütçeye 1.3
/// tavanıyla sokar — çeşitlilik ekseni). hpMultByTier: kademe başına birim HP
/// çarpanı eğrisi (anahtar Difficulty.rawValue) — asıl zorluk kaldıracı.
/// normal/zor/cokZor: GreedyPolicy bütçe oranları {0.8, 0.9, 1.0} medyanı
/// kademenin kendi hedef bandına oturana dek ikili aramayla ayarlanır
/// (kademe can/maliyet kimliği simde ETKİN). kabus: kazanılabilirlik-öncelikli —
/// en az BİR varyantın kazandığı en büyük çarpan; 1.0 bile kazanılamazsa
/// 0.85 tabanına dek aşağı kelepçelenir (kimlik 3 candan gelir).
/// Çarpan gelir-nötrdür (ödül/can bedeli taban kalır).
/// Harita topolojisi her ikisinden de bağımsızdır.
public enum TunedDifficulty {
    public static let dByLevel: [Double] = [
        1.000, 1.000, 1.000, 1.000, 1.000, 1.150, 1.150, 1.150, 1.150, 1.150,
        1.300, 1.300, 1.300, 1.300, 1.300, 1.450, 1.450, 1.450, 1.450, 1.450,
        1.600, 1.600, 1.600, 1.600, 1.600, 1.750, 1.750, 1.750, 1.750, 1.750,
        1.900, 1.900, 1.900, 1.900, 1.900, 2.050, 2.050, 2.050, 2.050, 2.050,
        2.200, 2.200, 2.200, 2.200, 2.200, 2.200, 2.200, 2.200, 2.200, 2.200,
    ]

    /// Kademe başına birim HP çarpanı (H1b): motor düşman HP'sini
    /// LevelGenerator.hpMultiplier(_:difficulty:) üzerinden bununla ölçekler.
    public static let hpMultByTier: [String: [Double]] = [
        "normal": [
            1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000,
            3.500, 2.875, 3.188, 2.875, 3.500, 2.250, 2.250, 2.875, 2.875, 3.383,
            2.875, 3.500, 2.250, 2.250, 2.250, 2.250, 2.250, 2.250, 2.250, 2.250,
            2.875, 3.500, 3.500, 3.188, 3.500, 2.875, 3.500, 2.875, 3.500, 3.500,
            3.500, 2.875, 3.500, 3.500, 2.875, 2.875, 3.500, 3.188, 3.500, 3.188,
        ],
        "zor": [
            1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000,
            3.500, 2.875, 3.188, 2.875, 3.500, 2.250, 2.875, 3.188, 2.875, 3.383,
            2.875, 3.500, 2.250, 2.875, 2.250, 2.250, 2.250, 2.250, 2.875, 2.875,
            2.875, 2.875, 3.500, 3.188, 3.031, 2.563, 3.500, 2.875, 3.500, 3.500,
            2.875, 2.875, 3.500, 3.500, 2.875, 2.250, 3.500, 3.031, 3.344, 3.188,
        ],
        "cokZor": [
            1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000,
            2.875, 2.875, 3.188, 2.250, 2.875, 2.250, 2.250, 2.250, 2.250, 2.875,
            2.250, 3.500, 2.250, 2.250, 2.250, 1.625, 2.250, 2.250, 2.250, 2.250,
            2.563, 2.563, 2.875, 2.875, 2.563, 2.602, 2.875, 2.250, 2.875, 3.188,
            2.875, 2.563, 2.875, 2.875, 2.563, 2.250, 3.393, 2.563, 2.875, 2.875,
        ],
        "kabus": [
            2.550, 2.141, 2.849, 2.520, 3.085, 2.400, 2.650, 2.604, 2.313, 2.200,
            2.550, 2.742, 3.120, 2.740, 2.849, 1.542, 2.400, 2.400, 2.400, 3.085,
            2.475, 3.350, 2.057, 2.400, 2.057, 2.057, 2.100, 1.542, 2.400, 2.150,
            2.100, 2.250, 2.700, 2.200, 2.100, 2.350, 2.400, 2.127, 2.400, 2.949,
            2.400, 2.279, 2.400, 2.571, 2.100, 1.800, 3.026, 2.279, 2.313, 2.450,
        ],
    ]
}
