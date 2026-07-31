# Paste implementation constraints

- Paste targets macOS 26+ and Swift 6.
- It is a clipboard-only extraction from TinyCast commit `79c07daece9a161e74f82a5735424fbaa121e997`.
- Visual design has no discretionary changes. Preserve TinyCast's Liquid Glass controls, edge dissolve, thin scrollbar, row styling, dimensions, spacing, typography, and interaction states. Paste supports system, light, and dark appearances through adaptive color tokens.
- `RootPaletteView` intentionally removes TinyCast's launcher back arrow because Paste has no launcher. Do not introduce replacement chrome without an explicit request.
- `AppCore.shared` owns all long-lived managers and window controllers.
- `PaletteWindowController` alone owns the panel frame; the hosting view must keep `sizingOptions = []`.
- The app appearance defaults to the system setting and can be overridden with `.aqua` or `.darkAqua`; palette colors use an adaptive primary-alpha ramp over the unobscured system material.
- User-facing strings must remain localized in both `en.lproj` and `zh-Hans.lproj`. The language preference defaults to the system locale and supports live switching.
- Paste has no menu bar extra or Dock icon. The global clipboard shortcut is the only primary launcher; settings remain available from the palette.
- The General settings switch for disabling system clipboard history controls Spotlight's macOS 26+ `PasteboardHistoryEnabled` preference. Never stop `pboard`: Paste and system Copy/Paste depend on it.
- Clipboard writes must retain the private internal marker so Paste never captures its own synthetic writes.
- Keep `ClipboardStore.swift` Foundation + SQLite3 only so `Tools/clipboard-test.swift` can compile it standalone.
- Do not modify `Core/EdgeDissolve.swift` or `Core/ThinScrollbar.swift` unless the task explicitly changes their appearance.
- Use `./script/build_and_run.sh` as the build/run entrypoint.
