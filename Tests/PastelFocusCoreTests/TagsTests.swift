import XCTest
@testable import PastelFocusCore

final class TagsTests: XCTestCase {
    func testFirstTagOnTheLineDecidesSkippingLater() {
        func category(_ line: String) -> String? { TaskLineParser.parse(line)?.category }
        XCTAssertEqual(category("- [ ] Read docs #Learning #career"), "learning", "first tag, lowercased")
        XCTAssertEqual(category("- [ ] Ship it #later #coding"), "coding", "#later marks priority and is skipped")
        XCTAssertEqual(category("- [ ] Hermes invented this #deep-work"), "deep-work", "any tag counts, not a fixed list")
        XCTAssertNil(category("- [ ] Someday #later"))
        XCTAssertNil(category("- [ ] No tags"))
    }

    func testNewTagsTakeTheLeastUsedSlot() {
        var r = TagRegistry()
        XCTAssertTrue(r.adopt(["career", "#Coding", "later", "career", "9lives"]))
        XCTAssertEqual(r.tags.map(\.name), ["career", "coding"], "reserved, duplicate and invalid names are skipped")
        XCTAssertEqual(r.tags.map(\.slot), [.a, .b])
        r.setSlot(.b, for: "career") // both on B now
        r.adopt(["health"])
        XCTAssertEqual(r.tag(named: "health")?.slot, .a, "least used, earliest letter")
        XCTAssertFalse(r.adopt(["health", "HEALTH"]), "already listed")
        // Eleven tags over ten slots: sharing a plant is fine.
        r.adopt((1...8).map { "t\($0)" })
        XCTAssertEqual(r.tags.count, 11)
        XCTAssertEqual(Set(r.tags.map(\.slot)).count, 10)
    }

    func testSlotLookupWithThemeOverridesAndFallback() {
        var r = TagRegistry([TagDefinition(name: "focus", slot: .b)])
        r.setOverride(.a, for: "focus", theme: "deep-space")
        XCTAssertEqual(r.slot(for: "#Focus", theme: "pastel-retro"), .b)
        XCTAssertEqual(r.slot(for: "focus", theme: "deep-space"), .a)
        XCTAssertEqual(r.slot(for: "unknown", theme: "deep-space"), TagRegistry.fallback)
        XCTAssertEqual(r.slot(for: nil, theme: "deep-space"), TagRegistry.fallback)
        r.setOverride(nil, for: "focus", theme: "deep-space")
        XCTAssertEqual(r.slot(for: "focus", theme: "deep-space"), .b)
    }

    func testAddRenameRemoveRules() throws {
        var r = TagRegistry()
        try r.add("#Reading")
        XCTAssertThrowsError(try r.add("reading")) { XCTAssertEqual($0 as? TagError, .exists) }
        XCTAssertThrowsError(try r.add("later")) { XCTAssertEqual($0 as? TagError, .reserved) }
        XCTAssertThrowsError(try r.add("2fast")) { XCTAssertEqual($0 as? TagError, .invalidName) }
        try r.rename("reading", to: "Books")
        XCTAssertNotNil(r.tag(named: "books"))
        XCTAssertNil(r.tag(named: "reading"))
        r.remove("books")
        XCTAssertTrue(r.tags.isEmpty)
    }

    func testReorderKeepsHiddenTagsInPlace() {
        var r = TagRegistry(["a", "b", "c", "d", "e"].map { TagDefinition(name: $0, slot: .a) })
        r.reorder(["#D", "b", "nope", "b"]) // only b and d are shown, dragged d before b
        XCTAssertEqual(r.tags.map(\.name), ["a", "d", "c", "b", "e"])
        r.move(fromOffsets: [4], toOffset: 0)
        XCTAssertEqual(r.tags.map(\.name), ["e", "a", "d", "c", "b"])
        r.move(fromOffsets: [0, 1], toOffset: 5)
        XCTAssertEqual(r.tags.map(\.name), ["d", "c", "b", "e", "a"])
        XCTAssertEqual(TagRegistry.parse(r.markdown()).tags.map(\.name), r.tags.map(\.name), "the order is kept in Tags.md")
    }

