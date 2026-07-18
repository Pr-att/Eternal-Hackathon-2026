//
//  DeepLinkManager.swift
//  Eternal-Hackathon-2026 (main app)
//
//  Parses inbound URLs (custom scheme or universal links) into typed routes.
//  Keeping URL parsing in one place means SceneDelegate/AppDelegate stay
//  dumb and every entry point produces the same `DeepLinkRoute`.
//

import Foundation

/// Where an inbound link should take the user.
enum DeepLinkRoute: Equatable {
    /// Launched from the Share Extension — the shared inbox should open.
    case sharedInbox
    /// Unrecognized — callers can ignore or show a fallback.
    case unknown
}

enum DeepLinkManager {

    /// Maps a URL to a route. Returns `.unknown` for anything we don't own.
    static func route(for url: URL) -> DeepLinkRoute {
        // Custom scheme: eternalhackathon://shared
        if url.scheme?.lowercased() == SharedConstants.urlScheme {
            if url.host?.lowercased() == SharedConstants.sharedHost {
                return .sharedInbox
            }
        }
        // Universal link (https) support: https://<yourdomain>/shared
        // Enable by hosting an apple-app-site-association file + adding an
        // Associated Domains entitlement. Path-based routing lives here so
        // both entry points converge on the same routes.
        if url.scheme?.lowercased() == "https",
           url.path.lowercased().hasPrefix("/\(SharedConstants.sharedHost)") {
            return .sharedInbox
        }
        return .unknown
    }
}
