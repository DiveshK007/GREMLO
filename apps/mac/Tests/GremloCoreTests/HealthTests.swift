import Testing
@testable import GremloCore

struct HealthTests {
    @Test func blockerNamesTheFirstThingToFix() {
        var g = Health.Gate(server: nil, thisMacPaired: true)
        #expect(Health.blocker(g) == nil, "a paired Mac with a campaign counts views")
        g.stream = true; g.sponsored = false
        #expect(Health.blocker(g)?.hasPrefix("stream mode") == true, "stream mode is named before sponsored lines")
        g.egg = true
        #expect(Health.blocker(g)?.hasPrefix("still an egg") == true, "a fresh install is an egg and shows no lines")
        g.thisMacPaired = false
        #expect(Health.blocker(g) == "this Mac isn't paired", "pairing comes before local switches")
        g.server = .serverDown
        #expect(Health.blocker(g) == "server unreachable", "the server comes first")
        var h = Health.Gate(server: nil, thisMacPaired: nil)
        h.campaign = false
        #expect(Health.blocker(h) == "no campaign running", "unknown pairing isn't reported as unpaired")
        // every reason fits one panel row next to "Counting views" (about 30 characters with the "no: ")
        var all = Health.Gate(server: nil, thisMacPaired: true)
        for set in [{ all.silenced = true }, { all.campaign = false }, { all.capped = true }, { all.quietHours = true }, { all.sponsored = false },
                    { all.stream = true }, { all.focus = true }, { all.paused = true }, { all.demo = true }, { all.egg = true },
                    { all.thisMacPaired = false }, { all.secureEnclave = false }, { all.server = .unregistered }] as [() -> Void] {
            set()
            #expect((Health.blocker(all)?.count ?? 0) <= 26, "\(Health.blocker(all) ?? "")")
        }
    }

    @Test func viewsLineLeavesOutZeros() {
        #expect(Health.views(today: 0, held: 0, payable: 0, settledToday: 0, holdbackHours: 24) == "0 today")
        #expect(Health.views(today: 12, held: 8, payable: 4, settledToday: 3, holdbackHours: 24) == "12 today \u{00B7} 8 on hold 24 h \u{00B7} 4 to pay \u{00B7} 3 paid today")
        #expect(Health.views(today: 2, held: 2, payable: nil, settledToday: nil, holdbackHours: 0) == "2 today \u{00B7} 2 on hold", "an older server sends no queue numbers")
    }
}

struct MenuBarStateTests {
    @Test func approvalWinsThenTheServerThenQuiet() {
        #expect(MenuBarState.of(approvalWaiting: true, server: .serverDown, paused: true, focus: false) == .approval)
        #expect(MenuBarState.of(approvalWaiting: false, server: .serverDown, paused: true, focus: false) == .away("can't reach the server"))
        #expect(MenuBarState.of(approvalWaiting: false, server: nil, paused: false, focus: true) == .quiet("focus"))
        #expect(MenuBarState.of(approvalWaiting: false, server: nil, paused: false, focus: false).label("Gremlo") == "Gremlo")
        #expect(MenuBarState.approval.label("Gremlo") == "Gremlo: needs your approval")
    }
}
