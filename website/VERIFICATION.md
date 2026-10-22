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
