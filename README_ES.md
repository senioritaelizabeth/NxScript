# Nz-Dialogue

Un lenguaje de scripting para diálogos simple y flexible para proyectos en Haxe. Perfecto para juegos, historias interactivas, o cualquier proyecto que necesite una forma limpia de manejar conversaciones y flujo de scripts.

[Read in English](README.md)

## Qué es esto?

Nz-Dialogue es un sistema de scripting que te permite escribir diálogos y lógica de juego en archivos `.dia` simples. Maneja variables, funciones, condicionales, y comandos personalizados - todo con una sintaxis fácil de leer y escribir.

## Inicio Rápido

### Instalación

1. Agrega esto a tu proyecto:

```bash
haxelib git nz-dialogue https://github.com/senioritaelizabeth/Nz-Dialogue.git
```

2. Agrégalo a tu archivo `.hxml`:

```
-lib nz-dialogue
```

### Uso Básico

Así es como ejecutas un script de diálogo:

```haxe
import nz.tokenizer.Tokenizer;
import nz.parser.Parser;
import nz.executor.Executor;

// Carga tu script
var script = sys.io.File.getContent("dialogo.dia");

// Procésalo
var tokenizer = new Tokenizer(script);
var tokens = tokenizer.tokenize();

var parser = new Parser(tokens);
var blocks = parser.parse();

var executor = new Executor(blocks);

// Ejecuta paso a paso
while (executor.hasNext()) {
    var result = executor.nextExecute();

    switch (result) {
        case ERDialog(text):
            trace("El personaje dice: " + text);

        case ERAtCall(command, args):
            trace("Comando: " + command);
            // Maneja tus comandos personalizados aquí

        case ERVar(name, value):
            trace("Variable asignada: " + name + " = " + value);

        default:
            // Otros resultados de ejecución
    }
}
```

## Escribiendo Scripts

### Comentarios

```dia
# Esto es un comentario
# Los comentarios empiezan con # y se ignoran durante la ejecución
```

### Variables

```dia
var nombreJugador = "Alex"
var salud = 100
var estaVivo = true
```

### Líneas de Diálogo

Simplemente escribe texto directamente - cualquier línea que no sea un comando o palabra clave se trata como diálogo:

```dia
Hola!
Bienvenido a nuestro juego.
Cómo estás hoy?
```

### Funciones

Define bloques de código reutilizables:

```dia
func saludarJugador
    Hola, aventurero!
    Listo para tu misión?
end

func curarJugador
    Tus heridas han sido curadas.
    @playSound "heal"
end
```

Llámalas con `@`:

```dia
@saludarJugador
@curarJugador
```

### Condicionales

```dia
if (salud > 50)
    Te ves saludable!
elseif (salud > 20)
    Podrías descansar un poco.
else
    Estás en condición crítica!
end
```

### Switch

```dia
switch (eleccionJugador)
    case 1
        Elegiste la opción 1.
        @hacerAlgo
    case 2
        Elegiste la opción 2.
        @hacerOtraCosa
    case 3
        Elegiste la opción 3.
end
```

### Comandos Personalizados

Usa `@` para llamar comandos personalizados en tu juego:

```dia
@playSound "victoria"
@showPortrait "heroe_feliz"
@loadScene "bosque" rapido
@curar_jugador 50
```

Maneja estos en tu código con un callback:

```haxe
executor.setCallbackHandler({
    handleAtCall: function(command:String, args:Array<Dynamic>):Void {
        switch (command) {
            case "playSound":
                // Reproduce el sonido
            case "showPortrait":
                // Muestra el retrato del personaje
            case "loadScene":
                // Carga la escena
        }
    }
});
```

## Ejemplo Completo

Aquí hay un script completo mostrando diferentes características:

```dia
# Ejemplo de Diálogo RPG

var nombreJugador = "Héroe"
var salud = 80
var tieneLlave = false

func entrarPueblo
    Bienvenido al Pueblo Riverside!
    @playMusic "town_theme"
    @showBackground "plaza_pueblo"
end

# Inicio de la historia
@entrarPueblo

if (salud > 50)
    Llegas sintiéndote fuerte y listo.
else
    Llegas cojeando al pueblo, apenas de pie.
    Tal vez deberías buscar una posada...
end

El guardia se te acerca.
Guardia: Alto! Declara tu propósito.

switch (eleccionJugador)
    case 1
        Vengo a comerciar bienes.
        Guardia: Muy bien, el mercado está abierto.
        @abrirTienda
    case 2
        Busco aventura!
        Guardia: Revisa la taberna para misiones.
        @mostrarTaberna
    case 3
        Solo estoy de paso.
        Guardia: Buen viaje entonces.
end

@entrarPueblo
```

## Referencia del API

### Tokenizer

Convierte el código fuente en tokens:

```haxe
var tokenizer = new Tokenizer(codigoFuente);
var tokens = tokenizer.tokenize();
```

### Parser

Convierte los tokens en un AST ejecutable:

```haxe
var parser = new Parser(tokens);
var blocks = parser.parse();
```

### Executor

Ejecuta el script paso a paso:

```haxe
var executor = new Executor(blocks);

// Verifica si hay más pasos
if (executor.hasNext()) {
    var result = executor.nextExecute();
}

// Reinicia al principio
executor.reset();

// Llama una función específica
executor.callFunction("saludarJugador");

// Obtener/Asignar variables
var salud = executor.getVariable("salud");
executor.setVariable("salud", 100);
```

### Resultados de Ejecución

`nextExecute()` devuelve diferentes resultados basados en lo que se ejecutó:

- `ERDialog(text)` - Una línea de diálogo
- `ERComment(text)` - Un comentario
- `ERVar(name, value)` - Declaración de variable
- `ERFunc(name)` - Definición de función
- `ERFuncCall(name)` - Llamada a función
- `ERIf(condition, result)` - Sentencia if
- `ERSwitch(value, result)` - Sentencia switch
- `ERReturn` - Sentencia return
- `ERAtCall(command, args)` - Comando personalizado
- `EREnd` - Fin de ejecución

## Almacenamiento de Tokens

Puedes reconstruir el script original desde los tokens:

```haxe
var storage = new TokenStorage();
storage.save(tokens, "salida.dia");
```

Esto preserva la estructura y formato de tu script original.

## Estructura del Proyecto

```
src/nz/
├── tokenizer/      # Análisis léxico
├── parser/         # Análisis sintáctico y AST
├── executor/       # Ejecución en tiempo de ejecución
└── storage/        # Reconstrucción de código
```

Revisa el [src/README.md](src/README.md) para más detalles sobre la arquitectura.

## Ejemplos

Revisa la carpeta `test/examples/` para ejemplos más completos:

- `example.dia` - Muestra todas las características del lenguaje
- `function_test.dia` - Definición y llamado de funciones
- `flow_test.dia` - Flujo de control y orden de ejecución

## Ejecutar Tests

```bash
haxe test.hxml
```

Todos los tests deberían pasar mostrando el flujo de ejecución y resultados.

## Licencia

Siéntete libre de usar esto en tus proyectos. Sin restricciones.

## Contribuir

Encontraste un bug o quieres agregar una característica? Siéntete libre de abrir un issue o PR. Mantenlo simple y asegúrate de que los tests pasen.
