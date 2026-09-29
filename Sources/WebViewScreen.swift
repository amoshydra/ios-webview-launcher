import SwiftUI
import WebKit

/// Mirror of the Android `MainActivity`: a fullscreen `WKWebView` that loads
/// the supplied URL and evaluates the supplied JavaScript two seconds after the
/// page finishes loading.
struct WebViewScreen: View {
    let urlText: String
    let jsText: String
    let cachePolicy: CachePolicy
    let edgeToEdge: Bool
    let insetOverride: InsetOverride

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var injectionError: String?

    var body: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(
                url: URL(string: urlText) ?? URL(string: "about:blank")!,
                jsText: jsText,
                cachePolicy: cachePolicy,
                edgeToEdge: edgeToEdge,
                insetOverride: insetOverride,
                isLoading: $isLoading,
                injectionError: $injectionError
            )
            .ignoresSafeArea()

            chrome
        }
        // Mirrors the Android original: immersive by default, status bar visible
        // when edge-to-edge is on so the page still learns about the top inset.
        .statusBarHidden(!edgeToEdge)
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("Close")

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Spacer()

                Text(URL(string: urlText)?.host ?? urlText)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()

            if let injectionError {
                Text(injectionError)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.85))
            }
        }
    }
}

/// Bridges `WKWebView` into SwiftUI.
private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    let jsText: String
    let cachePolicy: CachePolicy
    let edgeToEdge: Bool
    let insetOverride: InsetOverride
    @Binding var isLoading: Bool
    @Binding var injectionError: String?

    #if DEBUG
    /// Identifies this run in the probe report, so multiple runs can be told apart.
    var probeLabel: String {
        let override = insetOverride
        return "edgeToEdge=\(edgeToEdge) top=\(override.top.map(String.init) ?? "-")" +
            " right=\(override.right.map(String.init) ?? "-")" +
            " bottom=\(override.bottom.map(String.init) ?? "-")" +
            " left=\(override.left.map(String.init) ?? "-")"
    }
    #endif

    #if DEBUG
    /// What UIKit reports for this view, so the native and page-side readings can
    /// be compared directly. If these differ, the override never reached `env()`.
    static func nativeInsets(_ webView: WKWebView) -> String {
        let safe = webView.safeAreaInsets
        let window = webView.window?.safeAreaInsets
        func fmt(_ v: UIEdgeInsets) -> String {
            "t:\(Int(v.top)) r:\(Int(v.right)) b:\(Int(v.bottom)) l:\(Int(v.left))"
        }
        let windowStr = window.map(fmt) ?? "no-window"
        return "webview=\(fmt(safe)) window=\(windowStr)"
    }
    #endif

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = InsetOverrideWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Required for env(safe-area-inset-*) to be populated at all. Any other
        // value lets UIKit inset the scroll view, which is what suppresses the
        // page's own safe-area reporting.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Set before the first layout pass so the initial safe-area read already
        // reflects the override, matching the Android original's ordering.
        webView.insetOverride = insetOverride

        context.coordinator.pendingURL = url
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let overridable = webView as? InsetOverrideWebView {
            overridable.insetOverride = insetOverride
        }
        // Re-assert on every update: SwiftUI may hand back a view whose scroll
        // view adjustment was reset by a layout change.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Only load once; SwiftUI calls this on every state change.
        guard let pending = context.coordinator.pendingURL else { return }
        context.coordinator.pendingURL = nil

        var request = URLRequest(url: pending)
        if cachePolicy == .reloadIgnoringLocalCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        var pendingURL: URL?
        private var injectionTask: Task<Void, Never>?

        init(parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            parent.isLoading = true
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            parent.isLoading = false
            scheduleInjection(after: 2, in: webView)
            #if DEBUG
            if ProcessInfo.processInfo.environment["ENV_PROBE"] == "1" {
                let native = WebViewRepresentable.nativeInsets(webView)
                EnvProbe.run(in: webView, label: parent.probeLabel + " | native " + native) { report in
                    EnvProbe.write(report)
                }
            }
            #endif
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.isLoading = false
        }

        /// Reproduces the Android behaviour of waiting two seconds after load
        /// before evaluating the injected script.
        private func scheduleInjection(after seconds: Double, in webView: WKWebView) {
            injectionTask?.cancel()
            let js = parent.jsText
            injectionTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                guard !js.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                webView.evaluateJavaScript(js) { [self] _, error in
                    if let error {
                        self.parent.injectionError = "JS error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
