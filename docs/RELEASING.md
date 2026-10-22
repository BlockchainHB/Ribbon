# Releasing Ribbon

`release.json` is the source for the app version, build number, Git tag, and downloadable archive name. The website imports it for the exact asset URL; beta releases do not rely on GitHub's stable-only `releases/latest` redirect.

## Requirements

- Apple silicon Mac with Xcode 26 or later, Python 3, and the pinned Rust toolchain.
- Installed **Developer ID Application** certificate with its private key.
- Apple notarization credentials stored in a Keychain profile. Create them interactively using `xcrun notarytool store-credentials Ribbon`; do not put credentials in source, environment files, or shell history.

## Prepare

1. Update `release.json`, release notes, and any versioned README links.
2. Run `scripts/verify.sh`. Run `npm ci`, `npm run check`, and `npm run build` in `website/`.
3. Record physical desktop QA separately. Automated engine tests do not establish desktop compatibility.
4. Commit the exact source for the release.
5. Run `scripts/prepare-release.sh Ribbon`.

The script builds the app, enables Hardened Runtime, timestamps signatures, submits to Apple, waits for acceptance, staples and validates the ticket, checks Gatekeeper, and creates a final ZIP with checksums and source-commit provenance. It stops before publication. It does not install or launch window management.

Artifacts are in `build/releases/<tag>/`. Publish only the named release ZIP, `SHA256SUMS.txt`, and `release-manifest.json`; the notarization upload and local receipts remain private. Never upload a debug build or change the bytes of an existing release asset. Increment the release for a replacement.

## Publish

Create the matching Git tag at the recorded source commit and a GitHub release using the reviewed release notes. Mark early releases as prereleases. Upload the three verified artifacts. Verify their public download URLs and checksums before announcing availability.

Keep signing keys and notarization credentials in Keychain. CI checks source and website builds; it does not receive signing credentials or publish releases.
