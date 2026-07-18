//
//  SharedContent.swift
//  Shared between the main app and the Share Extension.
//
//  The transport model that crosses the process boundary. It is `Codable`
//  so it can be serialized into the App Group's UserDefaults. Binary blobs
//  (images/PDFs/videos) are NOT embedded here — they are written to the
//  shared container as files and referenced by `fileName`, keeping the
//  UserDefaults payload tiny (UserDefaults is not meant for large data).
//

import Foundation

/// The category of a shared payload. Raw values are stable strings so the
/// enum survives JSON round-tripping across app versions.
public enum SharedContentKind: String, Codable {
    case url
    case text
    case image
    case pdf
    case video
    case file      // fallback for any other supported UTType
}

/// A single item that flowed from the Share Extension into the app.
public struct SharedContent: Codable, Identifiable, Equatable {

    /// Stable identity. We store it as a String so `Identifiable` works in
    /// SwiftUI/diffable data sources without extra bridging.
    public let id: String

    public let kind: SharedContentKind

    /// For `.url` — the absolute string. For `.text` — the text itself.
    /// For file-backed kinds this is usually nil (see `fileName`).
    public let value: String?

    /// Relative filename inside the shared payloads directory, for
    /// file-backed kinds (image/pdf/video/file). Resolve to a full URL via
    /// `SharedDataManager.payloadURL(for:)`.
    public let fileName: String?

    /// Free-form metadata (e.g. suggested title, source app, MIME type).
    public let metadata: [String: String]

    /// Seconds since 1970. We pass the timestamp in explicitly rather than
    /// calling `Date()` at random call sites so behaviour stays testable.
    public let createdAt: TimeInterval

    public init(
        id: String,
        kind: SharedContentKind,
        value: String? = nil,
        fileName: String? = nil,
        metadata: [String: String] = [:],
        createdAt: TimeInterval
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.fileName = fileName
        self.metadata = metadata
        self.createdAt = createdAt
    }
}
