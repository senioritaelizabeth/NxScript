package nx.script;

import nx.script.SyntaxRules;

import nx.script.Bytecode;
import nx.script.NativeProxy;
import nx.script.BytecodeSerializer;
import nx.script.Compiler;
import nx.script.NxProxy;
import nx.script.Parser;
import nx.script.Tokenizer;
import nx.script.VM;
import haxe.io.Path;

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
	static var EMPTY_ARGS:Array<Value> = [];
	static var IMPORT_RE = ~/^\s*import\s+(?:"([^"]+)"|'([^']+)'|([A-Za-z_][A-Za-z0-9_\.]*))\s*;?\s*$/;

	public var vm:VM;
	public var globals(get, never):Map<String, Value>;
	public var natives(get, never):Map<String, Value>;

	@:deprecated("Use 'globals' instead")
	public var variables(get, never):Map<String, Value>;

	@:deprecated("Use 'natives' instead")
	public var methods(get, never):Map<String, Value>;

	/** Controls VM cache flushing strategy. See GcKind for options. Default: SOFT. */
	public var gc_kind(get, set):GcKind;
	inline function get_gc_kind():GcKind return vm.gc_kind;
	inline function set_gc_kind(v:GcKind):GcKind { vm.gc_kind = v; return v; }

	/** Object count threshold used in SOFT gc mode before flushing caches. Default: 512. */
	public var gc_softThreshold(get, set):Int;
	inline function get_gc_softThreshold():Int return vm.gc_softThreshold;
	inline function set_gc_softThreshold(v:Int):Int { vm.gc_softThreshold = v; return v; }

	/** Manually flush all VM internal caches, regardless of gc_kind. */
	public function gc():Void vm.gc();

	/**
	 * Run a script function once per native Haxe object — loop executes in Haxe, not in script.
	 *
	 * This is the fix for the "10k sprites = 24fps" problem. The script loop:
	 *
	 *   while (j < sprites.length) { spr.angle += 120*dt ... j++ }
	 *
	 * pays full VM overhead (bytecode fetch, stack ops, LT, JUMP) per iteration.
	 * With 10k sprites that is ~50k extra VM instructions per frame just for looping.
	 *
	 * Migration — instead of the script loop, write a script function:
	 *
	 *   func updateSprite(spr, i, dt) {
	 *       spr.angle += 120 * dt
	 *       var phase = counter + i
	 *       spr.x += 60 * dt * sin(phase)
	 *       spr.y += 30 * dt * cos(phase)
	 *       spr.color = color
	 *   }
	 *
	 * And call from Haxe each frame:
	 *
	 *   var fn = interp.resolveCallable("updateSprite");
	 *   interp.nativeForEach(sprites, fn, [interp.vm.haxeToValue(dt)]);
	 *
	 * The function body still runs in the VM (so reflection overhead remains for
	 * native field access), but loop overhead is gone — pure Haxe iteration.
	 */
	public function nativeForEach(items:Array<Dynamic>, fn:Value, ?extraArgs:Array<Value>):Void
		vm.nativeForEach(items, fn, extraArgs);

	/** Resolve a script callable by name for repeated host calls. Cache the result. */
	public function resolveCallable(name:String):Value
		return vm.resolveCallable(name);

	/** Call a script function by name, returning null on any error instead of throwing. */
	public function safeCall(name:String, ?args:Array<Value>):Null<Value>
		return vm.safeCall(name, args);

	/** Enable sandbox mode — blocks filesystem/network natives, limits instructions. */
	public function enableSandbox(?extraBlocklist:Array<String>):Void
		vm.enableSandbox(extraBlocklist);

	// ─── NativeProxy helpers ────────────────────────────────────────────────

	/**
	 * Wrap a single native Haxe object (e.g. FlxSprite) as a VDict proxy.
	 * Fields are read once into a shadow Map<String,Value> — script accesses
	 * are pure Map ops with no Reflection in the hot path.
	 *
	 * Call proxy.flush() after the script update to write changes back.
	 *
	 *   var proxy = interp.wrapNative(sprite, ["x","y","angle","color"]);
	 *   vm.globals.set("spr", proxy.value);
	 *   interp.run('update(spr, dt)');
	 *   proxy.flush();
	 */
	public function wrapNative(obj:Dynamic, ?fields:Array<String>):NativeProxy
		return NativeProxy.wrap(vm, obj, fields);

	/**
	 * Wrap many native objects at once (same field list for all).
	 * Returns a WrapManyResult with a VArray of VDicts for the script
	 * and the proxy list for calling flushAll() after the update.
	 *
	 *   var r = interp.wrapNativeMany(sprites, ["x","y","angle","color"]);
	 *   vm.globals.set("sprites", r.value);  // VArray of VDicts
	 *   interp.run('for (spr in sprites) update(spr, dt)');
	 *   NativeProxy.flushAll(r.proxies);
	 */
	public function wrapNativeMany(objects:Array<Dynamic>, ?fields:Array<String>):nx.script.WrapManyResult
		return NativeProxy.wrapMany(vm, objects, fields);

	/** Kept for API compat. Use -D NXDEBUG compile flag for actual debug output. */
	var debug:Bool = false;
	var strictByDefault:Bool = false;

	/** Active syntax rules for this interpreter. Change before calling run(). */
	public var rules:SyntaxRules = null;

	public function new(debug:Bool = false, strict:Bool = false, ?rules:SyntaxRules) {
		this.debug = debug;
		this.strictByDefault = strict;
		this.vm = new VM(debug);
		this.rules = rules ?? SyntaxRules.nxScript();

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
				lineInfo = '${normalizeScriptPath(vm.scriptName)}:${vm.currentInstruction.line}: ';
			}
			#if sys
			Sys.println(lineInfo + parts.join(" "));
			#else
			trace(lineInfo + parts.join(" "));
			#end

			return VNull;
		});

		register("print", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}
			#if sys
			Sys.print(parts.join(" "));
			#else
			trace(parts.join(" "));
			#end
			return VNull;
		});

		register("println", -1, function(args:Array<Value>):Value {
			var parts:Array<Dynamic> = [];
			for (arg in args) {
				parts.push(vm.valueToHaxe(arg));
			}
			#if sys
			Sys.println(parts.join(" "));
			#else
			trace(parts.join(" "));
			#end
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
				case VIterator(_, _): "iterator";
				case VEnumValue(eName, _, _): eName;
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

		register("clamp", 3, function(args:Array<Value>):Value {
			var value = switch (args[0]) {
				case VNumber(n): n;
				default: throw "clamp(value, min, max) expects numbers";
			}
			var minV = switch (args[1]) {
				case VNumber(n): n;
				default: throw "clamp(value, min, max) expects numbers";
			}
			var maxV = switch (args[2]) {
				case VNumber(n): n;
				default: throw "clamp(value, min, max) expects numbers";
			}
			if (minV > maxV)
				throw "clamp(value, min, max): min must be <= max";
			return VNumber(Math.min(Math.max(value, minV), maxV));
		});

		register("lerp", 3, function(args:Array<Value>):Value {
			var a = switch (args[0]) {
				case VNumber(n): n;
				default: throw "lerp(a, b, t) expects numbers";
			}
			var b = switch (args[1]) {
				case VNumber(n): n;
				default: throw "lerp(a, b, t) expects numbers";
			}
			var t = switch (args[2]) {
				case VNumber(n): n;
				default: throw "lerp(a, b, t) expects numbers";
			}
			return VNumber(a + (b - a) * t);
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

		// range: variadic — range(n) -> [0..n-1], range(from, to) -> [from..to-1]
		vm.natives.set("range", VNativeFunction("range", -1, function(args:Array<Value>):Value {
			var from = 0;
			var to = 0;
			if (args.length == 1) {
				to = switch (args[0]) { case VNumber(n): Std.int(n); default: throw "range expects a number"; };
			} else if (args.length == 2) {
				from = switch (args[0]) { case VNumber(n): Std.int(n); default: throw "range expects numbers"; };
				to   = switch (args[1]) { case VNumber(n): Std.int(n); default: throw "range expects numbers"; };
			} else {
				throw "range expects 1 or 2 arguments";
			}
			return VArray([for (i in from...to) VNumber(i)]);
		}));

		register("contains", 2, function(args:Array<Value>):Value {
			return switch (args[0]) {
				case VArray(arr):
					VBool(Lambda.exists(arr, function(v) return vm.valueToString(v) == vm.valueToString(args[1])));
				case VString(s):
					switch (args[1]) {
						case VString(needle): VBool(s.indexOf(needle) >= 0);
						default: VBool(false);
					}
				case VDict(map):
					var key = switch (args[1]) {
						case VString(k): k;
						default: vm.valueToString(args[1]);
					}
					VBool(map.exists(key));
				default:
					throw "contains(container, value) expects array, string, or dict";
			}
		});

		register("keys", 1, function(args:Array<Value>):Value {
			return switch (args[0]) {
				case VDict(map):
					var out:Array<Value> = [];
					for (k in map.keys())
						out.push(VString(k));
					VArray(out);
				default:
					throw "keys(dict) expects a dictionary";
			}
		});

		register("values", 1, function(args:Array<Value>):Value {
			return switch (args[0]) {
				case VDict(map):
					var out:Array<Value> = [];
					for (k in map.keys())
						out.push(map.get(k));
					VArray(out);
				default:
					throw "values(dict) expects a dictionary";
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

		register("split", 2, function(args:Array<Value>):Value {
			var source = switch (args[0]) {
				case VString(s): s;
				default: throw "split(string, separator) expects strings";
			}
			var separator = switch (args[1]) {
				case VString(s): s;
				default: throw "split(string, separator) expects strings";
			}
			return VArray([for (part in source.split(separator)) VString(part)]);
		});

		register("join", 2, function(args:Array<Value>):Value {
			var arr = switch (args[0]) {
				case VArray(values): values;
				default: throw "join(array, separator) expects an array as first argument";
			}
			var separator = switch (args[1]) {
				case VString(s): s;
				default: throw "join(array, separator) expects a string separator";
			}
			var parts:Array<String> = [];
			for (v in arr)
				parts.push(vm.valueToString(v));
			return VString(parts.join(separator));
		});

		register("convokeScript", 1, function(args:Array<Value>):Value {
			var scriptPath = switch (args[0]) {
				case VString(s): s;
				default: throw "convokeScript(path) expects a string path";
			};
			return runFile(scriptPath);
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
			var prepared = preprocessImports(source, scriptName);
			var scriptSource = prepared.source;
			var trimmed = StringTools.trim(scriptSource);
			var strictFromPragma = StringTools.startsWith(trimmed, '"use strict";')
				|| StringTools.startsWith(trimmed, "'use strict';")
				|| StringTools.startsWith(trimmed, '"use strict"')
				|| StringTools.startsWith(trimmed, "'use strict'");
			var strictMode = strictByDefault || strictFromPragma;

			// Set script name in VM
			vm.scriptName = scriptName;

			// Tokenize
			var tokenizer = new Tokenizer(scriptSource, rules);
			var tokens = tokenizer.tokenize();

			#if NXDEBUG
			trace("=== TOKENS ===");
			for (t in tokens) trace('${t.line}:${t.col} -> ${t.token}');
			#end

			// Parse
			var parser = new Parser(tokens, strictMode, rules);
			var ast = parser.parse();

			#if NXDEBUG
			trace("=== AST ===");
			for (stmt in ast) trace(stmt);
			#end

			// Compile to bytecode
			var compiler = new Compiler();
			var chunk = compiler.compile(ast);

			#if NXDEBUG
			trace("=== BYTECODE ===");
			disassemble(chunk);
			#end

			// Execute
			var result = vm.execute(chunk);

			#if NXDEBUG
			trace("=== RESULT ===");
			trace(result);
			#end

			return result;
		} catch (e:Dynamic) {
			var pretty = formatPrettyError(Std.string(e), source, scriptName);
			__print_ln(pretty);
			throw pretty;
		}
	}
	static function __print_ln(s:String):Void {
		#if sys
		Sys.println(s);
		#else
		trace(s);
		#end
	}
	function preprocessImports(source:String, scriptName:String, ?visited:Map<String, Bool>):{source:String} {
		if (visited == null)
			visited = new Map<String, Bool>();

		var normalized = StringTools.replace(StringTools.replace(source, "\r\n", "\n"), "\r", "\n");
		var lines = normalized.split("\n");
		var out:Array<String> = [];

		for (i in 0...lines.length) {
			var line = lines[i];
			var module = parseImportLine(line);
			if (module != null) {
				if (module != null && module != "") {
					if (isScriptImport(module)) {
						var importPath = resolveImportPath(scriptName, module);
						if (!visited.exists(importPath)) {
							visited.set(importPath, true);
							var imported = tryLoadScriptText(importPath);
							if (imported != null) {
								var nested = preprocessImports(imported, importPath, visited);
								out.push("");
								out.push(nested.source);
							} else {
								__print_ln('Warning: Cant load script import: ' + module + ' (resolved: ' + importPath + ')');
							}
						}
					} else if (!resolveImportedModule(module)) {
						// Check if it's already registered as a global native (e.g. Sys, Math)
						if (!vm.globals.exists(module) && !vm.natives.exists(module)) {
							__print_ln('Warning: Cant find module that package name: ' + module);
						}
					}
				}
				// Keep line count stable for diagnostics.
				if (!isScriptImport(module))
					out.push("");
				continue;
			}
			out.push(line);
		}

		return {source: out.join("\n")};
	}

	function parseImportLine(line:String):Null<String> {
		if (line == null)
			return null;

		if (IMPORT_RE.match(line)) {
			var m = IMPORT_RE.matched(1);
			if (m == null || m == "")
				m = IMPORT_RE.matched(2);
			if (m == null || m == "")
				m = IMPORT_RE.matched(3);
			return (m != null && m != "") ? m : null;
		}

		var trimmed = StringTools.trim(line);
		if (!StringTools.startsWith(trimmed, "import "))
			return null;

		var spaceIdx = trimmed.indexOf(" ");
		if (spaceIdx < 0)
			return null;

		var rest = StringTools.trim(trimmed.substr(spaceIdx + 1));
		if (rest == "")
			return null;

		if (StringTools.endsWith(rest, ";"))
			rest = StringTools.trim(rest.substr(0, rest.length - 1));

		if (rest.length >= 2) {
			var first = rest.charAt(0);
			var last = rest.charAt(rest.length - 1);
			if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
				var inner = rest.substr(1, rest.length - 2);
				return inner != "" ? inner : null;
			}
		}

		return rest;
	}

	function isScriptImport(module:String):Bool {
		if (module == null || module == "")
			return false;
		return StringTools.endsWith(module, ".nx")
			|| module.indexOf("/") >= 0
			|| module.indexOf("\\") >= 0
			|| StringTools.startsWith(module, "./")
			|| StringTools.startsWith(module, "../");
	}

	function resolveImportPath(scriptName:String, module:String):String {
		var normalizedModule = StringTools.replace(module, "\\", "/");
		var isAbsolute = StringTools.startsWith(normalizedModule, "/") || ~/^[A-Za-z]:\//.match(normalizedModule);
		if (!StringTools.endsWith(normalizedModule, ".nx")) {
			normalizedModule += ".nx";
		}
		if (isAbsolute)
			return Path.normalize(normalizedModule);

		var baseDir = getScriptDirectory(scriptName);
		if (baseDir == "")
			return normalizedModule;
		return Path.normalize(baseDir + "/" + normalizedModule);
	}

	function getScriptDirectory(scriptName:String):String {
		if (scriptName == null || scriptName == "" || scriptName == "script")
			return "";
		var normalized = StringTools.replace(scriptName, "\\", "/");
		var idx = normalized.lastIndexOf("/");
		if (idx < 0)
			return "";
		return normalized.substr(0, idx);
	}

	function normalizeScriptPath(path:String):String {
		if (path == null || path == "")
			return "script";
		return StringTools.replace(path, "\\", "/");
	}

	function tryLoadScriptText(path:String):Null<String> {
		var normalized = StringTools.replace(path, "\\", "/");

		#if openfl
		try {
			if (openfl.utils.Assets.exists(normalized))
				return openfl.utils.Assets.getText(normalized);
		} catch (_:Dynamic) {}
		#end

		#if (!openfl && lime)
		try {
			if (lime.utils.Assets.exists(normalized))
				return lime.utils.Assets.getText(normalized);
		} catch (_:Dynamic) {}
		#end

		#if sys
		try {
			return sys.io.File.getContent(normalized);
		} catch (_:Dynamic) {}
		#end

		return null;
	}

	function resolveImportedModule(module:String):Bool {
		var cls = Type.resolveClass(module);
		if (cls != null) {
			registerImportedSymbol(module, cls);
			return true;
		}

		var en = Type.resolveEnum(module);
		if (en != null) {
			registerImportedSymbol(module, en);
			return true;
		}

		return false;
	}

	function registerImportedSymbol(module:String, sym:Dynamic):Void {
		var parts = module.split(".");
		var shortName = parts[parts.length - 1];
		globals.set(shortName, VNativeObject(sym));
	}

	function formatPrettyError(raw:String, source:String, scriptName:String):String {
		var message = sanitizeHostErrorPrefix(raw);
		var stackTail = "";

		var stackIdx = message.indexOf("\nStack trace");
		if (stackIdx >= 0) {
			var full = message;
			message = full.substr(0, stackIdx);
			stackTail = full.substr(stackIdx + 1);
		}

		var loc = extractLineCol(raw);
		var normalized = StringTools.replace(StringTools.replace(source, "\r\n", "\n"), "\r", "\n");
		var lines = normalized.split("\n");
		var targetLine = loc.line;
		if (targetLine < 1)
			targetLine = 1;
		if (targetLine > lines.length)
			targetLine = lines.length;

		var from = targetLine - 1;
		if (from < 1)
			from = 1;
		var to = targetLine + 1;
		if (to > lines.length)
			to = lines.length;

		var out:Array<String> = [];
		for (ln in from...to + 1) {
			out.push('l | ' + lines[ln - 1]);
		}

		var caretCol = loc.col;
		if (caretCol < 1)
			caretCol = 1;
		var pointerSpaces = [for (_ in 0...caretCol - 1) " "].join("");
		out.push('> ' + pointerSpaces + '^');

		var red = "\x1b[31m";
		var reset = "\x1b[0m";
		var shownPath = normalizeScriptPath(scriptName);
		out.push('> ' + red + 'Error: ' + message + reset + ' - ' + shownPath + ':' + targetLine);

		if (stackTail != "")
			out.push(stackTail);

		return out.join("\n");
	}

	function sanitizeHostErrorPrefix(raw:String):String {
		var hostPrefix = ~/^[^\n]*\.hx:[0-9]+:\s*/;
		if (hostPrefix.match(raw))
			return hostPrefix.replace(raw, "");
		return raw;
	}

	function extractLineCol(raw:String):{line:Int, col:Int} {
		var patterns = [
			~/line\s+([0-9]+),\s*col\s+([0-9]+)/i,
			~/line\s+([0-9]+):([0-9]+)/i,
			~/:([0-9]+):([0-9]+)/
		];

		for (re in patterns) {
			if (re.match(raw)) {
				var line = Std.parseInt(re.matched(1));
				var col = Std.parseInt(re.matched(2));
				if (line != null && col != null)
					return {line: line, col: col};
			}
		}

		return {line: 1, col: 1};
	}

	/**
	 * Run source code from a file
	 */
	public function runFile(path:String):Value {
		var normalized = normalizeScriptPath(path);
		var content = tryLoadScriptText(normalized);
		if (content == null)
			throw 'Unable to load script file: ' + normalized;
		return run(content, normalized);
	}
	/**
	 * Reset the VM context — clears globals, reloads built-ins, etc.
	 * Useful if you want to run multiple scripts in the same process without
	 * them interfering with each other via globals.
	 * Note: doesn't reset registered natives since those are meant to be shared.
	**/
	public function reset_context() {
		this.vm = new VM(debug);
		registerBuiltins();
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
		var prepared = preprocessImports(source, scriptName);
		var scriptSource = prepared.source;
		var trimmed = StringTools.trim(scriptSource);
		var strictFromPragma = StringTools.startsWith(trimmed, '"use strict";')
			|| StringTools.startsWith(trimmed, "'use strict';")
			|| StringTools.startsWith(trimmed, '"use strict"')
			|| StringTools.startsWith(trimmed, "'use strict'");
		var strictMode = strictByDefault || strictFromPragma;

		// Tokenize
		var tokenizer = new Tokenizer(scriptSource, rules);
		var tokens = tokenizer.tokenize();

		// Parse
		var parser = new Parser(tokens, strictMode, rules);
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

	/** Fast path for calling zero-argument functions without allocating [] every call. */
	public inline function call0(name:String):Value {
		return vm.callMethod(name, EMPTY_ARGS);
	}


	/** Call a resolved callable with custom arguments. */
	public inline function callResolved(callee:Value, args:Array<Value>):Value {
		return vm.callResolved(callee, args);
	}

	/** Fast path for zero-argument call on a resolved callable. */
	public inline function callResolved0(callee:Value):Value {
		return vm.callResolved(callee, EMPTY_ARGS);
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
