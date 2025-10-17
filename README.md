# Nz-Dialogue

A simple and flexible dialogue scripting language for Haxe projects. Perfect for games, interactive stories, or any project that needs a clean way to manage conversations and script flow.

[Leer en Español](README_ES.md)

## What is this?

Nz-Dialogue is a scripting system that lets you write dialogue and game logic in simple `.dia` files. It handles variables, functions, conditionals, and custom commands - all with a syntax that's easy to read and write.

## Quick Start

### Installation

1. Add this to your project:

```bash
haxelib git nz-dialogue https://github.com/senioritaelizabeth/Nz-Dialogue.git
```

2. Add it to your `.hxml` file:

```
-lib nz-dialogue
```

### Basic Usage

Here's how to run a dialogue script:

```haxe
import nz.tokenizer.Tokenizer;
import nz.parser.Parser;
import nz.executor.Executor;

// Load your script
var script = sys.io.File.getContent("dialogue.dia");

// Process it
var tokenizer = new Tokenizer(script);
var tokens = tokenizer.tokenize();

var parser = new Parser(tokens);
var blocks = parser.parse();

var executor = new Executor(blocks);

// Execute step by step
while (executor.hasNext()) {
    var result = executor.nextExecute();

    switch (result) {
        case ERDialog(text):
            trace("Character says: " + text);

        case ERAtCall(command, args):
            trace("Command: " + command);
            // Handle your custom commands here

        case ERVar(name, value):
            trace("Variable set: " + name + " = " + value);

        default:
            // Other execution results
    }
}
```

## Writing Scripts

### Comments

```dia
# This is a comment
# Comments start with # and are ignored during execution
```

### Variables

```dia
var playerName = "Alex"
var health = 100
var isAlive = true
```

### Dialog Lines

Just write text directly - any line that isn't a command or keyword is treated as dialogue:

```dia
Hello there!
Welcome to our game.
How are you doing today?
```

### Functions

Define reusable blocks of code:

```dia
func greetPlayer
    Hello there, adventurer!
    Ready for your quest?
end

func healPlayer
    Your wounds have been healed.
    @playSound "heal"
end
```

Call them with `@`:

```dia
@greetPlayer
@healPlayer
```

### Conditionals

```dia
if (health > 50)
    You're looking healthy!
elseif (health > 20)
    You could use some rest.
else
    You're in critical condition!
end
```

### Switch Statements

```dia
switch (playerChoice)
    case 1
        You chose option 1.
        @doSomething
    case 2
        You chose option 2.
        @doAnotherThing
    case 3
        You chose option 3.
end
```

### Custom Commands

Use `@` to call custom commands in your game:

```dia
@playSound "victory"
@showPortrait "hero_happy"
@loadScene "forest" fast
@heal_player 50
```

Handle these in your code with a callback:

```haxe
executor.setCallbackHandler({
    handleAtCall: function(command:String, args:Array<Dynamic>):Void {
        switch (command) {
            case "playSound":
                // Play the sound
            case "showPortrait":
                // Show character portrait
            case "loadScene":
                // Load the scene
        }
    }
});
```

## Complete Example

Here's a full script showing different features:

```dia
# RPG Dialog Example

var playerName = "Hero"
var health = 80
var hasKey = false

func enterTown
    Welcome to Riverside Town!
    @playMusic "town_theme"
    @showBackground "town_square"
end

# Start of the story
@enterTown

if (health > 50)
    You arrive feeling strong and ready.
else
    You limp into town, barely standing.
    Maybe you should find an inn...
end

The guard approaches you.
Guard: Halt! State your business.

switch (playerChoice)
    case 1
        I'm here to trade goods.
        Guard: Very well, the market is open.
        @openShop
    case 2
        I'm looking for adventure!
        Guard: Check the tavern for quests.
        @showTavern
    case 3
        Just passing through.
        Guard: Safe travels then.
end

@enterTown
```

## API Reference

### Tokenizer

Converts source code into tokens:

```haxe
var tokenizer = new Tokenizer(sourceCode);
var tokens = tokenizer.tokenize();
```

### Parser

Converts tokens into an executable AST:

```haxe
var parser = new Parser(tokens);
var blocks = parser.parse();
```

### Executor

Executes the script step by step:

```haxe
var executor = new Executor(blocks);

// Check if there are more steps
if (executor.hasNext()) {
    var result = executor.nextExecute();
}

// Reset to beginning
executor.reset();

// Call a specific function
executor.callFunction("greetPlayer");

// Get/Set variables
var health = executor.getVariable("health");
executor.setVariable("health", 100);
```

### Execution Results

`nextExecute()` returns different results based on what was executed:

- `ERDialog(text)` - A dialogue line
- `ERComment(text)` - A comment
- `ERVar(name, value)` - Variable declaration
- `ERFunc(name)` - Function definition
- `ERFuncCall(name)` - Function call
- `ERIf(condition, result)` - If statement
- `ERSwitch(value, result)` - Switch statement
- `ERReturn` - Return statement
- `ERAtCall(command, args)` - Custom command
- `EREnd` - End of execution

## Token Storage

You can reconstruct the original script from tokens:

```haxe
var storage = new TokenStorage();
storage.save(tokens, "output.dia");
```

This preserves the structure and formatting of your original script.

## Project Structure

```
src/nz/
├── tokenizer/      # Lexical analysis
├── parser/         # Syntax analysis and AST
├── executor/       # Runtime execution
└── storage/        # Code reconstruction
```

Check the [src/README.md](src/README.md) for more details on the architecture.

## Examples

Check out the `test/examples/` folder for more complete examples:

- `example.dia` - Shows all language features
- `function_test.dia` - Function definition and calling
- `flow_test.dia` - Control flow and execution order

## Running Tests

```bash
haxe test.hxml
```

All tests should pass with output showing the execution flow and results.

## License

Feel free to use this in your projects. No restrictions.

## Contributing

Found a bug or want to add a feature? Feel free to open an issue or PR. Keep it simple and make sure the tests pass.
