# 0.1.0 — prototype build 8

**Early public prototype, far from a final release.** iPhone/iPad, iOS/iPadOS 16+. Published from the existing build of 26 October 2026; publication cleanup changes documentation and repository setup, not app code.

[Download the unsigned IPA](https://github.com/edouaz/Cat-Notes/releases/download/v0.1.0-prototype.8/CatNotes-ios16-build8-unsigned.ipa) · [Installation](https://edouaz.github.io/Cat-Notes/develop.html#install)

## Build 8

- Custom instrument bar with compact layout and real ink/eraser previews.
- Stable paper and ink colors between light and dark appearance.
- Double tap alternates fitting the page width and height after manual zoom.
- PencilKit remains the drawing engine; the native palette preference is removed.

## Installation and limits

The IPA is **unsigned**, arm64, iPhoneOS, with app and extension build number 8. It needs signing and provisioning before installation. There is no App Store or TestFlight distribution. Installation of this unsigned artifact after signing has not been verified.

Prefer building in Xcode using your own team. For upgrades, retain the same bundle identifiers, signing identity and App Group; export a native backup first. Do not uninstall your existing app before backing up.

Physical Pencil performance, older devices, accessibility and cloud synchronization remain unvalidated. The app is not ready to be the only copy of important notes.

## Artifact integrity

SHA-256:

```text
989d3a1d6af6f331bbabdd7d564be3b91862d3d035ce060f05cf30460d67cb0c
```

The ZIP integrity, app/extension versions, deployment target and absence of embedded provisioning were checked before publication. [Build manifest](build8-package.json).
