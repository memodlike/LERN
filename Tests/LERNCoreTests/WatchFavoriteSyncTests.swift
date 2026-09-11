import Foundation
import Testing
@testable import LERNCore

struct WatchFavoriteSyncTests {
    private let entryID = String(repeating: "a", count: 64)

    @Test func acknowledgementRemovesOnlyTheMatchingPendingMutation() {
        var pending = PendingFavoriteMutations()
        let first = pending.replace(entryID: entryID, desiredFavorite: true, mutationID: "00000000-0000-0000-0000-000000000001")
        let removed = pending.acknowledge(FavoriteAck(mutationID: first.mutationID, entryID: entryID, result: .applied))
        #expect(removed)
        #expect(pending.isEmpty)
    }

    @Test func olderAcknowledgementCannotClearANewerToggle() {
        var pending = PendingFavoriteMutations()
        let old = pending.replace(entryID: entryID, desiredFavorite: true, mutationID: "00000000-0000-0000-0000-000000000001")
        let new = pending.replace(entryID: entryID, desiredFavorite: false, mutationID: "00000000-0000-0000-0000-000000000002")
        let removed = pending.acknowledge(FavoriteAck(mutationID: old.mutationID, entryID: entryID, result: .applied))
        #expect(!removed)
        #expect(pending.mutation(for: entryID)?.mutationID == new.mutationID)
        #expect(pending.mutation(for: entryID)?.desiredFavorite == false)
    }

    @Test func pendingMutationsSurviveRelaunchAndSkipOutstandingTransfers() throws {
        var pending = PendingFavoriteMutations()
        let mutation = pending.replace(entryID: entryID, desiredFavorite: true, mutationID: "00000000-0000-0000-0000-000000000003")
        let restored = try JSONDecoder().decode(PendingFavoriteMutations.self, from: JSONEncoder().encode(pending))
        #expect(restored.mutation(for: entryID) == mutation)
        #expect(restored.pendingForTransfer(excluding: [mutation.mutationID]).isEmpty)
        #expect(restored.pendingForTransfer(excluding: []).map(\.mutationID) == [mutation.mutationID])
    }

    @Test func incomingSnapshotKeepsNewerPendingDesiredState() {
        var pending = PendingFavoriteMutations()
        _ = pending.replace(entryID: entryID, desiredFavorite: true, mutationID: "00000000-0000-0000-0000-000000000004")
        var entry = EntryValue(draft: EntryDraft(text: "Snapshot thought")); entry.id = entryID; entry.favorite = false
        #expect(pending.applying(to: [entry]).first?.favorite == true)
    }

    @Test func persistenceFailureProducesNoAcknowledgement() {
        let mutation = FavoriteMutation(mutationID: "00000000-0000-0000-0000-000000000005", entryID: entryID, desiredFavorite: true)
        struct DatabaseFailure: Error {}
        #expect(throws: DatabaseFailure.self) {
            try commitFavoriteMutation(mutation) { _, _ in throw DatabaseFailure() }
        }
    }

    @Test func missingEntryIsATerminalAcknowledgedRejection() throws {
        let mutation = FavoriteMutation(mutationID: "00000000-0000-0000-0000-000000000006", entryID: entryID, desiredFavorite: true)
        let ack = try commitFavoriteMutation(mutation) { _, _ in false }
        #expect(ack.result == .rejectedMissingEntry)
    }

    @Test func invalidPayloadsFailClosed() {
        let invalid = FavoriteMutation(mutationID: "invalid", entryID: "not-an-entry", desiredFavorite: true)
        #expect(!invalid.isValid())
        let invalidAck = FavoriteAck(mutationID: "invalid", entryID: "not-an-entry", result: .applied)
        var pending = PendingFavoriteMutations()
        let removed = pending.acknowledge(invalidAck)
        #expect(!removed)
    }
}
