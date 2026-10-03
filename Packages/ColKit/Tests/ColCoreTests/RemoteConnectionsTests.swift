import Testing
@testable import ColCore

@Suite struct RemoteConnectionsTests {
    @Test func silentConnectionsNeverKeepThePhoneOut() {
        var pending = PendingConnections(limit: 16, perHost: 4)
        // Someone on the network opens connections from many addresses and sends nothing.
        for id in UInt64(1)...16 {
            let leaving = pending.admit(id, from: "10.0.0.\(id)", besides: 0)
            #expect(leaving == [])
        }
        #expect(pending.count == 16)
        // The phone still gets in: the connection waiting longest makes room.
        let leaving = pending.admit(100, from: "192.168.1.20", besides: 0)
        #expect(leaving == [1])
        #expect(pending.contains(100))
        #expect(pending.count == 16)
    }

    @Test func oneAddressHoldsAFewSlotsAtMost() {
        var pending = PendingConnections(limit: 16, perHost: 4)
        for id in UInt64(1)...4 { _ = pending.admit(id, from: "10.0.0.9", besides: 0) }
        _ = pending.admit(5, from: "192.168.1.20", besides: 0)
        // A fifth from the same address replaces its own oldest, not the phone's.
        let leaving = pending.admit(6, from: "10.0.0.9", besides: 0)
        #expect(leaving == [1])
        #expect(pending.entries.map(\.id) == [2, 3, 4, 5, 6])
        #expect(pending.entries.filter { $0.host == "10.0.0.9" }.count == 4)
    }

    @Test func theBusiestAddressMakesRoomFirst() {
        var pending = PendingConnections(limit: 6, perHost: 4)
        _ = pending.admit(1, from: "phone", besides: 0)
        for id in UInt64(2)...6 { _ = pending.admit(id, from: id.isMultiple(of: 2) ? "a" : "b", besides: 0) }
        // "a" holds three (2, 4, 6), "b" two, the phone one: the oldest of "a" goes, not the phone's older one.
        let leaving = pending.admit(7, from: "c", besides: 0)
        #expect(leaving == [2])
        #expect(pending.contains(1))
    }

    @Test func phonesLetInCountTowardTheLimit() {
        var pending = PendingConnections(limit: 4, perHost: 4)
        _ = pending.admit(1, from: "a", besides: 2)
        _ = pending.admit(2, from: "b", besides: 2)
        let leaving = pending.admit(3, from: "c", besides: 2)
        #expect(leaving == [1])
        // Every slot held by phones already let in: the newcomer is refused.
        var full = PendingConnections(limit: 4, perHost: 4)
        let refused = full.admit(1, from: "a", besides: 4)
        #expect(refused == nil)
        #expect(full.count == 0)
    }

    @Test func aConnectionThatGoesFreesItsSlot() {
        var pending = PendingConnections(limit: 2, perHost: 2)
        _ = pending.admit(1, from: "a", besides: 0)
        _ = pending.admit(2, from: "b", besides: 0)
        let removed = pending.remove(1)
        let removedAgain = pending.remove(1)
        #expect(removed)
        #expect(!removedAgain)
        let leaving = pending.admit(3, from: "c", besides: 0)
        #expect(leaving == [])
    }
}
