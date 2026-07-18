//
//  ReviewEditViewController.swift
//  AIRecipeShopping
//
//  Screen 3 — the extracted list in a UITableView. User can reorder / delete items.
//

import UIKit

// MARK: - Cell

final class GroceryItemCell: UITableViewCell {

    static let reuseID = "GroceryItemCell"

    private let container = UIView()
    private let thumb = ThumbnailView(emoji: "🍅", size: 40)
    private let nameLabel = Make.label("", font: Theme.Font.bodyMedium(), color: Theme.Color.textPrimary)

    // Quantity stepper: [−] qty [+]
    private let stepper = UIView()
    private let minusButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private let qtyLabel = Make.label("1", font: Theme.Font.bodyMedium(), color: Theme.Color.textPrimary, align: .center)

    private var quantity = 1

    /// Fired when the quantity changes; passes the new value (always ≥ 1).
    var onQuantityChange: ((Int) -> Void)?
    /// Fired when "−" is tapped at quantity 1 — i.e. the user removes the item.
    var onRemove: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildLayout() {
        container.backgroundColor = Theme.Color.surface
        container.layer.cornerRadius = 14
        container.layer.borderWidth = 1
        container.layer.borderColor = Theme.Color.stroke.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        thumb.translatesAutoresizingMaskIntoConstraints = false

        buildStepper()

        let stack = UIStackView(arrangedSubviews: [thumb, nameLabel, UIView(), stepper])
        stack.spacing = 12
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        stack.pin(to: container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            thumb.widthAnchor.constraint(equalToConstant: 40),
            thumb.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func buildStepper() {
        // Small glyphs so the stepper reads as a compact control rather than
        // two chunky buttons.
        let glyphConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        for button in [minusButton, plusButton] {
            button.tintColor = Theme.Color.green   // match the "Ingredients" accent
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        }
        minusButton.setImage(UIImage(systemName: "minus", withConfiguration: glyphConfig), for: .normal)
        plusButton.setImage(UIImage(systemName: "plus", withConfiguration: glyphConfig), for: .normal)
        minusButton.addTarget(self, action: #selector(minusTapped), for: .touchUpInside)
        plusButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)

        qtyLabel.textColor = Theme.Color.green
        qtyLabel.setContentHuggingPriority(.required, for: .horizontal)
        qtyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true

        let row = UIStackView(arrangedSubviews: [minusButton, qtyLabel, plusButton])
        row.spacing = 2
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        stepper.backgroundColor = Theme.Color.greenSoftFill
        stepper.layer.cornerRadius = 10
        stepper.layer.borderWidth = 1
        stepper.layer.borderColor = Theme.Color.green.withAlphaComponent(0.5).cgColor
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: stepper.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: stepper.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: stepper.leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: stepper.trailingAnchor, constant: -4)
        ])
    }

    func configure(with item: GroceryItem) {
        nameLabel.text = item.name
        thumb.setEmoji(item.emoji)
        quantity = max(1, item.quantity)
        qtyLabel.text = "\(quantity)"
    }

    @objc private func minusTapped() {
        guard quantity > 1 else { onRemove?(); return }
        quantity -= 1
        qtyLabel.text = "\(quantity)"
        onQuantityChange?(quantity)
    }

    @objc private func plusTapped() {
        quantity += 1
        qtyLabel.text = "\(quantity)"
        onQuantityChange?(quantity)
    }
}

// MARK: - View controller

final class ReviewEditViewController: UIViewController {

    private enum Tab: Int, CaseIterable {
        case toBuy, equipment, staples
        var title: String {
            switch self {
            case .toBuy:     return "Ingredients"
            case .equipment: return "Equipment"
            case .staples:   return "Staples"
            }
        }
        var icon: String {
            switch self {
            case .toBuy:     return "cart"
            case .equipment: return "wrench.and.screwdriver"
            case .staples:   return "leaf"
            }
        }
    }

    private var consumables = SampleData.consumables
    private var equipment   = SampleData.equipment
    private var staples     = SampleData.staples.map { GroceryItem(name: $0, emoji: "🧂", isSelected: false) }

