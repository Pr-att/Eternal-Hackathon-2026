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
