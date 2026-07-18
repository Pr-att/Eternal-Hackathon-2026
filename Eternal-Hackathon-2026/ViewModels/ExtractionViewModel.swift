// MVVM: ViewModel — bridges IngredientExtractor to the UI.
// Views bind to items/isExtracting/errorMessage; no extraction logic lives here.

import Foundation
import Observation

@MainActor
@Observable
final class ExtractionViewModel {
    var items: [ExtractedItem] = []
    var isExtracting = false
    var errorMessage: String?

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
    /// loopback directly; a physical iPhone needs the Mac's LAN IP here.
    // ponytail: hardcoded dev URL; make it a setting if we ever demo off this Mac
    static let backendURL = URL(string: "http://127.0.0.1:8000")!

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
        do {
            if let page = try? await Self.ingest(url: link) {
                var videoPath: String?
                if let videoUrl = page.videoUrl { videoPath = await Self.download(videoUrl) }
                defer { videoPath.map { try? FileManager.default.removeItem(atPath: $0) } }
                items = try await extractor.extract(
                    title: page.title, description: page.description,
                    transcript: page.transcriptText, videoPath: videoPath).items
            } else {
                // backend down or not a supported page — treat as a direct video URL
                guard let videoPath = await Self.download(link) else {
                    throw URLError(.cannotLoadFromNetwork)
                }
                defer { try? FileManager.default.removeItem(atPath: videoPath) }
                items = try await extractor.extract(videoPath: videoPath).items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private static func download(_ link: String) async -> String? {
        guard let url = URL(string: link),
              let (tmp, _) = try? await URLSession.shared.download(from: url) else { return nil }
        let local = tmp.deletingLastPathComponent().appendingPathComponent("video.mp4")
        try? FileManager.default.removeItem(at: local)
        try? FileManager.default.moveItem(at: tmp, to: local)
        return local.path
    }
}
