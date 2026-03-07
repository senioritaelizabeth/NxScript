package nz.script;

import nz.script.Bytecode;
import nz.script.BytecodeSerializer;
import nz.script.Compiler;
import nz.script.NxProxy;
import nz.script.Parser;
import nz.script.Tokenizer;
import nz.script.VM;

/**
 * The front door. Tokenizes, parses, compiles, and runs your script in one call.
 *
 * For most use cases you just need:
 *   var interp = new Interpreter();
 *   interp.globals.set("someValue", VNumber(42));
 *   interp.run(sourceCode);
 *
 * If you need class instances from script code, use NxProxy — don't access
 * VInstance fields manually unless you enjoy pain.
 *
 * `variables` and `methods` still work but are deprecated.
 * Update your code. They're going away eventually.
 */
class Interpreter {
	public var vm:VM;
	public var globals(get, never):Map<String, Value>;
	public var natives(get, never):Map<String, Value>;

	@:deprecated("Use 'globals' instead")
	public var variables(get, never):Map<String, Value>;

	@:deprecated("Use 'natives' instead")
	public var methods(get, never):Map<String, Value>;

	var debug:Bool = false;

	public function new(debug:Bool = false) {
		this.debug = debug;
		this.vm = new VM(debug);

		// Register built-in functions
		registerBuiltins();
	}

