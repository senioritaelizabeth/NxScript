# NzLang Suite 🚀

> Una suite completa de lenguajes de scripting para proyectos Haxe

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Haxe](https://img.shields.io/badge/language-Haxe-orange.svg)](https://haxe.org)

[🇬🇧 Read in English](README.md)

## 📖 ¿Qué es NzLang Suite?

**NzLang Suite** es una colección de tres lenguajes de scripting especializados diseñados para desarrollo de juegos y aplicaciones interactivas. Cada lenguaje está optimizado para casos de uso específicos mientras mantiene una sintaxis consistente y fácil de aprender.

### Los Tres Lenguajes

| Lenguaje | Extensión | Propósito | Estado |
|----------|-----------|-----------|--------|
| **Nz-Script** | `.nzs` | Scripting general con bytecode | ✅ Listo |
| **Nz-Dialogue** | `.dia` | Diálogos y conversaciones interactivas | ✅ Listo |
| **Nz-Cinematic** | `.cin` | Cinemáticas y secuencias de cámara | 🚧 Próximamente |

---

## ⚡ Nz-Script - Lenguaje de Bytecode

Un poderoso lenguaje de scripting de propósito general con compilación a bytecode, VM basada en stack y características modernas.

### ✨ Características Principales

- 🔢 **Bytecode Hexadecimal** - Opcodes de 0x00 a 0xFF
- 📦 **VM basada en Stack** - Ejecución rápida y eficiente
- 🔤 **Tres Tipos de Variables**
  - `let` - Variables locales al script
  - `var` - Variables modificables externamente
  - `const` - Constantes inmutables
- ⚙️ **Funciones y Lambdas** - Funciones de primera clase con closures
- 📊 **Estructuras de Datos** - Arrays y Diccionarios
- 🎯 **Métodos de Tipos** - Métodos de String y Number integrados
- 🔄 **Control de Flujo** - if/else, while, for loops
- ♻️ **Recursión** - Soporte completo de funciones recursivas
- 🐛 **Info de Debug** - Seguimiento de línea/columna en salida

### 📝 Ejemplo de Sintaxis

```nzs
# Variables y Constantes
let nombre = "Héroe"
var salud = 100
const SALUD_MAXIMA = 100

# Funciones
func curar(cantidad) {
    salud = salud + cantidad
    if (salud > SALUD_MAXIMA) {
        salud = SALUD_MAXIMA
    }
    return salud
}

# Lambdas
let doble = (x) -> x * 2
let cuadrado = (x) -> x * x

print("Salud: " + salud)
curar(25)
print("Después de curar: " + salud)

# Arrays
let inventario = ["espada", "escudo", "poción"]
inventario.push("llave")

for (item in inventario) {
    print("- " + item)
}

# Diccionarios
let jugador = {
    "nombre": "Héroe",
    "nivel": 5,
    "clase": "Guerrero"
}

print("Jugador: " + jugador["nombre"])
print("Nivel: " + jugador["nivel"])

# Recursión
func fibonacci(n) {
    if (n <= 1) {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

print("Fibonacci(10): " + fibonacci(10))

# Métodos de String y Number
let mensaje = "hola mundo"
print(mensaje.upper())  # "HOLA MUNDO"
print(mensaje.lower())  # "hola mundo"

let pi = 3.14159
print(pi.floor())  # 3
print(pi.round())  # 3
```

### 🎮 Uso en Haxe

```haxe
import nz.script.Interpreter;

class Juego {
    static function main() {
        // Crear intérprete
        var interp = new Interpreter(false);
        
        // Cargar y ejecutar script
        var script = sys.io.File.getContent("juego.nzs");
        var resultado = interp.run(script, "juego.nzs");
        
        // Acceder/modificar variables desde Haxe
        interp.vm.variables.set("salud_jugador", VNumber(100));
        var salud = interp.vm.variables.get("salud_jugador");
        
        // Llamar funciones del script desde Haxe
        trace("Script ejecutado exitosamente!");
    }
}
```

### 📍 Seguimiento de Ubicación

Nz-Script rastrea números de línea y columna para debugging:

```
[juego.nzs - 15:1] Salud: 100
[juego.nzs - 17:1] Después de curar: 125
[juego.nzs - 23:5] - espada
[juego.nzs - 23:5] - escudo
```

---

## 💬 Nz-Dialogue - Sistema de Diálogos Interactivos

Un lenguaje especializado para escribir diálogos ramificados, conversaciones y flujos narrativos.

### ✨ Características Principales

- 💭 **Escritura Simple de Diálogos** - Solo escribe texto naturalmente
- 🔀 **Lógica Ramificada** - Declaraciones if/else, switch/case
- 🎯 **Funciones** - Bloques de diálogo reutilizables
- 📞 **Comandos Personalizados** - @comandos para integración con el juego
- 🔢 **Variables** - Seguimiento del estado del diálogo
- 🎲 **Operadores** - Operadores aritméticos y lógicos completos
- 🌐 **Operadores de Palabras** - Usa `and`, `or`, `not` junto a símbolos

### 📝 Ejemplo de Diálogo

```dia
# Diálogo de Misión RPG

var nombreJugador = "Héroe"
var misionCompletada = false
var oro = 0

func saludarJugador
    ¡Bienvenido, valiente aventurero!
    Mi nombre es el Anciano Thorne.
    ¿Qué te trae a nuestra aldea?
end

func darMision
    Tenemos un problema con bandidos cerca.
    ¿Puedes ayudarnos?
    
    @mostrarMisionUI "Derrotar a los Bandidos"
    misionCompletada = false
end

func recompensaMision
    ¡Gracias por tu ayuda!
    Aquí está tu recompensa.
    
    oro = oro + 100
    @darObjeto "Espada Mágica"
    @reproducirSonido "recompensa"
    
    ¡Has ganado 100 de oro!
end

# Iniciar conversación
@saludarJugador

Anciano: Entonces, ¿qué dices?

switch (eleccionJugador)
    case 1
        @darMision
        Anciano: ¡Buena suerte, héroe!
        @fundirAPantalla
        
    case 2
        Anciano: Entiendo. Vuelve si cambias de opinión.
        @finalizarDialogo
        
    case 3
        Anciano: El mercado está justo al final del camino.
end

# Verificar estado de la misión más tarde
if (misionCompletada and not haRecibidoRecompensa)
    @recompensaMision
    haRecibidoRecompensa = true
elseif (misionCompletada)
    Anciano: ¡Gracias de nuevo por tu ayuda!
else
    Anciano: ¿Ya te has ocupado de esos bandidos?
end
```

### 🎮 Uso en Haxe

```haxe
import nz.dialogue.tokenizer.Tokenizer;
import nz.dialogue.parser.Parser;
import nz.dialogue.executor.Executor;

class SistemaDialogo {
    var executor:Executor;
    
    public function cargarDialogo(archivo:String) {
        var script = sys.io.File.getContent(archivo);
        
        var tokenizer = new Tokenizer(script);
        var tokens = tokenizer.tokenize();
        
        var parser = new Parser(tokens);
        var bloques = parser.parse();
        
        executor = new Executor(bloques);
    }
    
    public function actualizar() {
        if (executor.hasNext()) {
            var resultado = executor.nextExecute();
            
            switch (resultado) {
                case ERDialog(texto):
                    // Mostrar texto de diálogo al jugador
                    mostrarCuadroDialogo(texto);
                    
                case ERAtCall(comando, args):
                    // Manejar comandos del juego
                    manejarComando(comando, args);
                    
                case ERVar(nombre, valor):
                    // Variable fue establecida
                    trace('Variable $nombre = $valor');
                    
                default:
                    // Otros resultados de ejecución
            }
        }
    }
    
    function manejarComando(cmd:String, args:Array<Dynamic>) {
        switch (cmd) {
            case "mostrarMisionUI":
                mostrarMision(args[0]);
            case "darObjeto":
                agregarAInventario(args[0]);
            case "reproducirSonido":
                reproducirAudio(args[0]);
            case "fundirAPantalla":
                fundirPantalla();
        }
    }
}
```

---

## 🎬 Nz-Cinematic *(Próximamente)*

Un lenguaje especializado para cinemáticas, movimientos de cámara y secuencias cinematográficas.

### 🎯 Características Planeadas

- 🎥 Control y movimientos de cámara
- 🎭 Posicionamiento y animación de actores
- ⏱️ Secuenciación basada en timeline
- 🎵 Disparadores de audio y música
- 💫 Efectos visuales y transiciones
- 🎬 Composición de escenas

---

## 📦 Instalación

### Vía Haxelib

```bash
haxelib git nzlang-suite https://github.com/senioritaelizabeth/Nz-Lang.git
```

### En tu archivo `.hxml`

```hxml
-lib nzlang-suite
```

---

## 🧪 Pruebas

### Probar Nz-Script (30 pruebas)

```bash
haxe test.hxml
```

Las pruebas incluyen:
- ✅ Operaciones aritméticas (+, -, *, /, %)
- ✅ Variables (let, var, const)
- ✅ Funciones y recursión
- ✅ Expresiones lambda
- ✅ Arrays y diccionarios
- ✅ Métodos de string (upper, lower)
- ✅ Métodos de number (floor, round, abs)
- ✅ Control de flujo (if/else, while, for)
- ✅ Todos los operadores de comparación
- ✅ Todos los operadores lógicos

### Probar Nz-Dialogue (42 pruebas)

```bash
cd tests
haxe all.hxml
```

Las pruebas incluyen:
- ✅ Declaraciones y asignaciones de variables
- ✅ Definiciones y llamadas de funciones
- ✅ @Comandos
- ✅ Flujo de diálogo
- ✅ Operadores de comparación
- ✅ Operadores lógicos (&&, ||, !, and, or, not)
- ✅ Manejo de booleanos
- ✅ Condiciones complejas
- ✅ Control de flujo (if/elseif/else/switch)

---

## 📖 Ejemplos

### Ejecutar Ejemplo de Nz-Script

```bash
haxe run_example.hxml
```

El ejemplo demuestra:
- Variables y constantes
- Todas las operaciones aritméticas
- Métodos de string y number
- Arrays con push/pop
- Diccionarios con acceso por clave
- Condicionales if/else
- Bucles while
- Bucles for
- Funciones con parámetros
- Expresiones lambda
- Recursión (factorial, fibonacci)
- Todos los operadores

### Probar Ejemplos de Nz-Dialogue

Revisa el archivo `tests/all_tests.dia` para un ejemplo completo de diálogo con:
- Gestión de variables
- Llamadas a funciones
- Diálogos ramificados
- Integración de @Comandos
- Condicionales complejos

---

## 📁 Estructura del Proyecto

```
nzlang-suite/
├── src/nz/
│   ├── script/           # Lenguaje bytecode Nz-Script
│   │   ├── Tokenizer.hx
│   │   ├── Parser.hx
│   │   ├── Compiler.hx
│   │   ├── VM.hx
│   │   ├── Interpreter.hx
│   │   ├── Bytecode.hx  # Definiciones de opcode
│   │   ├── AST.hx       # Tipos de árbol sintáctico
│   │   └── Token.hx
│   │
│   ├── dialogue/         # Sistema Nz-Dialogue
│   │   ├── tokenizer/
│   │   ├── parser/
│   │   ├── executor/
│   │   └── storage/
│   │
│   └── cinematic/        # Nz-Cinematic (próximamente)
│       └── README.md
│
├── example.nzs           # Ejemplo completo de Nz-Script
├── RunExample.hx         # Ejecutor de ejemplos
├── TestAll.hx            # Suite de pruebas para Nz-Script
└── tests/
    └── all_tests.dia     # Suite de pruebas de diálogo
```

---

## 🎯 Casos de Uso

### Nz-Script es Perfecto Para:
- 🎮 Lógica y mecánicas de juego
- 🔧 Configuración con lógica dinámica
- 🎲 Reglas de generación procedural
- 🤖 Scripts de comportamiento de IA
- ⚙️ Soporte de mods y extensibilidad
- 📚 Programación educativa

### Nz-Dialogue es Perfecto Para:
- 💬 Sistemas de diálogo RPG
- 📖 Ficción interactiva
- 🎭 Novelas visuales
- 🗺️ Sistemas de misiones
- 📋 Secuencias de tutorial
- 🎬 Juegos narrativos

---

## 🛠️ Referencia de API

### API de Nz-Script

```haxe
// Crear intérprete
var interp = new Interpreter(debug:Bool = false);

// Ejecutar script
var resultado:Value = interp.run(source:String, scriptName:String = "script");

// Acceder a VM
var vm:VM = interp.vm;

// Variables
vm.variables.set("clave", VNumber(42));
var valor:Value = vm.variables.get("clave");

// Tipos de valores
VNumber(v:Float)
VString(v:String)
VBool(v:Bool)
VNull
VArray(elements:Array<Value>)
VDict(map:Map<String, Value>)
VFunction(func:FunctionChunk, closure:Map<String, Value>)
VNativeFunction(name:String, arity:Int, fn:Array<Value>->Value)
```

### API de Nz-Dialogue

```haxe
// Tokenizer
var tokenizer = new Tokenizer(source:String);
var tokens:Array<TokenPos> = tokenizer.tokenize();

// Parser
var parser = new Parser(tokens:Array<TokenPos>);
var bloques:Array<Block> = parser.parse();

// Executor
var executor = new Executor(bloques:Array<Block>);

// Ejecución
executor.hasNext():Bool
executor.nextExecute():ExecutionResult
executor.reset():Void
executor.callFunction(name:String):Void

// Acceso a variables
executor.getVariable(name:String):Dynamic
executor.setVariable(name:String, value:Dynamic):Void
```

---

## 🌟 ¿Por Qué Elegir NzLang Suite?

| Característica | Beneficio |
|----------------|-----------|
| 🚀 **Fácil de Aprender** | Sintaxis limpia y minimalista |
| ⚡ **Ejecución Rápida** | Compilación a bytecode para rendimiento |
| 🔧 **Flexible** | Tres lenguajes especializados para diferentes necesidades |
| 🎯 **Diseñado a Propósito** | Cada lenguaje optimizado para su dominio |
| 📦 **Nativo de Haxe** | Integración perfecta con proyectos Haxe |
| 🐛 **Debuggeable** | Seguimiento completo de línea/columna |
| 🧪 **Probado en Batalla** | 72+ pruebas en todos los módulos |
| 📖 **Bien Documentado** | Ejemplos y guías completas |
| 🆓 **Libre y Abierto** | Sin restricciones, úsalo donde quieras |

---

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Así es como puedes ayudar:

- 🐛 Reportar bugs e issues
- ✨ Proponer nuevas características
- 📝 Mejorar documentación
- 🧪 Agregar más pruebas
- 💻 Enviar pull requests

### Desarrollo

```bash
# Clonar el repositorio
git clone https://github.com/senioritaelizabeth/Nz-Lang.git

# Ejecutar pruebas
haxe test.hxml

# Ejecutar ejemplo
haxe run_example.hxml
```

---

## 📄 Licencia

Licencia Apache 2.0 - Libre para usar en tus proyectos sin restricciones.

---

## 🙏 Créditos

Creado con ❤️ por [@senioritaelizabeth](https://github.com/senioritaelizabeth)

Construido para la comunidad Haxe

---

## 🔗 Enlaces

- [Documentación](src/nz/README.md)
- [Guía de Nz-Script](src/nz/script/README.md)
- [Guía de Nz-Dialogue](src/nz/dialogue/README.md)
- [Rastreador de Issues](https://github.com/senioritaelizabeth/Nz-Lang/issues)

---

Hecho con ❤️ para desarrolladores de juegos y narradores interactivos
