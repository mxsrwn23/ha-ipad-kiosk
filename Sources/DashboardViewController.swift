import UIKit
import WebKit

/// Full-screen Home Assistant dashboard with automatic reconnect and an
/// in-app, gesture-hidden way to (re)configure the server URL — there is no
/// nav bar in kiosk mode, so a Settings-bundle entry would be easy to miss.
final class DashboardViewController: UIViewController {

    private static let serverURLKey = "ha_server_url"

    private var webView: WKWebView!
    private let connectivity = ConnectivityMonitor()

    private var statusOverlay: UIView!
    private var statusLabel: UILabel!
    private var spinner: UIActivityIndicatorView!

    private var retryDelay: TimeInterval = 2
    private let maxRetryDelay: TimeInterval = 30
    private var retryWorkItem: DispatchWorkItem?
    private var watchdogTimer: Timer?
    private var lastSuccessfulLoad: Date?
    private var isLoading = false

    private var didRequestInitialURL = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupWebView()
        setupStatusOverlay()
        setupConfigGesture()
        setupConnectivityMonitor()

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Presenting a UIAlertController from viewDidLoad can silently no-op on a
        // cold launch, since the view isn't reliably attached to the window yet.
        guard !didRequestInitialURL else { return }
        didRequestInitialURL = true

        if let url = Self.storedServerURL() {
            load(url: url)
        } else {
            promptForServerURL(initialText: nil) { [weak self] url in
                self?.load(url: url)
            }
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - WebView

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func load(url: URL) {
        isLoading = true
        retryWorkItem?.cancel()
        webView.load(URLRequest(url: url))
    }

    /// Called by the app delegate when returning to the foreground or waking
    /// from a background-fetch cycle, in case the connection died while the
    /// screen was off or another app briefly took over (e.g. a phone call UI).
    func reloadIfNeeded() {
        guard let url = Self.storedServerURL() else { return }
        let staleThreshold: TimeInterval = 60
        let isStale = lastSuccessfulLoad.map { Date().timeIntervalSince($0) > staleThreshold } ?? true
        if isStale && !isLoading {
            load(url: url)
        }
    }

    private func watchdogTick() {
        guard let url = Self.storedServerURL() else { return }
        let staleThreshold: TimeInterval = 90
        let isStale = lastSuccessfulLoad.map { Date().timeIntervalSince($0) > staleThreshold } ?? true
        if isStale && !isLoading {
            load(url: url)
        }
    }

    // MARK: - Connectivity

    private func setupConnectivityMonitor() {
        connectivity.onBecameReachable = { [weak self] in
            guard let self = self, let url = Self.storedServerURL() else { return }
            self.retryDelay = 2
            self.load(url: url)
        }
        connectivity.onBecameUnreachable = { [weak self] in
            self?.showOverlay(text: "Keine Netzwerkverbindung …")
        }
        connectivity.start()
    }

    private func scheduleRetry() {
        retryWorkItem?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, maxRetryDelay)
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let url = Self.storedServerURL() else { return }
            self.load(url: url)
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Status overlay

    private func setupStatusOverlay() {
        statusOverlay = UIView()
        statusOverlay.translatesAutoresizingMaskIntoConstraints = false
        statusOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        statusOverlay.isHidden = true
        view.addSubview(statusOverlay)
        NSLayoutConstraint.activate([
            statusOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            statusOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        spinner = UIActivityIndicatorView(style: .whiteLarge)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        statusOverlay.addSubview(spinner)

        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 17, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusOverlay.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: statusOverlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: statusOverlay.centerYAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: statusOverlay.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: statusOverlay.trailingAnchor, constant: -32)
        ])
    }

    private func showOverlay(text: String) {
        statusLabel.text = text
        statusOverlay.isHidden = false
        spinner.startAnimating()
    }

    private func hideOverlay() {
        statusOverlay.isHidden = true
        spinner.stopAnimating()
    }

    // MARK: - Hidden server-URL configuration

    /// A 3-second long-press in the top-left corner reopens the URL prompt.
    /// Kept intentionally inside the app (not a Settings-bundle entry) since
    /// kiosk mode hides the status/nav chrome a user would need to find one.
    private func setupConfigGesture() {
        let hotCorner = UIView()
        hotCorner.translatesAutoresizingMaskIntoConstraints = false
        hotCorner.backgroundColor = .clear
        view.addSubview(hotCorner)
        NSLayoutConstraint.activate([
            hotCorner.topAnchor.constraint(equalTo: view.topAnchor),
            hotCorner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hotCorner.widthAnchor.constraint(equalToConstant: 60),
            hotCorner.heightAnchor.constraint(equalToConstant: 60)
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleConfigGesture))
        longPress.minimumPressDuration = 3.0
        hotCorner.addGestureRecognizer(longPress)
    }

    @objc private func handleConfigGesture(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        promptForServerURL(initialText: Self.storedServerURL()?.absoluteString) { [weak self] url in
            self?.retryDelay = 2
            self?.load(url: url)
        }
    }

    private func promptForServerURL(initialText: String?, completion: @escaping (URL) -> Void) {
        let alert = UIAlertController(
            title: "Home Assistant Server",
            message: "Gib die Adresse deines Home Assistant Servers ein, z.B. http://192.168.1.50:8123",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = initialText
            field.placeholder = "http://homeassistant.local:8123"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        let save = UIAlertAction(title: "Speichern", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text,
                  let url = Self.normalizedURL(from: text) else {
                self?.promptForServerURL(initialText: initialText, completion: completion)
                return
            }
            Self.setStoredServerURL(url)
            completion(url)
        }
        alert.addAction(save)

        if initialText != nil {
            alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        }

        present(alert, animated: true)
    }

    // MARK: - Persistence helpers

    private static func storedServerURL() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: serverURLKey) else { return nil }
        return URL(string: raw)
    }

    private static func setStoredServerURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: serverURLKey)
    }

    private static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }
}

// MARK: - WKNavigationDelegate

extension DashboardViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        lastSuccessfulLoad = Date()
        retryDelay = 2
        hideOverlay()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        showOverlay(text: "Verbindung zu Home Assistant verloren.\nErneuter Versuch …")
        scheduleRetry()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        showOverlay(text: "Home Assistant nicht erreichbar.\nErneuter Versuch …")
        scheduleRetry()
    }
}

// MARK: - WKUIDelegate

extension DashboardViewController: WKUIDelegate {
    // Home Assistant dashboards sometimes open links/cameras in a new window;
    // keep everything inside the single kiosk web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                  for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
