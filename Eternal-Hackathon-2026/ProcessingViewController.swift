//
//  ProcessingViewController.swift
//  AIRecipeShopping
//
//  Screen 2 — analysing the video URL and building the list.
//

import UIKit

private enum StepStatus {
    case done, inProgress, pending

    var text: String {
        switch self {
        case .done:       return "Done"
        case .inProgress: return "In progress"
        case .pending:    return "Pending"
        }
    }
    var color: UIColor {
        switch self {
        case .done:       return Theme.Color.green
        case .inProgress: return Theme.Color.gradientEnd
        case .pending:    return Theme.Color.textTertiary
        }
    }
}

final class ProcessingViewController: UIViewController {

    private let ring = CircularProgressView()

    // Each step completes once analysis progress crosses its fraction.
    private let steps: [(title: String, completeAt: CGFloat)] = [
        ("Reading captions",     0.20),
        ("Finding ingredients",  0.45),
        ("Understanding recipe", 0.65),
        ("Matching groceries",   0.90),
        ("Building your cart",   1.00)
    ]
    private var stepRows: [StepRowView] = []

    private var progress: CGFloat = 0
    private var timer: Timer?

    /// Link to actually analyze; nil = pure demo animation with sample data.
    private let link: String?
    private let viewModel = ExtractionViewModel()
    private var extractionTask: Task<Void, Never>?
    private var extractionDone = false

    init(link: String? = nil) {
        self.link = link
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background
        navigationItem.hidesBackButton = true
        buildLayout()
        updateSteps()                 // initial state: first step in progress
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAnalysis()
        startExtraction()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
        extractionTask?.cancel()
    }

    /// Kick off the real on-device extraction behind the progress animation.
    private func startExtraction() {
        guard let link, extractionTask == nil else { return }
        extractionTask = Task { [weak self] in
            await self?.viewModel.extract(fromLink: link)
            guard let self, !Task.isCancelled else { return }
            if let message = self.viewModel.errorMessage {
                self.showError(message)
            } else {
                self.extractionDone = true   // releases the ring's 92% ceiling
            }
        }
    }

    private func showError(_ message: String) {
        guard navigationController?.topViewController === self else { return }
        timer?.invalidate()
        timer = nil
        let alert = UIAlertController(title: "Couldn't analyze video",
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: Progress driver

    private func startAnalysis() {
        guard timer == nil, progress < 1 else { return }
        // Advance the ring smoothly to 100% over ~3.5s, updating the checklist
        // as each step's threshold is reached.
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.link == nil {
                // pure demo: ease-out sweep to 100% over ~3.5s
                let remaining = 1 - self.progress
                self.progress = min(1, self.progress + max(0.004, remaining * 0.02))
            } else {
                // Chase the real pipeline progress (byte-accurate download,
                // frame walk, per-batch model calls) instead of racing ahead
                // and stalling; a slow ~1%/s creep keeps the ring alive
                // between real updates. Hold ≤98% until extraction returns.
                let ceiling: CGFloat = self.extractionDone ? 1 : 0.98
                let target = max(CGFloat(self.viewModel.progress), self.progress + 0.0004)
                self.progress = min(ceiling, self.progress + max(0.0004, (target - self.progress) * 0.06))
            }
            self.ring.setProgress(self.progress, animated: false)
            self.updateSteps()

            if self.progress >= 1 {
                t.invalidate()
                self.timer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    self?.advance()
                }
            }
        }
    }

