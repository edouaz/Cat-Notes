# Contributing to OpenNotes

Start with the [developer guide](https://edouaz.github.io/OpenNotes/develop.html) and [architecture](docs/ARCHITECTURE.md). The app is a prototype; small, focused fixes are welcome.

1. Open an issue describing the problem, device, iOS version and steps to reproduce. Use synthetic notes and remove personal information from screenshots.
2. Fork the repository and create a branch for one change.
3. Follow the surrounding Swift patterns. Keep local use independent of accounts, preserve iOS 16 compatibility and handle failed saves without dropping pending data.
4. Add or update a focused test for behavior changes. Run affected tests, then the unit suite. For canvas or layout changes, run the relevant UI tests and include a screenshot.
5. If files were added or removed, run `python3 scripts/generate-project.py` and commit the generated Xcode project. Change build settings in that script so regeneration preserves them.
6. Open a pull request explaining the problem, behavior after the fix, checks performed and any hardware testing still needed.

Do not commit credentials, signing certificates, provisioning profiles, personal notebooks, DerivedData or IPA files. `Config/Supabase.plist` is local and ignored. Cloud work must retain row-level security and reject privileged keys in the app.

The GitHub Actions workflow builds and runs unit tests on an available iPad simulator. Simulator tests do not establish physical Pencil latency or compatibility with every iOS 16 device.
