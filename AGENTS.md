# Agent rules

- Do not build, run, launch, restart, or terminate the app unless the user explicitly requests that exact action. The user owns the active Xcode run session.
- Do not invoke `xcodebuild`, `swift build`, project run scripts, or other build/launch automation unless the user explicitly requests it.
- Do not modify Xcode scheme settings on your own (including reverting or regenerating `*.xcscheme`).
- Treat `Paste.xcodeproj` as the source of truth. Do not generate or regenerate the Xcode project; edit only the required project file entries when the user requests a source change.
