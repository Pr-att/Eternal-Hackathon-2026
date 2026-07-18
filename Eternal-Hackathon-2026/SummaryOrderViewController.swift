//
//  SummaryOrderViewController.swift
//  AIRecipeShopping
//
//  Screen 4 — final review in a UICollectionView (compositional layout with card-style sections).
//

import UIKit

// MARK: - Grid item cell (image + name)

final class SummaryGridCell: UICollectionViewCell {
    static let reuseID = "SummaryGridCell"

    private let thumb = ThumbnailView(emoji: "🍅", size: 44, corner: 14)
    private let nameLabel = Make.label("", font: Theme.Font.caption(),
                                       color: Theme.Color.textSecondary, align: .center, lines: 2)
    // "×N" pill shown on the thumbnail when the user picked more than one.
    private let qtyBadge = Make.label("", font: Theme.Font.captionBold(), color: .black, align: .center)

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [thumb, nameLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        qtyBadge.backgroundColor = Theme.Color.green
        qtyBadge.layer.cornerRadius = 9
        qtyBadge.layer.masksToBounds = true
        qtyBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(qtyBadge)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 56),
            thumb.heightAnchor.constraint(equalToConstant: 56),

            qtyBadge.centerXAnchor.constraint(equalTo: thumb.trailingAnchor, constant: -3),
            qtyBadge.centerYAnchor.constraint(equalTo: thumb.topAnchor, constant: 3),
            qtyBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            qtyBadge.heightAnchor.constraint(equalToConstant: 18)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with item: GroceryItem) {
        thumb.setEmoji(item.emoji)
        nameLabel.text = item.name
        qtyBadge.text = "  ×\(item.quantity)  "
        qtyBadge.isHidden = item.quantity <= 1
    }
}

// MARK: - Staples cell (full width text)

final class StaplesCell: UICollectionViewCell {
    static let reuseID = "StaplesCell"
    private let label = Make.label("", font: Theme.Font.bodyMedium(), color: Theme.Color.textPrimary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        label.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String) { label.text = text }
}

// MARK: - Section header (icon + title + count badge)

final class SummaryHeaderView: UICollectionReusableView {
    static let reuseID = "SummaryHeaderView"

    private let icon = UIImageView()
    private let title = Make.label("", font: Theme.Font.headline(), color: Theme.Color.textPrimary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(icon symbol: String, tint: UIColor, title text: String, count: Int) {
        subviews.forEach { $0.removeFromSuperview() }
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = tint
        title.text = text
        let badge = CountBadge(count: count, background: Theme.Color.surfaceElevated, foreground: Theme.Color.textPrimary)

        let row = UIStackView(arrangedSubviews: [icon, title, UIView(), badge])
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        // Pad the heading away from the card's top edge (and sides) directly in
        // the view so the spacing is independent of the compositional layout's
        // supplementary-item content insets.
        row.pin(to: self, insets: .init(top: 22, left: 18, bottom: 14, right: 18))
    }
}

// MARK: - Section card background decoration

final class SectionCardDecoration: UICollectionReusableView {
    static let reuseID = "SectionCardDecoration"
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        layer.cornerRadius = Theme.Metric.cardRadius
        layer.borderWidth = 1
        layer.borderColor = Theme.Color.stroke.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - View controller

final class SummaryOrderViewController: UIViewController {

    private enum Section: Int, CaseIterable { case toBuy, equipment, staples }

    // Injected from the Review & Edit screen so this screen reflects the user's
    // actual edits (removed items, changed quantities) — not static sample data.
    private let consumables: [GroceryItem]
    private let equipment: [GroceryItem]
    private let staples: [String]

    private var collectionView: UICollectionView!

    init(consumables: [GroceryItem] = SampleData.consumables,
         equipment: [GroceryItem] = SampleData.equipment,
         staples: [String] = SampleData.staples) {
        self.consumables = consumables
        self.equipment = equipment
        self.staples = staples
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background
        navigationItem.hidesBackButton = true
        buildLayout()
    }

    // MARK: Layout

    private func buildLayout() {
        let header = makeHeader()
        let bottomBar = makeBottomBar()

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCompositionalLayout())
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.contentInset = .init(top: 8, left: 0, bottom: 16, right: 0)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(SummaryGridCell.self, forCellWithReuseIdentifier: SummaryGridCell.reuseID)
        collectionView.register(StaplesCell.self, forCellWithReuseIdentifier: StaplesCell.reuseID)
        collectionView.register(SummaryHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SummaryHeaderView.reuseID)

        [header, collectionView, bottomBar].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Metric.screenInset),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Metric.screenInset),

