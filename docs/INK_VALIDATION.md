# Native ink build 10 — validation

Target: iOS/iPadOS 16.0+. Xcode 27.1. Simulator runtime iOS 27.0.
Scope: the 16 behaviors in the supplied migration specification. Legacy conversion explicitly waived by the user; no automatic note deletion. Old PencilKit ink cannot be opened by this build.

## Automated coverage and physical-device checklist

| ID | Automated evidence | Manual iPad check still required |
|---|---|---|
| PEN-01 | Ball diameter constant, including raw pressure changes | Light/heavy Pencil force, reload |
| PEN-02 | Progressive Fountain profile, saved style | Slow/fast pressure ramp |
| PEN-03 | Wider Brush response | Expressive curves and sharp turns |
| PEN-04 | Frozen sharpness, point/short-stroke geometry | Hooks, dots, 0–100% cap appearance |
| PEN-05 | Causal prefix stability, synthetic jitter reduction | Latency and small writing at zoom |
| PEN-06 | Arc-length dot/dash sampling-density invariance | Patterns on tight curves at different speeds |
| PEN-07 | Color/style unchanged on old ink and reload | Blue then red with Pencil |
| GEST-01 | Dense overlapping scribble vs negative handwriting fixtures | Repeated ratures on words, false positives |
| GEST-02 | Editable fragments, separate dot preserved, exact undo | Partially cross out handwriting and dot of i |
| GEST-03 | Circle stays stored, contour eligibility, expiry | Draw circle, lift, long press its contour, move selection |
| GEST-04 | Line/ellipse/polygon/curve recognition; held geometry routed | Hold Pencil still for 550 ms |
| GEST-05 | Anchored scaling/rotation; geometry/raw separation | Adjust while still pressed, lift without jump |
| INPUT-01 | Pencil-only rejects direct input, cancel ignores unrelated contacts | Palm resting + Pencil + two-finger navigation |
| INPUT-02 | Ephemeral overlay by construction; guarded system hover preference | Compatible Pencil hover and older iPad fallback |
| DOC-01 | Exact snapshots through erase/shape undo+redo; real finger UI test | Interrupt gestures and repeat editing history |
| DOC-02 | Exact JSON/IDs/raw/style/PNG after new-session reopen | Close/relaunch after real writing |

All physical-device checks above are **NOT RUN**. No Goodnotes parity, FPS, pressure calibration or physical Pencil latency is claimed.

## Known limits

- Pressure, stabilization, gesture thresholds and 550 ms hold duration are initial calibration, not measured Goodnotes values.
- Partial erasing splits longitudinal paths where the eraser touches the painted envelope. It removes the affected cross-section; it does not retain lateral fringes of a thick stroke. Pattern/taper geometry is baked into editable solid fragments after a cut.
- Very long scribbles with over 2048 simplified vertices stay ordinary ink, preserving classifier cost and avoiding accidental deletion.
- Committed geometry is cached in retained vector layers. 1k/10k synthetic serialization/render diagnostics do not establish live Pencil latency or older-device memory use.
- iOS 16 API compilation is checked by the deployment target; actual iPadOS 16 execution needs hardware/runtime unavailable here.

## Execution log

Pending final suite and packaging results. Interrupted work: see `MIGRATION_AUDIT.md`, branch `codex/custom-ink-engine`.
