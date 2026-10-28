# Architecture and data

OpenNotes is a SwiftUI app with a UIKit/PencilKit canvas. It targets iOS/iPadOS 16 and uses system frameworks without external packages.

## Follow a change

`OpenNotes/App/LibraryStore.swift` owns library state and mutations. The workspace opens notebooks in tabs. `EditorSession` coordinates editing, while `WritingCanvas` and its coordinator bridge SwiftUI and PencilKit. `PageRenderer` renders page content for previews and export. Codable domain models live in `Core`; services implement disk storage, PDF text indexing, diagnostics and experimental cloud sync.

Before editing a shared model or canvas function, search its callers and tests. Keep the existing separation: views describe controls, editor code handles drawing and coordinates, services handle persistence and external I/O.

## Writing interaction

The app uses PencilKit for live freehand rendering, committed stroke storage, zoom, and input recognition, with its own toolbar. Freehand strokes are not processed or reassigned at pen-up, even when legacy stabilization preferences exist. This avoids switching from a synthetic preview to a different final stroke. The native ruler keeps its constrained input path. Stroke and partial erasing also use PencilKit; the legacy intelligent mode retains its custom behavior. Partial eraser width is configurable on iOS 16.4 and later.

Draw-and-hold locks a recognized line, rectangle or ellipse after 650 ms. Further movement adjusts the shape; small release jitter cannot restore the raw stroke. Lines keep their first endpoint; closed shapes rotate and scale around their center. The visible stroke enters the existing pending-save path and commits as one undo step. Cancelled native strokes restore the previous drawing.

The live-ink preview is reserved for intentional draw-and-hold shapes and remains visible until PencilKit reports that the replacement drawing has rendered. Ordinary writing does not create that preview or swap to a resting bitmap on PDF pages. PDF export retains its existing compositing rules; on-screen freehand markers use PencilKit throughout the gesture and afterward. Legacy processing helpers remain for compatibility and isolated previews, not the freehand input path.

On iPadOS 17+, pen presets select native monoline, fountain-pen and pen inks. Disabling pressure chooses monoline (a uniform round tip rather than a modified calligraphy nib). The highlighter can use translucent monoline for a round, pressure/tilt-independent stroke. These settings update the active tool immediately and persist in `EditorToolSettings`; earlier OS versions retain the original native tools. New ink types require iPadOS 17+ when reopening the saved drawing. No post-processing is added to freehand input.

Selection movement caches the page without selected content and a transparent image of the selected ink/elements at pickup. Drag updates translate only the foreground image. `SelectionMoveSnapshot` shares hit-testing and page-edge constraints with the final edit. Cancellation discards the preview without changing the drawing; release commits one undoable edit. The ink preview stays until PencilKit has rendered the replacement. Whole-stroke eraser contact and Pencil hover display a cursor without consuming PencilKit’s erasing gesture.

Alternatives reviewed: [MaLiang](https://github.com/Harley-xk/MaLiang) (MIT, Metal drawing engine) and [HandDrawingSwiftMetal](https://github.com/eisukekusachi/HandDrawingSwiftMetal). Neither is added: replacing the document engine would expand migration, erasing and export work. Apple's [PKStroke API](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct) supports constructing editable strokes from our processed samples while retaining existing documents. No third-party source was copied.

Physical Pencil latency, pressure calibration and long-stroke performance still require device testing; simulator interaction tests cannot establish those properties.

## Local persistence

For update compatibility, the on-disk directory keeps its previous name: Application Support/CatNotes contains `library.json`, `library.backup.json` and `resources/`. Metadata is separate from drawing and imported resources. Writes are atomic; autosave waits approximately 700 ms. Leaving a page requires a successful flush. Pending drawing data must survive a failed write. Corruption produces an error and a recovery option rather than an empty replacement library.

Trash is recoverable; resources are not automatically purged. A `.catnote` file is versioned JSON with base64 resources and regenerated identifiers on import. Imports are limited to 150 MB; large notebooks need memory testing on older iPads. Native backups preserve editable data. PDF export keeps the PDF background vector-based but rasterizes ink at 2×.

## Optional cloud

Local notebooks do not require a backend. [Supabase notes](SUPABASE.md) describe the experimental REST integration, local configuration and SQL policies. It is not production-ready or validated across real devices. Do not advertise reliable synchronization or enable it by default.

## Generated project

`scripts/generate-project.py` collects sources from the app, shared, extension and test directories and writes the Xcode project and shared scheme. Edit the generator when changing build settings; regenerate after adding/removing source files. Bundle identifiers and App Group entitlements must match your signing setup for device builds.

## Validation boundaries

Unit and UI tests cover persistence, import/export, drawing state, geometry and controls. Real hardware is still needed for Pencil latency, palm rejection, pressure, energy, memory, VoiceOver and iOS 16 execution. The deployment target alone does not establish runtime validation on iOS 16.

## Rebrand compatibility identifiers

The product, Xcode project, module and source directories are OpenNotes. A small set of stable identifiers intentionally retains its legacy spelling:

- App and extension bundle identifiers: `fr.catnotes.app` and `fr.catnotes.app.share`.
- Shared import App Group: `group.fr.catnotes.app`.
- Existing Application Support directory: `CatNotes`.
- Keychain service: `fr.catnotes.auth`.
- Native document type/extension and clipboard interoperability identifiers.

These are compatibility keys, not displayed branding. Keep them stable when shipping an update to an existing installation. New signing configurations must be consistent across the app, extension, entitlements and developer account.
