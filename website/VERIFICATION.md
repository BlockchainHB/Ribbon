# Website verification

Verified locally on 21–22 October 2026.

- `npm run check`: passed, zero errors, warnings, or hints.
- `npm run build`: passed; static home and 404 pages generated.
- `scripts/verify.sh` from the repository root: passed. Detailed product log: `build/website-product-verification.log`.
- Production preview returned HTTP 200 at `http://127.0.0.1:4321/`.
- In-app Chromium browser: desktop and emulated mobile visual review. Observed CSS widths included 320, 390, 1139, 1147, and 2149 px, without horizontal document overflow. Emulation was cleared after review.
- All six site headings use weight 500; footer background is white. Desktop hides mobile-only controls. Images loaded successfully.
- FAQ summary keyboard activation expands and collapses its answer. Mobile navigation opens and Escape closes it. Copy-link keyboard activation shows confirmation and writes the current page URL to the clipboard.
- No captured browser warnings or errors during the final review.
- Screenshot evidence: `build/qa/website/desktop.jpg` and `build/qa/website/mobile.jpg`.

Initial production output before the label cleanup: 11,224-byte home HTML, 776 bytes of inline JavaScript (402 bytes gzip), no external JavaScript files, 17,284 bytes of CSS, and 116,816 bytes of assets. These are output sizes, not field performance or benchmark scores.

Release downloads and repository links were intentionally not exercised because their public destinations do not exist yet. No deployment, physical-phone check, Safari check, or native-app hardware QA was performed for this website change. Browser screenshots show illustrative window layouts, not live desktop behavior.

Label cleanup, 22 October: removed the hero and closing local-beta labels and the visible layout-illustration caption; renamed all three Download beta controls to Download. Astro check and build passed again. Reloaded preview confirmed the removed labels are absent, all three controls read Download, and no horizontal overflow appears.

Public release preparation, 22 October: download and source links now come from the checked-in root release manifest and GitHub repository. Astro check and build passed after wiring the URLs. Public asset retrieval is verified as part of release publication.


## Agent-first revision — 22 October 2026

- Implemented the approved Paper desktop and mobile agent-first artboards. Scenes cover agent + IDE, multiple agent windows, agent + Paper, and everyday work.
- `npm run check`: passed, 0 errors, warnings and hints. `npm run build`: passed, 2 static pages generated.
- `scripts/verify.sh`: passed, including engine configurations and 26 Swift tests. Log: `build/agent-first-product-verification.log`. No unrestricted engine or desktop window-management QA was started.
- Chromium desktop review at observed 1129 CSS px and mobile review at observed 390 CSS px: no horizontal document overflow. Additional 320 CSS px check: no horizontal overflow.
- All seven page headings retain weight 500; footer is white. Example app icons and display illustration load successfully. Agent overview labels use Codex, Claude, Terminal and Cursor.
- Agent-app FAQ expands and collapses with Enter and explains window management versus session integrations. No browser warnings or errors captured.
- Screenshot evidence: `build/qa/agent-first/desktop.png`, `desktop-hero.png`, and `mobile.png`. Browser device emulation was cleared after review.
- Existing release URLs are preserved; this website change does not replace the native release archive. GitHub Pages is not configured for this repository. The website is verified locally; no public site deployment, physical-phone test, Safari review or native-app hardware test is claimed.

## Product motion — 22 October 2026

- Added separate, once-per-view demonstrations for sliding, paired block reordering, and vertical stacking. Headings, overview, design example, displays, and footer remain still. No new dependencies.
- `npm run check`: passed, 0 errors, warnings, or hints. `npm run build`: passed. `git diff --check`: passed.
- `scripts/verify.sh`: passed; engine configurations and 26 Swift tests passed. Log: `build/website-motion-product-verification.log`. No unrestricted engine or native desktop QA was launched.
- Chromium review at observed CSS widths 320, 390, 767, 1024, and 1440: no horizontal document overflow. The new section retains 40 px mobile padding, 48 px tablet padding, and 80 px desktop padding. Mobile terminal text remains 12 px and fits its tile.
- Inspected six intermediate stacking frames: no browser/terminal intersection, and text transforms retain scale 1 throughout. At completion, a full-height agent sits beside two equal-height tiles, separated by 12 px on desktop and 8 px on mobile. Browser and terminal content fit the completed mobile tiles.
- Inspected paired movement at four timeline positions: both widths stay constant, and the internal gap stays within 0.1 px of its starting value. The pair moves in lockstep; the unrelated window crossfades during crossing.
- Keyboard Enter activates replay. Ten rapid replay requests recover to one sequence without queuing. Offscreen timelines pause without advancing and resume on return. Only one scene runs at a time.
- Live reduced-motion preference change cancels all timelines after the media-query event is delivered; initial reduced motion creates no animations. Replay controls are hidden in this mode. With JavaScript disabled, scenes remain visible and meaningful, including the finished stack; replay controls remain hidden.
- A 390-to-1440 px change during playback cancels motion and settles into valid geometry without page overflow. A 119 px-high viewport still starts one eligible scene. Idle scenes remeasure their initial geometry on width changes.
- No browser warnings or errors captured in the final review. Temporary device metrics, media preferences, and script-execution overrides were cleared.
- Home-page JavaScript bundle: 6043 bytes, 2153 bytes gzip at the recorded build. These are transfer sizes, not a frame-rate benchmark.
- Evidence: `build/qa/website-motion/implementation/verification.json`, `desktop-stacking.png`, `mobile-stacking.png`, and `mobile-static.png`.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM, fixed | `src/styles/scenes.css` stack browser content | The full three-line headline exceeded the shortened tile's content area. | Adjusted padding and line-height so the entire heading fits. | Resizing must preserve readable content. |
| LOW, fixed | `src/styles/scenes.css` mobile stack section | The new desktop section rule overrode mobile spacing. | Explicit mobile padding matches adjacent sections; terminal text stays 12 px. | Preserve the page's established density across breakpoints. |

