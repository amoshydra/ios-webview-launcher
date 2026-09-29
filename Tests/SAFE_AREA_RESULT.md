# Safe-area override: measured result

**Verdict: the `InsetOverrideWebView` override DOES reach `env()` on iOS.**

Measured on iPhone 17 Pro simulator, iOS 27.0 (24A434), Xcode 27.0, with the
`ENV_PROBE=1` harness, against a page served over HTTP declaring
`<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`.

## Method

`env()` has no JavaScript API, so the only way to observe what a page sees is to
resolve it through a hidden probe element and read the computed value.

Critically, the probe **samples repeatedly over ~6s and records every distinct
reading**, rather than reading once. This is not optional: see "Why the first
measurement was wrong" below.

Two validity guards:

- `env(safe-area-inset-top, 0px)` and `env(safe-area-inset-top, 77px)` are both
  read. If the second returned `77px`, `env()` would be unsupported and every
  other result meaningless. It returns `0px`, so `env()` is genuinely supported
  and genuinely resolving to a real value.
- The native reading is captured alongside the page reading
  (`webView.safeAreaInsets` vs. what the page computes), so the two can be
  compared directly.

## Results

Overrides applied: `top=150 right=40 bottom=180 left=40`. Real system insets on
these simulators are `62 / 0 / 34 / 0`.

| Runtime | Device | Overrides | Blank (real values) |
|---|---|---|---|
| 18.6 | iPhone 16 Pro | `150/40/180/40` ✓ | `62/0/34/0` ✓ |
| 26.5 | iPhone 17 Pro | `150/40/180/40` ✓ | — |
| 27.0 | iPhone 17 Pro | `111/44/222/33` ✓ | `62/0/34/0` ✓ |
| 27.0 | iPhone 18 Pro | `111/44/222/33` ✓ | `62/0/34/0` ✓ |
| 27.1 | iPhone Duo | `150/40/180/40` ✓ | — |

Per-edge independence was verified separately on 27.0: with only `top=111` set,
`env()` reported `111px / 0px / 34px / 0px` — the other three edges fell through
to their genuine system values.

**Blank fields fall through to real system values.** With no override,
`env()` reports `62px` top, matching `window.safeAreaInsets.top == 62` exactly.
So the pipeline reads genuine safe-area data, and the override substitutes
cleanly for it rather than fabricating values.

**Visual confirmation.** On
`https://amoshydra.github.io/demo-viewport/?fit=cover` — a page not written as
part of this test, so it rules out a self-confirming fixture — the page's own
`INSETS T R B L` readout shows `150 40 180 40`, and it draws
`top 150px` / `left 40px` / `right 40px` / `bottom 180px` overlays at the
overridden positions, with `100dvh` reduced to 678 to make room.

### Samples needed before the override is visible

Varies by configuration, which is why a single early read is unreliable:

| Runtime / device | Distinct readings |
|---|---|
| 18.6 iPhone 16 Pro | 2 (zero, then override) |
| 26.5 iPhone 17 Pro | 1 (override immediately) |
| 27.0 iPhone 17 Pro / 18 Pro | 2 (zero, then override) |
| 27.1 iPhone Duo | 1 (override immediately) |

## Why the first measurement was wrong

The initial test read `env()` once, on `WKNavigationDelegate.didFinish`, and
concluded the override did nothing. That was a false negative, for two reasons:

1. **WebKit bug 191872**: `env(safe-area-inset-*)` is zero on first load and only
   becomes correct "at some arbitrary time after the web view is initialized".
   `didFinish` lands inside exactly that window, so a single early read is
   guaranteed to see zeros. Reconfirmed in the time series: every run shows
   reading `[0]` as all-zeros, then a later reading with real values.

2. **The simulator reports no insets to the *window* by default in that path**,
   which made an all-zero baseline look plausible rather than suspicious. The
   native capture shows `window=t:62` — non-zero after all.

A single-shot read of a value WebKit documents as non-deterministically-timed
proves nothing. The fix was to sample and record the history.

Note that a page reading `env()` exactly once at load can observe the stale
all-zeros value, and only later recomputations see the override. That is a WebKit
behaviour pages must already cope with, not something this app can hide — the
Android original has the same property.

## Conclusion

The feature ports 1:1. Overriding `safeAreaInsets` on a `WKWebView` subclass does
feed `env()`, with no CSS injection and no document mutation, and works for pages
calling `env()` directly.

Required conditions, both already implemented:

- `scrollView.contentInsetAdjustmentBehavior == .never`, otherwise UIKit insets
  the scroll view and suppresses the page's safe-area reporting entirely.
- The document must declare `viewport-fit=cover`. This is the one remaining gap
  versus Android, whose WebView populates the values from `WindowInsets` with no
  opt-in.
