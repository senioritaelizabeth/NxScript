# NzLang Suite 🚀

> A comprehensive suite of scripting languages for Haxe projects

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Haxe](https://img.shields.io/badge/language-Haxe-orange.svg)](https://haxe.org)

[🇪🇸 Leer en Español](README_ES.md)

## 📖 What is NzLang Suite?

**NzLang Suite** is a collection of three specialized scripting languages designed for game development and interactive applications. Each language is optimized for specific use cases while maintaining a consistent, easy-to-learn syntax.

### The Three Languages

| Language         | Extension | Purpose                                | Status         |
| ---------------- | --------- | -------------------------------------- | -------------- |
| **Nz-Script**    | `.nzs`    | General-purpose bytecode scripting     | ✅ Ready       |
| **Nz-Dialogue**  | `.dia`    | Interactive dialogue and conversations | ✅ Ready       |
| **Nz-Cinematic** | `.cin`    | Cutscenes and camera sequences         | 🚧 Coming Soon |

---

## ⚡ Nz-Script - Bytecode Language

A powerful general-purpose scripting language with bytecode compilation, stack-based VM, and modern language features.

### ✨ Key Features

- 🔢 **Hexadecimal Bytecode** - Opcodes from 0x00 to 0xFF
- 📦 **Stack-based VM** - Fast and efficient execution
- 🔤 **Three Variable Types**
  - `let` - Script-local variables
  - `var` - Externally modifiable variables
  - `const` - Immutable constants
- ⚙️ **Functions & Lambdas** - First-class functions with closures
- 📊 **Data Structures** - Arrays and Dictionaries
- 🎯 **Type Methods** - String and Number methods built-in
- 🔄 **Control Flow** - if/else, while, for loops
- ♻️ **Recursion** - Full recursive function support
- 🐛 **Debug Info** - Line/column tracking in output

### 📝 Syntax Example

```nzs
# Variables and Constants
let name = "Hero"
var health = 100
const MAX_HEALTH = 100

# Functions
func heal(amount) {
    health = health + amount
    if (health > MAX_HEALTH) {
        health = MAX_HEALTH
    }
    return health
}

# Lambdas
let double = (x) -> x * 2
let square = (x) -> x * x

print("Health: " + health)
heal(25)
print("After heal: " + health)

# Arrays
let inventory = ["sword", "shield", "potion"]
inventory.push("key")

for (item in inventory) {
    print("- " + item)
}

# Dictionaries
let player = {
    "name": "Hero",
    "level": 5,
    "class": "Warrior"
}

print("Player: " + player["name"])
print("Level: " + player["level"])

# Recursion
func fibonacci(n) {
    if (n <= 1) {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

print("Fibonacci(10): " + fibonacci(10))

# String and Number Methods
let message = "hello world"
print(message.upper())  # "HELLO WORLD"
print(message.lower())  # "hello world"

let pi = 3.14159
print(pi.floor())  # 3
print(pi.round())  # 3
```

### 🎮 Usage in Haxe

```haxe
import nz.script.Interpreter;

class Game {
    static function main() {
        // Create interpreter
        var interp = new Interpreter(false);

        // Load and run script
        var script = sys.io.File.getContent("game.nzs");
        var result = interp.run(script, "game.nzs");

        // Access/modify variables from Haxe
        interp.vm.variables.set("player_health", VNumber(100));
        var health = interp.vm.variables.get("player_health");

        // Call script functions from Haxe
        trace("Script executed successfully!");
    }
}
```

### 📍 Location Tracking

Nz-Script tracks line and column numbers for debugging:

```
[game.nzs - 15:1] Health: 100
[game.nzs - 17:1] After heal: 125
[game.nzs - 23:5] - sword
[game.nzs - 23:5] - shield
```

---

## 💬 Nz-Dialogue - Interactive Dialogue System

A specialized language for writing branching dialogues, conversations, and narrative flows.

### ✨ Key Features

- 💭 **Simple Dialogue Writing** - Just write text naturally
- 🔀 **Branching Logic** - if/else, switch/case statements
- 🎯 **Functions** - Reusable dialogue blocks
- 📞 **Custom Commands** - @commands for game integration
- 🔢 **Variables** - Track dialogue state
- 🎲 **Operators** - Full arithmetic and logical operators
- 🌐 **Word Operators** - Use `and`, `or`, `not` alongside symbols

### 📝 Dialogue Example

```dia
# RPG Quest Dialogue

var playerName = "Hero"
var questCompleted = false
var gold = 0

func greetPlayer
    Welcome, brave adventurer!
    My name is Elder Thorne.
    What brings you to our village?
end

func giveQuest
    We have a problem with bandits nearby.
    Can you help us?

    @showQuestUI "Defeat the Bandits"
    questCompleted = false
end

func questReward
    Thank you for your help!
    Here is your reward.

    gold = gold + 100
    @giveItem "Magic Sword"
    @playSound "reward"

    You have earned 100 gold!
end

# Start conversation
@greetPlayer

Elder: So, what do you say?

switch (playerChoice)
    case 1
        @giveQuest
        Elder: Good luck, hero!
        @fadeOut

    case 2
        Elder: I understand. Come back if you change your mind.
        @endDialogue

    case 3
        Elder: The market is just down the road.
end

# Check quest status later
if (questCompleted and not hasReceivedReward)
    @questReward
    hasReceivedReward = true
elseif (questCompleted)
    Elder: Thanks again for your help!
else
    Elder: Have you dealt with those bandits yet?
end
```

### 🎮 Usage in Haxe

```haxe
import nz.dialogue.tokenizer.Tokenizer;
import nz.dialogue.parser.Parser;
import nz.dialogue.executor.Executor;

class DialogueSystem {
    var executor:Executor;

    public function loadDialogue(filename:String) {
        var script = sys.io.File.getContent(filename);

        var tokenizer = new Tokenizer(script);
        var tokens = tokenizer.tokenize();

        var parser = new Parser(tokens);
        var blocks = parser.parse();

        executor = new Executor(blocks);
    }

    public function update() {
        if (executor.hasNext()) {
            var result = executor.nextExecute();

            switch (result) {
                case ERDialog(text):
                    // Show dialogue text to player
                    showDialogueBox(text);

                case ERAtCall(command, args):
                    // Handle game commands
                    handleCommand(command, args);

                case ERVar(name, value):
                    // Variable was set
                    trace('Variable $name = $value');

                default:
                    // Other execution results
            }
        }
    }

    function handleCommand(cmd:String, args:Array<Dynamic>) {
        switch (cmd) {
            case "showQuestUI":
                displayQuest(args[0]);
            case "giveItem":
                addToInventory(args[0]);
            case "playSound":
                playAudio(args[0]);
            case "fadeOut":
                fadeScreen();
        }
    }
}
```

---

## 🎬 Nz-Cinematic _(Coming Soon)_

A specialized language for cutscenes, camera movements, and cinematic sequences.

### 🎯 Planned Features

- 🎥 Camera control and movements
- 🎭 Actor positioning and animation
- ⏱️ Timeline-based sequencing
- 🎵 Audio and music triggers
- 💫 Visual effects and transitions
- 🎬 Scene composition

---

## 📦 Installation

### Via Haxelib

```bash
haxelib git nzlang-suite https://github.com/senioritaelizabeth/Nz-Lang.git
```

### In your `.hxml` file

```hxml
-lib nzlang-suite
```

---

## 🧪 Testing

### Test Nz-Script (30 tests)

```bash
haxe test.hxml
```

Tests include:

- ✅ Arithmetic operations (+, -, \*, /, %)
- ✅ Variables (let, var, const)
- ✅ Functions and recursion
- ✅ Lambda expressions
- ✅ Arrays and dictionaries
- ✅ String methods (upper, lower)
- ✅ Number methods (floor, round, abs)
- ✅ Control flow (if/else, while, for)
- ✅ All comparison operators
- ✅ All logical operators

### Test Nz-Dialogue (42 tests)

```bash
cd tests
haxe all.hxml
```

Tests include:

- ✅ Variable declarations and assignments
- ✅ Function definitions and calls
- ✅ @Commands
- ✅ Dialogue flow
- ✅ Comparison operators
- ✅ Logical operators (&&, ||, !, and, or, not)
- ✅ Boolean handling
- ✅ Complex conditions
- ✅ Control flow (if/elseif/else/switch)

---

## 📖 Examples

### Run Nz-Script Example

```bash
haxe run_example.hxml
```

The example demonstrates:

- Variables and constants
- All arithmetic operations
- String and number methods
- Arrays with push/pop
- Dictionaries with key access
- If/else conditionals
- While loops
- For loops
- Functions with parameters
- Lambda expressions
- Recursion (factorial, fibonacci)
- All operators

### Try Nz-Dialogue Examples

Check the `tests/all_tests.dia` file for a comprehensive dialogue example with:

- Variable management
- Function calls
- Branching dialogues
- @Commands integration
- Complex conditionals

---

## 📁 Project Structure

```
nzlang-suite/
├── src/nz/
│   ├── script/           # Nz-Script bytecode language
│   │   ├── Tokenizer.hx
│   │   ├── Parser.hx
│   │   ├── Compiler.hx
│   │   ├── VM.hx
│   │   ├── Interpreter.hx
│   │   ├── Bytecode.hx  # Opcode definitions
│   │   ├── AST.hx       # Syntax tree types
│   │   └── Token.hx
│   │
│   ├── dialogue/         # Nz-Dialogue system
│   │   ├── tokenizer/
│   │   ├── parser/
│   │   ├── executor/
│   │   └── storage/
│   │
│   └── cinematic/        # Nz-Cinematic (coming soon)
│       └── README.md
│
├── example.nzs           # Complete Nz-Script example
├── RunExample.hx         # Example runner
├── TestAll.hx            # Test suite for Nz-Script
└── tests/
    └── all_tests.dia     # Dialogue test suite
```

---

## 🎯 Use Cases

### Nz-Script is Perfect For:

- 🎮 Game logic and mechanics
- 🔧 Configuration with dynamic logic
- 🎲 Procedural generation rules
- 🤖 AI behavior scripts
- ⚙️ Mod support and extensibility
- 📚 Educational programming

### Nz-Dialogue is Perfect For:

- 💬 RPG dialogue systems
- 📖 Interactive fiction
- 🎭 Visual novels
- 🗺️ Quest systems
- 📋 Tutorial sequences
- 🎬 Story-driven games

---

## 🛠️ API Reference

### Nz-Script API

```haxe
// Create interpreter
var interp = new Interpreter(debug:Bool = false);

// Execute script
var result:Value = interp.run(source:String, scriptName:String = "script");

// Access VM
var vm:VM = interp.vm;

// Variables
vm.variables.set("key", VNumber(42));
var value:Value = vm.variables.get("key");

// Value types
VNumber(v:Float)
VString(v:String)
VBool(v:Bool)
VNull
VArray(elements:Array<Value>)
VDict(map:Map<String, Value>)
VFunction(func:FunctionChunk, closure:Map<String, Value>)
VNativeFunction(name:String, arity:Int, fn:Array<Value>->Value)
```

### Nz-Dialogue API

```haxe
// Tokenizer
var tokenizer = new Tokenizer(source:String);
var tokens:Array<TokenPos> = tokenizer.tokenize();

// Parser
var parser = new Parser(tokens:Array<TokenPos>);
var blocks:Array<Block> = parser.parse();

// Executor
var executor = new Executor(blocks:Array<Block>);

// Execution
executor.hasNext():Bool
executor.nextExecute():ExecutionResult
executor.reset():Void
executor.callFunction(name:String):Void

// Variable access
executor.getVariable(name:String):Dynamic
executor.setVariable(name:String, value:Dynamic):Void
```

---

## 🌟 Why Choose NzLang Suite?

| Feature                | Benefit                                         |
| ---------------------- | ----------------------------------------------- |
| 🚀 **Easy to Learn**   | Clean, minimal syntax                           |
| ⚡ **Fast Execution**  | Bytecode compilation for performance            |
| 🔧 **Flexible**        | Three specialized languages for different needs |
| 🎯 **Purpose-Built**   | Each language optimized for its domain          |
| 📦 **Haxe Native**     | Seamless integration with Haxe projects         |
| 🐛 **Debuggable**      | Full line/column tracking                       |
| 🧪 **Battle-Tested**   | 72+ tests across all modules                    |
| 📖 **Well Documented** | Complete examples and guides                    |
| 🆓 **Free & Open**     | No restrictions, use anywhere                   |

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

- 🐛 Report bugs and issues
- ✨ Propose new features
- 📝 Improve documentation
- 🧪 Add more tests
- 💻 Submit pull requests

### Development

```bash
# Clone the repository
git clone https://github.com/senioritaelizabeth/Nz-Lang.git

# Run tests
haxe test.hxml

# Run example
haxe run_example.hxml
```

---

## 📄 License

Apache 2.0 License - Free to use in your projects with no restrictions.

---

## 🙏 Credits

Created with ❤️ by [@senioritaelizabeth](https://github.com/senioritaelizabeth)

Built for the Haxe community

---

## 🔗 Links

- [Documentation](src/nz/README.md)
- [Nz-Script Guide](src/nz/script/README.md)
- [Nz-Dialogue Guide](src/nz/dialogue/README.md)
- [Issue Tracker](https://github.com/senioritaelizabeth/Nz-Lang/issues)

---

Made with ❤️ for game developers and interactive storytellers
