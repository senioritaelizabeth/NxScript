package nz.script;

import nz.script.Tokenizer;
import nz.script.Parser;
import nz.script.Compiler;
import nz.script.VM;
import nz.script.Bytecode;

/**
 * Main interpreter class for the scripting language
 * Usage:
 * ```
 * var interp = new Interpreter();
 * interp.variables.set("x", VNumber(10));
 * var result = interp.run(sourceCode);
 * trace(result);
 * ```
 */
class Interpreter {
	public var vm:VM;
	public var variables(get, never):Map<String, Value>;
	public var methods(get, never):Map<String, Value>;

	var debug:Bool = false;

	public function new(debug:Bool = false) {
		this.debug = debug;
		this.vm = new VM(debug);

		// Register built-in functions
		registerBuiltins();
	}

	/**
	 * Register all built-in global functions
	 */
	private function registerBuiltins():Void {
		// Console output
		registerFunction("trace", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}

			// Get current instruction line info
			var lineInfo = "";
			if (vm.currentInstruction != null) {
				lineInfo = '${vm.scriptName}:${vm.currentInstruction.line}: ';
			}

			trace(lineInfo + parts.join(" "));
			return VNull;
		});

		registerFunction("print", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}
			// Sys.print(parts.join(" "));
			return VNull;
		});

		registerFunction("println", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}
			// Sys.println(parts.join(" "));
			return VNull;
		});

		// Type checking
		registerFunction("typeof", 1, function(args:Array<Value>):Value {
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
		registerFunction("int", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.floor(n);
				case VString(s): Std.parseInt(s);
				case VBool(b): b ? 1 : 0;
				default: 0;
			});
		});

		registerFunction("float", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): n;
				case VString(s): Std.parseFloat(s);
				case VBool(b): b ? 1.0 : 0.0;
				default: 0.0;
			});
		});

		registerFunction("str", 1, function(args:Array<Value>):Value {
			return VString(vm.valueToString(args[0]));
		});

		registerFunction("bool", 1, function(args:Array<Value>):Value {
			return VBool(switch (args[0]) {
				case VNull: false;
				case VBool(b): b;
				case VNumber(n): n != 0;
				case VString(s): s.length > 0;
				default: true;
			});
		});

		// Math functions
		registerFunction("abs", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.abs(n);
				default: 0;
			});
		});

		registerFunction("floor", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.floor(n);
				default: 0;
			});
		});

		registerFunction("ceil", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.ceil(n);
				default: 0;
			});
		});

		registerFunction("round", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.round(n);
				default: 0;
			});
		});

		registerFunction("sqrt", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.sqrt(n);
				default: 0;
			});
		});

		registerFunction("pow", 2, function(args:Array<Value>):Value {
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

		registerFunction("sin", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.sin(n);
				default: 0;
			});
		});

		registerFunction("cos", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.cos(n);
				default: 0;
			});
		});

		registerFunction("tan", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VNumber(n): Math.tan(n);
				default: 0;
			});
		});

		registerFunction("min", 2, function(args:Array<Value>):Value {
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

		registerFunction("max", 2, function(args:Array<Value>):Value {
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

		registerFunction("random", 0, function(args:Array<Value>):Value {
			return VNumber(Math.random());
		});

		// Array functions
		registerFunction("len", 1, function(args:Array<Value>):Value {
			return VNumber(switch (args[0]) {
				case VArray(arr): arr.length;
				case VString(s): s.length;
				case VDict(map): Lambda.count(map);
				default: 0;
			});
		});

		registerFunction("push", 2, function(args:Array<Value>):Value {
			switch (args[0]) {
				case VArray(arr):
					arr.push(args[1]);
					return VNull;
				default:
					throw "push() requires an array";
			}
		});

		registerFunction("pop", 1, function(args:Array<Value>):Value {
			return switch (args[0]) {
				case VArray(arr): arr.length > 0 ? arr.pop() : VNull;
				default: throw "pop() requires an array";
			}
		});

		// String functions
		registerFunction("upper", 1, function(args:Array<Value>):Value {
			return VString(switch (args[0]) {
				case VString(s): s.toUpperCase();
				default: "";
			});
		});

		registerFunction("lower", 1, function(args:Array<Value>):Value {
			return VString(switch (args[0]) {
				case VString(s): s.toLowerCase();
				default: "";
			});
		});

		registerFunction("trim", 1, function(args:Array<Value>):Value {
			return VString(switch (args[0]) {
				case VString(s): StringTools.trim(s);
				default: "";
			});
		});

		// Constants
		variables.set("PI", VNumber(Math.PI));
		variables.set("E", VNumber(Math.exp(1)));
		variables.set("NaN", VNumber(Math.NaN));
		variables.set("Infinity", VNumber(Math.POSITIVE_INFINITY));
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
		// var content = sys.io.File.getContent(path);
		return run("content");
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

	/**
	 * Set a variable with a Haxe value (auto-converted to script Value)
	 */
	public function setVar(name:String, value:Dynamic) {
		variables.set(name, vm.haxeToValue(value));
	}

	/**
	 * Get a variable value (auto-converted to Haxe Dynamic)
	 */
	public function getVarDynamic(name:String):Dynamic {
		var value = variables.get(name);
		if (value == null)
			return null;
		return vm.valueToHaxe(value);
	}

	/**
	 * Get a variable value as script Value
	 */
	public function getVar(name:String):Null<Value> {
		return variables.get(name);
	}

	/**
	 * Check if a variable exists
	 */
	public function hasVar(name:String):Bool {
		return variables.exists(name);
	}

	/**
	 * Register a native function
	 */
	public function registerFunction(name:String, arity:Int, fn:Array<Value>->Value) {
		methods.set(name, VNativeFunction(name, arity, fn));
	}

	/**
	 * Call a function defined in the script or native method
	 */
	public function callFunction(name:String, args:Array<Value>):Value {
		return vm.callMethod(name, args);
	}

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
			ScriptClass.instantiate(this, className, args);
		} else {
			ScriptClass.get(this, className);
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
	function get_variables():Map<String, Value> {
		return vm.variables;
	}

	function get_methods():Map<String, Value> {
		return vm.methods;
	}

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