	/**
	 * Registers all built-in global functions (trace, print, len, range, type, math stuff, etc).
	 * Called once in new(). Don't call it again unless you like duplicate registrations.
	 */
	private function registerBuiltins():Void {
		// Console output
		register("trace", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}

			// Get current instruction line info
			var lineInfo = "";
			if (vm.currentInstruction != null) {
				lineInfo = '${vm.scriptName}:${vm.currentInstruction.line}: ';
			}
			Sys.print(lineInfo + parts.join(" ") + "\n");

			return VNull;
		});

		register("print", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}
			Sys.print(parts.join(" "));
			return VNull;
		});

		register("println", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}
			Sys.println(parts.join(" "));
			return VNull;
		});

		// Type checking
		register("typeof", 1, function(args:Array<Value>):Value {
			return VString(switch (args[0]) {
				case VNull: "null";
				case VBool(_): "bool";
				case VNumber(_): "number";
				case VString(_): "string";
				case VArray(_): "array";
				case VDict(_): "dict";
				case VFunction(_, _): "function";
				case VClass(_): "class";
				case VInstance(className, _, _): "instance";
				case VNativeFunction(_, _, _): "function";
				case VNativeObject(_): "object";
			});
		});

		// Type conversion
		register("int", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.floor(n);
				case VString(s): Std.parseInt(s);
				case VBool(b): b ? 1 : 0;
				default: 0;
			});
		});

		register("float", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): n;
				case VString(s): Std.parseFloat(s);
				case VBool(b): b ? 1.0 : 0.0;
				default: 0.0;
			});
		});

		register("str", 1, function(args:Array<Value>):Value {
			return VString(vm.valueToString(args[0]));
		});

		register("bool", 1, function(args:Array<Value>):Value {
			return VBool(switch (args[0]) {
				case VNull: false;
				case VBool(b): b;
				case VNumber(n): n != 0;
				case VString(s): s.length > 0;
				default: true;
			});
		});

		// Math functions
		register("abs", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.abs(n);
				default: 0;
			});
		});

		register("floor", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.floor(n);
				default: 0;
			});
		});

		register("ceil", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.ceil(n);
				default: 0;
			});
		});

		register("round", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.round(n);
				default: 0;
			});
		});

		register("sqrt", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.sqrt(n);
				default: 0;
			});
		});

		register("pow", 2, function(args:Array<Value>):Value {
			var base = switch (args[0]) {
				case VNumber(n): n;
				default: 0.0;
			}
			var exp = switch (args[1]) {
				case VNumber(n): n;
				default: 0.0;
			}
			return VNumber(Math.pow(base, exp));
		});

		register("sin", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.sin(n);
				default: 0;
			});
		});

		register("cos", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.cos(n);
				default: 0;
			});
		});

		register("tan", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.tan(n);
				default: 0;
			});
		});

		register("min", 2, function(args:Array<Value>):Value {
			var a = switch (args[0]) {
				case VNumber(n): n;
				default: 0.0;
			}
			var b = switch (args[1]) {
				case VNumber(n): n;
				default: 0.0;
			}
			return VNumber(Math.min(a, b));
		});

		register("max", 2, function(args:Array<Value>):Value {
			var a = switch (args[0]) {
				case VNumber(n): n;
				default: 0.0;
			}
			var b = switch (args[1]) {
				case VNumber(n): n;
				default: 0.0;
			}
			return VNumber(Math.max(a, b));
		});

		register("random", 0, function(args:Array<Value>):Value {
			return VNumber(Math.random());
		});

		// Array functions
		register("len", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VArray(arr): arr.length;
				case VString(s): s.length;
				case VDict(map): Lambda.count(map);
				default: 0;
			});
		});

		register("push", 2, function(args:Array<Value>):Value {
			switch (args[0]) {
				case VArray(arr):
					arr.push(args[1]);
					return VNull;
				default:
					throw "push() requires an array";
			}
		});

		register("pop", 1, function(args:Array<Value>):Value {
			return switch (args[0]) {
				case VArray(arr): arr.length > 0 ? arr.pop() : VNull;
				default: throw "pop() requires an array";
			}
		});

		// String functions
		register("upper", 1, function(args:Array<Value>):Value {
			return VString(switch (args[0]) {
				case VString(s): s.toUpperCase();
				default: "";
			});
		});

		register("lower", 1, function(args:Array<Value>):Value {
			return VString(switch (args[0]) {
				case VString(s): s.toLowerCase();
				default: "";
			});
		});

		register("trim", 1, function(args:Array<Value>):Value {
			return VString(switch (args[0]) {
				case VString(s): StringTools.trim(s);
				default: "";
			});
		});

		// Constants
		globals.set("PI", VNumber(Math.PI));
		globals.set("E", VNumber(Math.exp(1)));
		globals.set("NaN", VNumber(Math.NaN));
		globals.set("Infinity", VNumber(Math.POSITIVE_INFINITY));
	}

	/**
	 * Run source code and return the result
	 */
	public function run(source:String, ?scriptName:String = "script"):Value {
		try {
			// Set script name in VM
			vm.scriptName = scriptName;

			// Tokenize
			var tokenizer = new Tokenizer(source);
			var tokens = tokenizer.tokenize();

			if (debug) {
				trace("=== TOKENS ===");
				for (t in tokens) {
					trace('${t.line}:${t.col} -> ${t.token}');
				}
			}

			// Parse
			var parser = new Parser(tokens);
			var ast = parser.parse();

			if (debug) {
				trace("=== AST ===");
				for (stmt in ast) {
					trace(stmt);
				}
			}

			// Compile to bytecode
			var compiler = new Compiler();
			var chunk = compiler.compile(ast);

			if (debug) {
				trace("=== BYTECODE ===");
				disassemble(chunk);
			}

			// Execute
			var result = vm.execute(chunk);

			if (debug) {
				trace("=== RESULT ===");
				trace(result);
			}

			return result;
		} catch (e:Dynamic) {
			trace('Error: $e');
			throw e;
		}
	}

	/**
	 * Run source code from a file
	 */
	public function runFile(path:String):Value {
		#if sys
		var content = sys.io.File.getContent(path);
		return run(content, path);
		#end
		return null;
	}

	/**
	 * Run source code and return result as Haxe Dynamic (auto-converted)
	 * Makes testing easier: `runDynamic("1 + 2") == 3`
	 */
	public function runDynamic(source:String, ?scriptName:String = "script"):Dynamic {
		var result = run(source, scriptName);
		return vm.valueToHaxe(result);
	}

	/**
	 * Evaluate an expression and return the result as a string
	 */
	public function eval(source:String):String {
		var result = run(source);
		return vm.valueToString(result);
	}

	/** Set a global variable (Haxe value auto-converted to script Value) */
	public function set(name:String, value:Dynamic) {
		globals.set(name, vm.haxeToValue(value));
	}

	@:deprecated("Use 'set' instead")
	public inline function setVar(name:String, value:Dynamic)
		set(name, value);

	/**
	 * Compila código fuente a bytecode (sin ejecutar)
	 */
	public function compile(source:String, ?scriptName:String = "script"):Chunk {
		// Tokenize
		var tokenizer = new Tokenizer(source);
		var tokens = tokenizer.tokenize();

		// Parse
		var parser = new Parser(tokens);
		var ast = parser.parse();

		// Compile to bytecode
		var compiler = new Compiler();
		var chunk = compiler.compile(ast);

		return chunk;
	}

	/**
	 * Ejecuta bytecode pre-compilado
	 */
	public function runChunk(chunk:Chunk, ?scriptName:String = "script"):Value {
		vm.scriptName = scriptName;
		return vm.execute(chunk);
	}

	/**
	 * Compila y guarda bytecode a un archivo
	 */
	public function compileToFile(source:String, outputPath:String):Void {
		var chunk = compile(source);
		BytecodeSerializer.saveToFile(chunk, outputPath);
	}

	/**
	 * Carga y ejecuta bytecode desde un archivo
	 */
	public function runFromBytecode(bytecodeFile:String, ?scriptName:String = "script"):Value {
		var chunk = BytecodeSerializer.loadFromFile(bytecodeFile);
		return runChunk(chunk, scriptName);
	}

	/** Serialize a chunk to bytes */
	public function serialize(chunk:Chunk):haxe.io.Bytes {
		return BytecodeSerializer.serialize(chunk);
	}

	@:deprecated("Use 'serialize' instead")
	public inline function serializeChunk(chunk:Chunk):haxe.io.Bytes
		return serialize(chunk);

	/** Deserialize a chunk from bytes */
	public function deserialize(bytes:haxe.io.Bytes):Chunk {
		return BytecodeSerializer.deserialize(bytes);
	}

	@:deprecated("Use 'deserialize' instead")
	public inline function deserializeChunk(bytes:haxe.io.Bytes):Chunk
		return deserialize(bytes);

	/** Get a global variable as Haxe Dynamic (auto-converted) */
	public function getDynamic(name:String):Dynamic {
		var value = globals.get(name);
		if (value == null)
			return null;
		return vm.valueToHaxe(value);
	}

	@:deprecated("Use 'getDynamic' instead")
	public inline function getVarDynamic(name:String):Dynamic
		return getDynamic(name);

	/** Get a global variable as script Value */
	public function get(name:String):Null<Value> {
		return globals.get(name);
	}

	@:deprecated("Use 'get' instead")
	public inline function getVar(name:String):Null<Value>
		return get(name);

	/** Check if a global variable exists */
	public function has(name:String):Bool {
		return globals.exists(name);
	}

	@:deprecated("Use 'has' instead")
	public inline function hasVar(name:String):Bool
		return has(name);

	/** Register a native function callable from scripts */
	public function register(name:String, arity:Int, fn:Array<Value>->Value) {
		natives.set(name, VNativeFunction(name, arity, fn));
	}

	@:deprecated("Use 'register' instead")
	public inline function registerFunction(name:String, arity:Int, fn:Array<Value>->Value)
		register(name, arity, fn);

	/** Call a named function from scripts or native methods */
	public function call(name:String, args:Array<Value>):Value {
		return vm.callMethod(name, args);
	}

	@:deprecated("Use 'call' instead")
	public inline function callFunction(name:String, args:Array<Value>):Value
		return call(name, args);

	/**
	 * Create a type-safe instance of a script class
	 * 
	 * Usage with Interface for IDE Support:
	 * ```haxe
	 * interface MyCat {
	 *     var meow:Bool;
	 *     var name:String;
	 *     function speak():String;
	 * }
	 * 
	 * // ✅ For IDE support with autocomplete and type checking:
	 * var cat = interp.createInstance("MyCat");
	 * var typedCat:MyCat = cat;  // Assign to typed variable for autocomplete
	 * 
	 * // Access fields (autocomplete works!)
	 * trace(typedCat.meow);
	 * 
	 * // Call methods using the Dynamic version to avoid interpreter type checks
	 * trace(cat.speak());
	 * 
	 * // ✅ Modify fields directly
	 * cat.meow = false;
	 * cat.name = "Fluffy";
	 * cat.__syncToScript__();  // Sync changes back to script
	 * ```
	 * 
	 * Note: In Haxe interpreter mode (--interp), use Dynamic for method calls
	 * to avoid runtime type verification issues. For field access, you can use
	 * typed variables to get IDE autocomplete.
	 * 
	 * In compiled targets (C++, JS, etc.), full type safety works without issues.
	 * 
	 * @param className The name of the script class to instantiate
	 * @param args Optional constructor arguments
	 * @return A dynamic proxy object that can be assigned to an interface type
	 */
	public function createInstance<T>(className:String, ?args:Array<Dynamic>):T {
		if (args == null)
			args = [];

		var proxy:Dynamic = if (args.length > 0) {
			NxProxy.instantiate(this, className, args);
		} else {
			NxProxy.get(this, className);
		}

		return proxy;
	}

	/**
	 * Create a strongly-typed instance using an interface (better IDE support)
	 * 
	 * Usage:
	 * ```haxe
	 * var cat = interp.typed(MyCat, "MyCat");
	 * // Now 'cat' has full autocomplete and type safety!
	 * ```
	 * 
	 * Note: This is a compile-time only helper. At runtime it's the same as createInstance.
	 */
	public inline function typed<T>(interfaceType:Class<T>, className:String, ?args:Array<Dynamic>):T {
		return createInstance(className, args);
	}

	// Getters
	inline function get_globals():Map<String, Value>
		return vm.globals;

	inline function get_natives():Map<String, Value>
		return vm.natives;

	inline function get_variables():Map<String, Value>
		return globals;

	inline function get_methods():Map<String, Value>
		return natives;

	// Debug utilities
	function disassemble(chunk:Chunk) {
		trace('=== Chunk ===');

		trace('\nStrings: ${chunk.strings.length}');
		for (i in 0...chunk.strings.length) {
			trace('  [$i] "${chunk.strings[i]}"');
		}

		trace('\nConstants: ${chunk.constants.length}');
		for (i in 0...chunk.constants.length) {
			trace('  [$i] ${chunk.constants[i]}');
		}

		trace('\nInstructions: ${chunk.instructions.length}');
		for (i in 0...chunk.instructions.length) {
			var inst = chunk.instructions[i];
			var opName = Op.getName(inst.op);
			var argStr = inst.arg != null ? ' ${inst.arg}' : '';
			trace('  [$i] 0x${StringTools.hex(inst.op, 2)} $opName$argStr');
		}

		if (chunk.functions.length > 0) {
			trace('\nFunctions: ${chunk.functions.length}');
			for (func in chunk.functions) {
				trace('\n  Function: ${func.name}');
				trace('  Params: ${func.paramNames.join(", ")}');
				disassemble(func.chunk);
			}
		}
	}
}
