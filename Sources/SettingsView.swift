import SwiftUI

/// Mirror of the Android `SettingsActivity`: collects a URL and a snippet of
/// JavaScript, then presents the fullscreen web view.
struct SettingsView: View {
    @AppStorage("url") private var urlText: String = "https://example.com"
    @AppStorage("js") private var jsText: String = "alert('Hello!');"
    @AppStorage("cachePolicy") private var cachePolicyRaw: String = CachePolicy.standard.rawValue
    @AppStorage("edgeToEdge") private var edgeToEdge: Bool = false
    @AppStorage("insetTop") private var insetTop: String = ""
    @AppStorage("insetRight") private var insetRight: String = ""
    @AppStorage("insetBottom") private var insetBottom: String = ""
    @AppStorage("insetLeft") private var insetLeft: String = ""

    @State private var isPresentingWebView = false
    @State private var validationError: String?
    @State private var didAutoLaunch = false

    private var cachePolicy: CachePolicy {
        CachePolicy(rawValue: cachePolicyRaw) ?? .standard
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("URL") {
                    TextField("https://example.com", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    TextEditor(text: $jsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("JavaScript")
                } footer: {
                    Text("Injected 2 seconds after the page finishes loading.")
                }

                Section("Cache") {
                    Picker("Policy", selection: cachePolicyBinding) {
                        ForEach(CachePolicy.allCases) { policy in
                            Text(policy.title).tag(policy.rawValue)
                        }
                    }
                }

                Section {
                    Toggle("Edge to edge", isOn: $edgeToEdge)
                } footer: {
                    Text("Keeps the status bar visible but transparent, so the page can extend underneath it and still see real safe-area insets.")
                }

                Section {
                    insetField("Top", text: $insetTop)
                    insetField("Right", text: $insetRight)
                    insetField("Bottom", text: $insetBottom)
                    insetField("Left", text: $insetLeft)
                } header: {
                    Text("Safe area inset override")
                } footer: {
                    Text(insetFooter)
                }

                Section {
                    Button {
                        launch()
                    } label: {
                        Text("Launch WebView")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("WebView Launcher")
            .fullScreenCover(isPresented: $isPresentingWebView) {
                WebViewScreen(
                    urlText: urlText,
                    jsText: jsText,
                    cachePolicy: cachePolicy,
                    edgeToEdge: edgeToEdge,
                    insetOverride: insetOverride
                )
            }
            .alert(
                "Invalid URL",
                isPresented: Binding(
                    get: { validationError != nil },
                    set: { if !$0 { validationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { validationError = nil }
            } message: {
                Text(validationError ?? "")
            }
            .onAppear {
                #if DEBUG
                // Lets the headless harness reach the web view without tap
                // injection, which this simulator install does not support.
                if ProcessInfo.processInfo.environment["ENV_PROBE"] == "1", !didAutoLaunch {
                    didAutoLaunch = true
                    isPresentingWebView = true
                }
                #endif
            }
        }
    }

    private var cachePolicyBinding: Binding<String> {
        Binding(
            get: { cachePolicyRaw },
            set: { cachePolicyRaw = $0 }
        )
    }

    private var insetOverride: InsetOverride {
        InsetOverride.parseEdges(
            top: insetTop,
            right: insetRight,
            bottom: insetBottom,
            left: insetLeft
        )
    }

    private func insetField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .disabled(!edgeToEdge)
    }

    /// Mirrors the Android hint, which explains both the edge-to-edge dependency
    /// and the WebKit `viewport-fit=cover` difference.
    private var insetFooter: String {
        guard edgeToEdge else {
            return "Only applies while Edge to edge is on."
        }
        return "Blank leaves that edge at the real system value. Values are in points and are not clamped.\n\nNote: unlike Android, WebKit reports env(safe-area-inset-*) as 0 unless the page sets viewport-fit=cover in its viewport meta tag."
    }

    private func launch() {
        var candidate = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            validationError = "Enter a URL to load."
            return
        }
        // Match the Android app, which also accepted scheme-less input.
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else {
            validationError = "Enter a valid http:// or https:// address."
            return
        }
        validationError = nil
        isPresentingWebView = true
    }
}

/// The subset of cache modes the Android launcher exposes.
enum CachePolicy: String, CaseIterable, Identifiable {
    case standard
    case reloadIgnoringLocalCache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .reloadIgnoringLocalCache: return "Ignore local cache"
        }
    }
}
