//
//  ViewController.swift
//  Eternal-Hackathon-2026
//
//  The storyboard's initial screen. Kept minimal — it just offers a manual
//  entry point into the Shared Inbox so you can inspect received content
//  without re-triggering the share sheet each time.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let button = UIButton(configuration: .borderedProminent())
        button.setTitle("Open Shared Inbox", for: .normal)
        button.addAction(UIAction { [weak self] _ in
            let inbox = SharedInboxViewController()
            let nav = UINavigationController(rootViewController: inbox)
            self?.present(nav, animated: true)
        }, for: .touchUpInside)

        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
