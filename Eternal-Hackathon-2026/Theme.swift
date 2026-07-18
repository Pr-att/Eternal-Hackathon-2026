//
//  Theme.swift
//  AIRecipeShopping
//
//  Central design tokens (colors, gradients, fonts, spacing) tuned to the mockup.
//

import UIKit

enum Theme {

    // MARK: Colors
    enum Color {
        static let background      = UIColor(hex: 0x0B0B10)   // near-black app background
        static let surface         = UIColor(hex: 0x16161D)   // cards
        static let surfaceElevated = UIColor(hex: 0x1E1E27)   // input fields / rows
        static let stroke          = UIColor(hex: 0x2A2A33)   // hairline borders

        static let textPrimary     = UIColor(hex: 0xFFFFFF)
        static let textSecondary   = UIColor(hex: 0x9A9AA5)
        static let textTertiary    = UIColor(hex: 0x6B6B75)

        static let green           = UIColor(hex: 0x3DDC63)   // "To Buy" / Continue accent
        static let greenSoftFill   = UIColor(hex: 0x14351F)   // active tab fill
        static let danger          = UIColor(hex: 0xE5484D)   // delete / trash

        // Gradient stops (purple -> blue) used for primary CTAs and progress ring
        static let gradientStart   = UIColor(hex: 0x8B5CF6)
        static let gradientMid     = UIColor(hex: 0x6D5AF0)
        static let gradientEnd     = UIColor(hex: 0x4F7BFF)
    }

    // MARK: Gradients
    static var primaryGradient: [CGColor] {
        [Color.gradientStart.cgColor, Color.gradientEnd.cgColor]
    }

    static var ringGradient: [CGColor] {
        [Color.gradientEnd.cgColor, Color.gradientStart.cgColor, Color.gradientEnd.cgColor]
    }

    // MARK: Fonts
    enum Font {
        static func hero() -> UIFont            { .systemFont(ofSize: 34, weight: .heavy) }
        static func title() -> UIFont           { .systemFont(ofSize: 20, weight: .bold) }
        static func headline() -> UIFont        { .systemFont(ofSize: 17, weight: .semibold) }
        static func body() -> UIFont            { .systemFont(ofSize: 15, weight: .regular) }
        static func bodyMedium() -> UIFont      { .systemFont(ofSize: 15, weight: .medium) }
        static func caption() -> UIFont         { .systemFont(ofSize: 13, weight: .regular) }
        static func captionBold() -> UIFont     { .systemFont(ofSize: 12, weight: .bold) }
        static func button() -> UIFont          { .systemFont(ofSize: 17, weight: .semibold) }
    }

    // MARK: Spacing / metrics
    enum Metric {
        static let screenInset: CGFloat = 20
        static let cardRadius: CGFloat  = 18
        static let ctaRadius: CGFloat   = 16
        static let ctaHeight: CGFloat   = 56
    }
}

// MARK: - Hex helper
extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue:  CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
