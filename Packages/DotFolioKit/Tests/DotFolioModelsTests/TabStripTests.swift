import Testing
@testable import DotFolioModels

struct TabStripTests {
    @Test func closingTheActiveTabActivatesItsRightNeighbour() {
        var tabs = TabStrip(ids: ["a", "b", "c"], active: "b")
        tabs.close("b")
        #expect(tabs == TabStrip(ids: ["a", "c"], active: "c"))
        tabs.close("c")                          // last one: the left neighbour
        #expect(tabs == TabStrip(ids: ["a"], active: "a"))
        tabs.close("a")
        #expect(tabs == TabStrip(ids: [], active: nil))
    }

    @Test func closingAnInactiveTabKeepsTheActiveOne() {
        var tabs = TabStrip(ids: ["a", "b", "c"], active: "a")
        tabs.close("c")
        #expect(tabs == TabStrip(ids: ["a", "b"], active: "a"))
    }

    @Test func closeOthersAndToTheRight() {
        var tabs = TabStrip(ids: ["a", "b", "c", "d"], active: "d")
        tabs.closeRight(of: "b")                 // active "d" is gone → "b"
        #expect(tabs == TabStrip(ids: ["a", "b"], active: "b"))
        var kept = TabStrip(ids: ["a", "b", "c"], active: "a")
        kept.closeRight(of: "b")                 // active survives
        #expect(kept == TabStrip(ids: ["a", "b"], active: "a"))
        kept.closeOthers(keeping: "b")
        #expect(kept == TabStrip(ids: ["b"], active: "b"))
        kept.closeAll()
        #expect(kept.isEmpty && kept.active == nil)
    }

    @Test func openAddsOnceAndActivatesTheFirst() {
        var tabs = TabStrip(ids: ["a"], active: "a")
        tabs.open(["b", "a", "c"])
        #expect(tabs == TabStrip(ids: ["a", "b", "c"], active: "b"))
        tabs.add("b")
        #expect(tabs.ids == ["a", "b", "c"])
    }

    @Test func pruneDropsDeletedItems() {
        var tabs = TabStrip(ids: ["a", "b", "c"], active: "a")
        tabs.prune(keeping: ["a", "c"])
        #expect(tabs.ids == ["a", "c"])
    }
}
