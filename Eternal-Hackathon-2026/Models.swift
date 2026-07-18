//
//  Models.swift
//  AIRecipeShopping
//

import Foundation

/// A single line item detected from the video (consumable, equipment or staple).
struct GroceryItem {
    let id = UUID()
    let name: String
    let emoji: String          // stand-in for a product thumbnail image
    var isSelected: Bool = true
    var quantity: Int = 1      // adjustable via the "− qty +" stepper
}

/// Picks a sensible stand-in emoji "thumbnail" for a freely-typed item name.
/// Matching is case-insensitive and looks for keywords anywhere in the name, so
/// "2 Ripe Tomatoes" still resolves to 🍅.
enum GroceryEmoji {

    /// Keyword → emoji. Ordered roughly specific-before-generic; the first
    /// keyword found in the name wins.
    private static let map: [(keyword: String, emoji: String)] = [
        // Proteins
        ("chicken", "🍗"), ("mutton", "🍖"), ("lamb", "🍖"), ("beef", "🥩"),
        ("pork", "🥓"), ("bacon", "🥓"), ("fish", "🐟"), ("prawn", "🦐"),
        ("shrimp", "🦐"), ("crab", "🦀"), ("egg", "🥚"), ("paneer", "🧀"),
        ("cheese", "🧀"), ("tofu", "🍥"),
        // Vegetables
        ("onion", "🧅"), ("tomato", "🍅"), ("potato", "🥔"), ("carrot", "🥕"),
        ("chilli", "🌶️"), ("chili", "🌶️"), ("pepper", "🫑"), ("capsicum", "🫑"),
        ("garlic", "🧄"), ("ginger", "🫚"), ("corn", "🌽"), ("mushroom", "🍄"),
        ("broccoli", "🥦"), ("cucumber", "🥒"), ("eggplant", "🍆"),
        ("brinjal", "🍆"), ("spinach", "🥬"), ("lettuce", "🥬"), ("cabbage", "🥬"),
        ("peas", "🫛"), ("bean", "🫘"), ("coriander", "🌿"), ("cilantro", "🌿"),
        ("mint", "🌿"), ("curry leaf", "🌿"), ("leaves", "🌿"),
        // Fruits
        ("apple", "🍎"), ("banana", "🍌"), ("mango", "🥭"), ("lemon", "🍋"),
        ("lime", "🍋"), ("orange", "🍊"), ("grape", "🍇"), ("strawberr", "🍓"),
        ("pineapple", "🍍"), ("coconut", "🥥"), ("avocado", "🥑"),
        // Grains / staples
        ("rice", "🍚"), ("wheat", "🌾"), ("flour", "🌾"), ("atta", "🌾"),
        ("bread", "🍞"), ("pasta", "🍝"), ("noodle", "🍜"), ("oats", "🥣"),
        // Dairy
        ("milk", "🥛"), ("curd", "🥣"), ("yogurt", "🥣"), ("yoghurt", "🥣"),
        ("butter", "🧈"), ("cream", "🍦"), ("ghee", "🧈"),
        // Pantry / condiments
        ("salt", "🧂"), ("sugar", "🍬"), ("honey", "🍯"), ("oil", "🫗"),
        ("water", "💧"), ("masala", "🌶️"), ("spice", "🌶️"), ("turmeric", "🟡"),
        ("sauce", "🥫"), ("ketchup", "🥫"), ("vinegar", "🧴"), ("tea", "🍵"),
        ("coffee", "☕"), ("chocolate", "🍫"), ("nut", "🥜"),
        // Equipment
        ("cooker", "🍲"), ("grinder", "🌀"), ("mixer", "🌀"), ("blender", "🌀"),
        ("pan", "🍳"), ("tawa", "🍳"), ("pot", "🍲"), ("knife", "🔪"),
        ("spoon", "🥄"), ("bowl", "🥣"), ("plate", "🍽️"), ("oven", "🔥")
    ]

    static func guess(for name: String) -> String {
        let lower = name.lowercased()
        for entry in map where lower.contains(entry.keyword) {
            return entry.emoji
        }
        return "🛒"   // generic grocery fallback
    }
}

/// The demo recipe chips on the home screen.
struct DemoRecipe {
    let title: String
    let emoji: String
}

/// Central sample data so every screen shows the same "extracted" cart.
enum SampleData {

    static let demoRecipes: [DemoRecipe] = [
        DemoRecipe(title: "Butter Chicken", emoji: "🍛"),
        DemoRecipe(title: "Veg Biryani",    emoji: "🍚"),
        DemoRecipe(title: "Paneer Tikka",   emoji: "🧆")
    ]

    static let consumables: [GroceryItem] = [
        GroceryItem(name: "Chicken (Curry Cut)", emoji: "🍗"),
        GroceryItem(name: "Onion",               emoji: "🧅"),
        GroceryItem(name: "Tomato",              emoji: "🍅"),
        GroceryItem(name: "Curd",                emoji: "🥣"),
        GroceryItem(name: "Ginger Garlic Paste", emoji: "🧄"),
        GroceryItem(name: "Garam Masala",        emoji: "🌶️"),
        GroceryItem(name: "Green Chilli",        emoji: "🫑"),
        GroceryItem(name: "Coriander Leaves",    emoji: "🌿")
    ]

    static let equipment: [GroceryItem] = [
        GroceryItem(name: "Pressure Cooker", emoji: "🍲"),
        GroceryItem(name: "Mixer Grinder",   emoji: "🌀"),
        GroceryItem(name: "Tawa / Pan",      emoji: "🍳")
    ]

    static let staples: [String] = ["Salt", "Water", "Oil", "Black Pepper"]
}
