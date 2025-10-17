# Nz-Dialogue Source Structure

This directory contains the source code for the Nz-Dialogue system, organized into logical modules.

## Directory Structure

```
src/nz/
├── tokenizer/          # Tokenization components
│   ├── Token.hx       # Token types and TokenPos definition
│   └── Tokenizer.hx   # Converts source code to tokens
│
├── parser/            # Parsing components
│   ├── Block.hx       # AST block types
│   └── Parser.hx      # Converts tokens to AST
│
├── executor/          # Execution engine
│   └── Executor.hx    # Executes dialogue code
│
├── storage/           # Serialization and storage
│   └── TokenStorage.hx # Saves/reconstructs code from tokens
│
└── Dialogue.hx        # Main API exports
```

## Module Overview

### Tokenizer

- **Purpose**: Lexical analysis
- **Input**: Raw dialogue source code (`.dia` files)
- **Output**: Stream of tokens
- **Main classes**:
  - `Token`: Enum representing all token types
  - `Tokenizer`: Converts source code into tokens

### Parser

- **Purpose**: Syntax analysis
- **Input**: Token stream
- **Output**: Abstract Syntax Tree (AST)
- **Main classes**:
  - `Block`: Enum representing AST nodes
  - `Parser`: Converts tokens into executable blocks

### Executor

- **Purpose**: Runtime execution
- **Input**: AST blocks
- **Output**: Executes dialogue with control flow
- **Main classes**:
  - `Executor`: Manages execution, variables, and functions
  - `ExecuteResult`: Represents execution results
  - `CallbackHandler`: Interface for custom @commands

### Storage

- **Purpose**: Code serialization
- **Input**: Token stream
- **Output**: Reconstructed source code
- **Main classes**:
  - `TokenStorage`: Saves tokens as `.dia` format

## Usage

### Simple Usage (Recommended)

```haxe
import nz.tokenizer.Tokenizer;
import nz.parser.Parser;
import nz.executor.Executor;

var tokenizer = new Tokenizer(sourceCode);
var tokens = tokenizer.tokenize();

var parser = new Parser(tokens);
var blocks = parser.parse();

var executor = new Executor(blocks);
while (executor.hasNext()) {
    var result = executor.nextExecute();
    // Handle result...
}
```

## Design Principles

1. **Separation of Concerns**: Each module has a single responsibility
2. **Clear Data Flow**: tokenizer → parser → executor
3. **Extensibility**: Easy to add new features to each module
4. **Type Safety**: Strong typing throughout the pipeline
5. **Documentation**: Each class has clear purpose and usage

## Adding New Features

- **New token types**: Add to `tokenizer/Token.hx`
- **New syntax**: Add to `parser/Block.hx` and update `Parser.hx`
- **New execution behavior**: Update `executor/Executor.hx`
- **New storage formats**: Add to or extend `storage/` module
