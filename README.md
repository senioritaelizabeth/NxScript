<div align="center">

<img src="assets/logo.png" alt="NxScript Logo" width="200"/>

# NxScript

**yes, another scripting lang. for haxe. you're welcome.**

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Haxe](https://img.shields.io/badge/language-Haxe-orange.svg)](https://haxe.org)
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen.svg)](#-testing)

---

### two languages walk into a bar. one handles dialogue, the other handles everything else. neither of them crash. probably.

</div>

## what even is this

**NxScript** is two things shoved into one library because making separate repos is for people with too much free time:

- **Nx-Dialogue** — a language for writing branching dialogue that doesn't make you want to cry
- **NxScript** — a bytecode-compiled scripting language with a stack-based VM that's somehow faster than the alternatives (we're just as surprised as you are)

Both compile to Haxe. Both actually work. Both are MIT-licensed, meaning you can do whatever you want with them and blame yourself when something breaks.

---

## NxScript — the good stuff

A general-purpose scripting language. Compiles to bytecode, runs on a stack VM, doesn't allocate a new array every time you call a function (unlike some other libs we won't name).

### features (yes it has them)

- **Bytecode compilation** — your scripts don't get interpreted line-by-line like it's 1998
- **Stack-based VM** — the hot path is actually hot; pre-allocated stack, no GC pressure per call
- **`var` / `let` / `const`** — because scoping rules matter and "just use globals" is not a personality
- **First-class functions & closures** — yes, you can pass functions around; no, it won't explode
- **Method chaining on primitives** — `(-5).abs().floor()` works, deal with it
- **Arrays and Dictionaries** — built-in, no imports required
- **`for` / `while` / `if-else`** — control flow, revolutionary stuff
- **Recursion** — Fibonacci works, don't push it past 30 in Neko
- **30+ built-ins** — math, strings, arrays, type conversion, the classics
- **Try/catch/throw** — exception handling that actually works
- **Classes with inheritance** — `extends` keyword, constructors, `this`, the whole circus
- **Line/column error tracking** — so you know _exactly_ which line you wrote something dumb on

### a real example, because docs without examples are a crime

Say you're making a game. You've got enemies. You want their logic in a script so you don't have to recompile every time you change a number. Here's how that looks:

```nx
# enemy.nx — logic for your extremely intimidating enemy

const SPEED = 120
const ATTACK_RANGE = 50

class Enemy {
    var x = 0
    var y = 0
    var hp = 100
    var alive = true

    func new(startX, startY) {
        x = startX
        y = startY
    }

    func takeDamage(amount) {
        hp = hp - amount
        if (hp <= 0) {
            alive = false
            trace("enemy died, rip")
        }
    }

    func distanceTo(tx, ty) {
        var dx = tx - x
        var dy = ty - y
        return (dx * dx + dy * dy).sqrt()
    }

    func update(playerX, playerY, dt) {
        if (!alive) { return }

        var dist = distanceTo(playerX, playerY)

        if (dist < ATTACK_RANGE) {
            trace("player got got")
        } else {
            # walk toward player
            var dx = playerX - x
            var dy = playerY - y
            var len = dist.max(0.001)
            x = x + (dx / len) * SPEED * dt
            y = y + (dy / len) * SPEED * dt
        }
    }
}
```

And from Haxe, you wire it up:

```haxe
import nz.script.Interpreter;
import nz.script.NxProxy;

// Define a typed interface so your IDE stops yelling at you
interface IEnemy extends IScriptInstance {
    var x:Float;
    var y:Float;
    var hp:Float;
    var alive:Bool;
    function update(px:Float, py:Float, dt:Float):Void;
    function takeDamage(amount:Float):Void;
}

class Game {
    var interp:Interpreter;
    var enemy:Dynamic; // Dynamic for operations (see IScriptInstance docs)

    public function new() {
        interp = new Interpreter();

        // load the script — it registers the Enemy class
        interp.run(sys.io.File.getContent("enemy.nx"), "enemy.nx");

        // create an instance at position (300, 200)
        enemy = NxProxy.instantiate(interp, "Enemy", [300.0, 200.0]);
    }

    public function update(dt:Float) {
        // call the script's update() — fields auto-sync
        enemy.update(playerX, playerY, dt);

        // read a field back — works like normal Haxe
        if (!enemy.alive) {
            trace("enemy is dead, spawning another one to ruin your day");
        }
    }

    public function hitEnemy(damage:Float) {
        enemy.takeDamage(damage);
        // optionally typecast for autocomplete:
        var typed:IEnemy = enemy;
        trace("enemy has " + typed.hp + " hp left");
    }
}
```

That's it. Your enemy logic lives in a `.nx` file, hot-reloadable, no recompile needed, no embarrassing `Dynamic` casts everywhere in game logic.

### method chaining because we can

