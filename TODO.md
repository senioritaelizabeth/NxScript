## TODO

### Core

* [x] optimize `getmembers` / `setmembers` — dict methods now use method dispatch (keys, values, has, remove, set, size)
* [ ] improve function call syntax `.()`
* [ ] add optional type hints
* [x] improve error messages with line + column — stack traces already include line:col
* [ ] support nested scopes for locals
* [ ] optimize variable lookup (locals → globals)
* [ ] optimize method calling

### Sintaxis

* [x] add shorthand lambda syntax — `x => expr` (single arg, no parens) and `(x, y) => expr`
* [x] allow trailing commas — in function calls, params, arrays, and dicts
* [x] optional semicolons — already supported (strictSemicolons=false by default)
* [ ] pattern matching / `match`
* [ ] destructuring assignments
* [x] better string interpolation — backtick template strings: `Hello ${name}!`

### Runtime / VM

* [x] bytecode optimization pass — constant folding already implemented in Compiler
* [x] constant folding — implemented for numeric, string, boolean, bitwise expressions
* [ ] tail call optimization
* [ ] improve stack safety
* [ ] faster property access

### Security

* [ ] sandboxed execution mode
* [ ] safeCall improvements
* [x] error stack traces — formatStackTrace() with line:col per frame

### Tooling

* [ ] formatter for `.nx` (fixes)
* [ ] update syntax highlighting (VSCode)
* [ ] update language server (LSP)
* [ ] update documentation generator

### Life Quality

* [x] standard library basics — print, println, range, str, int, float, abs, floor, ceil, round, sqrt, pow, min, max, random, sin, cos, tan, PI, INF, NAN
* [x] array methods — map, filter, reduce, forEach, find, findIndex, every, some, slice, concat, flat, copy, sort, sortBy
* [x] string methods — startsWith, endsWith, replace, replaceAll, repeat, padStart, padEnd
* [x] dict methods — keys(), values(), has(), remove(), set(), size()
* [ ] debug mode
* [ ] REPL
