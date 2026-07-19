//
//  Models.swift
//  AIRecipeShopping
//

import Foundation

/// A single line item detected from the video (consumable, equipment or staple).
struct GroceryItem {
    let id = UUID()
    let name: String
    let emoji: String          // fallback thumbnail when no SVG asset exists
    var imageName: String? = nil   // asset-catalog name (SVG); canonical ingredient id
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
    /// A short, appetizing summary shown above the ingredient list.
    let description: String
    /// Quick facts shown as pills: total time, servings, difficulty.
    let time: String
    let serves: String
    let difficulty: String
    /// Hardcoded ingredients shown when the chip is tapped (name, category).
    let ingredients: [(name: String, category: ItemCategory)]
    /// Step-by-step cooking method.
    let steps: [String]
}

/// Zero-asset product icons: map a model-emitted ingredient name (English,
/// plural, or Hinglish) to a canonical name + emoji thumbnail. This synonym
/// table doubles as the seed vocabulary for Blinkit SKU matching later.
enum IngredientIcon {

    static func emoji(for rawName: String, category: ItemCategory) -> String {
        let name = canonical(rawName)
        if let hit = icons[name] { return hit }
        // longest catalog key contained in the name wins:
        // "red chili powder" → "chili", "mustard oil" stays "mustard oil"
        if let key = icons.keys.filter({ name.contains($0) }).max(by: { $0.count < $1.count }) {
            return icons[key]!
        }
        switch category {           // fallback thumbnails
        case .consumable: return "🥗"
        case .staple:     return "🧂"
        case .equipment:  return "🍳"
        }
    }

    /// Lowercased, singularized, Hinglish-normalized name — stable enough to
    /// use as an ingredient id for SKU matching and as the SVG asset name.
    static func canonical(_ rawName: String) -> String {
        var name = rawName.lowercased().trimmingCharacters(in: .whitespaces)
        if let synonym = hinglish[name] { name = synonym }
        if icons[name] == nil, name.hasSuffix("es"), icons[String(name.dropLast(2))] != nil {
            name = String(name.dropLast(2))
        } else if icons[name] == nil, name.hasSuffix("s") {
            name = String(name.dropLast())
        }
        // fuzzy net for typos/transliteration drift ("tomatto", "tamater"):
        // nearest vocabulary entry within an edit-distance budget wins
        if icons[name] == nil, !name.isEmpty, !name.contains(" ") {
            let vocabulary = Array(icons.keys) + Array(hinglish.keys)
            if let best = vocabulary.min(by: { editDistance(name, $0) < editDistance(name, $1) }),
               editDistance(name, best) <= max(1, name.count / 4) {
                return hinglish[best] ?? best
            }
        }
        return name
    }

    // Plain Levenshtein. ponytail: O(n·m) per pair over a ~100-word vocabulary,
    // runs once per extracted item; index it only if the vocabulary grows huge.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]; row[0] = i
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? previous : min(previous, row[j], row[j-1]) + 1
                previous = row[j]; row[j] = cost
            }
        }
        return row[b.count]
    }

    // ponytail: flat dictionaries, extend as real reels surface new names
    private static let hinglish: [String: String] = [
        "tamatar": "tomato", "pyaaz": "onion", "pyaz": "onion", "kanda": "onion",
        "aloo": "potato", "alu": "potato", "adrak": "ginger", "lehsun": "garlic",
        "lahsun": "garlic", "hari mirch": "green chili", "mirchi": "chili",
        "mirch": "chili", "dhania": "coriander", "dhaniya": "coriander",
        "haldi": "turmeric", "jeera": "cumin", "zeera": "cumin", "nimbu": "lemon",
        "doodh": "milk", "dahi": "curd", "anda": "egg", "chawal": "rice",
        "atta": "flour", "maida": "flour", "besan": "gram flour",
        "palak": "spinach", "gobi": "cauliflower", "matar": "peas",
        "baingan": "brinjal", "methi": "fenugreek", "tawa": "tava",
        "kadhai": "pan", "kadai": "pan"
    ]

    private static let icons: [String: String] = [
        // vegetables & fresh
        "tomato": "🍅", "onion": "🧅", "potato": "🥔", "garlic": "🧄",
        "ginger": "🫚", "chili": "🌶️", "green chili": "🌶️", "lemon": "🍋",
        "carrot": "🥕", "peas": "🫛", "corn": "🌽", "capsicum": "🫑",
        "cucumber": "🥒", "brinjal": "🍆", "eggplant": "🍆", "mushroom": "🍄",
        "spinach": "🥬", "cabbage": "🥬", "cauliflower": "🥦", "broccoli": "🥦",
        "coriander": "🌿", "mint": "🌿", "curry leaf": "🍃", "fenugreek": "🌿",
        "kasuri methi": "🌿", "coconut": "🥥", "banana": "🍌", "apple": "🍎",
        "mango": "🥭",
        // dairy, protein, pantry
        "paneer": "🧀", "cheese": "🧀", "butter": "🧈", "ghee": "🧈",
        "cream": "🥛", "milk": "🥛", "curd": "🥣", "yogurt": "🥣", "egg": "🥚",
        "chicken": "🍗", "mutton": "🥩", "fish": "🐟", "prawn": "🦐",
        "flour": "🌾", "gram flour": "🌾", "rice": "🍚", "bread": "🍞",
        "roti": "🫓", "paratha": "🫓", "naan": "🫓", "sugar": "🍬",
        "honey": "🍯", "peanut": "🥜", "cashew": "🥜",
        // staples & spices (ground spices land on the jar)
        "salt": "🧂", "water": "💧", "oil": "🫗", "mustard oil": "🫗",
        "turmeric": "🫙", "cumin": "🫙", "masala": "🫙", "powder": "🫙",
        "ajwain": "🫙",
        // equipment
        "pan": "🍳", "tava": "🍳", "pressure cooker": "🍲", "pot": "🍲",
        "knife": "🔪", "cutter": "🔪", "rolling pin": "🪵", "mixer": "🌀",
        "grinder": "🌀", "oven": "♨️", "spoon": "🥄", "bowl": "🥣"
    ]
}

