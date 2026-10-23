# Ribbon website

Static Astro implementation of the approved Paper **Agent-first / Medium headings** design. The download area and footer stay white. Window scenes are editable illustrations, not an embedded window manager or agent integration.

Design source: [Paper, page 2](https://app.paper.design/file/01M5GQFBZ419QN9EYEE6N9TDS9/p-2-0), artboards **07 · Desktop / Agent-first** and **08 · Mobile / Agent-first**. The earlier artboards are preserved. Assets use Ribbon's approved Cobalt icon and locally extracted example-app icons.

The page leads with agent + IDE, multiple agent windows, and agent + design tool. Everyday work and independent displays follow. The README keeps installation, shortcuts, and beta limitations explicit. Research and copy decisions are recorded in [the copywriting brief](../docs/WEBSITE_COPY.md).

## Local development

Use Node 22.23.4 or newer. Dependencies are pinned and locked.

```sh
cd website
npm ci
npm run dev
```

Production checks and preview:

```sh
npm run check
npm run build
npm run preview -- --port 4321
```

Static output is in `dist/`. No application server or client framework is required.

## Favicon and social preview

- `public/favicon.svg`: the Fold mark traced from `branding/explorations/fold/mark.png` (potrace), cobalt with a lighter dark-mode fill. `favicon.ico` (16/32/48) and `apple-touch-icon.png` (from the approved Icon Composer artwork) are rendered from it.
- `public/social/og.mp4` and `og.jpg`: the 1200×630 link preview. Design source: Paper file "Ribbon", page "03 · Social & favicon". The video is the real hero loop (swipe, pair, stack), stepped frame by frame at 30 fps; the JPG is its poster and the universal `og:image`. `og:video` is also declared for apps that play it.
- Social tags need absolute URLs, so they are emitted only when `PUBLIC_SITE_URL` is set.
- `og:type` is `video.other` with a direct MP4 in `og:video`: Discord requires that for its inline video player, using `og:image` as the frame before playback, so the poster is the loop's first frame. Apple Messages downloads and autoplays a direct MP4 (muted, looping). `twitter:card` stays `summary_large_image`, so X, Slack and LinkedIn show the poster. The brand lives in `og:site_name`, not `og:title` (Apple guidance). Sources: [Discord link previews](https://docs.discord.com/developers/link-previews/overview), [Apple TN3156](https://developer.apple.com/documentation/technotes/tn3156-create-rich-previews-for-messages), [Facebook sharing](https://developers.facebook.com/docs/sharing/webmasters/).

Regenerate after changing the hero or brand (run from `website/`, after `npm run build`):

```sh
npm install --no-save --prefix /tmp/ribbon-render playwright-core@1
PLAYWRIGHT_CORE=/tmp/ribbon-render/node_modules/playwright-core/index.mjs node tools/render-brand-assets.mjs
```

It needs Google Chrome, ffmpeg and ImageMagick.

## Analytics

The shared layout (`src/layouts/Site.astro`) loads the [DataFast](https://datafa.st/docs/astro) tracking script on every page with `is:inline defer`. The website ID and domain are public identifiers; do not change them. DataFast ignores localhost and automated browsers, so development and headless QA send no events. The default script sets first-party `datafast_visitor_id` / `datafast_session_id` cookies. Every Download button records a `download_click` goal with `location` (`header`, `hero`, `download_section`) and `version` (the release tag), set in `src/components/DownloadLink.astro`. The site has no Content-Security-Policy; if one is added, allow `https://datafa.st` in `script-src` and `connect-src`.

## Release destinations

The build accepts optional environment variables:

| Variable | Purpose |
| --- | --- |
| `PUBLIC_SITE_URL` | Canonical public site origin. Without it, pages use `noindex, nofollow`. |
| `PUBLIC_DOWNLOAD_URL` | Real HTTPS release archive. |
| `PUBLIC_REPOSITORY_URL` | Real HTTPS public repository. |
| `PUBLIC_RELEASES_URL` | Real HTTPS release history. |

Download, Source, and Release notes default to the public GitHub repository and the exact release specified in the root `release.json`. The optional variables override those defaults. There are no placeholder setup, source, or release pages. No native archive is copied into this site.

## Structure

`src/pages/index.astro` owns section order; `src/components/` owns the presentation sections and `src/components/apps/` the illustrative app windows (Codex, Claude, Cursor, Safari, Terminal, Paper). `src/styles/site.css` owns page styling, `src/styles/apps.css` the window internals (container queries simplify narrow tiles), and `src/styles/scenes.css` the scene layouts, including their mobile variants. `src/scripts/scene-motion.ts` loops each scene's window movement while it is the most visible one. `src/lib/release.ts` is the single source for release URLs. Native disclosures handle FAQ interactions. Small scripts handle the mobile menu and copy-link action.

See `FRAMEWORK.md` for the researched framework decision and `VERIFICATION.md` for checks and limits.
