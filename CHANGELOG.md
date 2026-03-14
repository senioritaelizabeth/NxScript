# Changelog 0.2.4.1 (2026-03-13)

### Added

**`-D NXDEBUG` compile flag**
- Debug output (instruction trace, tokens, AST, bytecode) is now a compile-time flag — zero runtime overhead in production builds
- `vm.debug = true` still accepted for API compatibility but emits a warning at runtime unless compiled with `-D NXDEBUG`
- Add `-D NXDEBUG` to your `.hxml` to enable full debug output

**REPL + CLI** (`src/nx/script/Main.hx`, `run.hxml`, `haxelib.json`)
- `haxelib run nxscript run <file.nx>` — execute a script file
- `haxelib run nxscript run <file.nx> -w` — watch mode, re-runs on file change
- `haxelib run nxscript repl` — interactive REPL with multi-line buffering (open `{` or `(` and press Enter)
- `haxelib run nxscript <file.nx>` — shorthand for `run`
- REPL commands: `exit`, `:reset` (clear interpreter state), `:globals` (list all globals), `:clear` (clear buffer), `help`
- `haxelib.json` updated with `"main": "nx.script.Main"`

**Sandbox mode**
- `vm.enableSandbox(?extraBlocklist)` — blocks Sys/File/FileSystem/Http/Socket/Process/Reflect/Type, sets `maxInstructions=500_000`, `maxCallDepth=256`
- `vm.sandboxed:Bool` and `vm.sandboxBlocklist:Map<String,Bool>` — fully configurable
- Sandbox check happens in `getVariable` — blocked names throw immediately, before any code runs

**safeCall / safeGet**
- `vm.safeCall(name, ?args)` — calls a script function, returns `null` on any error instead of throwing
- `vm.safeCallResolved(fn, ?args)` — same for already-resolved `Value` callables
- `vm.safeGet(name)` — gets a global variable, returns `null` if missing
- All three forwarded on `Interpreter` as well

**Nested block scopes**
- `let` declarations inside `{ }` blocks are now properly scoped — they don't leak out of the block
- Implemented via new `ENTER_SCOPE` / `EXIT_SCOPE` opcodes (0xD0 / 0xD1) and `scopeStack` in the VM
- Only applies at module level; inside functions, locals already live on the stack frame

**`match` pattern matching**
```nx
match value {
    case 1        => "one"
    case 1...5    => "in range"
    case String   => "is a string"
    case Number   => "is a number"
    case [a, b]   => a + b          # array destructure
    case x        => x * 10         # bind to variable
    default       => "fallback"
}
```
- Cases support: exact values, numeric ranges (`from...to`), type names (`String`, `Number`, `Bool`, `Null`, `Array`, `Dict`, `Function`), array destructuring, variable binding
- Case bodies can be single expressions or full `{ }` blocks with multiple statements
- Falls through to `default` if no case matches

**Destructuring assignments**
```nx
var [a, b, _] = [1, 2, 3]          # array — _ skips element
var {x, y}    = {"x": 10, "y": 20} # dict/object
```
- Works with both `var` and `let`
- `_` in array destructure skips the element at that index
- Dict destructure extracts fields by name

### Changed
- `Compiler.hx`: `SBlock` now emits `ENTER_SCOPE`/`EXIT_SCOPE` at module level for correct `let` scoping
- `Parser.hx`: `parseLet` and `parseVar` now detect `[` and `{` after the keyword and route to destructure parsers

### Tests
- Added `test/tests/NewFeaturesTest2.hx` — 70+ assertions across 13 sections covering all features above

### To Fix

- `match` on `null` may throw `Null Access` in `src/nx/script/VM.hx` (line 1435) — should be fixed to fail gracefully.
---

# Changelog 0.2.4 (2026-03-13)


### Added

