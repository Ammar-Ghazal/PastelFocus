import XCTest
@testable import PastelFocusCore

final class ThemeTests: XCTestCase {
    func testSixThemesEachWithDarkAndLight() {
        XCTAssertEqual(ThemeCatalog.all.map(\.id), ["space", "cherry-blossom", "rainforest", "snow", "ember", "cyberpunk"])
        for t in ThemeCatalog.all {
            XCTAssertGreaterThanOrEqual(t.palettes.count, 6, t.name)
            XCTAssertTrue(t.palettes.contains { $0.isDark } && t.palettes.contains { !$0.isDark }, t.name)
        }
        XCTAssertEqual(Set(ThemeCatalog.all.map(\.scene)).count, ThemeCatalog.all.count, "each theme has its own scene")
    }

    func testIDsAndNamesAreUniqueAndStable() {
        let ids = ThemeCatalog.allPalettes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for t in ThemeCatalog.all {
            XCTAssertEqual(Set(t.palettes.map(\.name)).count, t.palettes.count, t.name)
            XCTAssertTrue(t.palettes.allSatisfy { $0.id.hasPrefix(t.id + "/") })
        }
        XCTAssertEqual(PaletteBuilder.slug("Will-o'-Wisp"), "will-o-wisp")
        XCTAssertNotNil(ThemeCatalog.theme("space")?.palette("space/saturn-gold"))
    }

    func testOldSelectionsCarryOver() {
        let kept = ThemeCatalog.migrate(ThemeSelection(themeID: "deep-space", paletteID: "deep-space/supernova"))
        XCTAssertEqual(kept, ThemeSelection(themeID: "space", paletteID: "space/supernova"))
        let original = ThemeCatalog.migrate(ThemeSelection(themeID: "pastel-retro", paletteID: "pastel-retro/midnight-blossom"))
        XCTAssertEqual(original.paletteID, "cherry-blossom/midnight-blossom")
        let other = ThemeCatalog.migrate(ThemeSelection(themeID: "terminal", paletteID: "terminal/amber-crt"))
        XCTAssertEqual(other, ThemeSelection(themeID: "cyberpunk", paletteID: "cyberpunk/neon-rain"))
        XCTAssertEqual(ThemeCatalog.resolve(ThemeSelection(themeID: "winter", paletteID: "winter/snowfall")).0.id, "snow")
        let current = ThemeSelection(themeID: "ember", paletteID: "ember/hearth")
        XCTAssertEqual(ThemeCatalog.migrate(current), current)
    }

    /// Readability rules every palette must meet, generated or hand-made.
    func testEveryPaletteIsReadable() {
        for p in ThemeCatalog.allPalettes {
            let tag = "\(p.id)"
            XCTAssertGreaterThanOrEqual(p.textPrimary.contrast(with: p.elevated), 7, "primary text \(tag)")
            XCTAssertGreaterThanOrEqual(p.textPrimary.contrast(with: p.glass.over(p.sceneTop)), 7, "primary text on glass \(tag)")
            XCTAssertGreaterThanOrEqual(p.textSecondary.contrast(with: p.surface), 4.5, "secondary text \(tag)")
            XCTAssertGreaterThanOrEqual(p.textTertiary.contrast(with: p.surface), 2.8, "tertiary text \(tag)")
            XCTAssertGreaterThanOrEqual(p.onAccent.contrast(with: p.accent), 4.5, "text on accent \(tag)")
            for (name, c) in [("focus", p.tagFocus), ("health", p.tagHealth), ("later", p.tagLater), ("high", p.tagHigh), ("learning", p.tagLearning)] {
                XCTAssertGreaterThanOrEqual(c.contrast(with: p.surface), 4.5, "tag \(name) \(tag)")
            }
        }
    }

    func testAllColoursInGamut() {
        for p in ThemeCatalog.allPalettes {
            let all = [p.surface, p.glass, p.elevated, p.highlight, p.track, p.border, p.borderActive, p.textPrimary, p.textSecondary,
                       p.textTertiary, p.accentLight, p.accent, p.accentStrong, p.onAccent, p.tagFocus, p.tagHealth, p.tagLater,
                       p.tagHigh, p.tagLearning, p.sceneTop, p.sceneBottom, p.ground, p.groundShade, p.glow, p.particle]
            XCTAssertTrue(all.allSatisfy(\.isInGamut), p.id)
        }
    }

    func testTagColoursAreDistinguishable() {
        for p in ThemeCatalog.allPalettes {
            let tags = [p.tagFocus, p.tagHealth, p.tagLater, p.tagHigh, p.tagLearning].map(OKLCH.init)
            for i in 0..<tags.count { for j in (i + 1)..<tags.count {
                XCTAssertGreaterThan(tags[i].distance(to: tags[j]), 0.05, "\(p.id) tags \(i)/\(j)")
            } }
        }
    }

    func testOriginalNightPaletteIsUnchanged() {
        let p = ThemeCatalog.resolve(.default).1
        XCTAssertEqual(p.name, "Midnight Blossom")
        XCTAssertEqual(p.surface.hexString, "#111827")
        XCTAssertEqual(p.accent.hexString, "#F6A6CF")
        XCTAssertEqual(p.textPrimary.hexString, "#F5EDF6")
    }

    func testResolveFallsBack() {
        let (t, p) = ThemeCatalog.resolve(ThemeSelection(themeID: "snow", paletteID: "missing"))
        XCTAssertEqual(t.id, "snow")
        XCTAssertEqual(p.id, t.defaultPalette.id)
        XCTAssertEqual(ThemeCatalog.resolve(ThemeSelection(themeID: "nope", paletteID: "x")).0.id, "cherry-blossom")
    }

    func testMatchSystemPicksClosestCounterpart() {
        let sel = ThemeSelection(themeID: "pastel-retro", paletteID: "pastel-retro/midnight-blossom")
        XCTAssertEqual(ThemeCatalog.resolve(sel, matchSystem: false, systemDark: false).1.name, "Midnight Blossom")
        XCTAssertEqual(ThemeCatalog.resolve(sel, matchSystem: true, systemDark: true).1.name, "Midnight Blossom")
        let light = ThemeCatalog.resolve(sel, matchSystem: true, systemDark: false).1
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(OKLCH(light.accent).h, OKLCH(RGBA(hex: 0xF6A6CF)).h, accuracy: 25, "keeps a pink accent")
        for t in ThemeCatalog.all {
            XCTAssertTrue(t.palettes.contains { $0.isDark } && t.palettes.contains { !$0.isDark }, "\(t.name) needs both modes for matching")
        }
    }

    func testOKLCHRoundTripAndGamutClip() {
        let pink = RGBA(hex: 0xF6A6CF)
        XCTAssertEqual(OKLCH(pink).rgb().hexString, "#F6A6CF")
        let wild = OKLCH(0.7, 0.4, 140).rgb() // far outside sRGB: chroma is reduced, not clipped per channel
        XCTAssertTrue(wild.isInGamut)
        XCTAssertEqual(OKLCH(wild).h, 140, accuracy: 3)
        XCTAssertEqual(RGBA(hex: 0x000000).contrast(with: RGBA(hex: 0xFFFFFF)), 21, accuracy: 0.01)
    }
}