/// Central sample data so every screen shows the same "extracted" cart.
enum SampleData {

    static let demoRecipes: [DemoRecipe] = [
        DemoRecipe(title: "Butter Chicken", emoji: "🍛",
                   description: "Tender chicken simmered in a velvety tomato-butter gravy, finished with cream and kasuri methi. A rich, mildly spiced North Indian classic best served with naan or rice.",
                   time: "45 min", serves: "4", difficulty: "Medium",
                   ingredients: [
            ("chicken", .consumable), ("butter", .consumable), ("cream", .consumable),
            ("onion", .consumable), ("tomato", .consumable), ("curd", .consumable),
            ("ginger garlic paste", .consumable), ("garam masala", .consumable),
            ("green chili", .consumable), ("kasuri methi", .consumable),
            ("coriander", .consumable),
            ("salt", .staple), ("oil", .staple),
            ("pan", .equipment)
        ], steps: [
            "Marinate the chicken in curd, ginger-garlic paste, salt and half the garam masala for at least 30 minutes.",
            "Sear the marinated chicken in a hot pan with a little oil until lightly charred, then set aside.",
            "In the same pan, sauté onions until golden, add pureed tomatoes and cook down until the oil separates.",
            "Blend the gravy smooth, return to the pan, stir in butter and the remaining garam masala.",
            "Add the chicken and a splash of water; simmer 10 minutes until cooked through.",
            "Finish with cream and crushed kasuri methi, garnish with coriander and serve hot."
        ]),
        DemoRecipe(title: "Veg Biryani", emoji: "🍚",
                   description: "Fragrant basmati rice layered with spiced mixed vegetables, fresh mint and fried onions, slow-cooked on dum. A wholesome one-pot meal that's a party on its own.",
                   time: "50 min", serves: "4", difficulty: "Medium",
                   ingredients: [
            ("basmati rice", .consumable), ("onion", .consumable), ("tomato", .consumable),
            ("curd", .consumable), ("ginger garlic paste", .consumable),
            ("carrot", .consumable), ("peas", .consumable), ("potato", .consumable),
            ("mint", .consumable), ("coriander", .consumable),
            ("biryani masala", .consumable), ("ghee", .consumable),
            ("salt", .staple), ("oil", .staple), ("water", .staple),
            ("pot", .equipment)
        ], steps: [
            "Soak the basmati rice for 20 minutes, then parboil in salted water until 70% cooked and drain.",
            "Fry sliced onions in ghee until golden and crisp; reserve half for layering.",
            "In the same pot, sauté ginger-garlic paste, tomatoes and biryani masala, then add the chopped vegetables.",
            "Stir in curd and cook until the vegetables are tender and the masala thickens.",
            "Layer the parboiled rice over the vegetables, scatter mint, coriander and fried onions on top.",
            "Cover tightly and cook on low (dum) for 15 minutes; fluff gently before serving."
        ]),
        DemoRecipe(title: "Paneer Tikka", emoji: "🧆",
                   description: "Cubes of paneer marinated in spiced yogurt with peppers and onions, then charred on a tava for a smoky finish. A crowd-favourite vegetarian starter with a squeeze of lemon.",
                   time: "30 min", serves: "3", difficulty: "Easy",
                   ingredients: [
            ("paneer", .consumable), ("curd", .consumable), ("capsicum", .consumable),
            ("onion", .consumable), ("ginger garlic paste", .consumable),
            ("lemon", .consumable), ("garam masala", .consumable),
            ("red chili powder", .consumable), ("kasuri methi", .consumable),
            ("mustard oil", .consumable),
            ("salt", .staple),
            ("tava", .equipment), ("skewers", .equipment)
        ], steps: [
            "Whisk curd with ginger-garlic paste, garam masala, red chili powder, salt, lemon juice and a little mustard oil.",
            "Fold in cubed paneer with diced capsicum and onion; coat well and rest for 20 minutes.",
            "Thread the paneer and vegetables onto skewers.",
            "Cook on a hot, oiled tava, turning until all sides are charred and golden.",
            "Crush kasuri methi over the top, finish with a squeeze of lemon and serve with mint chutney."
        ])
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
        GroceryItem(name: "Pressure Cooker", emoji: "🍲", isSelected: false),
        GroceryItem(name: "Mixer Grinder",   emoji: "🌀", isSelected: false),
        GroceryItem(name: "Tawa / Pan",      emoji: "🍳", isSelected: false)
    ]

    static let staples: [String] = ["Salt", "Water", "Oil", "Black Pepper"]
}
