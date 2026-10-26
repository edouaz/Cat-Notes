# Architecture and data

Cat Notes is a SwiftUI app with a UIKit/PencilKit canvas. It targets iOS/iPadOS 16 and uses system frameworks without external packages.

## Follow a change

`CatNotes/App/LibraryStore.swift` owns library state and mutations. The workspace opens notebooks in tabs. `EditorSession` coordinates editing, while `WritingCanvas` and its coordinator bridge SwiftUI and PencilKit. `PageRenderer` renders page content for previews and export. Codable domain models live in `Core`; services implement disk storage, PDF text indexing, diagnostics and experimental cloud sync.

Before editing a shared model or canvas function, search its callers and tests. Keep the existing separation: views describe controls, editor code handles drawing and coordinates, services handle persistence and external I/O.

## Local persistence

Application Support/CatNotes contains `library.json`, `library.backup.json` and `resources/`. Metadata is separate from drawing and imported resources. Writes are atomic; autosave waits approximately 700 ms. Leaving a page requires a successful flush. Pending drawing data must survive a failed write. Corruption produces an error and a recovery option rather than an empty replacement library.

Trash is recoverable; resources are not automatically purged. A `.catnote` file is versioned JSON with base64 resources and regenerated identifiers on import. Imports are limited to 150 MB; large notebooks need memory testing on older iPads. Native backups preserve editable data. PDF export keeps the PDF background vector-based but rasterizes ink at 2×.

## Optional cloud

Local notebooks do not require a backend. [Supabase notes](SUPABASE.md) describe the experimental REST integration, local configuration and SQL policies. It is not production-ready or validated across real devices. Do not advertise reliable synchronization or enable it by default.

## Generated project

`scripts/generate-project.py` collects sources from the app, shared, extension and test directories and writes the Xcode project and shared scheme. Edit the generator when changing build settings; regenerate after adding/removing source files. Bundle identifiers and App Group entitlements must match your signing setup for device builds.

## Validation boundaries

Unit and UI tests cover persistence, import/export, drawing state, geometry and controls. Real hardware is still needed for Pencil latency, palm rejection, pressure, energy, memory, VoiceOver and iOS 16 execution. The deployment target alone does not establish runtime validation on iOS 16.
