//
//  ShareViewController.swift
//  ShareExtension
//
//  The extension's entry point (referenced by NSExtensionPrincipalClass in
//  Info.plist). Deliberately THIN: it shows a small native-feeling status
//  card, hands the work to `ShareExtensionCoordinator`, then either opens
//  the main app via the custom URL scheme or completes the request.
//
//  It does NOT do heavy work, networking, or parsing — per Apple's guidance
//  extensions are memory-constrained and should return quickly.
//

import UIKit

final class ShareViewController: UIViewController {

    private let coordinator = ShareExtensionCoordinator(now: Date().timeIntervalSince1970)

    override func viewDidLoad() {
        super.viewDidLoad()
        // No visible UI: the extension is a silent pass-through. The user
        // taps our app in the share sheet, the sheet dismisses, and we launch
        // the main app — with no intermediate extension screen.
        view.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Start as EARLY as possible (before the sheet finishes its expand
        // animation) so we can complete the request almost immediately — the
        // user sees a brief flash instead of a fully-expanded compose sheet.
        processShareIfNeeded()
    }

    private var didStart = false
    private func processShareIfNeeded() {
        guard !didStart else { return }
        didStart = true

        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(with: .failure(.emptyShare))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let result = await self.coordinator.handle(items: items)
            // UI + extensionContext calls must be on the main actor.
            await MainActor.run { self.finish(with: result) }
        }
    }

    // MARK: - Completion

    private func finish(with result: ShareResult) {
        switch result {
        case .success(let deepLink, _):
            // Items are saved to the App Group. Now launch the main app via
            // its custom URL scheme. The open must happen BEFORE completing —
            // completing first tears the extension down and returns focus to
            // the host (Safari) instead of our app.
            openHostApp(deepLink)

        case .failure(let error):
            presentErrorAndDismiss(error)
        }
    }

    // MARK: - Opening the host app

    /// Launches the main app (`eternalhackathon://shared`).
    ///
    /// Opening its OWN containing app from a Share Extension is version-finicky,
    /// so we fire BOTH known mechanisms and never let teardown cancel the launch:
    ///
    /// 1. Responder-chain `openURL:` on the real `UIApplication`. This is the
    ///    battle-tested path. The previous code matched *any* responder that
    ///    merely responded to `openURL:` — on iOS 18+ the first match is often
    ///    NOT the application, so the call no-op'd and the sheet just flashed
    ///    and dismissed. We now cast to `UIApplication` so we hit the real one.
    /// 2. `NSExtensionContext.open(_:)` — the sanctioned API; harmless if it
    ///    no-ops for a custom scheme.
    ///
    /// `completeRequest` (which dismisses the sheet) is deferred behind a short
    /// watchdog. Calling it synchronously can cancel the pending launch and
    /// bounce focus back to the host app (Instagram) — the "flash and dismiss".
    private func openHostApp(_ url: URL) {
        let opened = openViaResponderChain(url)
        NSLog("[ShareExtension] openHostApp \(url.absoluteString) responderChainOpened=\(opened)")
        extensionContext?.open(url) { success in
            NSLog("[ShareExtension] extensionContext.open success=\(success)")
        }
        // Give the launch a beat to take effect before tearing the extension
        // down. If the app came forward, this no-ops; if it didn't, it releases
        // the sheet so we never hang.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.complete()
        }
    }

    /// Walks the responder chain to the hosting `UIApplication` and asks it to
    /// open our custom URL scheme — the reliable way for a Share Extension to
    /// launch its containing app.
    ///
    /// iOS 18+ stopped honoring the legacy one-arg `openURL:` selector (which
    /// earlier code used — that's why the sheet just flashed and dismissed). The
    /// surviving selector is the three-arg `openURL:options:completionHandler:`.
    /// `perform(_:with:)` can only pass one argument, so we resolve the method's
    /// implementation (`IMP`) and invoke it through a typed C function pointer.
    /// `UIApplication.open(_:…)` itself is compile-time unavailable in an
    /// extension, so the IMP route is also how we sidestep that.
    @discardableResult
    private func openViaResponderChain(_ url: URL) -> Bool {
        typealias OpenURLIMP = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, Any?) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")

        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector),
               let method = class_getInstanceMethod(type(of: current), selector) {
                let imp = method_getImplementation(method)
                let open = unsafeBitCast(imp, to: OpenURLIMP.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                NSLog("[ShareExtension] invoked openURL:options:completionHandler: on \(type(of: current))")
                return true
            }
            responder = current.next
        }
        NSLog("[ShareExtension] responder chain found no UIApplication responding to openURL:options:completionHandler:")
        return false
    }

    /// Completes the extension request successfully, dismissing the sheet.
    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// Cancels the extension request, propagating an error to the host.
    private func cancel(_ error: ShareError) {
        let ns = NSError(domain: "ShareExtension", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: error.errorDescription ?? "Error"])
        extensionContext?.cancelRequest(withError: ns)
    }

    private func presentErrorAndDismiss(_ error: ShareError) {
        let alert = UIAlertController(title: "Couldn't Share",
                                      message: error.errorDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.cancel(error)
        })
        present(alert, animated: true)
    }
}
