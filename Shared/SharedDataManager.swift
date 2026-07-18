//
//  SharedDataManager.swift
//  Shared between the main app and the Share Extension.
//
//  The single gateway to the App Group container. The extension WRITES
//  through it; the main app READS/CLEARS through it. All access is funneled
//  onto a private serial queue so concurrent reads/writes from the two
//  processes (and multiple threads) stay consistent.
//
//  Design notes:
//  • Lightweight metadata → UserDefaults(suiteName:) (the app group suite).
//  • Heavy binary → files inside the group container's Documents area.
//  • Everything is Result/throwing based; no force-unwraps, no crashes on
//    a missing container (which happens if the App Group capability is not
//    configured correctly — we surface that as an error instead).
//

import Foundation

/// Errors surfaced by the shared storage layer.
public enum SharedStorageError: LocalizedError {
    case appGroupUnavailable
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileWriteFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared App Group container is unavailable. Verify the App Groups capability and identifier match in both targets."
        case .encodingFailed(let e):
            return "Failed to encode shared content: \(e.localizedDescription)"
        case .decodingFailed(let e):
            return "Failed to decode shared content: \(e.localizedDescription)"
        case .fileWriteFailed(let e):
            return "Failed to write shared payload to disk: \(e.localizedDescription)"
        }
    }
}

public final class SharedDataManager {

    /// Shared instance. Safe to use from both processes — each process gets
    /// its own instance backed by the same on-disk container.
    public static let shared = SharedDataManager()

    /// Serial queue guarding all container access. Using a barrier-free
    /// serial queue keeps ordering deterministic and avoids data races.
    private let queue = DispatchQueue(label: "com.hackathon.sharedatamanager", qos: .userInitiated)

    private let defaults: UserDefaults?
    private let fileManager = FileManager.default

    /// Injected for testability; defaults to the real app-group suite.
    public init(appGroupID: String = SharedConstants.appGroupID) {
        self.defaults = UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Container URLs

    /// Root of the App Group container, or nil if the capability is missing.
    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupID)
    }

    /// True only when the App Groups capability is correctly enabled for this
    /// target. If this is false, the extension and app cannot share data —
    /// surface it to the user rather than failing silently.
    public var isSharedContainerAvailable: Bool { containerURL != nil }

    /// Directory where binary payloads live. Created on demand.
    private func payloadsDirectory() throws -> URL {
        guard let container = containerURL else { throw SharedStorageError.appGroupUnavailable }
        let dir = container.appendingPathComponent(SharedConstants.payloadsDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Resolves a stored `fileName` back to an absolute URL for reading.
    public func payloadURL(for fileName: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container
            .appendingPathComponent(SharedConstants.payloadsDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    // MARK: - Writing (used by the extension)

    /// Copies binary data into the shared container and returns the relative
    /// filename to store on a `SharedContent`. Keep the extension's work here
    /// minimal — just a disk copy, no processing.
    public func storePayload(_ data: Data, preferredExtension ext: String) throws -> String {
        try queue.sync {
            let dir = try payloadsDirectory()
            // A collision-resistant name without relying on Date()/random at
            // the call site: UUID is allowed and unique per invocation.
            let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
            let dest = dir.appendingPathComponent(name)
            do {
                try data.write(to: dest, options: .atomic)
            } catch {
                throw SharedStorageError.fileWriteFailed(error)
            }
            return name
        }
    }

    /// Appends items to the pending queue that the main app will drain.
    /// Thread-safe and additive: sharing twice before opening the app keeps
    /// both batches.
    public func enqueue(_ items: [SharedContent]) throws {
        guard !items.isEmpty else { return }
        // A valid suite object can exist even when the App Group entitlement
        // is missing — but the container won't. Check the container so the
        // extension reports the problem instead of writing to nowhere.
        guard isSharedContainerAvailable else { throw SharedStorageError.appGroupUnavailable }
        try queue.sync {
            guard let defaults else { throw SharedStorageError.appGroupUnavailable }
            var current = decodeItems(from: defaults)
            current.append(contentsOf: items)
            try encodeItems(current, into: defaults)
        }
    }

    // MARK: - Reading / clearing (used by the main app)

    /// Returns the queued items without removing them.
    public func pendingItems() -> [SharedContent] {
        queue.sync {
            guard let defaults else { return [] }
            return decodeItems(from: defaults)
        }
    }

    /// Atomically returns AND clears the queue — the app calls this once it
    /// has taken ownership of the items, so they aren't processed twice.
    public func drainPendingItems() -> [SharedContent] {
        queue.sync {
            guard let defaults else { return [] }
            let items = decodeItems(from: defaults)
            defaults.removeObject(forKey: SharedConstants.DefaultsKey.pendingItems)
            return items
        }
    }

    /// Deletes a payload file once the app has consumed it (housekeeping).
    public func deletePayload(fileName: String) {
        queue.sync {
            guard let url = payloadURL(for: fileName) else { return }
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Convenience typed writers (used by the extension coordinator)

    public func makeURLItem(_ url: URL, metadata: [String: String] = [:], now: TimeInterval) -> SharedContent {
        SharedContent(id: UUID().uuidString, kind: .url, value: url.absoluteString, metadata: metadata, createdAt: now)
    }

    public func makeTextItem(_ text: String, metadata: [String: String] = [:], now: TimeInterval) -> SharedContent {
        SharedContent(id: UUID().uuidString, kind: .text, value: text, metadata: metadata, createdAt: now)
    }

    public func makeFileItem(kind: SharedContentKind, fileName: String, metadata: [String: String] = [:], now: TimeInterval) -> SharedContent {
        SharedContent(id: UUID().uuidString, kind: kind, fileName: fileName, metadata: metadata, createdAt: now)
    }

    // MARK: - Private JSON helpers

    private func decodeItems(from defaults: UserDefaults) -> [SharedContent] {
        guard let data = defaults.data(forKey: SharedConstants.DefaultsKey.pendingItems) else { return [] }
        do {
            return try JSONDecoder().decode([SharedContent].self, from: data)
        } catch {
            // Corrupt payload should not wedge the app forever — log & reset.
            NSLog("[SharedDataManager] decode failed, resetting queue: \(error)")
            defaults.removeObject(forKey: SharedConstants.DefaultsKey.pendingItems)
            return []
        }
    }

    private func encodeItems(_ items: [SharedContent], into defaults: UserDefaults) throws {
        do {
            let data = try JSONEncoder().encode(items)
            defaults.set(data, forKey: SharedConstants.DefaultsKey.pendingItems)
        } catch {
            throw SharedStorageError.encodingFailed(error)
        }
    }
}
