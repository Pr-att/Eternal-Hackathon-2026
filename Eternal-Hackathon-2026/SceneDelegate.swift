//
//  SceneDelegate.swift
//  Eternal-Hackathon-2026
//
//  Handles the two ways shared content reaches the app:
//   1. The extension opens `eternalhackathon://shared` → openURLContexts.
//   2. The app was terminated when the extension ran → the URL arrives in
//      `willConnectTo` via connectionOptions, and/or we sweep pending items
//      when the scene becomes active.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = (scene as? UIWindowScene) else { return }

        // Cold start via deep link: the URL is delivered here, not in
        // openURLContexts.
        if let urlContext = connectionOptions.urlContexts.first {
            route(AppLaunchManager.shared.handle(url: urlContext.url))
        }
    }

    /// Warm open: app already running when the extension fired the URL.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        route(AppLaunchManager.shared.handle(url: url))
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Belt-and-suspenders: pick up anything the extension queued even if
        // the deep link didn't route us (e.g. user opened the app by hand).
        AppLaunchManager.shared.handleAppBecameActive()
    }

    // MARK: - Routing

    /// Presents the destination screen for a resolved route.
    private func route(_ route: DeepLinkRoute) {
        guard route == .sharedInbox else { return }
        DispatchQueue.main.async { [weak self] in
            self?.presentSharedInbox()
        }
    }

    private func presentSharedInbox() {
        guard let root = window?.rootViewController else { return }
        // Walk to the top-most presented controller so we push the inbox over
        // whatever screen is currently on top, not just the root.
        var top = root
        while let presented = top.presentedViewController { top = presented }
        // Avoid stacking multiple inbox screens.
        if top is UINavigationController { return }

        let inbox = SharedInboxViewController()
        let nav = UINavigationController(rootViewController: inbox)
        inbox.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) })
        nav.modalPresentationStyle = .fullScreen
        top.present(nav, animated: true)
    }
}
