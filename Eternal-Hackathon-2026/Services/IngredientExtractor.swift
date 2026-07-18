// MVVM: Service — fully on-device ingredient extraction.
// AVFoundation walks the video ~1 frame/second, Vision runs OCR + object
// classification per frame, Apple FoundationModels structures the result.
// No external AI, no network.

import AVFoundation
import Foundation
import FoundationModels
import Vision

struct IngredientExtractor {

    enum ExtractorError: LocalizedError {
        case modelUnavailable(String)
        case emptyInput
        case unreadableVideo
        case visionUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let status):
                return "Apple Intelligence model unavailable (\(status)) — enable Apple Intelligence in Settings"
            case .emptyInput:
                return "no text or video to analyze"
            case .unreadableVideo:
                return "couldn't decode the video (likely a VP9/AV1 stream, which Apple devices can't play, or a failed download) — get a fresh H.264 video_url from ingestion.py"
            case .visionUnavailable(let detail):
                return "video frame analysis unavailable (\(detail)) — the iOS simulator can't run Vision's neural models; test the video path on a real device or via backend/extraction.py, or paste recipe text instead"
            }
        }
    }

    static let instructions = """
    You aggregate evidence from a cooking video for a grocery assistant. The input \
    is tagged evidence blocks: [TITLE], [DESCRIPTION], [TRANSCRIPT] (spoken words), \
    [TEXT] (user-provided recipe text), [OCR] (on-screen text), [VISION] (approximate \
    object labels with frame counts).

    For every food item and piece of cooking equipment the evidence supports, output:
    - name: normalized, singular, lowercase; merge synonyms and duplicates into one item
    - category: consumable = an ingredient used up by the recipe that would need to be \
    bought (chicken, onion, turmeric, paneer); staple = a consumable so commonly already \
    owned it should not be added to a cart (salt, water, a little cooking oil); \
    equipment = a reusable tool or appliance, never bought automatically (pressure \
    cooker, tawa, oven, mixer grinder)
    - evidence: the tag of every block that actually mentions or shows the item — \
    cite only tags present in the input

    You are an aggregator, not a recipe expert. Never add typical ingredients for a \
    dish or guess from the dish name what "must" be in it. Ignore OCR noise like \
    usernames, hashtags, and watermarks. VISION labels are approximate — trust text \
    blocks over them when they conflict. Reject any item the evidence does not \
    support; an empty items list is a valid answer when the input is too vague.
    """

    func extract(
        title: String? = nil,
        description: String? = nil,
        transcript: String? = nil,
        text: String? = nil,
        videoPath: String? = nil
    ) async throws -> Extraction {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw ExtractorError.modelUnavailable("\(model.availability)")
        }

        // Tagged evidence blocks, text first — the small on-device model weights
        // early context most, and text usually names the actual dish/ingredients.
        // ponytail: hard per-block char caps — the model's context is 4096 tokens
        // total (prompt + output); summarize-then-extract if recipes get cut off
        var blocks: [(EvidenceSource, String)] = []
        func add(_ source: EvidenceSource, _ value: String?, cap: Int) {
            if let value, !value.isEmpty { blocks.append((source, String(value.prefix(cap)))) }
        }
        add(.title, title, cap: 150)
        add(.description, description, cap: 1000)
        add(.transcript, transcript, cap: 1800)
        add(.text, text, cap: 2500)
        if let videoPath, !videoPath.isEmpty {
            let frames = try await Self.analyzeVideo(videoPath)
            add(.ocr, frames.ocr, cap: 2000)
            add(.vision, frames.vision, cap: 500)
        }
        guard !blocks.isEmpty else { throw ExtractorError.emptyInput }

        let provided = Set(blocks.map(\.0))
        // English anchor line: OCR from Indian reels is often Latin-script
        // Hinglish, which alone trips the model's unsupported-language guardrail
        let prompt = String(("Evidence blocks from a cooking video follow.\n\n"
            + blocks.map { "[\($0.0.rawValue.uppercased())]\n\($0.1)" }
                .joined(separator: "\n\n")).prefix(6000))

        let session = LanguageModelSession(instructions: Self.instructions)
        var extraction = try await session.respond(to: prompt, generating: Extraction.self).content
        extraction.items = Self.aggregate(extraction.items, provided: provided)
        return extraction
    }

    // Deterministic trust layer: drop items whose cited evidence wasn't actually
    // in the input (hallucinations), dedupe the citations, and compute confidence
    // from source weights (noisy-or) instead of trusting the model's own estimate.
    static func aggregate(_ items: [ExtractedItem], provided: Set<EvidenceSource>) -> [ExtractedItem] {
        items.compactMap { item in
            var cited: [EvidenceSource] = []
            for e in item.evidence where provided.contains(e) && !cited.contains(e) {
                cited.append(e)
            }
            guard !cited.isEmpty else { return nil }
            var item = item
            // the model sometimes snake_cases names, mimicking the JSON schema
            item.name = item.name.replacingOccurrences(of: "_", with: " ")
            item.evidence = cited
            item.confidence = min(0.99, 1 - cited.reduce(1) { $0 * (1 - Self.weight($1)) })
            return item
        }
    }

    // Fixed trust per source. Cart policy downstream: vision-alone (0.42) never
    // auto-adds, description-only (0.55) = suggest for review.
    // ponytail: hand-tuned constants; recalibrate against real videos if ranking is off
    static func weight(_ source: EvidenceSource) -> Double {
        switch source {
        case .text: 0.95
        case .ocr: 0.85
        case .transcript: 0.82
        case .description, .title: 0.55
        case .vision: 0.42
        }
    }

    // Walk the video ~1 frame/second, OCR + classify each frame, and return
    // deduplicated OCR text and vision labels as separate evidence blocks.
    // Dense sampling is fine here: Vision is on-device and fast, and
    // aggregation keeps the language-model prompt small.
    static func analyzeVideo(_ path: String) async throws -> (ocr: String?, vision: String?) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        // VP9/AV1 streams and botched downloads surface here: no decodable video track
        guard let duration = try? await asset.load(.duration).seconds, duration > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              (try? await tracks[0].load(.formatDescriptions))?.isEmpty == false else {
            throw ExtractorError.unreadableVideo
        }
        // ponytail: 1s stride, 300-frame cap; items on screen < 1s can still be missed
        let step = max(1.0, duration / 300)
        let times = stride(from: 0.0, to: duration, by: step)
            .map { CMTime(seconds: $0, preferredTimescale: 600) }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 768, height: 768)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var seenLines = Set<String>()
        var ocrLines: [String] = []
        var labelCounts: [String: Int] = [:]
        var visionError: (any Error)?

        for await result in gen.images(for: times) {
            guard let image = try? result.image else { continue }
            let handler = VNImageRequestHandler(cgImage: image)
            let textReq = VNRecognizeTextRequest()
            textReq.recognitionLevel = .accurate
            let classReq = VNClassifyImageRequest()
            // performed separately so a classify failure can't take OCR down with it
            do { try handler.perform([textReq]) } catch { visionError = error }
            do { try handler.perform([classReq]) } catch { visionError = error }

            for line in textReq.results?.compactMap({ $0.topCandidates(1).first?.string }) ?? []
            where seenLines.insert(line).inserted {
                ocrLines.append(line)
            }
            // ponytail: raw confidence > 0.3 is a rough cut; tune if labels get noisy
            for obs in classReq.results ?? [] where obs.confidence > 0.3 {
                labelCounts[obs.identifier, default: 0] += 1
            }
        }

        // The iOS simulator can't run Vision's neural models ("Failed to create
        // espresso context"; OCR just silently returns nothing). Zero evidence
        // plus a Vision error means the environment failed, not an empty video.
        if ocrLines.isEmpty, labelCounts.isEmpty, let visionError {
            throw ExtractorError.visionUnavailable(visionError.localizedDescription)
        }

        let ocr = ocrLines.isEmpty ? nil : ocrLines.joined(separator: "\n")
        let vision = labelCounts.isEmpty ? nil : labelCounts.sorted { $0.value > $1.value }
            .prefix(25).map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
        return (ocr, vision)
    }
}
