# Nz-Script

Sistema de scripting con compilación a bytecode para Haxe.

## Características

- **Compilación a bytecode** - Alto rendimiento
- **Tres tipos de variables**:
  - `let` - Variables temporales (solo dentro del script)
  - `var` - Variables modificables desde fuera
  - `const` - Constantes inmutables
- **Funciones con closures y lambdas**
- **Tipos de datos**: Number, String, Bool, Array, Dictionary
- **Control de flujo**: if/else, while, for, break, continue
- **Métodos en tipos nativos**: `(100 / 2).floor()`, `"hello".upper()`
- **Interoperabilidad con Haxe**

## Instalación

```haxe
import nz.script.Interpreter;
import nz.script.Bytecode;

var interp = new Interpreter();
```

## Sintaxis Básica

### Variables

```javascript
let x = 10; // Variable temporal (solo script)
var y = 20; // Variable modificable desde Haxe
const PI = 3.14159; // Constante inmutable

// Con tipos explícitos
let age: Number = 25;
var name: String = "Alice";
```

### Funciones

```javascript
// Función básica
func greet(name: String) -> String {
    return "Hello, " + name
}

// Función con múltiples parámetros
func add(a: Number, b: Number) -> Number {
    return a + b
}

// Función sin retorno explícito
func sayHi() {
    print("Hi!")
}
```

### Lambdas

```javascript
// Lambda simple (expresión)
let square = (x: Number) -> x * x

// Lambda con cuerpo
let greet = (name: String) -> {
    let message = "Hello, " + name
    return message
}

// Uso
let result = square(5)  // 25
```

### Métodos en tipos nativos

```javascript
// Number
let x = (100 / 2).floor()        // 50
let y = 3.7.ceil()               // 4
let z = -5.abs()                 // 5
let w = 16.sqrt()                // 4

// Encadenamiento
let result = (10.5).add(5).mul(2).floor()  // 31

// String
let upper = "hello".upper()      // "HELLO"
let lower = "WORLD".lower()      // "world"
let trimmed = "  hi  ".trim()    // "hi"

// Array
let arr = [1, 2, 3]
let len = arr.length             // 3
arr.push(4)                      // [1, 2, 3, 4]
let last = arr.pop()             // 4
```

### Arrays

```javascript
let numbers = [1, 2, 3, 4, 5];
let first = numbers[0]; // 1
numbers[1] = 10; // [1, 10, 3, 4, 5]

// Arrays mixtos
let mixed = [1, "hello", true, null];

// Arrays anidados
let matrix = [
  [1, 2],
  [3, 4],
];
```

### Diccionarios

```javascript
let person = {
  name: "Alice",
  age: 25,
  active: true,
};

// Acceso
let name = person["name"]; // "Alice"
let age = person.age; // 25

// Modificación
person["age"] = 26;
person.city = "Madrid";

// Diccionarios anidados
let config = {
  server: {
    host: "localhost",
    port: 8080,
  },
};
```

### Control de flujo

```javascript
// If/Else
if (x > 10) {
  print("x is greater than 10");
} else if (x > 5) {
  print("x is greater than 5");
} else {
  print("x is small");
}

// While
let i = 0;
while (i < 10) {
  print(i);
  i = i + 1;
}

// For (sobre arrays)
let numbers = [1, 2, 3, 4, 5];
for (num in numbers) {
  print(num);
}

// Break y Continue
let sum = 0;
for (i in [1, 2, 3, 4, 5]) {
  if (i == 3) {
    continue; // Saltar 3
  }
  if (sum > 7) {
    break; // Salir del loop
  }
  sum = sum + i;
}
```

### Operadores

```javascript
// Aritméticos
let a = 10 + 5; // 15
let b = 10 - 5; // 5
let c = 10 * 5; // 50
let d = 10 / 5; // 2
let e = 10 % 3; // 1

// Comparación
10 == 10; // true
10 != 5; // true
10 > 5; // true
10 < 5; // false
10 >= 10; // true
10 <= 10; // true

// Lógicos
true && false; // false
true || false; // true
!true; // false

// Bitwise
5 & 3; // 1
5 | 3; // 7
5 ^ 3; // 6
~5; // -6
5 << 1; // 10
5 >> 1; // 2
```

## Uso desde Haxe

### Ejemplo básico

```haxe
import nz.script.Interpreter;
import nz.script.Bytecode;

class Main {
    static function main() {
        var interp = new Interpreter();

        // Ejecutar código
        var result = interp.run('
            let x = 10
            let y = 20
            x + y
        ');

        trace(result);  // VNumber(30)
    }
}
```

### Compartir variables

```haxe
var interp = new Interpreter();

// Establecer variables desde Haxe
interp.setVar("playerHealth", VNumber(100));
interp.setVar("playerName", VString("Hero"));

// Usar en el script
interp.run('
    var damage = 25
    playerHealth = playerHealth - damage
    print(playerName + " took " + damage + " damage!")
');

// Leer variables desde Haxe
var health = interp.getVar("playerHealth");
trace(health);  // VNumber(75)
```

### Registrar funciones nativas

```haxe
var interp = new Interpreter();

// Registrar función de Haxe
interp.registerFunction("random", 2, (args) -> {
    var min = switch (args[0]) {
        case VNumber(n): n;
        default: 0.0;
    }
    var max = switch (args[1]) {
        case VNumber(n): n;
        default: 1.0;
    }
    return VNumber(min + Math.random() * (max - min));
});

// Usar en el script
interp.run('
    let randomValue = random(1, 100)
    print("Random: " + randomValue)
');
```

