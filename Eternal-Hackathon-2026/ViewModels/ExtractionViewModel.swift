// MVVM: ViewModel — bridges IngredientExtractor to the UI.
// Views bind to items/isExtracting/errorMessage; no extraction logic lives here.

import Foundation
import Observation

@MainActor
@Observable
final class ExtractionViewModel {
    var items: [ExtractedItem] = [] {
        didSet {
            // debug: mirror the on-device model output to the Xcode console
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(items), let json = String(data: data, encoding: .utf8) {
                print("🍽 extraction result (\(items.count) items):\n\(json)")
            }
        }
    }
    var isExtracting = false
    var errorMessage: String?
    /// 0…1 pipeline progress: byte-accurate while the video downloads
    /// (Content-Length vs bytes received), milestone-based around it —
    /// on-device model generation exposes no progress to measure.
    var progress: Double = 0

    private let extractor = IngredientExtractor()

    func extract(text: String?, videoPath: String? = nil) async {
        isExtracting = true
        errorMessage = nil
        do {
            items = try await extractor.extract(text: text, videoPath: videoPath).items
        } catch {
            errorMessage = error.localizedDescription
        }
        isExtracting = false
    }

    /// Backend ingestion API (server.py). The simulator reaches the Mac's
    /// loopback directly; a physical iPhone needs the Mac's LAN IP here —
    /// update it when the network changes (server must run with --host 0.0.0.0).
    // ponytail: hardcoded dev URL; make it a setting if we ever demo off this Mac
    #if targetEnvironment(simulator)
    static let backendURL = URL(string: "http://127.0.0.1:8000")!
    #else
    static let backendURL = URL(string: "http://10.13.2.27:8000")!
    #endif

    private struct IngestResponse: Decodable {
        var title: String?
        var description: String?
        var transcriptText: String?
        var videoUrl: String?
    }

    /// A YouTube/Instagram page link is ingested via the backend (title +
    /// description + transcript, frames as supplement); any other http URL is
    /// treated as a direct video file; anything else as raw recipe text.
    func extract(fromLink link: String) async {
        // terminal copy-paste often brings the JSON quotes along with the URL
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’,"))
        guard link.lowercased().hasPrefix("http"), URL(string: link) != nil else {
            await extract(text: link)
            return
        }
        isExtracting = true
        errorMessage = nil
        progress = 0.05                       // ingesting metadata
        // the video download spans 15%→60% of the pipeline, byte-accurate
        let downloadSlice: @Sendable (Double) -> Void = { [weak self] fraction in
            guard let self else { return }
            Task { @MainActor in self.progress = 0.15 + 0.45 * fraction }
        }
        // extraction (frame walk + per-batch model calls) spans 60%→100%
        let extractSlice: @Sendable (Double) -> Void = { [weak self] fraction in
            guard let self else { return }
            Task { @MainActor in self.progress = 0.6 + 0.4 * fraction }
        }
        do {
            if let page = try? await Self.ingest(url: link) {
                progress = 0.15
                var videoPath: String?
                if let videoUrl = page.videoUrl {
                    videoPath = await Self.download(videoUrl, onProgress: downloadSlice)
                }
                progress = 0.6
                defer { videoPath.map { try? FileManager.default.removeItem(atPath: $0) } }
                items = try await extractor.extract(
                    title: page.title, description: page.description,
                    transcript: page.transcriptText, videoPath: videoPath,
                    onProgress: extractSlice).items
            } else {
                // backend down or not a supported page — treat as a direct video URL
                guard let videoPath = await Self.download(link, onProgress: downloadSlice) else {
                    throw URLError(.cannotLoadFromNetwork)
                }
                progress = 0.6
                defer { try? FileManager.default.removeItem(atPath: videoPath) }
                items = try await extractor.extract(videoPath: videoPath,
                                                    onProgress: extractSlice).items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        if errorMessage == nil { progress = 1 }
        isExtracting = false
    }

    private static func ingest(url: String) async throws -> IngestResponse {
        var components = URLComponents(url: backendURL.appendingPathComponent("ingest"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "url", value: url)]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(IngestResponse.self, from: data)
    }

    private static func download(_ link: String,
                                 onProgress: (@Sendable (Double) -> Void)? = nil) async -> String? {
        guard let url = URL(string: link),
              let (tmp, _) = try? await URLSession.shared.download(
                  from: url, delegate: onProgress.map(DownloadProgress.init)) else { return nil }
        let local = tmp.deletingLastPathComponent().appendingPathComponent("video.mp4")
        try? FileManager.default.removeItem(at: local)
        try? FileManager.default.moveItem(at: tmp, to: local)
        return local.path
    }
}

/// Byte-accurate download fraction: totalBytesWritten / Content-Length.
/// A server that streams chunked (no Content-Length) reports -1 expected
/// bytes and produces no updates — the milestone progress still moves.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void
    init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    // the async download(from:delegate:) call already hands back the file;
    // this required delegate method has nothing left to do
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
