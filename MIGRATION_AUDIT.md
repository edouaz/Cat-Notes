# Native ink migration — 2026-10-29

Branch: `codex/custom-ink-engine`. Baseline user edits saved in `f86396b`.
User scope: iOS/iPadOS 16.0+, unsigned IPA; no legacy-note conversion or legacy corpus required. Existing PencilKit resources must fail explicitly rather than appear as empty successful pages. No destructive automatic library reset.

| Existing files | Role | Decision |
|---|---|---|
| Editor/WritingCanvas.swift, CanvasTouchObserver.swift | PencilKit input, scroll, held previews | Replace capture; retain page viewport/navigation |
| Editor/EditorSession.swift, EditorSelection.swift | Autosave, undo, selection | Adapt to native immutable drawing snapshots |
| Editor/StrokeProcessing.swift, ShapeRecognition.swift, EraserEditing.swift | Geometry and gestures | Reuse and adapt |
| Editor/PageRenderer.swift, TiledPaperView.swift, InkPreview.swift | PDF, tiles, tool previews | Share native renderer |
| Editor/PreparedPage.swift, Services/NotebookArchive.swift, DocumentContext.swift | Decode/export | Native versioned JSON, explicit invalid-format errors |
| App/LibraryStore.swift | New pages and archive import | Native empty drawing and native validation |
| Core/EditorToolSettings.swift, EditorInstrumentOptions.swift | Preferences/UI | Add sharpness and patterns to existing options |
| scripts/generate-project.py, package-ipa.py | Project and IPA | Reuse, preserve app identifiers, build unsigned arm64 |

Integration: native InkDrawing snapshots remain the single document value; EditorSession replacement is the shared undoable mutation; logical page units remain independent of viewport zoom. Raw samples and frozen stroke settings are persisted; predictions and hover remain transient.

No migration flag or legacy importer: explicitly waived by user. Prior `.catnote` ink is unsupported in this build. Physical Pencil/hover/latency and Goodnotes equivalence cannot be certified by simulator tests.

## Progress
- `f86396b`: existing editor/UI work preserved before migration.
- `d63f466`: native model, schema validation, shared renderer and model tests.
- Input, editor, geometry/gesture, clipboard, export and storage integration implemented. Removed PencilKit imports/types and the old observer/preview handoff.
- First full simulator run: 148 XCTest cases + Swift Testing suites; two viewport assertions and one obsolete highlighter expectation failed. Native model/input/gesture/persistence suites passed. Viewport reset and expectation corrected.
- Final unit/UI run and unsigned Release archive in progress. Logs: `/tmp/catnotes-native-final-tests.log`, `/tmp/catnotes-native-archive.log`.
- Next: inspect final results/screenshots, package archive, verify arm64/minOS/no PencilKit dependency, write checksum, commit and publish branch/PR.

The initial baseline build overlapped native implementation and is not an independent baseline verification. Final migration builds/tests are the delivery evidence. Physical iPad calibration remains pending.
