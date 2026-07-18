//
//  SharedInboxViewController.swift
//  Eternal-Hackathon-2026 (main app)
//
//  Renders content received from the Share Extension in a table view.
//  Purely presentational: observes the notification, forwards items to the
//  view model, and reloads on `onChange`. This is the screen the deep link
//  routes to.
//

import UIKit

final class SharedInboxViewController: UIViewController {

    private let viewModel = SharedInboxViewModel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Shared With You"
        view.backgroundColor = .systemBackground
        setupTableView()
        setupEmptyState()
        bindViewModel()
        observeSharedContent()

        // Catch anything already waiting (cold-start via manual app open).
        viewModel.loadPending()
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.onChange = { [weak self] in
            guard let self else { return }
            self.tableView.reloadData()
            self.updateEmptyState()
        }
    }

    /// Shows the right empty message — and, crucially, flags a misconfigured
    /// App Group, which is the other reason the inbox stays empty (the
    /// extension writes to a container the app can't see).
    private func updateEmptyState() {
        emptyLabel.isHidden = !viewModel.isEmpty
        guard viewModel.isEmpty else { return }
        if SharedDataManager.shared.isSharedContainerAvailable {
            emptyLabel.text = "Nothing shared yet.\nShare a link, photo, or text into this app."
        } else {
            emptyLabel.text = "⚠️ App Group not available.\n\nEnable the “App Groups” capability\n(group.com.hackathon.Eternal-Hackathon-2026)\non BOTH the app and the ShareExtension\ntargets, then delete & reinstall the app."
        }
    }

    private func observeSharedContent() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSharedContent(_:)),
            name: .didReceiveSharedContent, object: nil)
    }

    @objc private func handleSharedContent(_ note: Notification) {
        // Storage is the single source of truth — drain it here so a live
        // share updates an already-open inbox.
        viewModel.loadPending()
    }

    // MARK: - UI

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyLabel.text = "Nothing shared yet.\nShare a link, photo, or text into this app."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }
}

// MARK: - UITableViewDataSource

extension SharedInboxViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.sections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = viewModel.sections[indexPath.section].rows[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = row.title
        config.secondaryText = row.subtitle
        config.textProperties.numberOfLines = 2
        if let thumb = row.thumbnail {
            config.image = thumb
            config.imageProperties.maximumSize = CGSize(width: 44, height: 44)
            config.imageProperties.cornerRadius = 6
        } else {
            config.image = UIImage(systemName: row.symbolName)
        }
        cell.contentConfiguration = config
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SharedInboxViewController: UITableViewDelegate {

    /// Switching on the typed `content` is exactly what the separated model
    /// enables: links open, text is copied, files are acknowledged.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = viewModel.sections[indexPath.section].rows[indexPath.row]
        switch row.content {
        case .link(let url):
            UIApplication.shared.open(url)
        case .text(let text):
            UIPasteboard.general.string = text
            let alert = UIAlertController(title: "Copied", message: nil, preferredStyle: .alert)
            present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { alert.dismiss(animated: true) }
        case .file:
            break // Hook a QuickLook preview here later.
        }
    }
}
