# Screenshot provenance

Current public screenshots show real OpenNotes build 11 views, not generated UI mockups. All notebook content is synthetic test data.

- `assets/goodnotes-build11/library-list.png`: `GoodnotesUIIntegrationTests/testCreationReadOnlyPaletteAndLibraryList`, creation, read-only, sticky placement, actual list layout with row-width assertion.
- `assets/goodnotes-build11/editor-reopened.png`: `NativeInkInteractionUITests/testFingerInkUndoRedoAndReopen`, actual finger ink retained after process relaunch.
- `assets/goodnotes-build11/pen-options.png`: reachable native pen options from the same successful UI test.
- Device: iPad Pro 13-inch (M5), iOS 27.0 simulator, 2064 × 2752 pixels. Exported attachment metadata: `assets/goodnotes-build11/manifest.json`.

## Historical build 9 screenshots

The earlier captures below are retained for provenance and are not the current UI.

- `assets/editor.png`: successful `CustomEditorExperienceTests/testCustomToolbarPreviewAndWidthSettingWithoutNativePalette`, iPad Pro 13-inch (M5), iOS 27.0, 2064 × 2752 pixels.
- `assets/pen-preview.png`: instrument settings and stroke preview from the same successful UI test.
- `assets/library.png`: successful `LibraryLayoutTests/testMixedLibraryVisualMatrix`, the app's actual SwiftUI library hosted at a 744 × 1133-point portrait window, rendered at 2× on the iPad simulator. It includes synthetic folders, notebook titles and dates.

App icon and mascot artwork are generated brand illustrations, not screenshots or evidence of app behavior. [Identity and icon exports](BRAND.md).

Earlier test evidence and planning drafts remain in `.local-archive/`, excluded from the public repository. The public repository keeps a curated set of images instead of repeated test attachments.
