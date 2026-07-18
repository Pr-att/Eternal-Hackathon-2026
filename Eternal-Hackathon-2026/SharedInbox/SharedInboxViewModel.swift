//
//  SharedInboxViewModel.swift
//  Eternal-Hackathon-2026 (main app)
//
//  MVVM view model for the screen that displays content received from the
//  Share Extension. It owns state + formatting; the view controller only
//  renders `rows` and reacts to `onChange`. No UIKit imports here (except
//  UIImage for thumbnail loading), keeping it testable.
//

import UIKit

/// The typed payload of a row — this is what actually separates a link from
/// plain text at the model level, instead of both being an untyped `title`
/// string. Consumers can switch on it to open a URL, copy text, preview a
/// file, etc.
enum SharedInboxContent: Equatable {
    case link(URL)
    case text(String)
    case file(kind: SharedContentKind, fileName: String?)
}

/// A presentation-ready row derived from a `SharedContent`.
struct SharedInboxRow {
    let id: String
    /// The separated, strongly-typed content (link vs text vs file).
    let content: SharedInboxContent
    let title: String
    let subtitle: String
    let symbolName: String     // SF Symbol for the leading icon
    let thumbnail: UIImage?    // nil for non-image kinds
}

/// A titled group of rows — gives the "clear separation between links and
/// other text" the UI shows as distinct table sections.
struct SharedInboxSection {
    let title: String
    let rows: [SharedInboxRow]
}

final class SharedInboxViewModel {

    /// Simple binding hook the VC assigns to get reloads on the main thread.
    var onChange: (() -> Void)?

    /// Rows grouped into sections (Links / Text / Files & Media). Only
    /// non-empty sections are included.
    private(set) var sections: [SharedInboxSection] = [] {
        didSet { DispatchQueue.main.async { [weak self] in self?.onChange?() } }
    }

    private let store: SharedDataManager
    private var content: [SharedContent] = []

    init(store: SharedDataManager = .shared) {
        self.store = store
    }

    /// Feed items delivered via the `.didReceiveSharedContent` notification.
    func ingest(_ items: [SharedContent]) {
        // Newest first.
        content.insert(contentsOf: items, at: 0)
        rebuildRows()
    }

    /// Also pick up anything still queued (e.g. app opened manually).
    func loadPending() {
        let pending = store.drainPendingItems()
        if !pending.isEmpty { ingest(pending) }
        else { rebuildRows() }
    }

    var isEmpty: Bool { content.isEmpty }

    // MARK: - Section building

    private func rebuildRows() {
        // Split by kind so links and text are visibly separated.
        let links = content.filter { $0.kind == .url }
        let texts = content.filter { $0.kind == .text }
        let files = content.filter { ![.url, .text].contains($0.kind) }

        var built: [SharedInboxSection] = []
        if !links.isEmpty { built.append(SharedInboxSection(title: "Links", rows: links.map(row(for:)))) }
        if !texts.isEmpty { built.append(SharedInboxSection(title: "Text", rows: texts.map(row(for:)))) }
        if !files.isEmpty { built.append(SharedInboxSection(title: "Files & Media", rows: files.map(row(for:)))) }
        sections = built
    }

    private func row(for item: SharedContent) -> SharedInboxRow {
        switch item.kind {
        case .url:
            // A link resolves to a URL payload; if the string can't be parsed
            // as a URL we fall back to treating it as text, so the model never
            // lies about being a valid link.
            if let raw = item.value, let url = URL(string: raw) {
                return SharedInboxRow(id: item.id, content: .link(url), title: raw,
                                      subtitle: "Link", symbolName: "link", thumbnail: nil)
            }
            return SharedInboxRow(id: item.id, content: .text(item.value ?? ""),
                                  title: item.value ?? "Link", subtitle: "Text",
                                  symbolName: "text.alignleft", thumbnail: nil)
        case .text:
            let text = item.value ?? ""
            return SharedInboxRow(id: item.id, content: .text(text),
                                  title: String(text.prefix(120)), subtitle: "Text",
                                  symbolName: "text.alignleft", thumbnail: nil)
        case .image:
            return SharedInboxRow(id: item.id, content: .file(kind: .image, fileName: item.fileName),
                                  title: item.metadata["originalName"] ?? "Image",
                                  subtitle: "Image", symbolName: "photo", thumbnail: thumbnail(for: item))
        case .pdf:
            return SharedInboxRow(id: item.id, content: .file(kind: .pdf, fileName: item.fileName),
                                  title: item.metadata["originalName"] ?? "Document.pdf",
                                  subtitle: "PDF", symbolName: "doc.richtext", thumbnail: nil)
        case .video:
            return SharedInboxRow(id: item.id, content: .file(kind: .video, fileName: item.fileName),
                                  title: item.metadata["originalName"] ?? "Video",
                                  subtitle: "Video", symbolName: "video", thumbnail: nil)
        case .file:
            return SharedInboxRow(id: item.id, content: .file(kind: .file, fileName: item.fileName),
                                  title: item.metadata["originalName"] ?? "File",
                                  subtitle: "File", symbolName: "doc", thumbnail: nil)
        }
    }

    /// Lightweight thumbnail load. This runs in the MAIN app (not the
    /// extension), so it's an acceptable place to touch disk. For large
    /// libraries you'd downsample; kept simple here.
    private func thumbnail(for item: SharedContent) -> UIImage? {
        guard let name = item.fileName,
              let url = store.payloadURL(for: name),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
