# OpenNotes

<img src="docs/assets/icon-light.png" width="96" height="96" alt="OpenNotes smiling notebook icon">

### A friendly place for your ideas.

A native, open-source notebook for iPad and iPhone, built with SwiftUI, UIKit, Core Graphics and PDFKit. Write by hand, annotate PDFs and keep your notebooks on your device. No account or external package is needed for local use.

**Current source · 0.1.0 / build 11 · iOS & iPadOS 16+**

The latest public download is prototype build 11.

Build 11 integrates the redesigned library/editor, vector precision erasing, lasso transformations and mixed clipboard, and editable rich-text sticky notes. Unsigned artifact validation and remaining differences are recorded in [IMPLEMENTATION_REPORT.md](IMPLEMENTATION_REPORT.md). Ink schema 1 remains readable; new writes use schema 2 and preserve original schema-1 resources in `ink-schema-backups` before rewriting. Existing PencilKit incompatibility from build 10 still applies.

[Explore the website](https://edouaz.github.io/OpenNotes/) · [Download the IPA](https://github.com/edouaz/OpenNotes/releases/download/v0.1.0-prototype.11/OpenNotes-ipados16-goodnotes-build11-unsigned.ipa) · [Installation & development](https://edouaz.github.io/OpenNotes/develop.html) · [Contribute](CONTRIBUTING.md)

![OpenNotes build 11 editor on iPad](docs/assets/goodnotes-build11/editor-reopened.png)

## Current source experience

The app has a redesigned notebook library with grid/list views and tabs for keeping several notebooks open. Open notebooks and the active tab are restored on launch.

- Apple Pencil writing with pen, highlighter, eraser and lasso, plus undo and redo.
- Tap the selected tool for color, width, ballpoint/fountain/brush profiles, stabilization, sharpness and solid/dashed/dotted patterns on iPadOS 16+.
- Move selected ink and attachments with a live preview. Whole-stroke erasing shows a tip cursor, including Pencil hover on supported iPads.
- Add pages directly; browse and reorder pages from the page counter.
- Paper templates, search, PDF export and native `.catnote` backups in the notebook menu.
- PDF import, folders, favorites and recoverable Trash in the library menu.
- Rich-text sticky notes with colors, collapse, locking and attached content.
- Precision, Standard and Stroke erasing, mixed-object clipboard and lasso scale/rotation.
- Existing native ink remains readable. Local storage, autosave and explicit save errors are retained.

Writing now uses the application's native ink engine. Raw Pencil samples, frozen styles and editable geometry are saved in versioned JSON. Predicted input and hover remain temporary. Standard erasing creates independent editable fragments; Precision preserves a clipped vector silhouette; draw-and-hold and circle-then-long-press use the existing editor selection and undo system.

**Build 10 changes the ink format. Old PencilKit pages are unsupported and produce an explicit error.** Create a new notebook for this build. No automatic conversion or deletion is performed. See [migration audit](MIGRATION_AUDIT.md) and [validation report](docs/INK_VALIDATION.md).
Build 11 reads native ink schema 1/2 and writes schema 2, backing up original schema-1 resources before their first overwrite. Read the [release notes](docs/RELEASE.md) before upgrading from build 9.

| Your library | Tune your pen |
| --- | --- |
| ![Notebook library, build 11](docs/assets/goodnotes-build11/library-list.png) | ![Pen options, build 11](docs/assets/goodnotes-build11/pen-options.png) |

Screenshots are real simulator captures. The images above show OpenNotes build 11. [Capture provenance](docs/SCREENSHOTS.md).

## Install the prototype

[Download build 11](https://github.com/edouaz/OpenNotes/releases/download/v0.1.0-prototype.11/OpenNotes-ipados16-goodnotes-build11-unsigned.ipa). **The IPA is unsigned**: opening it on an iPhone or iPad does not install it. Sign it using your own provisioning setup, or run the source in Xcode. The app and share extension need matching App Group entitlements. See the [installation guide](https://edouaz.github.io/OpenNotes/develop.html#install).

OpenNotes keeps the existing bundle identifiers, App Group, Keychain service and local data directory so an update can access earlier notes. Sign with the same team and identifiers and export a native backup before upgrading. Do not uninstall first. [Compatibility details](docs/ARCHITECTURE.md#rebrand-compatibility-identifiers).

This is an early prototype, far from a final release. Export backups before using valuable notes. Physical Apple Pencil performance, older iPad hardware, accessibility and cloud synchronization are not fully validated. Supabase is experimental and optional; local use works without it.

## Run from source

You need macOS, Xcode with an iOS simulator runtime, and Python 3 only when regenerating the project. No CocoaPods, Swift packages or backend setup.

```sh
git clone https://github.com/edouaz/OpenNotes.git
cd OpenNotes
open OpenNotes.xcodeproj
```

Select the **OpenNotes** scheme and an installed iPad or iPhone simulator, then Run. On hardware, select your signing team for both targets and configure matching bundle identifiers and App Groups. [Full developer guide](https://edouaz.github.io/OpenNotes/develop.html#development).

```sh
# After adding/removing Swift files; the project generator is the source of truth.
python3 scripts/generate-project.py

# Replace the destination with a simulator listed by xcodebuild -showdestinations.
xcodebuild -project OpenNotes.xcodeproj -scheme OpenNotes \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

## Find your way around

| Path | Responsibility |
| --- | --- |
| `OpenNotes/App/` | Library, workspace and shared visual style |
| `OpenNotes/Core/` | Codable models, paper and tool settings |
| `OpenNotes/Editor/` | Native ink capture, geometry, rendering, gestures and editing |
| `OpenNotes/Services/` | Persistence, PDF indexing, diagnostics and optional sync |
| `Shared/`, `ShareExtension/` | App Group inbox and iOS share extension |
| `OpenNotesTests/`, `OpenNotesUITests/` | Domain, storage, rendering and interaction tests |
| `Config/`, `scripts/` | Plists, entitlements, project generator and packaging |
| `docs/` | GitHub Pages, architecture and release information |

[Architecture & data](docs/ARCHITECTURE.md) · [Prototype release notes](docs/RELEASE.md) · [Security reporting](SECURITY.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

## License

MIT. Portions derived from [Signotes](https://github.com/SignoCreator/signotes) retain their original MIT notice. See [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md).
