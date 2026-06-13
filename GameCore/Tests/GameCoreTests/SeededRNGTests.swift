import XCTest
@testable import GameCore

final class SeededRNGTests: XCTestCase {
    /// SplitMix64 standart test vektörleri (seed=0) — xoshiro referans uygulamasından.
    func testSeedZeroProducesKnownSequence() {
        var rng = SeededRNG(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(rng.next(), 0x6E78_9E6A_A1B9_65F4)
        XCTAssertEqual(rng.next(), 0x06C4_5D18_8009_454F)
        XCTAssertEqual(rng.next(), 0xF88B_B8A8_724C_81EC)
        XCTAssertEqual(rng.next(), 0x1B39_896A_51A8_749B)
    }

    func testSameSeedSameSequence() {
        var a = SeededRNG(seed: 0xDEAD_BEEF)
        var b = SeededRNG(seed: 0xDEAD_BEEF)
        for _ in 0..<5 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiffer() {
        var a = SeededRNG(seed: 1)
        var b = SeededRNG(seed: 2)
        let seqA = (0..<5).map { _ in a.next() }
        let seqB = (0..<5).map { _ in b.next() }
        XCTAssertNotEqual(seqA, seqB)
    }
}
