# Changelog

All notable changes to this project are documented in this file.

### Added

- Native superclass metadata and native base integration for script classes extending Haxe/native classes.
- Native class instantiation support in VM `INSTANTIATE` flow (for examples like `new FlxText(...)` from script).
- Public VM APIs for host integration:
  - `instantiateClassByName(name, args)`
  - `callInstanceMethod(instance, methodName, args)`
  - `getNativeBaseInstance(instance)`
- Function keyword aliases in script parser:
  - `func`, `fn`, `fun`, `function`
- Additional loop syntax support:
  - `for (x of arr)`
  - `for (x in arr)`
  - `for (i from a to b)`
  - `for (i in a...b)`
- `TRange` (`...`) token support and parser lowering behavior for range loops.
- Interpreter strict-mode options:
  - constructor toggle (`new Interpreter(debug, strict)`)
  - script pragma (`"use strict"` / `'use strict'`)
- Builtin `range(start, end)` used by range lowering.
- Script import and runtime script-loading capabilities:
  - `import "./file.nx"`
  - `convokeScript("path/to/file.nx")`
- Loader fallback chain for script files:
  - OpenFL assets -> Lime assets -> `sys.io.File`
- VS Code extension release workflow:
  - `.github/workflows/vscode-extension-release.yml`
- Nightly minimal workflow:
  - `.github/workflows/nightly-minimal.yml`
- Rhythm demo (`demos/rythm`) features:
  - Dual music tracks (`tv_time`, `tv_time_guitar`)
  - Miss-based guitar muting
  - 16th-step chart recording/saving/loading
  - Chart mode controls (`TAB`, `DFJK`, `ENTER`, `R`)
  - Runtime speed control (`F3`, `F4`)
  - Script-driven gameplay tuning and flow (`game.nx`, `rhythm_core.nx`, `rhythm_flow.nx`)

### Changed

- Compiler now resolves bare method calls inside class methods to implicit `this.method()` when no local symbol shadows the call.
- Numeric tokenizer now correctly handles `0...2` without consuming dots incorrectly.
- Parser statement separator behavior:
  - non-strict mode allows optional semicolons
  - strict mode requires semicolon terminators
- Runtime diagnostics improved for script paths and stack output formatting.
- `PlayState` reduced to a minimal wrapper delegating to `RhythmGameState`.
- Rhythm spawn timing migrated to time-based scheduling with pre-roll alignment to reduce music/note desync.
- VM dispatch hot loop optimized:
  - inline opcode/arg fetch (`ip++` form)
  - cached `natives` map in loop locals
  - removed per-instruction `codeLen` bounds branch
- Compiler now guarantees top-level chunks end with `RETURN` to support branchless VM dispatch.

### Fixed

- Demo script issue with accidental `++trace(...)` causing invalid assignment target.
- Lane-resolution and spawn debugging issues in rhythm runtime bridge.
- Multiple rhythm sync regressions around chart spawn timing and startup lead behavior.
- Runtime handling for script-call fallback paths used by rhythm flow logic.
- Import alias false-positive parsing where `i = i + 1` could be misread as an import line.
- VM frame unwind bug where host calls (e.g. `call0("update")`) could resume stale `<main>` frame and re-run top-level script code.

### Docs

- README updated with:
  - Rhythm demo controls and data format
  - Recent rhythm architecture/behavior changes
  - Script import/loading usage
  - VS Code extension install instructions (dev host + VSIX)

### Notes

- Existing non-strict scripts remain compatible.
- Core test and demo commands continue to pass for current dev setup (`lime test hl` in `demos/rythm`).
