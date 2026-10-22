# Ribbon website

Static Astro implementation of the approved Paper **Medium headings** variant. The download area and footer stay white. Window scenes are layout illustrations, not an embedded window manager.

Design source: [Paper, page 2](https://app.paper.design/file/01M5GQFBZ419QN9EYEE6N9TDS9/p-2-0), desktop `L1-0` and mobile `QV-0`. Assets use Ribbon's approved Cobalt icon and the Paper illustrations.

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

Static output is in `dist/`. No application server, client framework, or third-party service is required.

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

`src/pages/index.astro` owns section order; `src/components/` owns the presentation sections; `src/styles/site.css` owns responsive styling. `src/lib/release.ts` is the single source for release URLs. Native disclosures handle FAQ interactions. Small scripts handle the mobile menu and copy-link action.

See `FRAMEWORK.md` for the researched framework decision and `VERIFICATION.md` for checks and limits.
