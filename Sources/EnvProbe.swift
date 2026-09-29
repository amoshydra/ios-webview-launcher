import Foundation
import WebKit

/// DEBUG-only harness that measures what a loaded page actually observes for
/// `env(safe-area-inset-*)` and writes the result to a file the test can read.
///
/// This exists because the safe-area override cannot be verified by reading the
/// Swift code: whether an overridden `safeAreaInsets` reaches `env()` is a
/// WebKit runtime behaviour, so the only honest check is to read the value back
/// out of the page. Excluded from release builds.
enum EnvProbe {
    /// Resolved by injecting a probe element, because `env()` has no JS API —
    /// this is the only way to observe what the page sees.
    private static let readEnv = """
    (function () {
      var p = document.createElement('div');
      p.style.cssText = 'position:fixed;top:0;left:0;visibility:hidden;' +
        'padding-top:env(safe-area-inset-top,0px);' +
        'padding-right:env(safe-area-inset-right,0px);' +
        'padding-bottom:env(safe-area-inset-bottom,0px);' +
        'padding-left:env(safe-area-inset-left,0px);';
      document.body.appendChild(p);
      var cs = getComputedStyle(p);
      var r = {
        top: cs.paddingTop, right: cs.paddingRight,
        bottom: cs.paddingBottom, left: cs.paddingLeft
      };
      p.remove();
      return JSON.stringify(r);
    })();
    """

    /// Verifies `viewport-fit=cover` is actually present, since without it WebKit
    /// reports 0 for every edge and the result would be meaningless.
    private static let readViewportFit = """
    (function () {
      var m = document.querySelector('meta[name=viewport]');
      return m ? (m.content || '') : 'NO_META_TAG';
    })();
    """

    /// Samples `env()` repeatedly over time.
    ///
    /// WebKit bug 191872 documents that `env(safe-area-inset-*)` is zero on
    /// first load and only becomes correct at an arbitrary later point. A single
    /// reading at `didFinish` therefore proves nothing, so sample a window and
    /// report every distinct reading plus the settled value.
    static func run(
        in webView: WKWebView,
        label: String,
        samples: Int = 12,
        interval: Double = 0.5,
        completion: @escaping (String) -> Void
    ) {
        var readings: [String] = []
        var settled: String?

        func sample(_ index: Int) {
            webView.evaluateJavaScript(readEnv) { result, error in
                let value = (result as? String)
                    ?? "ERROR: \(error?.localizedDescription ?? "nil")"
                if readings.last != value { readings.append(value) }
                if settled == nil { settled = value }

                if index + 1 < samples {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + interval
                    ) { sample(index + 1) }
                } else {
                    let history = readings.enumerated()
                        .map { "  [\($0.offset)] \($0.element)" }
                        .joined(separator: "\n")
                    completion("""
                    label=\(label)
                    settled=\(settled ?? "nil")
                    distinctReadings=\(readings.count)
                    history:
                    \(history)
                    """)
                }
            }
        }

        sample(0)
    }

    /// Single-shot reading, retained for quick checks.
    static func runOnce(in webView: WKWebView, label: String, completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript(readEnv) { envResult, envError in
            let env = (envResult as? String) ?? "ERROR: \(envError?.localizedDescription ?? "nil")"
            webView.evaluateJavaScript(readViewportFit) { fitResult, _ in
                let fit = (fitResult as? String) ?? "unknown"
                let report = """
                label=\(label)
                env=\(env)
                viewport=\(fit)
                """
                completion(report)
            }
        }
    }

    /// Writes a report next to the app's Documents directory, where the harness
    /// can read it without needing UI automation.
    static func write(_ report: String, to name: String = "env-probe.txt") {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        let url = docs.appendingPathComponent(name)
        // Append so a sequence of probes accumulates in one file.
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stamped = "---- \(label(for: name)) ----\n\(report)\n"
        try? (existing + stamped).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func label(for name: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(name) @ \(fmt.string(from: Date()))"
    }
}
