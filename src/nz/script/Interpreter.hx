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
		var content = sys.io.File.getContent(path);
		return run(content);
	}

	/**
	 * Evaluate an expression and return the result as a string
	 */
	public function eval(source:String):String {
		var result = run(source);
		return vm.valueToString(result);
	}

	/**
	 * Set a variable from Haxe code
	 */
	public function setVar(name:String, value:Value) {
		variables.set(name, value);
	}

	/**
	 * Get a variable value
	 */
	public function getVar(name:String):Null<Value> {
		return variables.get(name);
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
