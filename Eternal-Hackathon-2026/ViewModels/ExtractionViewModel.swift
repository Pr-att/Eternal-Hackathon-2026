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

    /// Test harness input: a direct video URL (e.g. the `video_url` from the
    /// backend's ingestion.py) is downloaded and analyzed; anything else is
    /// treated as raw recipe text.
    func extract(fromLink link: String) async {
        // terminal copy-paste often brings the JSON quotes along with video_url
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’,"))
        guard link.lowercased().hasPrefix("http"), let url = URL(string: link) else {
            await extract(text: link)
            return
        }
        isExtracting = true
        errorMessage = nil
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let local = tmp.deletingLastPathComponent().appendingPathComponent("video.mp4")
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.moveItem(at: tmp, to: local)
            defer { try? FileManager.default.removeItem(at: local) }
            items = try await extractor.extract(text: nil, videoPath: local.path).items
        } catch {
            errorMessage = error.localizedDescription
        }
        isExtracting = false
    }
}
