// MVVM: Model — on-device ingredient extraction output types.
// Shared by the iOS app and the backend CLI (tools/ExtractCLI.swift).

import Foundation
import FoundationModels

@Generable
enum ItemCategory: String, Codable {
    case consumable   // ingredient to buy
    case staple       // commonly owned already — suggest, don't add to cart
    case equipment    // reusable tool — never auto-added to cart
}

// Tags of the input blocks an item can cite as support. Raw values (uppercased)
// are the block headers in the prompt, e.g. [OCR].
@Generable
enum EvidenceSource: String, Codable {
    case title, description, transcript, text, ocr, vision, frames
}

@Generable
struct ExtractedItem: Codable {
    @Guide(description: "item name, normalized, singular, lowercase; synonyms and duplicates merged")
    var name: String
    @Guide(description: "consumable = ingredient to buy; staple = commonly owned already (salt, water, small amounts of oil); equipment = reusable tool or appliance")
    var category: ItemCategory
    @Guide(description: "quantity if stated, else null")
    var estimatedQuantity: Double?
    @Guide(description: "unit for the quantity (g, kg, ml, cup, tbsp, piece), else null")
    var unit: String?
    @Guide(description: "tags of every input block that mentions or shows this item; cite only blocks present in the input")
    var evidence: [EvidenceSource]
    // Not trusted from the model — overwritten deterministically from evidence
    // (IngredientExtractor.aggregate) before the extraction is returned.
    @Guide(description: "0 to 1: how sure this item is actually needed for this recipe")
    var confidence: Double
}

@Generable
struct Extraction: Codable {
    var items: [ExtractedItem]
}
