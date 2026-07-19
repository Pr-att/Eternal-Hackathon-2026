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

    /// Primary CTA — disabled while the link field is empty.
    private let analyzeButton = GradientButton(title: "Analyze Video", systemImage: "sparkles")

    /// Inline recipe preview shown above the demo chips when one is tapped.
    private let recipeCard = UIView()
    private let recipeContentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background
        buildLayout()

        // Tap anywhere outside the keyboard to dismiss it. cancelsTouchesInView
        // is false so taps still reach the demo chips and buttons underneath.
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissTap.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissTap)

        // A Safari link shared via the Share Extension lands right here on the
        // home screen. Observe the "content arrived" signal for warm opens, and
        // sweep anything already queued for cold starts (the notification may
        // fire before this VC exists).
        NotificationCenter.default.addObserver(
            self, selector: #selector(consumeSharedLink),
            name: .didReceiveSharedContent, object: nil)
        consumeSharedLink()

        // Lift the link field above the keyboard when it appears.
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frameValue = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return }

        // Keyboard's top edge, in this view's coordinate space.
        let keyboardFrame = view.convert(frameValue.cgRectValue, from: view.window)
        let keyboardTop = keyboardFrame.minY

        // Grow the scrollable area so it can scroll past the keyboard.
        let overlap = max(0, view.bounds.height - keyboardTop)
        let inset = max(0, overlap - view.safeAreaInsets.bottom)
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset

        // Scroll up by exactly the amount the field's bottom is hidden behind
        // the keyboard (plus a little breathing room).
        guard linkField.isFirstResponder else { return }
        let fieldMaxY = linkField.convert(linkField.bounds, to: view).maxY
        let hiddenBy = fieldMaxY + 20 - keyboardTop
        if hiddenBy > 0 {
            var offset = scrollView.contentOffset
            offset.y += hiddenBy
            scrollView.setContentOffset(offset, animated: true)
        }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    /// Pulls the newest shared `.url` item into the link field so sharing from
    /// Safari feels like it flows straight into the home screen.
    @objc private func consumeSharedLink() {
        let shared = SharedDataManager.shared.drainPendingItems()
        guard let link = shared.last(where: { $0.kind == .url })?.value else { return }
        linkField.text = link
        updateAnalyzeState()
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
        content.setCustomSpacing(8, after: content.arrangedSubviews.last!)
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

        let help = UIButton(type: .system)
        help.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
        help.tintColor = Theme.Color.textSecondary
        help.translatesAutoresizingMaskIntoConstraints = false
        help.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)

        bar.addSubview(help)
        NSLayoutConstraint.activate([
            help.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            help.topAnchor.constraint(equalTo: bar.topAnchor),
            help.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
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
            "Share a cooking video link and let AI build your grocery list.",
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
        container.layer.cornerRadius = Theme.Metric.cardRadius
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        // Warm, appetizing sunset gradient — far more inviting than the old
        // near-black backdrop.
        let bg = GradientView(colors: [UIColor(hex: 0xFF6A3D),
                                       UIColor(hex: 0xFF3D77),
                                       UIColor(hex: 0x7A2BE2)],
                              start: CGPoint(x: 0, y: 0),
                              end: CGPoint(x: 1, y: 1))
        container.addSubview(bg)
        bg.pin(to: container)

        // Soft glow circle behind the hero dish to add depth.
        let glow = UIView()
        glow.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        glow.translatesAutoresizingMaskIntoConstraints = false
        glow.layer.cornerRadius = 52
        container.addSubview(glow)

        // Big central "dish" emoji as the focal point.
        let dish = Make.label("🍳", font: .systemFont(ofSize: 58), color: .white, align: .center)
        dish.translatesAutoresizingMaskIntoConstraints = false

        // "AI-Powered" badge pill floating at the top-left.
        let badge = makeHeroBadge()

        // Ingredient emoji strip along the bottom.
        let emojis = Make.label("🍅  🥕  🧅  🌿  🌶️  🧄",
                                font: .systemFont(ofSize: 24),
                                color: .white, align: .center)
        emojis.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(dish)
        container.addSubview(badge)
        container.addSubview(emojis)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 190),

            glow.widthAnchor.constraint(equalToConstant: 104),
            glow.heightAnchor.constraint(equalToConstant: 104),
            glow.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            glow.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -12),

            dish.centerXAnchor.constraint(equalTo: glow.centerXAnchor),
            dish.centerYAnchor.constraint(equalTo: glow.centerYAnchor),

            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),

            emojis.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            emojis.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            emojis.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        return container
    }

    /// Small frosted "AI-Powered" pill used on the hero.
    private func makeHeroBadge() -> UIView {
        let pill = UIView()
        pill.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        pill.layer.cornerRadius = 13
        pill.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "sparkles"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let text = Make.label("AI-Powered", font: Theme.Font.captionBold(), color: .white)

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.spacing = 5
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = .init(top: 6, left: 10, bottom: 6, right: 12)
        pill.addSubview(row)
        row.pin(to: pill)
        return pill
    }

    private func makeInputCard() -> UIView {
        let card = Make.card()

        let label = Make.label("Share a video link here", font: Theme.Font.captionBold(),
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
        field.addTarget(self, action: #selector(linkFieldChanged), for: .editingChanged)

        let copy = UIButton(type: .system)
        copy.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        copy.tintColor = Theme.Color.green
        copy.setContentHuggingPriority(.required, for: .horizontal)
        copy.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)

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
        analyzeButton.translatesAutoresizingMaskIntoConstraints = false
        analyzeButton.heightAnchor.constraint(equalToConstant: Theme.Metric.ctaHeight).isActive = true
        analyzeButton.addTarget(self, action: #selector(analyzeTapped), for: .touchUpInside)
        updateAnalyzeState()
        return analyzeButton
    }

    /// Enables the Analyze button only when the link field has content.
    private func updateAnalyzeState() {
        let hasLink = !(linkField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        analyzeButton.isEnabled = hasLink
        analyzeButton.alpha = hasLink ? 1.0 : 0.5
    }

    @objc private func linkFieldChanged() { updateAnalyzeState() }

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

        for (index, recipe) in SampleData.demoRecipes.enumerated() {
            let chip = makeDemoChip(recipe)
            chip.tag = index
            chipRow.addArrangedSubview(chip)
        }

        // Recipe preview card sits above the chips; hidden until one is tapped.
        recipeContentStack.axis = .vertical
        recipeContentStack.spacing = 10
        recipeContentStack.translatesAutoresizingMaskIntoConstraints = false

        recipeCard.backgroundColor = Theme.Color.surface
        recipeCard.layer.cornerRadius = Theme.Metric.cardRadius
        recipeCard.layer.borderWidth = 1
        recipeCard.layer.borderColor = Theme.Color.green.withAlphaComponent(0.4).cgColor
        recipeCard.isHidden = true
        recipeCard.addSubview(recipeContentStack)
        recipeContentStack.pin(to: recipeCard, insets: .init(top: 16, left: 16, bottom: 16, right: 16))

        let stack = UIStackView(arrangedSubviews: [header, recipeCard, chipRow])
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(demoRecipeTapped(_:)))
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

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    /// Pastes the copied link from the system clipboard into the link field.
    @objc private func pasteTapped() {
        let pb = UIPasteboard.general
        let pasted = (pb.url?.absoluteString ?? pb.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pasted.isEmpty else {
            let alert = UIAlertController(title: "Nothing to paste",
                                          message: "Copy a video link first, then tap paste.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        linkField.text = pasted
        updateAnalyzeState()
        // Brief highlight so it's clear the link landed in the field.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flashLinkField()
    }

    private func flashLinkField() {
        guard let row = linkField.superview else { return }
        let original = row.backgroundColor
        UIView.animate(withDuration: 0.15, animations: {
            row.backgroundColor = Theme.Color.green.withAlphaComponent(0.18)
        }, completion: { _ in
            UIView.animate(withDuration: 0.35) { row.backgroundColor = original }
        })
    }

    @objc private func analyzeTapped() {
        let link = linkField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A shared link runs the real on-device extraction; an empty field
        // keeps the sample-data demo flow.
        let vc = ProcessingViewController(link: link.isEmpty ? nil : link)
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Demo chip → reveal that recipe's ingredients inline, above the chips.
    @objc private func demoRecipeTapped(_ sender: UITapGestureRecognizer) {
        guard let index = sender.view?.tag,
              SampleData.demoRecipes.indices.contains(index) else { return }
        showRecipeDetail(SampleData.demoRecipes[index])
    }

    /// Rebuilds and reveals the inline recipe preview card.
    private func showRecipeDetail(_ recipe: DemoRecipe) {
        recipeContentStack.arrangedSubviews.forEach {
            recipeContentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // Header: emoji thumb + title + close button.
        let thumb = ThumbnailView(emoji: recipe.emoji, size: 36, corner: 10)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumb.widthAnchor.constraint(equalToConstant: 36),
            thumb.heightAnchor.constraint(equalToConstant: 36)
        ])
        let title = Make.label(recipe.title, font: Theme.Font.headline(), color: Theme.Color.textPrimary)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = Theme.Color.textTertiary
        close.setContentHuggingPriority(.required, for: .horizontal)
        close.addTarget(self, action: #selector(closeRecipeDetail), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [thumb, title, UIView(), close])
        headerRow.spacing = 10
        headerRow.alignment = .center
        recipeContentStack.addArrangedSubview(headerRow)

        // Quick-facts pills: time · serves · difficulty.
        let metaRow = UIStackView(arrangedSubviews: [
            makeMetaPill("clock", recipe.time),
            makeMetaPill("person.2", "Serves \(recipe.serves)"),
            makeMetaPill("chart.bar", recipe.difficulty),
            UIView()
        ])
        metaRow.spacing = 8
        metaRow.alignment = .center
        recipeContentStack.addArrangedSubview(metaRow)
        recipeContentStack.setCustomSpacing(12, after: metaRow)

        // Proper recipe description.
        let desc = Make.label(recipe.description, font: Theme.Font.body(),
                              color: Theme.Color.textSecondary, lines: 0)
        recipeContentStack.addArrangedSubview(desc)
        recipeContentStack.setCustomSpacing(14, after: desc)

        // Step-by-step method.
        let methodTitle = Make.label("Method · \(recipe.steps.count) steps",
                                     font: Theme.Font.captionBold(), color: Theme.Color.textPrimary)
        recipeContentStack.addArrangedSubview(methodTitle)

        for (i, step) in recipe.steps.enumerated() {
            let number = Make.label("\(i + 1)", font: Theme.Font.captionBold(),
                                    color: .white, align: .center)
            number.backgroundColor = Theme.Color.green
            number.layer.cornerRadius = 11
            number.layer.masksToBounds = true
            number.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                number.widthAnchor.constraint(equalToConstant: 22),
                number.heightAnchor.constraint(equalToConstant: 22)
            ])
            number.setContentHuggingPriority(.required, for: .horizontal)

            let text = Make.label(step, font: Theme.Font.body(),
                                  color: Theme.Color.textSecondary, lines: 0)

            let row = UIStackView(arrangedSubviews: [number, text])
            row.spacing = 10
            row.alignment = .top
            recipeContentStack.addArrangedSubview(row)
        }

        // CTA: add this recipe's ingredients straight to the editable list
        // (the behaviour the demo chips used to trigger on tap).
        if let last = recipeContentStack.arrangedSubviews.last {
            recipeContentStack.setCustomSpacing(16, after: last)
        }
        let addButton = GradientButton(title: "Add ingredients to list", systemImage: "cart.badge.plus")
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        addButton.addAction(UIAction { [weak self] _ in self?.openReview(with: recipe) },
                            for: .touchUpInside)
        recipeContentStack.addArrangedSubview(addButton)

        recipeCard.isHidden = false
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    /// Pushes the editable list pre-filled with this recipe's ingredients.
    private func openReview(with recipe: DemoRecipe) {
        let items = recipe.ingredients.map {
            ExtractedItem(name: $0.name, category: $0.category,
                          estimatedQuantity: nil, unit: nil,
                          evidence: [], confidence: 1)
        }
        navigationController?.pushViewController(ReviewEditViewController(items: items), animated: true)
    }

    /// Small icon + text pill used for a recipe's quick facts.
    private func makeMetaPill(_ symbol: String, _ text: String) -> UIView {
        let pill = UIView()
        pill.backgroundColor = Theme.Color.surfaceElevated
        pill.layer.cornerRadius = 11
        pill.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
        icon.tintColor = Theme.Color.green
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = Make.label(text, font: Theme.Font.caption(), color: Theme.Color.textSecondary)

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 5
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = .init(top: 5, left: 9, bottom: 5, right: 10)
        pill.addSubview(row)
        row.pin(to: pill)
        return pill
    }

    @objc private func closeRecipeDetail() {
        recipeCard.isHidden = true
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    @objc private func helpTapped() {
        let alert = UIAlertController(
            title: "How it works",
            message: "Share a cooking video link and AI extracts every ingredient into a grocery list.\n\nAnalysis usually takes 10–15 seconds. Your video is processed on-device — nothing is uploaded.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default))
        present(alert, animated: true)
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