            collectionView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Metric.screenInset),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Metric.screenInset),
            collectionView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeHeader() -> UIView {
        let back = Make.backButton(target: self, action: #selector(backTapped))

        let title = Make.label("Summary & Order", font: Theme.Font.title(), color: Theme.Color.textPrimary, lines: 1)
        let titleRow = UIStackView(arrangedSubviews: [title])
        titleRow.spacing = 8
        titleRow.alignment = .center

        let subtitle = Make.label("Review everything and place the order.",
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

    private func makeBottomBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = Theme.Color.background
        bar.translatesAutoresizingMaskIntoConstraints = false

        let order = GradientButton(title: "Order now from Blinkit", systemImage: "arrow.right", trailing: true)
        order.translatesAutoresizingMaskIntoConstraints = false
        order.addTarget(self, action: #selector(orderTapped), for: .touchUpInside)

        let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
        lock.tintColor = Theme.Color.textTertiary
        lock.contentMode = .scaleAspectFit
        lock.translatesAutoresizingMaskIntoConstraints = false
        lock.widthAnchor.constraint(equalToConstant: 12).isActive = true
        let secure = Make.label("Secure checkout", font: Theme.Font.caption(), color: Theme.Color.textTertiary)
        let secureRow = UIStackView(arrangedSubviews: [lock, secure])
        secureRow.spacing = 6
        secureRow.alignment = .center

        let secureWrap = UIView()
        secureRow.translatesAutoresizingMaskIntoConstraints = false
        secureWrap.addSubview(secureRow)
        NSLayoutConstraint.activate([
            secureRow.centerXAnchor.constraint(equalTo: secureWrap.centerXAnchor),
            secureRow.topAnchor.constraint(equalTo: secureWrap.topAnchor),
            secureRow.bottomAnchor.constraint(equalTo: secureWrap.bottomAnchor)
        ])

        let stack = UIStackView(arrangedSubviews: [order, secureWrap])
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 12, left: Theme.Metric.screenInset, bottom: 8, right: Theme.Metric.screenInset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            order.heightAnchor.constraint(equalToConstant: Theme.Metric.ctaHeight)
        ])
        return bar
    }

    // MARK: Compositional layout

    private func makeCompositionalLayout() -> UICollectionViewLayout {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 16

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] sectionIndex, _ in
            guard let self, let section = Section(rawValue: sectionIndex) else { return nil }
            switch section {
            case .toBuy:     return self.gridSection(columns: 4, rowHeight: 96)
            case .equipment: return self.gridSection(columns: 3, rowHeight: 96)
            case .staples:   return self.staplesSection()
            }
        }, configuration: config)
        layout.register(SectionCardDecoration.self, forDecorationViewOfKind: SectionCardDecoration.reuseID)
        return layout
    }

    private func gridSection(columns: Int, rowHeight: CGFloat) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .fractionalHeight(1.0)))
        item.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                              heightDimension: .absolute(rowHeight)),
            subitem: item, count: columns)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 12, leading: 12, bottom: 16, trailing: 12)
        section.supplementariesFollowContentInsets = false
        section.boundarySupplementaryItems = [makeHeaderItem()]
        section.decorationItems = [makeDecoration()]
        return section
    }

    private func staplesSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(24)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                              heightDimension: .absolute(24)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 14, leading: 18, bottom: 18, trailing: 18)
        section.supplementariesFollowContentInsets = false
        section.boundarySupplementaryItems = [makeHeaderItem()]
        section.decorationItems = [makeDecoration()]
        return section
    }

    private func makeHeaderItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(74)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top)
        // Padding is baked into SummaryHeaderView itself (see configure), so the
        // layout item carries no additional content insets.
        header.contentInsets = .zero
        return header
    }

    private func makeDecoration() -> NSCollectionLayoutDecorationItem {
        let deco = NSCollectionLayoutDecorationItem.background(elementKind: SectionCardDecoration.reuseID)
        deco.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
        return deco
    }

    // MARK: Actions

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }

    @objc private func orderTapped() {
        let alert = UIAlertController(title: "Order placed 🎉",
                                      message: "Your grocery list has been sent to Blinkit.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.navigationController?.popToRootViewController(animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - Data source

extension SummaryOrderViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int { Section.allCases.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .toBuy:     return consumables.count
        case .equipment: return equipment.count
        case .staples:   return 1
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .toBuy:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SummaryGridCell.reuseID, for: indexPath) as! SummaryGridCell
            cell.configure(with: consumables[indexPath.item])
            return cell
        case .equipment:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SummaryGridCell.reuseID, for: indexPath) as! SummaryGridCell
            cell.configure(with: equipment[indexPath.item])
            return cell
        case .staples:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StaplesCell.reuseID, for: indexPath) as! StaplesCell
            cell.configure(text: staples.joined(separator: ", "))
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: SummaryHeaderView.reuseID, for: indexPath) as! SummaryHeaderView
        switch Section(rawValue: indexPath.section)! {
        case .toBuy:
            header.configure(icon: "cart.fill", tint: Theme.Color.green,
                             title: "To Buy (Consumables)", count: consumables.count)
        case .equipment:
            header.configure(icon: "wrench.and.screwdriver.fill", tint: Theme.Color.gradientEnd,
                             title: "Equipment", count: equipment.count)
        case .staples:
            header.configure(icon: "leaf.fill", tint: Theme.Color.green,
                             title: "Staples", count: staples.count)
        }
        return header
    }
}