    /// Reflect the current progress onto the checklist and the ring caption.
    private func updateSteps() {
        var markedCurrent = false
        for (i, row) in stepRows.enumerated() {
            if progress >= steps[i].completeAt {
                row.update(.done)
            } else if !markedCurrent {
                row.update(.inProgress)
                ring.setCaption(steps[i].title + "…")
                markedCurrent = true
            } else {
                row.update(.pending)
            }
        }
        if progress >= 1 { ring.setCaption("Analysis complete") }
    }

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 22
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Metric.screenInset),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Metric.screenInset)
        ])

        // Back button
        let back = Make.backButton(target: self, action: #selector(backTapped))
        let backRow = UIView()
        backRow.addSubview(back)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: backRow.leadingAnchor),
            back.topAnchor.constraint(equalTo: backRow.topAnchor),
            back.bottomAnchor.constraint(equalTo: backRow.bottomAnchor),
            back.widthAnchor.constraint(equalToConstant: 28),
            back.heightAnchor.constraint(equalToConstant: 28)
        ])
        content.addArrangedSubview(backRow)

        // Header
        let title = Make.label("Processing your video", font: Theme.Font.title(),
                               color: Theme.Color.textPrimary, align: .center)
        let subtitle = Make.label("We analyze the video and extract ingredients.",
                                  font: Theme.Font.body(), color: Theme.Color.textSecondary, align: .center)
        let headerStack = UIStackView(arrangedSubviews: [title, subtitle])
        headerStack.axis = .vertical
        headerStack.spacing = 6
        content.addArrangedSubview(headerStack)

        // Ring
        ring.translatesAutoresizingMaskIntoConstraints = false
        let ringWrap = UIView()
        ringWrap.addSubview(ring)
        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: ringWrap.centerXAnchor),
            ring.topAnchor.constraint(equalTo: ringWrap.topAnchor, constant: 8),
            ring.bottomAnchor.constraint(equalTo: ringWrap.bottomAnchor),
            ring.widthAnchor.constraint(equalToConstant: 190),
            ring.heightAnchor.constraint(equalToConstant: 190)
        ])
        content.addArrangedSubview(ringWrap)

        // "This may take 10-15 seconds" pill
        content.addArrangedSubview(centered(makePill("This may take 10–15 seconds")))

        // Step checklist
        content.addArrangedSubview(makeStepList())

        // "What we're doing" card
        content.addArrangedSubview(makeWhatCard())
    }

    // MARK: Pieces

    private func makePill(_ text: String) -> UIView {
        let label = Make.label(text, font: Theme.Font.caption(), color: Theme.Color.textSecondary)
        let pill = UIView()
        pill.backgroundColor = Theme.Color.surface
        pill.layer.cornerRadius = 14
        pill.layer.borderWidth = 1
        pill.layer.borderColor = Theme.Color.stroke.cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        label.pin(to: pill, insets: .init(top: 7, left: 14, bottom: 7, right: 14))
        return pill
    }

    private func centered(_ v: UIView) -> UIView {
        let wrap = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(v)
        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            v.topAnchor.constraint(equalTo: wrap.topAnchor),
            v.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
        ])
        return wrap
    }

    private func makeStepList() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stepRows = steps.map { StepRowView(title: $0.title) }
        stepRows.forEach { stack.addArrangedSubview($0) }
        return stack
    }

    private func makeWhatCard() -> UIView {
        let card = Make.card()

        let header = Make.label("What we're doing", font: Theme.Font.headline(),
                                color: Theme.Color.textPrimary)

        let rows: [(String, String)] = [
            ("play.rectangle.fill", "Watching your video"),
            ("pencil.and.outline",  "Extracting ingredients"),
            ("fork.knife",          "Matching with nearby products"),
            ("cart.fill",           "Building the perfect grocery list")
        ]

        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 14
        for (symbol, text) in rows {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = Theme.Color.textSecondary
            icon.contentMode = .scaleAspectFit
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 20).isActive = true

            let label = Make.label(text, font: Theme.Font.body(), color: Theme.Color.textSecondary)
            let r = UIStackView(arrangedSubviews: [icon, label])
            r.spacing = 12
            r.alignment = .center
            list.addArrangedSubview(r)
        }

        let stack = UIStackView(arrangedSubviews: [header, list])
        stack.axis = .vertical
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        stack.pin(to: card)
        return card
    }

    // MARK: Actions

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func advance() {
        guard navigationController?.topViewController === self else { return }
        let vc = ReviewEditViewController(items: link == nil ? nil : viewModel.items)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - A single checklist row whose status can be updated live

private final class StepRowView: UIView {

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(title: String) {
        super.init(frame: .zero)

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        nameLabel.text = title
        nameLabel.font = Theme.Font.bodyMedium()

        statusLabel.font = Theme.Font.caption()
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        spinner.color = Theme.Color.gradientEnd
        spinner.hidesWhenStopped = true

        let trailing = UIStackView(arrangedSubviews: [statusLabel, spinner])
        trailing.spacing = 6
        trailing.alignment = .center

        let row = UIStackView(arrangedSubviews: [iconView, nameLabel, UIView(), trailing])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        row.pin(to: self)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ status: StepStatus) {
        statusLabel.text = status.text
        statusLabel.textColor = status.color
        nameLabel.textColor = (status == .pending) ? Theme.Color.textSecondary : Theme.Color.textPrimary

        switch status {
        case .done:
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            iconView.tintColor = Theme.Color.green
            spinner.stopAnimating()
        case .inProgress:
            iconView.image = UIImage(systemName: "circle.righthalf.filled")
            iconView.tintColor = Theme.Color.gradientEnd
            spinner.startAnimating()
        case .pending:
            iconView.image = UIImage(systemName: "circle")
            iconView.tintColor = Theme.Color.textTertiary
            spinner.stopAnimating()
        }
    }
}
