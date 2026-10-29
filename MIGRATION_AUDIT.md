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

## Delivery status

- `f86396b`: existing editor/UI work preserved before migration.
- `d63f466`: native model, schema validation, shared renderer and model tests.
- `528fc69`: native capture, geometry/gestures, editor, clipboard, storage and export integration; removed PencilKit observer/preview paths.
- `11590c5`: pen-only gesture arbitration and popover UI test.
- `0635437`: sparse tapered-line rendering correction and regression coverage.
- **PASS:** final 150 XCTest + 7 Swift Testing tests; actual finger-writing/Undo/Redo/options/process-reopen UI smoke test; unsigned Release archive and IPA integrity checks.
- Final IPA: `build/artifacts/OpenNotes-ios16-native-ink-build10-unsigned.ipa`; checksum/provenance: `docs/native-ink-build10-package.json`.
- Final evidence, exact commands, synthetic performance numbers and remaining physical checks: [validation report](docs/INK_VALIDATION.md).

The initial baseline build overlapped implementation and is not independent baseline verification. Final migration builds/tests provide delivery evidence. Old-note conversion was waived; physical iPad/Pencil calibration and the recorded simulator keyboard incident remain validation limits. Implementation and local packaging are complete.
