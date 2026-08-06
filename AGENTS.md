# Agent rules

- Do not modify Xcode scheme settings on your own (including reverting or regenerating `*.xcscheme`).
- Do not run `xcodegen generate` (or any other project regeneration) on your own when it would rewrite `*.xcscheme` or other scheme settings. If package/project files must change, edit only the required files (e.g. `project.yml` / `pbxproj`) without regenerating schemes unless the user explicitly asks.