    /// Real on-device extraction results; nil keeps the sample-data demo.
    init(items: [ExtractedItem]? = nil) {
        super.init(nibName: nil, bundle: nil)
        guard let items else { return }
        func grocery(_ category: ItemCategory) -> [GroceryItem] {
            items.filter { $0.category == category }.map {
                GroceryItem(name: $0.name.capitalized,
                            emoji: IngredientIcon.emoji(for: $0.name, category: $0.category),
                            imageName: IngredientIcon.canonical($0.name),
                            // only consumables land in the cart by default
                            isSelected: category == .consumable)
            }
        }
        consumables = grocery(.consumable)
        equipment   = grocery(.equipment)
        staples     = grocery(.staple)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var selectedTab: Tab = .toBuy
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var tabButtons: [UIButton] = []
    private let itemCountLabel = Make.label("", font: Theme.Font.headline(), color: Theme.Color.textPrimary)

    private var currentItems: [GroceryItem] {
        switch selectedTab {
        case .toBuy:     return consumables
        case .equipment: return equipment
        case .staples:   return staples
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background
        navigationItem.hidesBackButton = true
        buildLayout()
        refreshCounts()
    }

    // MARK: Layout

    private func buildLayout() {
        let header = makeHeader()
        let tabs = makeTabBar()
        let bottomBar = makeBottomBar()

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(GroceryItemCell.self, forCellReuseIdentifier: GroceryItemCell.reuseID)
        tableView.contentInset = .init(top: 4, left: 0, bottom: 12, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        [header, tabs, tableView, bottomBar].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Metric.screenInset),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Metric.screenInset),

            tabs.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Metric.screenInset),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Metric.screenInset),

            tableView.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Metric.screenInset),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Metric.screenInset),
            tableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeHeader() -> UIView {
        let back = Make.backButton(target: self, action: #selector(backTapped))

        let title = Make.label("Review & Edit", font: Theme.Font.title(), color: Theme.Color.textPrimary, lines: 1)
        let titleRow = UIStackView(arrangedSubviews: [title])
        titleRow.spacing = 8
        titleRow.alignment = .center

        let subtitle = Make.label("Review items and edit before adding to cart.",
                                  font: Theme.Font.caption(), color: Theme.Color.textSecondary, align: .center)

        let centerStack = UIStackView(arrangedSubviews: [titleRow, subtitle])
        centerStack.axis = .vertical
        centerStack.spacing = 4
        centerStack.alignment = .center
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(back)
        container.addSubview(centerStack)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            back.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 28),
            back.heightAnchor.constraint(equalToConstant: 28),

            centerStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            centerStack.topAnchor.constraint(equalTo: container.topAnchor),
            centerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeTabBar() -> UIView {
        let row = UIStackView()
        row.spacing = 10
        row.distribution = .fillProportionally
        row.translatesAutoresizingMaskIntoConstraints = false

        for tab in Tab.allCases {
            let count: Int
            switch tab {
            case .toBuy:     count = consumables.count
            case .equipment: count = equipment.count
            case .staples:   count = staples.count
            }
            let button = makeTabButton(tab: tab, count: count)
            tabButtons.append(button)
            row.addArrangedSubview(button)
        }
        updateTabAppearance()
        return row
    }

    private func makeTabButton(tab: Tab, count: Int) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "\(tab.title) (\(count))"
        config.image = UIImage(systemName: tab.icon)
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        config.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        config.attributedTitle = AttributedString(config.title!,
            attributes: AttributeContainer([.font: Theme.Font.caption()]))
        button.configuration = config
        button.tag = tab.rawValue
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        return button
    }

    private func updateTabAppearance() {
        for (i, button) in tabButtons.enumerated() {
            let isActive = i == selectedTab.rawValue
            button.tintColor = isActive ? Theme.Color.green : Theme.Color.textSecondary
            button.backgroundColor = isActive ? Theme.Color.greenSoftFill : Theme.Color.surface
            button.layer.borderColor = (isActive ? Theme.Color.green : Theme.Color.stroke).cgColor
        }
    }

    private func makeBottomBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = Theme.Color.surface
        bar.layer.cornerRadius = Theme.Metric.cardRadius
        bar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        bar.layer.borderWidth = 1
        bar.layer.borderColor = Theme.Color.stroke.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false

        itemCountLabel.font = Theme.Font.headline()
        let sub = Make.label("Ready to add", font: Theme.Font.caption(), color: Theme.Color.textSecondary)
        let leftStack = UIStackView(arrangedSubviews: [itemCountLabel, sub])
        leftStack.axis = .vertical
        leftStack.spacing = 2

        let cont = GradientButton(title: "Continue", systemImage: "arrow.right", trailing: true)
        cont.translatesAutoresizingMaskIntoConstraints = false
        cont.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [leftStack, UIView(), cont])
        row.spacing = 12
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = .init(top: 14, left: 18, bottom: 14, right: 18)
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bar.topAnchor),
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            cont.heightAnchor.constraint(equalToConstant: 48),
            cont.widthAnchor.constraint(greaterThanOrEqualToConstant: 130)
        ])
        return bar
    }

    // MARK: Helpers

    private func refreshCounts() {
        let total = consumables.count + equipment.count + staples.count
        itemCountLabel.text = "\(total) items"
    }

    private func setItems(_ items: [GroceryItem]) {
        switch selectedTab {
        case .toBuy:     consumables = items
        case .equipment: equipment = items
        case .staples:   staples = items
        }
    }

    /// Removes an item and refreshes every count that depends on it. Reloading
    /// the whole section (rather than just `deleteRows`) is what fixes the stale
    /// number in the section-header badge — `deleteRows` never rebuilds the
    /// header, so its count used to lag behind the tab-bar count.
    private func removeItem(at row: Int) {
        var items = currentItems
        guard row < items.count else { return }
        items.remove(at: row)
        setItems(items)
        refreshCounts()
        rebuildTabTitles()
        tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    }

    // MARK: Actions

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }

    @objc private func tabTapped(_ sender: UIButton) {
        guard let tab = Tab(rawValue: sender.tag) else { return }
        selectedTab = tab
        updateTabAppearance()
        tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    }

    @objc private func continueTapped() {
        let vc = SummaryOrderViewController(
            consumables: consumables,
            equipment: equipment,
            staples: staples.map { $0.name })
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func addMoreTapped() {
        let alert = UIAlertController(title: "Add item",
                                     message: "Type an item name — we'll pick a matching icon.",
                                     preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "e.g. Paneer, Tomato, Rice"
            field.autocapitalizationType = .words
            field.returnKeyType = .done
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = (alert?.textFields?.first?.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            self.appendItem(named: name)
        })
        present(alert, animated: true)
    }

    /// Appends a freshly-typed item to the active tab, auto-picking an emoji icon.
    private func appendItem(named name: String) {
        var items = currentItems
        items.append(GroceryItem(name: name, emoji: GroceryEmoji.guess(for: name)))
        setItems(items)
        refreshCounts()
        rebuildTabTitles()
        tableView.reloadData()
    }

    private func rebuildTabTitles() {
        let counts = [consumables.count, equipment.count, staples.count]
        for (i, button) in tabButtons.enumerated() {
            guard let tab = Tab(rawValue: i) else { continue }
            button.configuration?.attributedTitle = AttributedString(
                "\(tab.title) (\(counts[i]))",
                attributes: AttributeContainer([.font: Theme.Font.caption()]))
        }
    }
}

