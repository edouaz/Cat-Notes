# OpenNotes 0.1.0 — prototype build 9

**Early public prototype, far from a final release.** Native iPhone/iPad app, iOS/iPadOS 16+.

[Download the unsigned IPA](https://github.com/edouaz/OpenNotes/releases/download/v0.1.0-prototype.9/OpenNotes-ios16-build9-unsigned.ipa) · [Installation](https://edouaz.github.io/OpenNotes/develop.html#install)

## What changes in build 9

- OpenNotes identity across the app, Xcode project, modules, source folders, repository and documentation.
- A smiling notebook app icon and mascot, with light, dark and tinted icon artwork.
- English interface, errors, accessibility labels, documentation and developer-facing text.
- A blue accent that works in light and dark appearances.
- A redesigned website with automatic system appearance and a saved manual light/dark override.

The existing editing tools, notebook formats and save behavior remain in place. This is a rebrand and presentation update, not a claim of production readiness.

## Upgrade compatibility

The app deliberately retains its earlier bundle identifiers, App Group, Keychain service, local data directory and `.catnote` format. Changing those identifiers during a rebrand would make an existing installation's notes or session inaccessible.

Export a native backup first. Install the signed update over the previous app using the **same team, bundle identifiers and App Group**. Do not uninstall the previous app before backing up. Changing signing identifiers can prevent access to the original data. An in-place upgrade on physical hardware has not been verified.

## Installation and limits

The IPA is **unsigned**, arm64, iPhoneOS, with app and share extension build number 9. It needs signing and provisioning before installation. There is no App Store or TestFlight distribution. Installation of this artifact after re-signing has not been verified.

Physical Pencil performance, older devices, accessibility and live cloud synchronization remain incompletely validated. OpenNotes should not be the only copy of important notes.

## Artifact integrity

The published [build manifest](build9-package.json) records the SHA-256 checksum, byte size, platform, architecture and deployment target. The release also includes the manifest as a downloadable asset.

Build 8 is historical. Its previous manifest remains in the source history for traceability; use the build 9 download above for OpenNotes.