No actionable UI-polish findings remain in the inspected Chromium states. Safari, physical-phone performance, real background-tab visibility transitions, and 60/120 Hz frame-budget profiling are **not verified**. The in-app browser kept `document.hidden` false when another tab was brought forward, so that action is not counted as a visibility test. Native app behavior and hardware compatibility are unchanged by these website illustrations.


## Unified hero revision — 22 October 2026

- Replaced the three separate animated examples with one nine-second hero story: swipe a column, outline and move the editor/preview as a group, then stack Claude beneath the editor. Lower illustrations remain static. No new dependencies or native-app changes.
- Larger travel distances, readable holds, and a taller stage make each action visible. One keyboard-accessible control supports Pause, Resume, and Replay.
- `npm --prefix website run check`: passed with zero errors, warnings, or hints. `npm --prefix website run build`: passed. `scripts/verify.sh`: passed, including the engine checks and 26 Swift tests; log: `build/hero-story-product-verification.log`.
- Chromium review at observed CSS widths 320, 390, 1025, 1440, and desktop 1756: no horizontal document overflow. Completed editor and Claude content fit their tiles. Device emulation is not physical-device testing.
- Inspected ten desktop frames and six mobile frames across swipe, grouping, and stacking. No visible window intersections; grouped windows preserve their gap (approximately 12 px desktop, 10 px mobile). Claude hides during the mobile group crossing, then enters the vacant lower tile. The final stack shares its left edge and width, beside a full-height preview.
- Enter pauses all eight product timelines without advancing across eight animation frames, then resumes them. Offscreen playback likewise pauses all eight timelines without advancing and resumes on return. Playback completes once, with explicit replay.
- Initial and live reduced-motion checks produce zero animations, a completed stack, and a hidden control. With JavaScript disabled, the static hero remains visible with no control or document overflow. Width changes settle the active sequence into valid final geometry.
- No browser warnings or errors captured. Device metrics, script-execution overrides, and media emulation were cleared; the normal preview was reloaded.
- Evidence: `build/qa/hero-story/verification.json`, `desktop-group.png`, `mobile-group.png`, and `mobile-stack.png`.

Safari, physical phones, real background-tab visibility transitions, and frame-rate profiling remain unverified. The release archive and native window-management behavior are unchanged. This revision is verified in the local production preview; no website deployment is claimed.

## Detailed looping window-management scenes — 22 October 2026

- Replaced generic windows with detailed, static Codex, Claude (spark before reply), Cursor-style IDE, Safari, Terminal and Paper windows. Feature scenes now loop window movement: pair block reorder, overview selection that scrolls the strip, column stacking, and width preset + strip scroll. Feature sections alternate text side and blue/porcelain cards; “Your everyday work, too.” section markup, display rules, and `displays.svg` are byte-identical to `main`.
- Every scene loops with infinite WAAPI animations; only the most visible scene plays. Replay removed; a pause/play toggle remains per scene (WCAG 2.2.2).
- `npm run check`: 0 errors, warnings or hints. `npm run build`: passed, 2 static pages. `git diff --check`: passed.
- Headless Chrome (Playwright with installed Chrome) at 1440×900 and 390×844: no console errors or warnings, no horizontal overflow; frames reviewed at five loop positions per scene, each loop closing on its first frame. Exactly one scene runs at a time; scrolling away pauses it; pause/play toggles state and accessible label; resizing rebuilds geometry and keeps loop position. Reduced motion (emulated): no scene runs, toggles hidden.
- Not performed: Safari/WebKit review (including the known WebKit paused-`currentTime` issue), real phone, 120 Hz compositor profiling, or deployment.

## DataFast analytics — 22 October 2026

- Added the DataFast tracking script to the shared layout `<head>` as `is:inline defer` with the supplied website ID and `data-domain="ribbonwm.com"`. No CSP exists in the site or Vercel project.
- `npm run check`: 0 errors, warnings or hints. `npm run build`: passed. Built `index.html` and `404.html` each contain the tag exactly once, emitted unbundled with `defer`.
- The tracker ignores localhost and automated browsers, so local and headless QA cannot produce dashboard events. Live event delivery must be confirmed from a normal browser visit and the DataFast dashboard.
- Download tracking: all three Download buttons carry `data-fast-goal="download_click"` with `location` and `version` parameters (verified in built HTML). Goal delivery, like pageviews, can only be confirmed from a normal browser and the DataFast dashboard.
