# Dialogue Module

A complete dialogue scripting system for interactive conversations and narrative content.

## Structure

```
dialogue/
├── tokenizer/          # Converts source code to tokens
│   ├── Token.hx       # Token definitions
│   └── Tokenizer.hx   # Tokenization logic
│
├── parser/            # Converts tokens to AST
│   ├── Block.hx       # AST node types
│   └── Parser.hx      # Parsing logic
│
├── executor/          # Executes dialogue scripts
│   └── Executor.hx    # Execution engine
│
├── storage/           # Saves/reconstructs scripts
│   └── TokenStorage.hx # Code reconstruction
│
└── Dialogue.hx        # Main exports and legacy API
```

## Quick Start

```haxe
import nz.dialogue.tokenizer.Tokenizer;
import nz.dialogue.parser.Parser;
import nz.dialogue.executor.Executor;

var script = sys.io.File.getContent("dialogue.dia");

var tokenizer = new Tokenizer(script);
var tokens = tokenizer.tokenize();

var parser = new Parser(tokens);
var blocks = parser.parse();

var executor = new Executor(blocks);

while (executor.hasNext()) {
    var result = executor.nextExecute();
    // Handle execution results
}
```

## Features

- Variables (var name = value)
- Functions (func/end)
- Conditionals (if/elseif/else)
- Switch statements (switch/case)
- Custom commands (@command args)
- Dialog lines
- Comments (#)
- Step-by-step execution

## Documentation

See the main project README for complete usage examples and API reference.
