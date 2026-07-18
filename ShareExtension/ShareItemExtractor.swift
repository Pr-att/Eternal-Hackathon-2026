//
//  ShareItemExtractor.swift
//  ShareExtension
//
//  Turns the raw `NSExtensionContext` handed to the extension into an array
//  of clean `SharedContent` values. This is the "read NSExtensionItem →
//  NSItemProvider → load object" layer, wrapped in async/await so the
//  callback-based `loadItem`/`loadDataRepresentation` APIs read linearly.
//
//  Keep this FAST: it only extracts and copies bytes into the shared
//  container. No network, no thumbnailing, no parsing — that belongs in the
//  main app.
//

import Foundation
import UniformTypeIdentifiers

/// Errors specific to extraction.
enum ExtractionError: LocalizedError {
    case emptyShare
    case unsupportedContent
    case loadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .emptyShare:        return "Nothing was shared."
        case .unsupportedContent: return "This type of content isn't supported yet."
        case .loadFailed(let e): return "Couldn't load the shared item: \(e.localizedDescription)"
        }
    }
}

struct ShareItemExtractor {

    private let store: SharedDataManager
    /// Timestamp injected once per extraction so every produced item shares a
    /// consistent, testable `createdAt`.
    private let now: TimeInterval

    init(store: SharedDataManager = .shared, now: TimeInterval) {
        self.store = store
        self.now = now
    }

    /// Content types we advertise support for, ordered by how we prefer to
    /// interpret an attachment. To support a NEW type later: add its UTType
    /// here AND widen the NSExtensionActivationRule in Info.plist.
    private static let supportedTypes: [UTType] = [
        .url, .plainText, .image, .pdf, .movie
    ]

    /// Extracts every attachment from every extension item.
    /// - Returns: parsed `SharedContent` values (may be empty).
    /// - Throws: `ExtractionError.emptyShare` when there is genuinely nothing.
    func extract(from items: [NSExtensionItem]) async throws -> [SharedContent] {
        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { throw ExtractionError.emptyShare }

        var results: [SharedContent] = []
        // Process sequentially: disk writes to the shared container are cheap
        // and sequential keeps ordering/labels predictable for multi-share.
        // A single attachment can produce SEVERAL items (e.g. text with an
        // embedded link → one .url + one .text), so we collect arrays.
        for provider in providers {
            let items = try await parse(provider)
            results.append(contentsOf: items)
        }

        guard !results.isEmpty else { throw ExtractionError.unsupportedContent }
        return results
    }

    // MARK: - Per-provider parsing