**Syntax**
- **Trailing commas** — now allowed in function parameters, call arguments, array literals, and dict literals. `[1, 2, 3,]`, `f(a, b,)`, `{"k": v,}` all parse cleanly.
- **Shorthand lambda `=>`** — single-arg lambdas no longer require parentheses: `x => x * 2`. Multi-arg form `(a, b) => a + b` also supported. `=>` accepted everywhere `->` was, including block bodies `x => { ... }`.
- **Template strings** — backtick strings with `${}` interpolation: `` `Hello ${name}, result is ${a + b}` ``. Expressions inside `${}` are fully re-tokenized and evaluated at runtime. Escape sequences (`\n`, `\t`, `\\`, `` \` ``) supported.

**Array methods** — `map`, `filter`, `reduce`, `forEach`, `find`, `findIndex`, `every`, `some`, `slice`, `concat`, `flat`, `copy`, `sort`, `sortBy`

**String methods** — `startsWith`, `endsWith`, `replace`, `repeat`, `padStart`, `padEnd`

**Dict methods** — `.keys()`, `.values()`, `.has(k)`, `.remove(k)`, `.set(k, v)`, `.size()`

**Global natives**
- `print(...) / println(...)` — variadic trace wrappers
- `range(n)` → `[0..n-1]`,  `range(from, to)` → `[from..to-1]`
- `str(x)`, `int(x)`, `float(x)` — explicit type conversions
- `keys(dict)`, `values(dict)` — global convenience wrappers
- Math: `abs`, `floor`, `ceil`, `round`, `sqrt`, `pow`, `min`, `max`, `random`, `sin`, `cos`, `tan`
- Constants: `PI`, `INF`, `NAN`

**GC control** — `GcKind` enum with three modes configurable via `interp.gc_kind`:
- `AGGRESSIVE` — flush all internal VM caches on every `execute()`. Lowest memory footprint.
- `SOFT` — flush caches when tracked object count exceeds `interp.gc_softThreshold` (default 512). Balanced default.
- `VERY_SOFT` — never flush proactively; trust the host runtime GC. Max throughput for hot re-execution.
- `interp.gc()` — manual flush at any time regardless of mode.

> Note: GC control manages VM-internal caches (`arrayMethodCache`, `instanceMethodCache`, `nativeArgBuffers`, `_typeNameCache`). Releasing these allows the host runtime GC to reclaim objects. Direct GC cycle triggering is not available from Haxe userland on most targets.

### Fixed
- `range(n)` (single-arg) now works correctly — the old `Interpreter` registration hardcoded arity 2 and overwrote the variadic VM version.

### Tests
- Added `TodoFeaturesTest.hx` covering all features above (61 assertions across 8 sections).

---

# Changelog 0.2.3.1 (2026-03-11)

### Added
- NativeReflection module (`NxReflect`, `CppReflect`, `HlReflect`, `JsReflect`) for platform-optimized native object access.
- VM optimization: per-class method cache, no try/catch, direct native access for get/set/callMethod/isFunction.
- `VIterator(arr, idx)` enum case in `Value` — replaces `VDict` Map allocation on every `for` loop entry. Iterator state is a single `Array<Int>[1]` box instead of a 3-entry Map.
- `FOR_RANGE_SETUP` + `FOR_RANGE` opcodes for tight integer range loops inside functions — eliminates `constVars` Map lookup on every iteration.
- VM: `VNativeFunction` closures for native object methods are now cached in `instanceMethodCache` per instance — eliminates closure allocation on every `getMember` call in hot loops.
- Compatibility typedefs for `nz.script` (deprecated).
- SpeedCheck and SpeedLoopCheck tests with timing and crash fixes.
- Benchmark: `NxReflectionVsReflection.hx` compares NxReflect vs Reflect in get/set/callMethod/isFunction (1M iterations).

### Fixed
- C++: `isFunction` now uses `Std.isOfType(v, cpp.Function) == true` to avoid abstract-as-value error.
- Fixed "Cannot use abstract as value" in VM cache logic.
- `Interpreter.hx` and `VM.hx`: exhaustive switches over `Value` now cover `VIterator`.

### Changed
- All VM native object access now routed through `NxReflect` for platform speed.
- `Compiler.hx`: `SForRange` inside functions now emits `FOR_RANGE_SETUP` + `FOR_RANGE` + `INC_LOCAL` instead of `STORE_CONST` + `LOAD_VAR` + `LT` + `JUMP_IF_FALSE` + `ADD` + `STORE_VAR`. Module-level fallback unchanged.
- `VM.hx`: `getIterator` and `iteratorNext` rewritten to use `VIterator` — no Map alloc, no `map.get`/`map.set` per step.
- Modular repo structure and docs updated.

### Notes
- `callMethod` performance vs `Reflect.callMethod` is within noise (~0.01ms delta at 1000 iterations) — both hit `hxcpp __Run` internally. No further optimization possible from Haxe userland.
- `FOR_RANGE` and `VIterator` optimizations only apply to code inside functions. Module-level scripts still use the Map-based fallback. Wrapping scripts in an implicit function (`runDynamic` auto-wrap) is planned for 0.2.3.2.
# Changelog 0.2.3 (latest)

### Changed
- Modular repo structure: dialogue and cinematic modules moved to their own repositories
- VS Code extension (`nxscript-vsext`) moved outside the main repo
- Deprecated `nz.script` alias, now use `nx.script` (typedefs for compatibility)

### Fixed
- Fix for-range continue bug, elseif keyword, postfix side effects, and return value ([commit](https://github.com/senioritaelizabeth/NxScript/commit/a76c3dfc6314b7b454850f43de71f62e317e394d), [PR #9](https://github.com/senioritaelizabeth/NxScript/pull/9))

### Migration Notes
- Update your imports from `nz.script` to `nx.script`
- For dialogue and cinematic, install their new repositories
- VS Code extension is now in `nxscript-vsext` outside the main repo


# Changelog 0.2.1 - 0.2.0

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
- Compiler/VM now use dedicated closure upvalue slots (`LOAD_UPVALUE` / `STORE_UPVALUE`) for captured outer-scope identifiers.
- Top-level `const` declarations now use indexed global slots with const-mask metadata instead of name-based const map lookups.
- Bytecode serializer format bumped to v3:
  - stores chunk-level global const mask
  - stores function-level upvalue name tables
  - remains backward compatible with v1/v2 deserialization
- Compiler now performs constant folding for pure literal expressions (e.g. `2 + 3` -> `5`) during bytecode emission.
- Member invocation compilation/runtime now includes `CALL_MEMBER` fast path to avoid `GET_MEMBER + CALL` overhead in common cases.
- VM call paths now reuse native argument buffers and include direct array-method fast routes for member calls.
- Script keyword alias added: `moewvar` behaves like `var`.

### Fixed

- Demo script issue with accidental `++trace(...)` causing invalid assignment target.
- Lane-resolution and spawn debugging issues in rhythm runtime bridge.
- Multiple rhythm sync regressions around chart spawn timing and startup lead behavior.
- Runtime handling for script-call fallback paths used by rhythm flow logic.
- Import alias false-positive parsing where `i = i + 1` could be misread as an import line.
- VM frame unwind bug where host calls (e.g. `call0("update")`) could resume stale `<main>` frame and re-run top-level script code.
- Reassignment to top-level `const` declared through global slots now throws reliably in VM `STORE_GLOBAL` path.

### Docs

- README updated with:
  - Rhythm demo controls and data format
  - Recent rhythm architecture/behavior changes
  - Script import/loading usage
  - VS Code extension install instructions (dev host + VSIX)

### Notes

- Existing non-strict scripts remain compatible.
- Core test and demo commands continue to pass for current dev setup (`lime test hl` in `demos/rythm`).