```nx
# numbers know math now
var x = (-2000 / 2).abs().floor()   // 1000

# strings are also civilized
var name = "  SCREAMING  ".trim().lower()  // "screaming"

# arrays have opinions too
var arr = [3, 1, 4, 1, 5]
trace(arr.first())   // 3
trace(arr.last())    // 5
trace(arr.length)    // 5
```

---

## Nx-Dialogue — talk to your NPCs

A scripting language specifically for branching dialogue. Because using a general-purpose language to write "Hello traveler" is like using a sledgehammer to hang a picture frame.

### things it does

- Write dialogue as plain text — no quotes, no ceremony, just text
- Branch with `if/else` — classic
- Call game functions with `@commands` — `@openShop`, `@playSound "slam"`, whatever
- Track state with variables — `questActive = true`, `playerKills = playerKills + 1`
- Reuse logic with `func` blocks
- `and`, `or`, `not` as words because real humans don't write `&&`

### quick example

```
# shopkeeper.nxd
var bribed = false
var goldSpent = 0

func greet
    Shopkeeper: Ah, a customer. How... wonderful.
    What do you want?
end

func bribeAttempt
    if (goldSpent >= 100)
        Shopkeeper: Fine. I'll look the other way. Just this once.
        bribed = true
    else
        Shopkeeper: That's not enough. Come back when you're serious.
    end
end

@greet

if (playerHasItem "suspicious_package")
    Shopkeeper: Is that what I think it is?
    @bribeAttempt
else
    Shopkeeper: Browse freely. Touch nothing expensive.
end
```

Integration with Haxe (the boring but necessary part):

```haxe
import nz.dialogue.Dialogue;

var dialogue = new Dialogue();
dialogue.load(sys.io.File.getContent("shopkeeper.nxd"));

// pump the dialogue line by line
while (dialogue.hasNext()) {
    switch (dialogue.next()) {
        case Dialog(text):
            showTextBox(text); // your UI call

        case AtCall(command, args):
            handleCommand(command, args); // @openShop, etc.

        case Variable(name, value):
            gameState.set(name, value); // track variables
    }
}
```

---

## installation

### via haxelib (the sane way)

```bash
haxelib git nxscript https://github.com/senioritaelizabeth/NxScript.git
```

### `.hxml`

```hxml
-lib nxscript
-main YourMainClass
-neko output.n
```

### lime / OpenFL

```xml
<haxelib name="nxscript"/>
```

---

## testing

```bash
cd test/tests
haxe basic.hxml    # variables, arithmetic, control flow
haxe methods.hxml  # string/number/array built-in methods
haxe classes.hxml  # class definitions, instantiation, inheritance
```

For when you want numbers:

```bash
cd test
haxe -cp test -cp src -main ScriptTargetBench -lib hscript-improved -lib hscript-iris -cpp test/bin/cpp_scriptbench
./test/bin/cpp_scriptbench/ScriptTargetBench
```

---

## performance (the part you're actually here for)

C++ target benchmarks. Not Neko. Don't benchmark on Neko and then complain.

| Benchmark           | ops/sec        |
| ------------------- | -------------- |
| Arithmetic          | ~1.67M ops/sec |
| Array Operations    | ~1.00M ops/sec |
| String Operations   | ~1.00M ops/sec |
| Method Chaining     | ~556K ops/sec  |
| Class Instantiation | ~333K ops/sec  |

Faster than HScript. Faster than Iris. Tested. Not sorry.

---

## project structure

```
NxScript/
├── src/nz/
│   ├── dialogue/        # Dialogue system
│   │   ├── Dialogue.hx
│   │   ├── executor/
│   │   ├── parser/
│   │   └── tokenizer/
│   │
│   ├── script/          # Script language
│   │   ├── Interpreter.hx
│   │   ├── VM.hx
│   │   ├── Compiler.hx
│   │   ├── Parser.hx
│   │   ├── Tokenizer.hx
│   │   ├── Bytecode.hx
│   │   └── Token.hx
│   │
│   └── cinematic/       # Cinematic system
│
├── test/
│   └── tests/          # Test suites
│       ├── BasicTest.hx
│       ├── MethodsTest.hx
│       └── ClassesTest.hx
│
├── examples/           # Usage examples
│   ├── BuiltinFunctionsExample.hx
│   ├── MethodChainingExample.hx
│   └── ClassExample.hx
│
├── ScriptTargetBench.hx # Consolidated performance benchmark suite
└── README.md
```

---

## Use Cases

### Perfect For:

| Nx-Dialogue         | Nx-Script                |
| ------------------- | ------------------------ |
| RPG conversations   | Game logic and mechanics |
| Interactive fiction | Mod support              |
| Visual novels       | Procedural generation    |
| Quest systems       | AI behavior              |
| Tutorial sequences  | Configuration with logic |
| Story-driven games  | Educational programming  |

---

## Built-in Functions (Nx-Script)

### Console Output

`trace(...args)` • `print(...args)` • `println(...args)`

### Type Utilities

`typeof(value)` • `int(value)` • `float(value)` • `str(value)` • `bool(value)`