// MARK: - Table data source / delegate

extension ReviewEditViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        currentItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: GroceryItemCell.reuseID, for: indexPath) as! GroceryItemCell
        let item = currentItems[indexPath.row]
        cell.configure(with: item)
        cell.onQuantityChange = { [weak self, weak cell] qty in
            guard let self, let cell, let idx = self.tableView.indexPath(for: cell) else { return }
            var items = self.currentItems
            items[idx.row].quantity = qty
            self.setItems(items)
        }
        cell.onRemove = { [weak self, weak cell] in
            guard let self, let cell, let idx = self.tableView.indexPath(for: cell) else { return }
            self.removeItem(at: idx.row)
        }
        return cell
    }

    // Section header: "TO BUY (CONSUMABLES)   [count]"
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()

        let titleText: String
        switch selectedTab {
        case .toBuy:     titleText = "INGREDIENTS"
        case .equipment: titleText = "EQUIPMENT"
        case .staples:   titleText = "STAPLES"
        }
        let title = Make.label(titleText, font: Theme.Font.captionBold(), color: Theme.Color.green)
        let badge = CountBadge(count: currentItems.count)

        let row = UIStackView(arrangedSubviews: [title, UIView(), badge])
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -2)
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 44 }

    // Footer: dashed "+ Add more item" button
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footer = UIView()
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "Add more item"
        config.image = UIImage(systemName: "plus")
        config.imagePadding = 6
        config.baseForegroundColor = Theme.Color.green
        config.attributedTitle = AttributedString("Add more item",
            attributes: AttributeContainer([.font: Theme.Font.bodyMedium()]))
        button.configuration = config
        button.tintColor = Theme.Color.green
        button.backgroundColor = Theme.Color.greenSoftFill.withAlphaComponent(0.4)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = Theme.Color.green.withAlphaComponent(0.5).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(addMoreTapped), for: .touchUpInside)

        footer.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: footer.topAnchor, constant: 8),
            button.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -8),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])
        return footer
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 64 }

    // Swipe to delete
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, done in
            guard let self else { done(false); return }
            self.removeItem(at: indexPath.row)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = Theme.Color.danger
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // Reorder support
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        var items = currentItems
        let moved = items.remove(at: sourceIndexPath.row)
        items.insert(moved, at: destinationIndexPath.row)
        setItems(items)
    }
}