    func testTagsMarkdownRoundTripsAndToleratesHandEdits() {
        var r = TagRegistry([TagDefinition(name: "career", slot: .c), TagDefinition(name: "coding", slot: .j)])
        r.setOverride(.e, for: "coding", theme: "deep-space")
        r.setOverride(.a, for: "coding", theme: "aurora")
        let md = r.markdown()
        XCTAssertTrue(md.contains("| #coding | J | aurora: A, deep-space: E |"))
        XCTAssertEqual(TagRegistry.parse(md), r)
        let edited = md + "| #broken | Z | |\n| not a tag | A | |\n| #later | B | |\n| #career | D | |\n"
        let back = TagRegistry.parse(edited)
        XCTAssertEqual(back.tag(named: "broken")?.slot, TagRegistry.fallback, "unknown slot letter falls back")
        XCTAssertNil(back.tag(named: "later"))
        XCTAssertEqual(back.tag(named: "career")?.slot, .c, "first row wins")
    }
}

final class TagsVaultTests: XCTestCase {
    var config: VaultConfig!
    var c: Coordinator!

    override func setUp() {
        config = makeVault()
        write("## Today's task list\n\n- [ ] Write tests #coding #career 🆔 aa11\n- [ ] Plan week #career 🆔 bb22\n- [ ] Code review #code 🆔 cc33\n- [ ] Someday #later 🆔 dd44\n",
              to: config.dailyNote("2026-10-07"))
        c = Coordinator(config: config, calendar: dubai, clock: FixedClock("2026-10-07T05:00:00Z"),
                        supportDir: config.root.appendingPathComponent(".support"))
    }

    func testRefreshListsTagsInTagsMdAndKeepsEdits() throws {
        c.refresh()
        XCTAssertEqual(c.tagRegistry.tags.map(\.name), ["coding", "career", "code"])
        XCTAssertTrue(read(config.tags).contains("| #career | B | |"))
        // Hermes adds a new tag; you change a slot by hand in Obsidian.
        write(read(config.tags).replacingOccurrences(of: "| #career | B |", with: "| #career | H |"), to: config.tags)
        write(read(config.dailyNote("2026-10-07")) + "- [ ] Stretch #health 🆔 ee55\n", to: config.dailyNote("2026-10-07"))
        c.refresh()
        XCTAssertEqual(c.tagRegistry.tag(named: "career")?.slot, .h, "hand edits are kept")
        XCTAssertEqual(c.tagRegistry.tag(named: "health")?.slot, .b, "new tag on the least-used slot (B was freed)")
        XCTAssertTrue(read(config.tags).contains("| #health | B | |"))
    }

    func testRenameUpdatesEveryTaskLineAndOnlyWholeTags() throws {
        c.refresh()
        try c.renameTag("career", to: "Work")
        let note = read(config.dailyNote("2026-10-07"))
        XCTAssertTrue(note.contains("Write tests #coding #work"))
        XCTAssertTrue(note.contains("Plan week #work"))
        XCTAssertTrue(note.contains("Code review #code"), "other tags untouched")
        XCTAssertNil(c.tagRegistry.tag(named: "career"), "the old name doesn't come back")
        XCTAssertNotNil(c.tagRegistry.tag(named: "work"))
        try c.renameTag("code", to: "reviews")
        XCTAssertTrue(read(config.dailyNote("2026-10-07")).contains("Write tests #coding #work"), "#code rename leaves #coding alone")
        XCTAssertThrowsError(try c.renameTag("work", to: "coding")) { XCTAssertEqual($0 as? TagError, .exists) }
    }

    func testOnlyUnusedTagsCanBeRemoved() throws {
        c.refresh()
        XCTAssertThrowsError(try c.removeTag("career")) { XCTAssertEqual($0 as? TagError, .inUse(2)) }
        try c.updateTags { try $0.add("unused") }
        try c.removeTag("unused")
        XCTAssertNil(c.tagRegistry.tag(named: "unused"))
        XCTAssertFalse(read(config.tags).contains("#unused"))
    }

    func testGardenPlantsCarryTheirTaskTag() throws {
        c.refresh()
        try c.startFocus(task: c.store.find("aa11"))
        let clock = c.clock as! FixedClock
        clock.advance(1500)
        c.sessionEnded(try XCTUnwrap(c.tick()))
        XCTAssertEqual(c.garden().items.first?.tag, "coding", "the first tag decides the plant")
    }
}
