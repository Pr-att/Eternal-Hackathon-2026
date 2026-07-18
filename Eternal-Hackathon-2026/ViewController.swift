//
//  ViewController.swift
//  Eternal-Hackathon-2026
//
//  The storyboard's initial screen. Kept minimal — it just offers a manual
//  entry point into the Shared Inbox so you can inspect received content
//  without re-triggering the share sheet each time.
//
//  MVVM: View — test harness for on-device ingredient extraction.
//  Paste a direct .mp4 URL (from `python3 backend/ingestion.py <link>` ->
//  "video_url") or raw recipe text, tap Extract, see classified items.
//

import UIKit

class ViewController: UIViewController {

    private let viewModel = ExtractionViewModel()

    private let linkField: UITextField = {
        let field = UITextField()
        field.placeholder = "YouTube/Instagram link, .mp4 URL, or recipe text"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        return field
    }()

    private let extractButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Extract Ingredients"
        return UIButton(configuration: config)
    }()

    private let spinner = UIActivityIndicatorView(style: .medium)

    private let resultsView: UITextView = {
        let view = UITextView()
        view.isEditable = false
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.text = "Results appear here.\n\nTip: start the backend first —\n  cd backend && .venv/bin/uvicorn server:app --port 8000\nthen paste a YouTube/Instagram link."
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground


//         let button = UIButton(configuration: .borderedProminent())
//         button.setTitle("Open Shared Inbox", for: .normal)
//         button.addAction(UIAction { [weak self] _ in
//             let inbox = SharedInboxViewController()
//             let nav = UINavigationController(rootViewController: inbox)
//             self?.present(nav, animated: true)
//         }, for: .touchUpInside)

//         button.translatesAutoresizingMaskIntoConstraints = false
//         view.addSubview(button)
//         NSLayoutConstraint.activate([
//             button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//             button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//         ])


        extractButton.addTarget(self, action: #selector(extractTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [linkField, extractButton, spinner, resultsView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
    }

    @objc private func extractTapped() {
        guard let input = linkField.text, !input.isEmpty else { return }
        linkField.resignFirstResponder()
        extractButton.isEnabled = false
        spinner.startAnimating()
        resultsView.text = "Analyzing on-device…"

        Task {
            await viewModel.extract(fromLink: input)
            spinner.stopAnimating()
            extractButton.isEnabled = true
            resultsView.text = viewModel.errorMessage.map { "Error: \($0)" }
                ?? Self.format(viewModel.items)
        }
    }

    private static func format(_ items: [ExtractedItem]) -> String {
        guard !items.isEmpty else { return "No items found." }
        return Dictionary(grouping: items, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { category, items in
                category.rawValue.uppercased() + "\n" + items.map { item in
                    let qty = item.estimatedQuantity.map { q in
                        " — \(q.formatted())\(item.unit.map { " \($0)" } ?? "")"
                    } ?? ""
                    return "  • \(item.name)\(qty)  (\(item.confidence.formatted()))"
                }.joined(separator: "\n")
            }
            .joined(separator: "\n\n")

    }
}
