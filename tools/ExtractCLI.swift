// CLI shim so the Python backend can call the app's on-device extraction.
// Reuses the app's MVVM Model + Service files — no logic duplicated here.
//
// stdin:  {"title", "description", "transcript", "text", "video_path"}   (all optional)
// stdout: {"items": [{"name", "category", "estimated_quantity", "unit", "evidence", "confidence"}]}
// `--selfcheck` runs the deterministic evidence-aggregation checks (no model needed).
//
// Built automatically by backend/extraction.py; manual build:
//   swiftc -O -parse-as-library \
//     Eternal-Hackathon-2026/Models/ExtractedItem.swift \
//     Eternal-Hackathon-2026/Services/IngredientExtractor.swift \
//     tools/ExtractCLI.swift -o backend/apple_extract

import Foundation

struct Input: Codable {
    var title: String?
    var description: String?
    var transcript: String?
    var text: String?
    var video_path: String?
}

func selfcheck() {
    let item = { (name: String, evidence: [EvidenceSource]) in
        ExtractedItem(name: name, category: .consumable, estimatedQuantity: nil,
                      unit: nil, evidence: evidence, confidence: 0)
    }
    let out = IngredientExtractor.aggregate(
        [item("tomato", [.ocr, .transcript]),
         item("chicken", []),                        // no evidence: hallucination, dropped
         item("paneer", [.transcript, .transcript]), // duplicate citation deduped
         item("ghost", [.text]),                     // cites a block not provided, dropped
         item("pizza", [.vision]),
         item("paratha", [.frames, .transcript]),    // iOS 27 image path + transcript
         item("tawa", [.frames]),                    // frames-only: suggest, never auto-add
         item("onions", [.ocr]),                     // same item from two chunked model
         item("onion", [.frames])],                  // calls: plural-merged, singular kept
        provided: [.ocr, .transcript, .vision, .frames])
    precondition(out.map(\.name) == ["tomato", "paneer", "pizza", "paratha", "tawa", "onion"])
    precondition(out[0].confidence > 0.95 && out[0].evidence == [.ocr, .transcript])
    precondition(abs(out[1].confidence - 0.82) < 1e-9 && out[1].evidence == [.transcript])
    precondition(abs(out[2].confidence - 0.42) < 1e-9)
    precondition(abs(out[3].confidence - 0.946) < 1e-9)  // 1 - (1-0.7)(1-0.82)
    precondition(abs(out[4].confidence - 0.7) < 1e-9)
    precondition(out[5].evidence == [.ocr, .frames])
    precondition(abs(out[5].confidence - 0.955) < 1e-6)  // 1 - (1-0.85)(1-0.7)
    print("selfcheck ok")
}

@main
struct ExtractCLI {
    static func main() async {
        if CommandLine.arguments.contains("--selfcheck") { return selfcheck() }
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let input = try JSONDecoder().decode(Input.self, from: data)
            let result = try await IngredientExtractor().extract(
                title: input.title, description: input.description,
                transcript: input.transcript, text: input.text,
                videoPath: input.video_path)

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            print(String(data: try encoder.encode(result), encoding: .utf8)!)
        } catch let error as IngredientExtractor.ExtractorError {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}
