import SwiftUI
import WebKit

/// A `WKWebView` whose reported safe-area insets can be overridden per edge.
///
/// This is the iOS counterpart to the Android app's `InsetAwareWebView`.
///
/// WebKit derives the page's `env(safe-area-inset-*)` from the receiving view's
/// `safeAreaInsets`, so overriding that getter is what makes the page observe the
/// overridden values. No CSS is injected and the document is never mutated, so
/// pages that read `env()` directly see the override rather than a doubled-up
/// result.
///
/// Scope: the override reaches `env()` only, and only for documents that declare
/// `viewport-fit=cover` in their viewport meta tag. WebKit reports `0` for every
/// `env(safe-area-inset-*)` otherwise, and no native change can alter that.
final class InsetOverrideWebView: WKWebView {
    /// Per-edge overrides in points. `nil` leaves that edge at the real system value.
    /// Values are intentionally not clamped, matching the Android original: a value
    /// larger than the real inset pushes page content further in.
    var insetOverride = InsetOverride() {
        didSet {
            guard insetOverride != oldValue else { return }
            // UIKit memoises safe-area geometry per layout pass, so the override is
            // only re-read once something invalidates that cache.
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    override var safeAreaInsets: UIEdgeInsets {
        let base = super.safeAreaInsets
        return insetOverride.applying(to: base)
    }
}

/// Per-edge safe-area overrides. `nil` means "leave this edge alone".
struct InsetOverride: Equatable {
    var top: CGFloat?
    var right: CGFloat?
    var bottom: CGFloat?
    var left: CGFloat?

    static let none = InsetOverride()

    /// True when no edge is overridden, i.e. the page sees real system values.
    var isEmpty: Bool {
        top == nil && right == nil && bottom == nil && left == nil
    }

    func applying(to base: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top ?? base.top,
            left: left ?? base.left,
            bottom: bottom ?? base.bottom,
            right: right ?? base.right
        )
    }

    /// Mirrors the Android sentinel: an empty field means "use the real system
    /// value", and a non-numeric field is treated the same way rather than
    /// silently becoming `0`.
    static func parseEdges(
        top: String,
        right: String,
        bottom: String,
        left: String
    ) -> InsetOverride {
        InsetOverride(
            top: parse(top),
            right: parse(right),
            bottom: parse(bottom),
            left: parse(left)
        )
    }

    private static func parse(_ raw: String) -> CGFloat? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
        return CGFloat(value)
    }
}