### Llamar funciones del script

```haxe
var interp = new Interpreter();

// Definir función en el script
interp.run('
    func calculate(a: Number, b: Number) -> Number {
        return (a + b) * 2
    }
');

// Llamar desde Haxe
var result = interp.callFunction("calculate", [
    VNumber(10),
    VNumber(5)
]);

trace(result);  // VNumber(30)
```

### Modo debug

```haxe
var interp = new Interpreter(true);  // Activa debug
interp.run('let x = 10 + 20');

// Muestra:
// === TOKENS ===
// === AST ===
// === BYTECODE ===
// === RESULT ===
```

## Ejemplos completos

### Sistema de combate

```javascript
var playerHP = 100
var enemyHP = 80

func attack(attacker: String, target: String, damage: Number) -> String {
    if (attacker == "player") {
        enemyHP = enemyHP - damage
        return "Player deals " + damage + " damage! Enemy HP: " + enemyHP
    } else {
        playerHP = playerHP - damage
        return "Enemy deals " + damage + " damage! Player HP: " + playerHP
    }
}

func isGameOver() -> Bool {
    return playerHP <= 0 || enemyHP <= 0
}

// Simulación de combate
let turn = 0
while (!isGameOver()) {
    if (turn % 2 == 0) {
        let dmg = (10 + turn).floor()
        print(attack("player", "enemy", dmg))
    } else {
        let dmg = 8
        print(attack("enemy", "player", dmg))
    }
    turn = turn + 1
}

if (playerHP > 0) {
    print("Player wins!")
} else {
    print("Enemy wins!")
}
```

### Procesamiento de datos

```javascript
let data = [
    {"name": "Alice", "score": 85},
    {"name": "Bob", "score": 92},
    {"name": "Charlie", "score": 78}
]

func getAverageScore(students) -> Number {
    let total = 0
    let count = 0

    for (student in students) {
        total = total + student.score
        count = count + 1
    }

    return (total / count).floor()
}

func getTopStudent(students) -> String {
    let topName = ""
    let topScore = 0

    for (student in students) {
        if (student.score > topScore) {
            topScore = student.score
            topName = student.name
        }
    }

    return topName
}

let avg = getAverageScore(data)
let top = getTopStudent(data)

print("Average score: " + avg)
print("Top student: " + top)
```

### Calculadora con lambdas

```javascript
let operations = {
    "add": (a, b) -> a + b,
    "sub": (a, b) -> a - b,
    "mul": (a, b) -> a * b,
    "div": (a, b) -> a / b
}

func calculate(op: String, a: Number, b: Number) -> Number {
    let operation = operations[op]
    return operation(a, b)
}

let result1 = calculate("add", 10, 5)   // 15
let result2 = calculate("mul", 10, 5)   // 50
let result3 = calculate("div", 10, 5)   // 2
```

## Arquitectura

El sistema sigue esta pipeline:

```
Source Code
    ↓
Tokenizer (Token.hx, Tokenizer.hx)
    ↓
Tokens
    ↓
Parser (AST.hx, Parser.hx)
    ↓
Abstract Syntax Tree
    ↓
Compiler (Compiler.hx)
    ↓
Bytecode (Bytecode.hx)
    ↓
Virtual Machine (VM.hx)
    ↓
Result
```

### Componentes

- **Token.hx** - Define tokens y operadores
- **Tokenizer.hx** - Convierte código fuente en tokens
- **AST.hx** - Define el Abstract Syntax Tree
- **Parser.hx** - Convierte tokens en AST
- **Bytecode.hx** - Define instrucciones de bytecode
- **Compiler.hx** - Compila AST a bytecode
- **VM.hx** - Máquina virtual que ejecuta bytecode
- **Interpreter.hx** - API principal

## Tipos de valores

```haxe
enum Value {
    VNumber(v:Float);
    VString(v:String);
    VBool(v:Bool);
    VNull;
    VArray(elements:Array<Value>);
    VDict(map:Map<String, Value>);
    VFunction(func:FunctionChunk, closure:Map<String, Value>);
    VNativeFunction(name:String, arity:Int, fn:Array<Value>->Value);
}
```

## Limitaciones actuales

- No hay garbage collection explícito (se usa el GC de Haxe)
- Los diccionarios solo soportan claves String
- No hay soporte para clases/objetos custom
- No hay manejo de excepciones con try/catch (planeado)
- No hay imports/modules (planeado)

## Futuras características

- [ ] Sistema de módulos/imports
- [ ] Try/catch para manejo de errores
- [ ] Operadores de asignación compuesta (+=, -=, etc.)
- [ ] Destructuring de arrays y dicts
- [ ] Spread operator (...)
- [ ] String templates
- [ ] Rangos (1..10)
- [ ] Comprensiones de listas
- [ ] Pattern matching
- [ ] Async/await
- [ ] `@append_haxe` para código Haxe inline

## Licencia

Mismo que el proyecto Nz-Dialogue. Module

(Coming soon)

This module will provide general-purpose scripting for game logic and events.

## Planned Features

- Event system
- Trigger conditions
- Entity behaviors
- Custom game logic
- State machines
- Timer/scheduler system

## Status

Currently in planning phase. Check back later for updates.
