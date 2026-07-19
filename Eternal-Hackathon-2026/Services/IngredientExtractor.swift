// MVVM: Service — fully on-device ingredient extraction.
// AVFoundation walks the video at 10 fps keeping only visually-distinct
// frames, Vision runs OCR (+ object classification on the 26 path; on
// iOS/macOS 27 the model instead sees distinct keyframes directly as prompt
// attachments, chunked over up to 3 calls), Apple FoundationModels
// structures the result. No external AI, no network.

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

    static func instructions(frames: Bool) -> String {
        let visual = frames
            ? "[FRAMES] (attached images sampled from the video)"
            : "[VISION] (approximate object labels with frame counts)"
        let visualRule = frames
            ? "Cite FRAMES only for items clearly visible in the attached images."
            : "VISION labels are approximate — trust text blocks over them when they conflict."
        return """
        You aggregate evidence from a cooking video for a grocery assistant. The input \
        is tagged evidence blocks: [TITLE], [DESCRIPTION], [TRANSCRIPT] (spoken words), \
        [TEXT] (user-provided recipe text), [OCR] (on-screen text), \(visual).

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
        usernames, hashtags, and watermarks. \(visualRule) Reject any item the evidence \
        does not support; an empty items list is a valid answer when the input is too vague.
        """
    }

    func extract(
        title: String? = nil,
        description: String? = nil,
        transcript: String? = nil,
        text: String? = nil,
        videoPath: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
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
        // On 27 the model can see actual pixels — skip the garbage classifier
        // labels and keep sampled keyframes to attach to the prompt instead.
        #if compiler(>=6.4)
        var useFrames = false
        if #available(iOS 27.0, macOS 27.0, *) { useFrames = true }
        #else
        let useFrames = false
        #endif

        var keyframes: [CGImage] = []
        if let videoPath, !videoPath.isEmpty {
            do {
                // ponytail: 18 = 6 frames/call × 3 calls; 6 ≈ what one 4096-token
                // context holds after the text blocks (respondWithFrames still
                // trims per call if it doesn't)
                let frames = try await Self.analyzeVideo(
                    videoPath, classify: !useFrames, keyframes: useFrames ? 18 : 0)
                add(.ocr, frames.ocr, cap: 2000)
                add(.vision, frames.vision, cap: 500)
                keyframes = frames.keyframes
            } catch {
                // frames only supplement text evidence — an undecodable video or
                // a Vision-less simulator shouldn't kill a text-backed extraction
                guard !blocks.isEmpty else { throw error }
            }
        }
        onProgress?(0.4)   // frame walk done; the rest is model time
        guard !blocks.isEmpty || !keyframes.isEmpty else { throw ExtractorError.emptyInput }

        var provided = Set(blocks.map(\.0))
        // English anchor line: OCR from Indian reels is often Latin-script
        // Hinglish, which alone trips the model's unsupported-language guardrail
        let prompt = String(("Evidence blocks from a cooking video follow.\n\n"
            + blocks.map { "[\($0.0.rawValue.uppercased())]\n\($0.1)" }
                .joined(separator: "\n\n")).prefix(6000))

        var extraction: Extraction?
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), !keyframes.isEmpty {
            // ≤3 sequential calls, ≤6 frames each — the on-device model
            // serializes requests anyway, so parallel sessions buy nothing;
            // aggregate() below merges duplicate items across calls
            var merged: [ExtractedItem] = []
            var lastError: (any Error)?
            let batches = stride(from: 0, to: keyframes.count, by: 6)
                .map { Array(keyframes[$0..<min($0 + 6, keyframes.count)]) }
            for (i, batch) in batches.enumerated() {
                do {
                    merged += try await Self.respondWithFrames(text: prompt, frames: batch).items
                } catch {
                    // one bad batch (guardrail, beta bug) keeps the others' results
                    lastError = error
                }
                onProgress?(0.4 + 0.6 * Double(i + 1) / Double(batches.count))
            }
            if merged.isEmpty, let lastError {
                // every batch failed — degrade to exactly the 26 text-only
                // behavior below, unless there's no text to fall back on
                guard !blocks.isEmpty else { throw lastError }
            } else {
                extraction = Extraction(items: merged)
                provided.insert(.frames)
            }
        }
        #endif
        if extraction == nil {
            let session = LanguageModelSession(instructions: Self.instructions(frames: false))
            extraction = try await session.respond(to: prompt, generating: Extraction.self).content
        }
        var result = extraction!
        result.items = Self.aggregate(result.items, provided: provided)
        return result
    }

    #if compiler(>=6.4)
    // The only 27-only code: attach keyframes to the prompt, trimming frames
    // until instructions + prompt + output fit the model context.
    @available(iOS 27.0, macOS 27.0, *)
    static func respondWithFrames(text: String, frames: [CGImage]) async throws -> Extraction {
        let model = SystemLanguageModel.default
        var frames = frames
        func build() -> Prompt {
            Prompt {
                text
                "[FRAMES]"
                for f in frames { Attachment(f).label("FRAMES") }
            }
        }
        // ponytail: fixed 1200-token reserve for instructions + schema + output;
        // refine per-part measurement only if real runs still clip
        var prompt = build()
        while frames.count > 1,
              try await model.tokenCount(for: prompt) > model.contextSize - 1200 {
            frames.removeLast()
            prompt = build()
        }
        let session = LanguageModelSession(instructions: instructions(frames: true))
        return try await session.respond(to: prompt, generating: Extraction.self).content
    }
    #endif

    // Deterministic trust layer: drop items whose cited evidence wasn't actually
    // in the input (hallucinations), merge duplicate items by name (within one
    // model call or across chunked keyframe calls) unioning their evidence, and
    // compute confidence from source weights (noisy-or) instead of trusting the
    // model's own estimate.
    static func aggregate(_ items: [ExtractedItem], provided: Set<EvidenceSource>) -> [ExtractedItem] {
        var out: [ExtractedItem] = []
        var index: [String: Int] = [:]   // merge key -> position in out
        for var item in items {
            let cited = item.evidence.filter { provided.contains($0) }
            guard !cited.isEmpty else { continue }
            // the model sometimes snake_cases names or pads them with spaces
            item.name = item.name.replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespaces)
            // junk guard: OCR noise can yield empty or absurd "ingredients"
            guard item.name.contains(where: \.isLetter), item.name.count <= 60 else { continue }
            // ponytail: naive plural key ("onions" == "onion"); the app layer
            // adds synonym/Hinglish dedup via IngredientIcon.canonical
            var key = item.name.lowercased()
            if key.hasSuffix("s") { key = String(key.dropLast()) }
            // same item seen again: union evidence, keep the shorter (usually
            // singular) name; first occurrence keeps category/quantity
            if let i = index[key] {
                if item.name.count < out[i].name.count { out[i].name = item.name }
                for e in cited where !out[i].evidence.contains(e) { out[i].evidence.append(e) }
            } else {
                item.evidence = cited.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
                index[key] = out.count
                out.append(item)
            }
        }
        return out.map {
            var item = $0
            item.confidence = min(0.99, 1 - item.evidence.reduce(1) { $0 * (1 - Self.weight($1)) })
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
        case .frames: 0.7   // model saw actual pixels; beats classifier labels, below named-in-text
        case .description, .title: 0.55
        case .vision: 0.42
        }
    }

    // Scene-diff thumbnail: 32×32 grayscale via CoreGraphics — CPU-only, so it
    // works on the simulator where Vision's neural models don't. nil = context
    // failed → caller keeps the frame (never silently drop evidence).
    static func grayThumb(_ image: CGImage) -> [UInt8]? {
        var px = [UInt8](repeating: 0, count: 32 * 32)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 32, height: 32,
                                      bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        return ok ? px : nil
    }

    static func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0
        for i in a.indices { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(a.count)   // 0…255
    }

    // Walk the video at 10 fps, drop frames that look like the last kept one
    // (scene gate), OCR (and optionally classify) each distinct frame, and
    // return deduplicated OCR text and vision labels as separate evidence
    // blocks — plus, for the 27 image path, up to `keyframes` distinct frames
    // spread evenly across the video's scene changes. Dense sampling is fine
    // here: decode is one sequential hardware pass, and the scene gate keeps
    // the expensive Vision work bounded by distinct scenes, not duration.
    static func analyzeVideo(
        _ path: String, classify: Bool = true, keyframes keyframeCount: Int = 0
    ) async throws -> (ocr: String?, vision: String?, keyframes: [CGImage]) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        // VP9/AV1 streams and botched downloads surface here: no decodable video track
        guard let duration = try? await asset.load(.duration).seconds, duration > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              (try? await tracks[0].load(.formatDescriptions))?.isEmpty == false else {
            throw ExtractorError.unreadableVideo
        }
        // ponytail: 10 fps to catch sub-second flashes, 900-decode cap — full
        // density up to 90s (reel max), ~3 fps at 5 min; raise cap if long
        // videos miss items
        let step = max(0.1, duration / 900)
        let times = stride(from: 0.0, to: duration, by: step)
            .map { CMTime(seconds: $0, preferredTimescale: 600) }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 768, height: 768)
        // tolerance = half the stride: a fixed ±0.5s window at a 0.1s stride
        // would legally snap neighboring requests to the same decoded frame
        gen.requestedTimeToleranceBefore = CMTime(seconds: step / 2, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: step / 2, preferredTimescale: 600)

        var lastThumb: [UInt8]?
        var candidates: [CGImage] = []
        var thin = 1, keptCount = 0

        var seenLines = Set<String>()
        var ocrLines: [String] = []
        var labelCounts: [String: Int] = [:]
        var visionError: (any Error)?

        for await result in gen.images(for: times) {
            guard let image = try? result.image else { continue }
            // scene gate: skip frames that look like the last KEPT frame.
            // ponytail: threshold 20/255 mean |Δgray| ≈ 8% luminance; hand-motion
            // churn ≲15 (measured on the fixture reel), hard cut ≳25 — recalibrate
            // on real reels; upgrade to VNGenerateImageFeaturePrintRequest
            // distance if flicker churns
            if let thumb = Self.grayThumb(image) {
                if let last = lastThumb, Self.meanAbsDiff(thumb, last) < 20 { continue }
                lastThumb = thumb
            }
            if keyframeCount > 0 {
                if keptCount % thin == 0 { candidates.append(image) }
                keptCount += 1
                // ponytail: memory cap — past 2× the ask, halve the list and keep
                // every 2nd future frame; ≤2N retained CGImages, spread stays even
                if candidates.count > 2 * keyframeCount {
                    candidates = stride(from: 0, to: candidates.count, by: 2).map { candidates[$0] }
                    thin *= 2
                }
            }
            let handler = VNImageRequestHandler(cgImage: image)
            let textReq = VNRecognizeTextRequest()
            textReq.recognitionLevel = .accurate
            let classReq = VNClassifyImageRequest()
            // performed separately so a classify failure can't take OCR down with it
            do { try handler.perform([textReq]) } catch { visionError = error }
            if classify {
                do { try handler.perform([classReq]) } catch { visionError = error }
            }

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
        // plus a Vision error means the environment failed, not an empty video —
        // unless keyframes were captured, which are evidence by themselves.
        var kept = candidates
        if keyframeCount > 0, kept.count > keyframeCount {
            kept = (0..<keyframeCount).map { kept[$0 * kept.count / keyframeCount] }
        }
        if ocrLines.isEmpty, labelCounts.isEmpty, kept.isEmpty, let visionError {
            throw ExtractorError.visionUnavailable(visionError.localizedDescription)
        }

        let ocr = ocrLines.isEmpty ? nil : ocrLines.joined(separator: "\n")
        let vision = labelCounts.isEmpty ? nil : labelCounts.sorted { $0.value > $1.value }
            .prefix(25).map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
        return (ocr, vision, kept)
    }
}
