//
//  ShareExtensionCoordinator.swift
//  ShareExtension
//
//  The "brain" of the extension, kept UIKit-free so it is unit-testable.
//  It orchestrates: extract → persist to the App Group → build the deep link
//  that will wake the main app. The view controller stays thin and just
//  drives this and reports the result to the user.
//

import Foundation

/// The outcome of handling a share, consumed by `ShareViewController`.
enum ShareResult {
    case success(deepLink: URL, itemCount: Int)
    case failure(ShareError)
}

/// User-facing error taxonomy for the extension.
enum ShareError: LocalizedError {
    case emptyShare
    case unsupported
    case storageFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .emptyShare:            return "There was nothing to share."
        case .unsupported:           return "This content type isn't supported yet."
        case .storageFailed(let m):  return m
        case .timedOut:              return "Sharing took too long. Please try again."
        }
    }
}

final class ShareExtensionCoordinator {

    private let store: SharedDataManager
    private let extractor: ShareItemExtractor
    /// Hard ceiling so the extension never hangs the share sheet. The system
    /// will kill a slow extension anyway; we fail gracefully first.
    private let timeout: TimeInterval

    init(store: SharedDataManager = .shared,
         now: TimeInterval,
         timeout: TimeInterval = 12) {
        self.store = store
        self.extractor = ShareItemExtractor(store: store, now: now)
        self.timeout = timeout
    }

    /// Handles the incoming extension items end-to-end.
    func handle(items: [NSExtensionItem]) async -> ShareResult {
        do {
            let content = try await withTimeout(timeout) {
                try await self.extractor.extract(from: items)
            }

            do {
                try store.enqueue(content)
            } catch {
                return .failure(.storageFailed(error.localizedDescription))
            }

            return .success(deepLink: Self.makeDeepLink(), itemCount: content.count)

        } catch is TimeoutError {
            return .failure(.timedOut)
        } catch let ext as ExtractionError {
            switch ext {
            case .emptyShare:        return .failure(.emptyShare)
            case .unsupportedContent: return .failure(.unsupported)
            case .loadFailed(let e): return .failure(.storageFailed(e.localizedDescription))
            }
        } catch {
            return .failure(.storageFailed(error.localizedDescription))
        }
    }

    /// Builds `eternalhackathon://shared` — the URL the app opens to.
    static func makeDeepLink() -> URL {
        var components = URLComponents()
        components.scheme = SharedConstants.urlScheme
        components.host = SharedConstants.sharedHost
        // Fall back to a hand-built URL only if components ever fail (they won't
        // for these static values) — never force-unwrap.
        return components.url ?? URL(string: "\(SharedConstants.urlScheme)://\(SharedConstants.sharedHost)")!
    }
}

// MARK: - Lightweight timeout helper

private struct TimeoutError: Error {}

/// Races an async operation against a timer; whichever finishes first wins.
private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        // First result wins; cancel the loser.
        guard let result = try await group.next() else { throw TimeoutError() }
        group.cancelAll()
        return result
    }
}
