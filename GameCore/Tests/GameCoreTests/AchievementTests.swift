import XCTest
@testable import GameCore

/// E5 Başarımlar: 11 tanımlık katalog + saf değerlendirme motoru.
/// Her kural pozitif+negatif; already filtreleme; çoklu aynı anda kazanım.
final class AchievementTests: XCTestCase {

    /// Hiçbir başarımı tetiklemeyen taban bağlam; testler tek alanı oynatır.
    private func ctx(won: Bool = false,
                     leaks: Int = 5,
                     kinds: Set<TowerKind> = [.machineGun, .rocket],
                     built: Int = 6,
                     difficulty: Difficulty = .normal,
                     mode: AchievementContext.Mode = .freePlay,
                     reachedWave: Int = 7,
                     normalPlus: Int = 0,
                     kabusWins: Int = 0,
                     treasury: Int = 0,
                     totalKills: Int = 0,
                     dailyWins: Int = 0,
                     bestEndless: Int = 0) -> AchievementContext {
        AchievementContext(won: won, leaks: leaks, towerKindsUsed: kinds,
                           towersBuilt: built, difficulty: difficulty, mode: mode,
                           reachedWave: reachedWave, normalPlusWinLevels: normalPlus,
                           kabusWinLevels: kabusWins, treasury: treasury,
                           totalKills: totalKills, dailyWins: dailyWins,
                           bestEndlessWave: bestEndless)
    }

    private func ids(_ ctx: AchievementContext,
                     already: Set<String> = []) -> Set<String> {
        Set(AchievementEngine.evaluate(ctx, already: already).map(\.id))
    }

    // MARK: - Katalog

    func testCatalogHasElevenWellFormedDefinitions() {
        let all = AchievementEngine.all
        XCTAssertEqual(all.count, 11)
        XCTAssertEqual(all.map(\.id),
                       ["ilk-zafer", "kusursuz", "tek-tip", "spartali",
                        "kabus-avcisi", "sefer-fatihi", "obsidyen-efendisi",
                        "zengin", "katliam", "dalga-ustasi", "mudavim"])
        for a in all {
            XCTAssertFalse(a.title.isEmpty, "\(a.id) başlık boş")
            XCTAssertFalse(a.desc.isEmpty, "\(a.id) açıklama boş")
            XCTAssertFalse(a.icon.isEmpty, "\(a.id) ikon boş")
        }
        XCTAssertEqual(Set(all.map(\.icon)).count, all.count, "ikonlar ayrışık olmalı")
    }

    func testBaselineContextEarnsNothing() {
        XCTAssertTrue(ids(ctx()).isEmpty)
    }

    func testIsKabusConvenience() {
        XCTAssertTrue(ctx(difficulty: .kabus).isKabus)
        XCTAssertFalse(ctx(difficulty: .cokZor).isKabus)
    }

    // MARK: - Galibiyet bazlı kurallar

    func testIlkZafer() {
        // Herhangi bir kipte galibiyet yeter.
        XCTAssertTrue(ids(ctx(won: true)).contains("ilk-zafer"))
        XCTAssertTrue(ids(ctx(won: true, mode: .daily)).contains("ilk-zafer"))
        XCTAssertFalse(ids(ctx(won: false)).contains("ilk-zafer"))
    }

    func testKusursuz() {
        XCTAssertTrue(ids(ctx(won: true, leaks: 0)).contains("kusursuz"))
        // Tek can kaybı (boss livesCost>1 → 5 sızıntı sayılır, kabul) bozar.
        XCTAssertFalse(ids(ctx(won: true, leaks: 1)).contains("kusursuz"))
        // Kayıpta sızıntısızlık anlamsız.
        XCTAssertFalse(ids(ctx(won: false, leaks: 0)).contains("kusursuz"))
    }

    func testTekTip() {
        XCTAssertTrue(ids(ctx(won: true, kinds: [.shock], built: 3)).contains("tek-tip"))
        // İki tür → değil; 3'ten az kule → değil (boş zafere verilmez); kayıp → değil.
        XCTAssertFalse(ids(ctx(won: true, kinds: [.shock, .dart], built: 6)).contains("tek-tip"))
        XCTAssertFalse(ids(ctx(won: true, kinds: [.shock], built: 2)).contains("tek-tip"))
        XCTAssertFalse(ids(ctx(won: false, kinds: [.shock], built: 3)).contains("tek-tip"))
    }

    func testSpartali() {
        XCTAssertTrue(ids(ctx(won: true, built: 4)).contains("spartali"))
        XCTAssertFalse(ids(ctx(won: true, built: 5)).contains("spartali"))
        XCTAssertFalse(ids(ctx(won: false, built: 4)).contains("spartali"))
    }

    func testKabusAvcisi() {
        XCTAssertTrue(ids(ctx(won: true, difficulty: .kabus)).contains("kabus-avcisi"))
        XCTAssertFalse(ids(ctx(won: true, difficulty: .cokZor)).contains("kabus-avcisi"))
        XCTAssertFalse(ids(ctx(won: false, difficulty: .kabus)).contains("kabus-avcisi"))
    }

    // MARK: - Kalıcı sayaç bazlı kurallar (galibiyet ŞART DEĞİL)

    func testSeferFatihi() {
        XCTAssertTrue(ids(ctx(normalPlus: 50)).contains("sefer-fatihi"))
        XCTAssertFalse(ids(ctx(normalPlus: 49)).contains("sefer-fatihi"))
    }

    func testObsidyenEfendisi() {
        XCTAssertTrue(ids(ctx(kabusWins: 50)).contains("obsidyen-efendisi"))
        XCTAssertFalse(ids(ctx(kabusWins: 49)).contains("obsidyen-efendisi"))
    }

    func testZengin() {
        XCTAssertTrue(ids(ctx(treasury: 2000)).contains("zengin"))
        XCTAssertFalse(ids(ctx(treasury: 1999)).contains("zengin"))
    }

    func testKatliam() {
        XCTAssertTrue(ids(ctx(totalKills: 5000)).contains("katliam"))
        XCTAssertFalse(ids(ctx(totalKills: 4999)).contains("katliam"))
    }

    func testDalgaUstasi() {
        XCTAssertTrue(ids(ctx(bestEndless: 25)).contains("dalga-ustasi"))
        XCTAssertFalse(ids(ctx(bestEndless: 24)).contains("dalga-ustasi"))
    }

    func testMudavim() {
        XCTAssertTrue(ids(ctx(dailyWins: 3)).contains("mudavim"))
        XCTAssertFalse(ids(ctx(dailyWins: 2)).contains("mudavim"))
    }

    // MARK: - already filtreleme + çoklu kazanım

    func testAlreadyEarnedAreFiltered() {
        let c = ctx(won: true, leaks: 0)
        XCTAssertEqual(ids(c), ["ilk-zafer", "kusursuz"])
        XCTAssertEqual(ids(c, already: ["ilk-zafer"]), ["kusursuz"])
        XCTAssertTrue(ids(c, already: ["ilk-zafer", "kusursuz"]).isEmpty)
    }

    func testMultipleAtOnceInCatalogOrder() {
        // Kusursuz Kâbus zaferi, tek türden tam 3 kule: beş başarım birden.
        let c = ctx(won: true, leaks: 0, kinds: [.crystal], built: 3,
                    difficulty: .kabus, mode: .campaign)
        let earned = AchievementEngine.evaluate(c, already: [])
        XCTAssertEqual(earned.map(\.id),
                       ["ilk-zafer", "kusursuz", "tek-tip", "spartali", "kabus-avcisi"],
                       "katalog sırası korunmalı")
    }
}
