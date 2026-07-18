//
//  HomeViewController.swift
//  AIRecipeShopping
//
//  Screen 1 — landing. Paste a link, hit Analyze. Hero is an image (not a video player).
//

import UIKit

final class HomeViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let content = UIStackView()

    /// The paste-a-link field. Promoted to a property so a link shared from
    /// Safari via the Share Extension can be dropped in here.
    private let linkField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background
        buildLayout()

        // A Safari link shared via the Share Extension lands right here on the
        // home screen. Observe the "content arrived" signal for warm opens, and
        // sweep anything already queued for cold starts (the notification may
        // fire before this VC exists).
        NotificationCenter.default.addObserver(
            self, selector: #selector(consumeSharedLink),
            name: .didReceiveSharedContent, object: nil)
        consumeSharedLink()
    }

    /// Pulls the newest shared `.url` item into the link field so sharing from
    /// Safari feels like it flows straight into the home screen.
    @objc private func consumeSharedLink() {
        let shared = SharedDataManager.shared.drainPendingItems()
        guard let link = shared.last(where: { $0.kind == .url })?.value else { return }
        linkField.text = link
    }

    // MARK: Layout

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        content.axis = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Metric.screenInset),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Metric.screenInset)
        ])

        content.addArrangedSubview(makeTopBar())
        content.setCustomSpacing(24, after: content.arrangedSubviews.last!)
        content.addArrangedSubview(makeTitleBlock())
        content.addArrangedSubview(makeHeroImage())
        content.addArrangedSubview(makeInputCard())
        content.addArrangedSubview(makeAnalyzeButton())
        content.addArrangedSubview(makeOrDivider())
        content.addArrangedSubview(makeDemoSection())
        content.addArrangedSubview(makeFooter())
    }

    // MARK: Pieces

    private func makeTopBar() -> UIView {
        let bar = UIView()

        let chip = UIView()
        chip.backgroundColor = Theme.Color.surface
        chip.layer.cornerRadius = 14
        chip.layer.borderWidth = 1
        chip.layer.borderColor = Theme.Color.stroke.cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false

        let num = Make.label("1", font: Theme.Font.captionBold(), color: .black, align: .center)
        num.backgroundColor = Theme.Color.gradientEnd
        num.layer.cornerRadius = 10
        num.layer.masksToBounds = true
        NSLayoutConstraint.activate([
            num.widthAnchor.constraint(equalToConstant: 20),
            num.heightAnchor.constraint(equalToConstant: 20)
        ])
        let step = Make.label("Paste Video URL", font: Theme.Font.bodyMedium(), color: Theme.Color.textPrimary, lines: 1)

        let chipStack = UIStackView(arrangedSubviews: [num, step])
        chipStack.spacing = 8
        chipStack.alignment = .center
        chipStack.isLayoutMarginsRelativeArrangement = true
        chipStack.layoutMargins = .init(top: 7, left: 10, bottom: 7, right: 14)
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(chipStack)
        chipStack.pin(to: chip)

        let help = UIButton(type: .system)
        help.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
        help.tintColor = Theme.Color.textSecondary
        help.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(chip)
        bar.addSubview(help)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            chip.topAnchor.constraint(equalTo: bar.topAnchor),
            chip.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            help.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            help.centerYAnchor.constraint(equalTo: chip.centerYAnchor)
        ])
        return bar
    }

    private func makeTitleBlock() -> UIView {
        let title = UILabel()
        title.numberOfLines = 2
        let attr = NSMutableAttributedString(
            string: "AI ",
            attributes: [.font: Theme.Font.hero(), .foregroundColor: Theme.Color.gradientStart]
        )
        attr.append(NSAttributedString(
            string: "Recipe\nShopping",
            attributes: [.font: Theme.Font.hero(), .foregroundColor: Theme.Color.textPrimary]
        ))
        title.attributedText = attr
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = Make.label(
            "Paste a cooking video link and let AI build your grocery list.",
            font: Theme.Font.body(), color: Theme.Color.textSecondary
        )

        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    /// Hero *image* (per requirement: use an image, not a video player).
    private func makeHeroImage() -> UIView {
        let container = UIView()
        container.backgroundColor = Theme.Color.surface
        container.layer.cornerRadius = Theme.Metric.cardRadius
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        // Gradient backdrop to imply a rich hero photo.
        let bg = GradientView(colors: [UIColor(hex: 0x1B1140), UIColor(hex: 0x0E1030)])
        container.addSubview(bg)
        bg.pin(to: container)

        // Static "AI Recipe" image using SF Symbol + food emojis (no play control).
        let imageView = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        imageView.tintColor = UIColor.white.withAlphaComponent(0.15)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let emojis = Make.label("🍲  🥕  🍅  🧅  🌿",
                                font: .systemFont(ofSize: 34),
                                color: .white, align: .center)

        let stack = UIStackView(arrangedSubviews: [imageView, emojis])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 190),
            imageView.heightAnchor.constraint(equalToConstant: 60),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeInputCard() -> UIView {
        let card = Make.card()

        let label = Make.label("Paste video link", font: Theme.Font.captionBold(),
                               color: Theme.Color.textSecondary)

        let linkIcon = UIImageView(image: UIImage(systemName: "link"))
        linkIcon.tintColor = Theme.Color.textSecondary
        linkIcon.contentMode = .scaleAspectFit
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        linkIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let field = linkField
        field.attributedPlaceholder = NSAttributedString(
            string: "https://youtu.be/abcd123…",
            attributes: [.foregroundColor: Theme.Color.textTertiary,
                         .font: Theme.Font.body()]
        )
        field.textColor = Theme.Color.textPrimary
        field.font = Theme.Font.body()
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.tintColor = Theme.Color.green

        let copy = UIButton(type: .system)
        copy.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copy.tintColor = Theme.Color.textSecondary
        copy.setContentHuggingPriority(.required, for: .horizontal)

        let fieldRow = UIStackView(arrangedSubviews: [linkIcon, field, copy])
        fieldRow.spacing = 10
        fieldRow.alignment = .center
        fieldRow.isLayoutMarginsRelativeArrangement = true
        fieldRow.layoutMargins = .init(top: 12, left: 12, bottom: 12, right: 12)
        fieldRow.backgroundColor = Theme.Color.surfaceElevated
        fieldRow.layer.cornerRadius = 12
        fieldRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [label, fieldRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        stack.pin(to: card)
        return card
    }

    private func makeAnalyzeButton() -> UIView {
        let button = GradientButton(title: "Analyze Video", systemImage: "sparkles")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: Theme.Metric.ctaHeight).isActive = true
        button.addTarget(self, action: #selector(analyzeTapped), for: .touchUpInside)
        return button
    }

    private func makeOrDivider() -> UIView {
        func line() -> UIView {
            let v = UIView()
            v.backgroundColor = Theme.Color.stroke
            v.translatesAutoresizingMaskIntoConstraints = false
            v.heightAnchor.constraint(equalToConstant: 1).isActive = true
            return v
        }
        let or = Make.label("or", font: Theme.Font.caption(), color: Theme.Color.textTertiary)
        let stack = UIStackView(arrangedSubviews: [line(), or, line()])
        stack.spacing = 12
        stack.alignment = .center
        stack.distribution = .fill
        (stack.arrangedSubviews.first as? UIView)?.widthAnchor.constraint(
            equalTo: (stack.arrangedSubviews.last as! UIView).widthAnchor).isActive = true
        return stack
    }

    private func makeDemoSection() -> UIView {
        let header = Make.label("Try these demo recipes", font: Theme.Font.captionBold(),
                                color: Theme.Color.textSecondary)

        let chipRow = UIStackView()
        chipRow.spacing = 12
        chipRow.distribution = .fillEqually

        for recipe in SampleData.demoRecipes {
            chipRow.addArrangedSubview(makeDemoChip(recipe))
        }

        let stack = UIStackView(arrangedSubviews: [header, chipRow])
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }

    private func makeDemoChip(_ recipe: DemoRecipe) -> UIView {
        let card = Make.card()

        let thumb = ThumbnailView(emoji: recipe.emoji, size: 34, corner: 10)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumb.widthAnchor.constraint(equalToConstant: 34),
            thumb.heightAnchor.constraint(equalToConstant: 34)
        ])

        let title = Make.label(recipe.title, font: Theme.Font.caption(),
                               color: Theme.Color.textPrimary, align: .center, lines: 2)

        let stack = UIStackView(arrangedSubviews: [thumb, title])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 12, left: 8, bottom: 12, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        stack.pin(to: card)

        let tap = UITapGestureRecognizer(target: self, action: #selector(analyzeTapped))
        card.addGestureRecognizer(tap)
        return card
    }

    private func makeFooter() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "checkmark.shield.fill"))
        icon.tintColor = Theme.Color.green
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let text = Make.label("Secure • Private • Powered by AI",
                              font: Theme.Font.caption(), color: Theme.Color.textTertiary)

        let stack = UIStackView(arrangedSubviews: [icon, text])
        stack.spacing = 6
        stack.alignment = .center
        stack.distribution = .fill

        let wrapper = UIView()
        wrapper.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    // MARK: Actions

    @objc private func analyzeTapped() {
        let vc = ProcessingViewController()
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - Small pin helper
extension UIView {
    func pin(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }
}
