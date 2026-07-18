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
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // The home screen is `HomeViewController` (the AI Recipe Shopping flow),
        // presented programmatically inside a nav controller with the bar hidden
        // in favour of the custom in-screen headers. This replaces the old
        // storyboard `ViewController` test harness.
        let args = ProcessInfo.processInfo.arguments
        let root: UIViewController = args.contains("-showSummary") ? SummaryOrderViewController()
            : args.contains("-showReview") ? ReviewEditViewController() : HomeViewController()
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.isHidden = true
        nav.view.backgroundColor = Theme.Color.background

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = nav
        window.overrideUserInterfaceStyle = .dark   // this design is dark-only
        window.makeKeyAndVisible()
        self.window = window

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

    /// A shared link no longer opens a separate inbox — the home screen
    /// (`HomeViewController`) observes `.didReceiveSharedContent` and pulls the
    /// URL into its link field. `AppLaunchManager.handle` has already posted
    /// that signal, so there is nothing to present here.
    private func route(_ route: DeepLinkRoute) {
        guard route == .sharedInbox else { return }
        // Home screen consumes the shared link via notification; no-op here.
    }
}