### Math Functions

`abs(n)` • `floor(n)` • `ceil(n)` • `round(n)` • `sqrt(n)` • `pow(base, exp)`  
`sin(n)` • `cos(n)` • `tan(n)` • `min(a, b)` • `max(a, b)` • `random()`

### String Functions

`upper(s)` • `lower(s)` • `trim(s)`

### Array Functions

`len(arr)` • `push(arr, item)` • `pop(arr)`

### Constants

`PI` • `E` • `NaN` • `Infinity`

[View complete API documentation →](docs/BUILTIN_FUNCTIONS.md)

---

## Contributing

Contributions are welcome! Here's how:

1.  Report bugs via [Issues](https://github.com/senioritaelizabeth/NxScript/issues)
2.  Propose features
3.  Improve documentation
4.  Add tests
5.  Submit pull requests

### Development Setup

```bash
# Clone repository
git clone https://github.com/senioritaelizabeth/NxSciprt.git
cd NxScript

# Run tests
haxe test.hxml

# Run benchmarks
haxe -cp test -cp src -main ScriptTargetBench -lib hscript-improved -lib hscript-iris -cpp test/bin/cpp_scriptbench
```

---

## License

**Apache 2.0 License** - Free to use in any project, commercial or otherwise.

---

## Acknowledgments

Created with ❤️ by [@senioritaelizabeth](https://github.com/senioritaelizabeth)
Thanks to RapperGfDev for feedback, testing and optimizations.

---

## Demos

### Rhythm Demo (Flixel + NxScript)

Location: `demos/rythm`

```bash
cd demos/rythm
lime test hl
```

The gameplay logic is scripted in:

- `demos/rythm/assets/scripts/game.nx`
- `demos/rythm/assets/scripts/rhythm_core.nx`
- `demos/rythm/assets/scripts/rhythm_flow.nx`

Main runtime bridge classes:

- `demos/rythm/source/PlayState.hx` (minimal wrapper)
- `demos/rythm/source/RhythmGameState.hx` (Flixel bridge + script calls)

### Rhythm demo controls

- `D F J K`: hit notes / chart lanes
- `TAB`: toggle chart mode
- `ENTER`: save chart
- `R`: restart song/chart timeline
- `F3/F4`: speed down/up

### Rhythm demo data

- Chart file: `demos/rythm/assets/data/chart_steps16.json`
- Quantization: 16th steps (`division: 16`)
- Audio tracks: `tv_time` + `tv_time_guitar` (guitar mutes on miss)
- BPM: `148`

### Recent rhythm changes

- Script-driven gameplay rules (hit window, score, combo, speed clamps, sync thresholds).
- Script-driven lane layout and flow helpers.
- Chart/debug mode that records DFJK lanes and saves JSON charts.
- Time-based chart spawning with pre-roll so notes can arrive in sync.
- Runtime debug traces (`RHYTHM-DBG`) for lane/spawn diagnostics.

### Script imports and loader

NxScript now supports script file imports directly:

```nx
import "./rhythm_core.nx"
```

You can also load scripts at runtime from script code:

```nx
convokeScript("assets/scripts/other.nx")
```

Runtime loading tries OpenFL/Lime assets first and falls back to `sys.io.File`.

Also supported from scripts:

- `convokeScript("path/to/file.nx")`

---

## VS Code Extension Release

- Manual/publish by tag workflow: `.github/workflows/vscode-extension-release.yml`
- Nightly minimal branch sync/checks: `.github/workflows/nightly-minimal.yml`
- Docs validation in CI: `.github/workflows/ci.yml` (`docs-check` job)
- Docs publishing to GitHub Pages: `.github/workflows/docs-publish.yml`

Required secret for Marketplace publish:

- `VSCE_PAT`

GitHub Pages docs are published automatically from `main` (or manually via workflow dispatch).

## VS Code Extension Install

Extension source in this repo:

- `nxscript-vsext`

### Local install (development)

```bash
cd nxscript-vsext
npm install
npm run compile
```

Then in VS Code:

1. Open `nxscript-vsext`.
2. Press `F5` to launch an Extension Development Host.
3. Open a `.nx` file in the dev host and verify features.

### VSIX package/install

```bash
cd nxscript-vsext
npm install -g @vscode/vsce
vsce package
```

Install the generated `.vsix` from the Extensions menu (`Install from VSIX...`).

Built for the Haxe game development community.

---

## Resources

<!-- - 📚 [Dialogue Documentation](src/nz/dialogue/README.md) -->
<!-- - 📚 [Script Documentation](src/nz/script/README.md) -->
<!-- - 📚 [Built-in Functions Guide](docs/BUILTIN_FUNCTIONS.md) -->

- [Issue Tracker](https://github.com/senioritaelizabeth/NxScript/issues)
- [Discussions](https://github.com/senioritaelizabeth/NxScript/discussions)

---

<div align="center">

**Made with ❤️ for game developers and interactive storytellers**

</div>
