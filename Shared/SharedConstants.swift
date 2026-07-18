//
//  SharedConstants.swift
//  Shared between the main app and the Share Extension.
//
//  Single source of truth for identifiers that MUST match the values you
//  configure in Xcode (App Group, URL scheme). Keeping them here prevents
//  the classic "extension writes to one container, app reads from another"
//  bug caused by a typo'd group id.
//

import Foundation

/// Namespaced constants shared by every target.
public enum SharedConstants {

    /// The App Group identifier. This EXACT string must be enabled in the
    /// "App Groups" capability for BOTH the app target and the extension
    /// target. If they differ by even one character, the shared container
    /// will be nil and nothing will be handed off.
    public static let appGroupID = "group.com.hackathon.Eternal-Hackathon-2026"

    /// Custom URL scheme the extension uses to wake the main app.
    /// Must be declared under CFBundleURLTypes in the MAIN app's Info.plist.
    public static let urlScheme = "eternalhackathon"

    /// The host used in deep-link URLs, e.g. `eternalhackathon://shared`.
    public static let sharedHost = "shared"

    /// UserDefaults (suite = app group) keys.
    public enum DefaultsKey {
        /// JSON-encoded array of `SharedContent` items awaiting the app.
        static let pendingItems = "pending_shared_items"
    }

    /// Sub-directory (inside the App Group container) where large payloads
    /// such as images/PDFs/videos are copied. UserDefaults only stores the
    /// lightweight metadata + a filename reference.
    public static let payloadsDirectoryName = "SharedPayloads"
}
