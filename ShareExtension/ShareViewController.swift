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

    /// Launches the main app (`eternalhackathon://shared`). Uses the supported
    /// `NSExtensionContext.open(_:)` first, then the responder-chain fallback
    /// for older iOS, and completes the request once the open is dispatched.
    private func openHostApp(_ url: URL) {
        guard let context = extensionContext else { complete(); return }
        context.open(url) { [weak self] success in
            guard let self else { return }
            if !success { self.openViaResponderChain(url) }
            self.complete()
        }
    }

    /// Walks the responder chain for an object implementing `openURL:` and
    /// invokes it. Fallback for iOS versions where `extensionContext.open`
    /// declines a custom scheme.
    @discardableResult
    private func openViaResponderChain(_ url: URL) -> Bool {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
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