    private func parse(_ provider: NSItemProvider) async throws -> [SharedContent] {
        // Order matters: a provider may conform to several types (e.g. a URL
        // also conforms to public.text). Check the most specific first.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return try await loadURL(provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return try await loadFile(provider, as: .image, kind: .image)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return try await loadFile(provider, as: .pdf, kind: .pdf)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return try await loadFile(provider, as: .movie, kind: .video)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return try await loadText(provider)
        }
        // Unknown attachment — skip it rather than failing the whole share.
        return []
    }

    // MARK: - Loaders

    private func loadURL(_ provider: NSItemProvider) async throws -> [SharedContent] {
        let object = try await loadItem(provider, typeIdentifier: UTType.url.identifier)
        // `loadItem` for public.url yields an NSURL (web or file URL).
        if let url = object as? URL {
            if url.isFileURL {
                // A file URL masquerading as public.url — copy the bytes.
                return [try copyFile(at: url, kind: kind(forFileURL: url))]
            }
            return [store.makeURLItem(url, metadata: ["source": "public.url"], now: now)]
        }
        if let str = object as? String, let url = URL(string: str) {
            return [store.makeURLItem(url, now: now)]
        }
        throw ExtractionError.unsupportedContent
    }

    private func loadText(_ provider: NSItemProvider) async throws -> [SharedContent] {
        let object = try await loadItem(provider, typeIdentifier: UTType.plainText.identifier)
        guard let raw = object as? String else { throw ExtractionError.unsupportedContent }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ExtractionError.unsupportedContent }
        return splitLinksAndText(text)
    }

    /// Cleanly separates any links embedded in shared text from the remaining
    /// prose. "Read this https://apple.com now" → a `.url` item for the link
    /// AND a `.text` item "Read this now". A bare pasted URL becomes just a
    /// `.url` item. Text with no links stays a single `.text` item.
    private func splitLinksAndText(_ text: String) -> [SharedContent] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return [store.makeTextItem(text, now: now)]
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else {
            // No links — it's pure text.
            return [store.makeTextItem(text, now: now)]
        }

        var linkItems: [SharedContent] = []
        var remaining = text
        for match in matches {
            guard let url = match.url else { continue }
            linkItems.append(store.makeURLItem(url, metadata: ["source": "detected-in-text"], now: now))
            if let range = Range(match.range, in: text) {
                remaining = remaining.replacingOccurrences(of: String(text[range]), with: " ")
            }
        }

        // Whatever prose is left after removing the URLs, collapsed.
        let prose = remaining
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        var items = linkItems
        if !prose.isEmpty {
            // Text first, then its links — a natural reading order.
            items.insert(store.makeTextItem(prose, now: now), at: 0)
        }
        return items.isEmpty ? [store.makeTextItem(text, now: now)] : items
    }

    /// Generic file-backed loader used for image/pdf/video. Prefers
    /// `loadFileRepresentation` (gives a temp file URL we copy) and falls
    /// back to an in-memory data representation.
    private func loadFile(_ provider: NSItemProvider, as type: UTType, kind: SharedContentKind) async throws -> [SharedContent] {
        // Fast path: file representation → copy from temp URL.
        if let url = try? await loadFileRepresentation(provider, typeIdentifier: type.identifier) {
            return [try copyFile(at: url, kind: kind)]
        }
        // Fallback: raw data representation.
        let data = try await loadDataRepresentation(provider, typeIdentifier: type.identifier)
        let ext = type.preferredFilenameExtension ?? "dat"
        let fileName = try store.storePayload(data, preferredExtension: ext)
        return [store.makeFileItem(kind: kind, fileName: fileName,
                                   metadata: ["uti": type.identifier], now: now)]
    }

    /// Copies a (temporary) file URL into the shared container.
    private func copyFile(at url: URL, kind: SharedContentKind) throws -> SharedContent {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let fileName = try store.storePayload(data, preferredExtension: ext)
        return store.makeFileItem(kind: kind, fileName: fileName,
                                  metadata: ["originalName": url.lastPathComponent], now: now)
    }

    private func kind(forFileURL url: URL) -> SharedContentKind {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .file }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf)   { return .pdf }
        if type.conforms(to: .movie) { return .video }
        return .file
    }

    // MARK: - async/await bridges over the callback APIs

    private func loadItem(_ provider: NSItemProvider, typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { object, error in
                if let error { continuation.resume(throwing: ExtractionError.loadFailed(error)) }
                else { continuation.resume(returning: object) }
            }
        }
    }

    private func loadFileRepresentation(_ provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // The provided URL is only valid inside the completion handler,
            // so we read/copy synchronously before it's cleaned up.
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error { continuation.resume(throwing: ExtractionError.loadFailed(error)); return }
                guard let url else { continuation.resume(throwing: ExtractionError.unsupportedContent); return }
                do {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: tmp)
                    continuation.resume(returning: tmp)
                } catch {
                    continuation.resume(throwing: ExtractionError.loadFailed(error))
                }
            }
        }
    }

    private func loadDataRepresentation(_ provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error { continuation.resume(throwing: ExtractionError.loadFailed(error)); return }
                guard let data else { continuation.resume(throwing: ExtractionError.unsupportedContent); return }
                continuation.resume(returning: data)
            }
        }
    }
}
