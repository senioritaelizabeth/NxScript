# Nz Framework Structure

This is the main source directory for the Nz framework, organized into three main modules:

## Modules

### dialogue/

The dialogue scripting system - handles conversation, variables, functions, and control flow.

**Use this for:** Interactive conversations, branching dialogue trees, RPG dialogue systems.

### cinematic/

(Coming soon) Cinematic and cutscene scripting.

**Use this for:** In-game cinematics, cutscenes, camera movements, timed sequences.

### script/

(Coming soon) General-purpose scripting for game logic.

**Use this for:** Game events, triggers, entity behaviors, custom game logic.

## Current Status

- **dialogue/** - Fully implemented and tested
- **cinematic/** - Planned
- **script/** - Planned

## Usage

Each module is self-contained and can be used independently:

```haxe
// Dialogue system
import nz.dialogue.tokenizer.Tokenizer;
import nz.dialogue.parser.Parser;
import nz.dialogue.executor.Executor;

// Future: Cinematic system
// import nz.cinematic.*;

// Future: Script system
// import nz.script.*;
```

See the README in each module folder for specific documentation.
