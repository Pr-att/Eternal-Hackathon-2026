//
//  AppLaunchManager.swift
//  Eternal-Hackathon-2026 (main app)
//
//  Central place that decides what to do when the app is launched or
//  foregrounded — whether from a deep link OR from a cold start where the
//  extension enqueued items while the app was terminated. It resolves a
//  route and drains the shared queue, then notifies observers.
//

import UIKit

/// Broadcast when new shared content has been drained and is ready to route.
extension Notification.Name {
    static let didReceiveSharedContent = Notification.Name("didReceiveSharedContent")
}

final class AppLaunchManager {

    static let shared = AppLaunchManager()

    private let store: SharedDataManager
    private init(store: SharedDataManager = .shared) { self.store = store }

    /// Call from SceneDelegate when the app is opened with URL(s).
    /// - Returns: the resolved route so the caller can navigate.
    @discardableResult
    func handle(url: URL) -> DeepLinkRoute {
        let route = DeepLinkManager.route(for: url)
        if route == .sharedInbox { signalIfContentWaiting() }
        return route
    }

    /// Call on every foreground/launch to catch items the extension saved
    /// while the app wasn't the one opened (belt-and-suspenders: the deep
    /// link may not always fire, e.g. user opens the app manually later).
    func handleAppBecameActive() {
        signalIfContentWaiting()
    }

    /// Posts a refresh signal WITHOUT draining. Draining happens only in the
    /// inbox (the single consumer), so items are never dropped when no screen
    /// is listening yet — that was the "shared but inbox empty" bug: we used
    /// to drain here and post the items, but the inbox wasn't observing yet.
    private func signalIfContentWaiting() {
        guard !store.pendingItems().isEmpty else { return }
        NotificationCenter.default.post(name: .didReceiveSharedContent, object: nil)
    }
}
