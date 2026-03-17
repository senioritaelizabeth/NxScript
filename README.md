<div align="center">

<img src="assets/logo.png" alt="NxScript Logo" width="200"/>

# NxScript

**a scripting language for haxe that doesn't make you want to rewrite it yourself**

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Haxe](https://img.shields.io/badge/language-Haxe-orange.svg)](https://haxe.org)
[![Tests](https://img.shields.io/badge/tests-195%20passing-brightgreen.svg)](#testing)

</div>

---

## what is it

NxScript is a bytecode-compiled scripting language that runs inside Haxe. You write `.nx` files, the library compiles them to bytecode at runtime, and a stack-based VM executes them. Hot-reloadable logic, no recompile, no nonsense.

Built for games. Works for anything.

---

## install

```bash
haxelib git nxscript https://github.com/senioritaelizabeth/NxScript.git
```

```hxml
-lib nxscript
```

```xml
<!-- lime / OpenFL -->
<haxelib name="nxscript"/>
```

---

## quick start

```haxe
import nx.script.Interpreter;

var interp = new Interpreter();
interp.run('
    func greet(name) {
        return "Hello " + name + "!"
    }
');
trace(interp.call("greet", ["world"])); // Hello world!
```

---

## the language

### variables

```nx
var x = 10
let y = 20        # block-scoped
const MAX = 100   # immutable
```

### functions

```nx
func add(a, b) {
    return a + b
}

# shorthand lambda
var double = x => x * 2
var sum = (a, b) => a + b
```

### control flow

```nx
# braceless bodies work
if (x > 0) doThing()
else doOther()

while (i < 10) i++

for (item in array) trace(item)
for (i from 0 to 10) trace(i)
```

### truthy coercion

Everything evaluates as a condition without explicit comparison — JS-style:

```nx
if (count)      # false if count == 0
if (name)       # false if name == ""
if (items)      # false if items == []
if (result)     # false if result == null
```

Falsy values: `null`, `0`, `""`, `[]`, `{}`, `NaN`. Everything else is truthy.

### null handling

```nx
# null coalescing
var name = user ?? "anonymous"
var port = config.port ?? 8080

# chained
var val = a ?? b ?? c ?? "default"

# optional chain — returns null instead of throwing
var city = user?.address?.city
var tag  = node?.children?.first() ?? "none"
```

### template strings

```nx
var name = "world"
`Hello ${name}!`          # backtick
'Hello ${name}!'          # single quote
"Hello ${name}!"          # double quote — all three work
```

### classes

```nx
class Animal {
    var name
    var hp = 100

    func new(n) {
        this.name = n
    }

    func speak() {
        return this.name + " makes noise"
    }

    func takeDamage(amount) {
        this.hp -= amount
        return this.hp > 0
    }
}

class Dog extends Animal {
    func new(n) { super.new(n) }
    func speak() { return this.name + " says woof" }
}

var d = new Dog("Rex")
trace(d.speak())        # Rex says woof
trace(d.takeDamage(30)) # true
trace(d.hp)             # 70
```

### match

```nx
match score {
    case 90...100 => "A"
    case 80...89  => "B"
    case 70...79  => "C"
    default       => "F"
}

match value {
    case String  => "is a string"
    case Number  => "is a number"
    case n       => "bound: " + n    # lowercase = bind
}

match cmd {
    case "attack" => dealDamage()
    case "flee"   => runAway()
    default       => trace("unknown")
}
```

### destructuring

```nx
var [a, b, c] = [1, 2, 3]
var [first, _, third] = items   # _ skips

var {x, y} = getPosition()
```

### enums

```nx
enum Direction { North, South, East, West }
enum Result { Ok(value), Err(message) }

var dir = Direction["North"]
trace(dir.variant)   # North
trace(dir.enum)      # Direction

var ok = Result["Ok"](42)
trace(ok.values[0])  # 42

match dir {
    case North => moveUp()
    case South => moveDown()
    default    => trace("sideways")
}
```

### abstract types

```nx
abstract Meters(Float) {
    func new(v) { this.value = v }
    func toKm() { return this.value * 0.001 }
}

var dist = new Meters(1500)
trace(dist.toKm())   # 1.5
```

### try / catch / throw

```nx
try {
    if (hp <= 0) throw "dead"
    doRiskyThing()
} catch (e) {
    trace("caught: " + e)
}
```

### is operator

```nx
42 is Number       # true
"hi" is String     # true
null is Null       # true
[1,2] is Array     # true
```

---

## built-in methods

### numbers
```nx
(3.7).floor()    # 3
(-5).abs()       # 5
(2).pow(8)       # 256
(9).sqrt()       # 3
(1.4).ceil()     # 2
(1.5).round()    # 2
```

### strings
```nx
"hello".upper()                      # HELLO
"  hi  ".trim()                      # hi
"hello world".replace("world", "!")  # hello !
"ha".repeat(3)                       # hahaha
"5".padStart(4, "0")                 # 0005
"hello".startsWith("he")             # true
"hello".split("")                    # ["h","e","l","l","o"]
"hello".charAt(1)                    # e
"hello".indexOf("ll")                # 2
"hello".substr(1, 3)                 # ell
```

### arrays
```nx
[1,2,3].map(x => x * 2)              # [2,4,6]
[1,2,3,4].filter(x => x > 2)         # [3,4]
[1,2,3].reduce((a, x) => a + x, 0)   # 6
[1,3,5,8].find(x => x % 2 == 0)      # 8
[1,3,5,8].findIndex(x => x > 4)      # 2
[1,2,3].includes(2)                   # true
[3,1,2].sort((a, b) => a - b)         # [1,2,3]
["b","aa","ccc"].sortBy(s => s.length) # ["b","aa","ccc"]
[1,2].concat([3,4])                   # [1,2,3,4]
[[1,2],[3,4]].flat()                  # [1,2,3,4]
var b = arr.copy()                    # independent copy
[1,2,3].first()                       # 1
[1,2,3].last()                        # 3
[1,2,3].join(", ")                    # "1, 2, 3"
[3,1,2].reverse()                     # [2,1,3]
```

### dicts
```nx
var d = {"x": 1, "y": 2}
d.has("x")       # true
d.size()         # 2
d.keys()         # ["x", "y"]
d.values()       # [1, 2]
d.remove("x")
d.set("z", 99)
d.clear()
```

### global functions
```nx
range(5)           # [0,1,2,3,4]
range(2, 7)        # [2,3,4,5,6]
str(42)            # "42"
int(3.9)           # 3
float("3.14")      # 3.14
abs(-5)            # 5
floor(3.9)         # 3
ceil(3.1)          # 4
sqrt(16)           # 4
pow(2, 10)         # 1024
min(3, 7)          # 3
max(3, 7)          # 7
sin(PI / 2)        # 1.0
cos(0)             # 1.0
random()           # 0.0..1.0
type(42)           # "Number"
typeof(x)          # "number" / "string" / "array" / ...
```

---

## haxe integration

### basic

```haxe
var interp = new Interpreter();
interp.run(code);

var result = interp.call("myFunc", [arg1, arg2]);
interp.globals.set("score", interp.vm.haxeToValue(100));

var v = interp.safeCall("maybeExists", []); // null if missing
```

### expose haxe objects to scripts

```haxe
// script can call game.add(sprite), game.sprites.push(spr), etc.
// Arrays passed this way are LIVE references — push() works on the real array
interp.globals.set("game", interp.vm.haxeToValue(this));
```

### NxProxy — script class instances in Haxe

```haxe
interp.run('
    class Enemy {
        var hp = 100
        func takeDamage(n) { this.hp -= n }
    }
');

var enemy:Dynamic = NxProxy.instantiate(interp, "Enemy", []);
enemy.takeDamage(30);
trace(enemy.hp); // 70
```

### NativeProxy — hot loop optimization

When scripts update many native objects per frame (e.g. 10k sprites), use `NativeProxy` to eliminate per-access `Reflection` calls. Script syntax is **unchanged**:

```haxe
var result = NativeProxy.wrapMany(vm, sprites, ["x","y","angle","color"]);
vm.globals.set("sprites", VArray(result.values));

// script is identical — spr.angle, spr.x etc. work the same
interp.run(script);

// write shadow maps back to native objects once per frame
NativeProxy.flushAll(result.proxies);
```

### per-frame calls — avoid allocations

```haxe
var updateFn = interp.vm.resolveCallable("update"); // resolve once
var args = [VNumber(0.0)];                          // reuse array

// every frame:
args[0] = VNumber(elapsed);
interp.vm.callResolved(updateFn, args);
```

### sandbox

```haxe
interp.enableSandbox();                    // blocks Sys, File, network
interp.enableSandbox(["DangerousClass"]);  // also block custom names
```

---

## syntax rules

Customize keyword and operator spelling per interpreter:

```haxe
import nx.script.SyntaxRules;

var rules = new SyntaxRules();
rules.addKeywordAlias("fn",  "func");   // fn x() {}
rules.addKeywordAlias("let", "var");    // let x = 1
rules.addOperatorAlias("not", "!");     // not true
rules.addOperatorAlias("and", "&&");    // x and y
rules.addOperatorAlias("or",  "||");    // x or y

var interp = new Interpreter(false, false, rules);
```

### presets

```haxe
SyntaxRules.nxScript()   // default — all features on
SyntaxRules.pythonish()  // def, not/and/or, True/False/None
SyntaxRules.minimal()    // no lambdas, no templates, no braceless
SyntaxRules.haxeStyle()  // function keyword, etc.
```

---

## bridges

```haxe
import nx.bridge.NxStd;
NxStd.registerAll(interp.vm);
// adds: parseInt, parseFloat, isNaN, isFinite,
//       jsonParse, jsonStringify, readFile, writeFile,
//       command, exit, getEnv, sleep, time, args, cwd

import nx.bridge.NxDate;
NxDate.registerAll(interp.vm);
// adds: dateNow(), dateFromTime(), dateFromString(),
//       dateFormat(), dateDelta(), timerStamp()
```

---

## gc control

```haxe
interp.gc_kind = AGGRESSIVE;      // clear caches every run
interp.gc_kind = SOFT;            // clear at threshold (default)
interp.gc_kind = VERY_SOFT;       // never proactively clear
interp.gc_softThreshold = 256;
interp.gc();                      // manual trigger
```

---

## project structure

```
src/nx/
├── script/
│   ├── Interpreter.hx     # main entry point
│   ├── VM.hx              # stack-based VM
│   ├── Compiler.hx        # AST → bytecode
│   ├── Parser.hx          # tokens → AST
│   ├── Tokenizer.hx       # source → tokens
│   ├── Bytecode.hx        # opcodes + Value enum
│   ├── Token.hx           # token types
│   ├── AST.hx             # expression/statement nodes
│   ├── SyntaxRules.hx     # configurable syntax aliases
│   ├── NativeClasses.hx   # built-in methods
│   ├── NxProxy.hx         # script class → Haxe proxy
│   └── NativeProxy.hx     # Haxe object → shadow map
└── bridge/
    ├── NxStd.hx           # stdlib (json, file, sys)
    └── NxDate.hx          # date/time
```

---

## testing

```bash
cd test/tests
haxelib run nxscript test
```

195 tests, 0 failing.

---

## license

Apache 2.0.

---

<div align="center">

made by [@senioritaelizabeth](https://github.com/senioritaelizabeth) · thanks to RapperGfDev for testing and optimizations

</div>
