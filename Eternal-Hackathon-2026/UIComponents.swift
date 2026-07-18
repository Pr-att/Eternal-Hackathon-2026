//
//  UIComponents.swift
//  AIRecipeShopping
//
//  Small reusable building blocks shared across the four screens.
//

import UIKit

// MARK: - Self-sizing gradient background view

final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    init(colors: [UIColor],
         start: CGPoint = CGPoint(x: 0, y: 0),
         end: CGPoint = CGPoint(x: 1, y: 1)) {
        super.init(frame: .zero)
        gradientLayer.colors = colors.map { $0.cgColor }
        gradientLayer.startPoint = start
        gradientLayer.endPoint = end
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Gradient CTA button (purple -> blue)

final class GradientButton: UIButton {

    private let gradient = CAGradientLayer()

    init(title: String, systemImage: String? = nil, trailing: Bool = false) {
        super.init(frame: .zero)
        configure(title: title, systemImage: systemImage, trailing: trailing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(title: String, systemImage: String?, trailing: Bool) {
        gradient.colors = Theme.primaryGradient
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint   = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = Theme.Metric.ctaRadius
        layer.insertSublayer(gradient, at: 0)

        // Build the label + icon as a centered, non-interactive stack. This
        // renders reliably for a UIButton subclass with a manual gradient
        // sublayer, where UIButton.Configuration / classic setImage were
        // dropping the title or the icon.
        let label = UILabel()
        label.text = title
        label.font = Theme.Font.button()
        label.textColor = .white

        var arranged: [UIView] = [label]
        if let systemImage {
            let symConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let iconView = UIImageView(image: UIImage(systemName: systemImage,
                                                      withConfiguration: symConfig))
            iconView.tintColor = .white
            iconView.contentMode = .center
            iconView.setContentHuggingPriority(.required, for: .horizontal)
            arranged = trailing ? [label, iconView] : [iconView, label]
        }

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.isUserInteractionEnabled = false          // let taps reach the button
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        contentStack = stack
        layer.cornerRadius = Theme.Metric.ctaRadius
        layer.masksToBounds = true
    }

    /// Dim the content while the button is pressed.
    override var isHighlighted: Bool {
        didSet { contentStack?.alpha = isHighlighted ? 0.6 : 1.0 }
    }

    private weak var contentStack: UIStackView?

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

// MARK: - Circular gradient progress ring (screen 2)

final class CircularProgressView: UIView {

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()

    private let percentLabel = UILabel()
    private let captionLabel = UILabel()

    private var lastLaidOutBounds: CGRect = .zero

    init() {
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        trackLayer.strokeColor = Theme.Color.stroke.cgColor
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineWidth = 12
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)

        progressLayer.strokeColor = UIColor.white.cgColor   // acts as mask for gradient
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineWidth = 12
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0

        // Conic gradient fill, masked by the progress ring path.
        gradientLayer.type = .conic
        gradientLayer.colors = Theme.ringGradient
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.mask = progressLayer
        layer.addSublayer(gradientLayer)

        captionLabel.text = "Analyzing recipe…"
        captionLabel.font = Theme.Font.caption()
        captionLabel.textColor = Theme.Color.textSecondary
        captionLabel.textAlignment = .center

        percentLabel.font = .systemFont(ofSize: 52, weight: .heavy)
        percentLabel.textColor = Theme.Color.textPrimary
        percentLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [captionLabel, percentLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only rebuild geometry when the size actually changes. Reassigning the
        // shape paths on every layout pass triggers implicit animations that make
        // the ring flicker during navigation transitions and scrolling.
        guard bounds != lastLaidOutBounds else { return }
        lastLaidOutBounds = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        let inset = trackLayer.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: rect.width / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
        CATransaction.commit()
    }

    /// Animate the ring and the percentage label to a value in 0...1.
    func setProgress(_ value: CGFloat, animated: Bool = true) {
        let clamped = max(0, min(1, value))
        percentLabel.attributedText = percentString(Int(clamped * 100))

        if animated {
            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
            anim.toValue = clamped
            anim.duration = 0.6
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.fillMode = .both
            progressLayer.add(anim, forKey: "progress")
        }
        // Set the model value without a second implicit animation competing
        // with the explicit one above.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = clamped
        CATransaction.commit()
    }

    /// Update the caption shown above the percentage (e.g. the current step).
    func setCaption(_ text: String) {
        captionLabel.text = text
    }

    private func percentString(_ pct: Int) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: "\(pct)",
            attributes: [.font: UIFont.systemFont(ofSize: 52, weight: .heavy),
                         .foregroundColor: Theme.Color.textPrimary]
        )
        s.append(NSAttributedString(
            string: "%",
            attributes: [.font: UIFont.systemFont(ofSize: 20, weight: .bold),
                         .foregroundColor: Theme.Color.textSecondary]
        ))
        return s
    }
}

// MARK: - Emoji thumbnail (stand-in for product image)

final class ThumbnailView: UIView {

    private let label = UILabel()

    init(emoji: String, size: CGFloat = 40, corner: CGFloat = 12) {
        super.init(frame: .zero)
        backgroundColor = Theme.Color.surfaceElevated
        layer.cornerRadius = corner
        layer.borderWidth = 1
        layer.borderColor = Theme.Color.stroke.cgColor

        label.text = emoji
        label.font = .systemFont(ofSize: size * 0.55)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setEmoji(_ emoji: String) { label.text = emoji }
}

// MARK: - Small count badge (e.g. the "8" pills)

final class CountBadge: UILabel {
    init(count: Int, background: UIColor = Theme.Color.green, foreground: UIColor = .black) {
        super.init(frame: .zero)
        text = "\(count)"
        font = Theme.Font.captionBold()
        textColor = foreground
        backgroundColor = background
        textAlignment = .center
        layer.cornerRadius = 11
        layer.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Factory helpers

enum Make {

    static func label(_ text: String,
                      font: UIFont,
                      color: UIColor,
                      align: NSTextAlignment = .natural,
                      lines: Int = 0) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.textAlignment = align
        l.numberOfLines = lines
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    static func card() -> UIView {
        let v = UIView()
        v.backgroundColor = Theme.Color.surface
        v.layer.cornerRadius = Theme.Metric.cardRadius
        v.layer.borderWidth = 1
        v.layer.borderColor = Theme.Color.stroke.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    static func backButton(target: Any?, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        b.tintColor = Theme.Color.textPrimary
        b.addTarget(target, action: action, for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
}
