import Foundation

/// A desired-state command for Watch favorite synchronization. It is safe to
/// deliver more than once because the desired value, rather than a toggle, is
/// persisted on the phone.
public struct FavoriteMutation: Codable, Hashable, Sendable, Identifiable {
    public static let schemaVersion = 1
    public var schemaVersion: Int
    public var mutationID: String
    public var entryID: String
    public var desiredFavorite: Bool
    public var createdAt: Date

    public var id: String { mutationID }

    public init(mutationID: String = UUID().uuidString, entryID: String, desiredFavorite: Bool, createdAt: Date = Date()) {
        self.schemaVersion = Self.schemaVersion
        self.mutationID = mutationID
        self.entryID = entryID
        self.desiredFavorite = desiredFavorite
        self.createdAt = createdAt
    }

    public func isValid() -> Bool {
        schemaVersion == Self.schemaVersion && UUID(uuidString: mutationID) != nil && Self.isEntryID(entryID)
    }

    public static func isEntryID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public enum FavoriteMutationResult: String, Codable, Sendable {
    case applied
    case rejectedMissingEntry
}

public enum FavoriteMutationError: Error, Sendable { case invalidPayload }

/// Pure application-level commit contract used by tests and mirrored by the
/// asynchronous iPhone bridge. A throwing persistence closure deliberately
/// produces no acknowledgement.
public func commitFavoriteMutation(_ mutation: FavoriteMutation, apply: (String, Bool) throws -> Bool) throws -> FavoriteAck {
    guard mutation.isValid() else { throw FavoriteMutationError.invalidPayload }
    let result: FavoriteMutationResult = try apply(mutation.entryID, mutation.desiredFavorite) ? .applied : .rejectedMissingEntry
    return FavoriteAck(mutationID: mutation.mutationID, entryID: mutation.entryID, result: result)
}

/// Application-level confirmation. A transport completion is deliberately not
/// treated as this acknowledgement.
public struct FavoriteAck: Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public var schemaVersion: Int
    public var mutationID: String
    public var entryID: String
    public var result: FavoriteMutationResult

    public init(mutationID: String, entryID: String, result: FavoriteMutationResult) {
        self.schemaVersion = Self.schemaVersion
        self.mutationID = mutationID
        self.entryID = entryID
        self.result = result
    }

    public func isValid() -> Bool {
        schemaVersion == Self.schemaVersion && UUID(uuidString: mutationID) != nil && FavoriteMutation.isEntryID(entryID)
    }
}

/// Durable, entry-coalesced Watch pending state. An ACK can remove a value
/// only if it names the currently pending mutation for that entry.
public struct PendingFavoriteMutations: Codable, Sendable, Equatable {
    private var byEntryID: [String: FavoriteMutation]

    public init(_ values: [FavoriteMutation] = []) {
        byEntryID = [:]
        for value in values where value.isValid() { byEntryID[value.entryID] = value }
    }

    public var values: [FavoriteMutation] { byEntryID.values.sorted { $0.createdAt < $1.createdAt } }
    public var isEmpty: Bool { byEntryID.isEmpty }
    public func mutation(for entryID: String) -> FavoriteMutation? { byEntryID[entryID] }
    public func pendingForTransfer(excluding outstandingMutationIDs: Set<String>) -> [FavoriteMutation] {
        values.filter { !outstandingMutationIDs.contains($0.mutationID) }
    }

    public mutating func replace(entryID: String, desiredFavorite: Bool, mutationID: String = UUID().uuidString, createdAt: Date = Date()) -> FavoriteMutation {
        let mutation = FavoriteMutation(mutationID: mutationID, entryID: entryID, desiredFavorite: desiredFavorite, createdAt: createdAt)
        if mutation.isValid() { byEntryID[entryID] = mutation }
        return mutation
    }

    @discardableResult public mutating func acknowledge(_ ack: FavoriteAck) -> Bool {
        guard ack.isValid(), byEntryID[ack.entryID]?.mutationID == ack.mutationID else { return false }
        byEntryID.removeValue(forKey: ack.entryID)
        return true
    }

    public func applying(to entries: [EntryValue]) -> [EntryValue] {
        entries.map { entry in
            guard let mutation = byEntryID[entry.id] else { return entry }
            var value = entry; value.favorite = mutation.desiredFavorite; return value
        }
    }
}
