import Foundation
import SwiftData
import LERNCore

public enum SharedStore {
    private static let notificationScheduleDirtyKey = "notificationScheduleDirty"
    public static var directory: URL {
        #if DEBUG
        if let session = ProcessInfo.processInfo.environment["LERN_UI_TEST_SESSION"], UUID(uuidString: session) != nil {
            return URL.applicationSupportDirectory.appendingPathComponent("LERN-QA-" + session, isDirectory: true)
        }
        #endif
        #if os(iOS) || os(watchOS)
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Product.appGroup) { return shared }
        #endif
        return URL.applicationSupportDirectory.appendingPathComponent("LERN", isDirectory: true)
    }
    private static let containerLock = NSLock()
    private static var cachedContainers: [URL: ModelContainer] = [:]

    public static func container(for url: URL) throws -> ModelContainer {
        containerLock.lock()
        defer { containerLock.unlock() }
        if let existing = cachedContainers[url] {
            return existing
        }
        let container = try StorageFactory.container(url: url)
        cachedContainers[url] = container
        return container
    }

    #if DEBUG
    public static func resetContainerCache() {
        containerLock.lock()
        defer { containerLock.unlock() }
        cachedContainers.removeAll()
    }
    #endif

    public static func open() throws -> LibraryStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.store")
        return LibraryStore(modelContainer: try container(for: url))
    }
    public static var photosDirectory: URL { directory.appendingPathComponent("photos", isDirectory: true) }
    public static func photoURL(_ name: String) -> URL? {
        guard LibraryBackup.safeAssetName(name) else { return nil }
        return photosDirectory.appendingPathComponent(name)
    }
    public static func markNotificationScheduleDirty() {
        UserDefaults(suiteName: Product.appGroup)?.set(true, forKey: notificationScheduleDirtyKey)
    }
    public static func notificationScheduleIsDirty() -> Bool {
        UserDefaults(suiteName: Product.appGroup)?.bool(forKey: notificationScheduleDirtyKey) ?? false
    }
    public static func clearNotificationScheduleDirty() {
        UserDefaults(suiteName: Product.appGroup)?.removeObject(forKey: notificationScheduleDirtyKey)
    }
}
