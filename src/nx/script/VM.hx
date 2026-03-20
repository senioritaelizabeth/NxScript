package nx.script;

import nx.script.Bytecode;
import haxe.ds.ObjectMap;
import nx.bridge.Reflection;
using StringTools;


/**
 * VM — Register-based bytecode interpreter for NxScript.
 *
 * Executes `Chunk` objects produced by the `Compiler`.
 * Everything that runs at script runtime lives here.
 *
 * ### Stack
 * Pre-allocated 512-slot `Array<Value>`. `sp` is the logical top.
 * Locals live at `stack[stackBase .. stackBase + localCount - 1]` per call frame.
 * No `Array.push`/`pop` in the hot path — just `stack[sp++]`.
 *
 * ### Call frames
 * `CallFrame` objects stacked in `frames`. Each carries its own `chunk`, `ip`,
 * `stackBase`, `localVars`, and `upvalues`. `RETURN` pops a frame and resumes
 * the outer one in the same `run()` invocation — trampoline-style, never recursive.
 *
 * ### Flat code array
 * Instructions are stored as `[op, arg, op, arg, …]` pairs in `Chunk.code:Array<Int>`.
 * Reading two ints per step is measurably faster than fetching `Instruction` objects
 * in the hot loop. `Chunk.instructions` is the parallel debug/error-formatter view.
 *
 * ### Globals — two tiers
 * - `scopeVars` / `constVars` — named Map for module-level `let` / `const`
 * - `globalSlotValues` — slot-indexed Array for compiled `var` (O(1) access)
 *
 * ### Closures
 * Captured via `Map<String,Value>` snapshot on `MAKE_LAMBDA`.
 * Functions with no captures share `EMPTY_MAP` to avoid per-call allocation.
 *
 * ### Caches
 * - `EMPTY_MAP` — shared sentinel for zero-capture closures (never write to this)
 * - `EMPTY_UPVALUES` — shared sentinel for no-upvalue functions
 * - `funcCache` — per-chunk `VFunction(chunk, EMPTY_MAP)` cache
 * - `arrayMethodCache` — per-array-instance bound-method cache
 * - `instanceMethodCache` — per-instance bound script-method cache
 *
 * ### Built-in type method dispatch
 * All primitive method calls (`arr.push(x)`, `"hi".upper()`, `(3.5).floor()`)
 * resolve through `getArrayMethod`, `getStringMethod`, or `getNumberMethod`.
 * These are the single authoritative implementations — `CALL_MEMBER` delegates
 * to them rather than duplicating logic inline.
 */
class VM {

	/** One Map to rule them all — shared across every zero-capture function. Never write to this. */
	static var EMPTY_MAP:Map<String, Value> = new Map<String, Value>();
	/** One Array to rule them all — shared across every no-upvalue function. Never write to this. */
	static var EMPTY_UPVALUES:Array<Value> = [];
	static inline var NATIVE_SUPER_INSTANCE_FIELD = "__native_super_instance";

	/**
	 * The stack. 512 slots, pre-allocated, sp is the logical top.
	 * If you overflow this, you wrote infinite recursion. That's on you.
	 */
	var stack:Array<Value>;
	var sp:Int = 0;

	/** Global variables. Set from Haxe with `vm.globals.set(name, value)`, or via top-level script assignments. */
	public var globals:Map<String, Value>;
	/** Names registered as static — preserved across reset_context(). Populated by Interpreter after compilation. */
	public var staticNames:Map<String, Bool> = new Map();

	/** Let-scoped variables (block-level) and compile-time constants */
	var scopeVars:Map<String, Value>;
	var constVars:Map<String, Value>;
	/**
	 * Stack of scope frames for nested block-level `let` vars (module-level only)
	 * Each entry is a Set (Map<String,Bool>) of keys that existed BEFORE the scope opened.
	 * On EXIT_SCOPE, any key absent from that set was introduced inside the scope and gets removed.
	 * Map<String,Bool> gives O(1) lookup vs the old Array<String>.indexOf which was O(n).
	 */
	var scopeStack:Array<Map<String,Bool>> = [];

	/** The call stack. frames[last] is currentFrame. Don't touch frames directly in hot code. */
	var frames:Array<CallFrame> = [];
	var currentFrame:CallFrame;

	/** Externally-registered native Haxe functions. Prefer `Interpreter.register()` over writing to this directly. */
	public var natives:Map<String, Value>;

	/** Classes registered via `using ClassName` — searched for extension methods. */
	public var usingClasses:Array<String> = [];

	/** Class registry. Populated by MAKE_CLASS instructions and NativeClasses.registerAll(). Used for inheritance lookups during instantiation. */
	public var classes:Map<String, ClassData>;


	/** Maximum instructions before the VM throws. Default 10,000,000. Raise it if you have a very long-running script; lower it if you want a tighter sandbox. */
	public var maxInstructions:Int = 10000000;

	/** Maximum call depth before the VM throws. Default 10,000. Set <= 0 to disable this guard. */
	public var maxCallDepth:Int = 10000;

	/**
	 * Sandboxed execution mode.
	 *
	 * When true, the VM blocks access to any native registered under a name
	 * in `sandboxBlocklist`. By default the blocklist is empty — populate it
	 * before executing untrusted scripts.
	 *
	 * Also enforces tighter defaults:
	 *   maxInstructions = 500_000  (prevent infinite loops)
	 *   maxCallDepth    = 256      (prevent stack overflow exploits)
	 *
	 * Usage:
	 *   vm.sandboxed = true;
	 *   vm.sandboxBlocklist.set("Sys", true);
	 *   vm.sandboxBlocklist.set("sys", true);
	 */
	public var sandboxed:Bool = false;

	/**
	 * Extension method registry populated by `using ClassName` declarations.
	 * Maps className -> list of static method containers (VClass or VNativeObject).
	 * When getMember fails to find a method, these are searched with obj as first arg.
	 */

	/** Set of native/global names blocked in sandboxed mode. */
	public var sandboxBlocklist:Map<String, Bool> = new Map();

	/**
	 * Enable sandbox with sensible defaults in one call.
	 * Blocks: Sys, sys, File, FileSystem, Http, Socket, Process.
	 * Sets maxInstructions=500_000, maxCallDepth=256.
	 */


	/**
	 * Enables sandboxed execution mode.
	 *
	 * When active:
	 * - Any native registered under a name in `sandboxBlocklist` is blocked.
	 * - `maxInstructions` is capped at 500,000.
	 * - `maxCallDepth` is capped at 256.
	 *
	 * @param extraBlocklist  Additional native names to block (e.g. `["Sys", "sys"]`).
	 */
	public function enableSandbox(?extraBlocklist:Array<String>):Void {
		sandboxed = true;
		maxInstructions = 500000;
		maxCallDepth = 256;
		for (name in ["Sys", "sys", "File", "FileSystem", "Http", "Socket", "Process", "Reflect", "Type"])
			sandboxBlocklist.set(name, true);
		if (extraBlocklist != null)
			for (name in extraBlocklist)
				sandboxBlocklist.set(name, true);
	}

	/**
	 * Controls how aggressively the VM reclaims internal caches between script executions.
	 *
	 *   AGGRESSIVE  — Clears all caches (arrayMethodCache, instanceMethodCache, nativeArgBuffers,
	 *                 caches) on every execute() call. Minimises memory at the cost of
	 *                 re-warming caches on each run. Best for short-lived scripts or tight memory.
	 *
	 *   SOFT        — Clears caches only when the number of tracked objects exceeds a threshold
	 *                 (default 512). Good balance for long-running hosts that re-run scripts often.
	 *
	 *   VERY_SOFT   — Never proactively clears caches; relies entirely on the host GC. Maximum
	 *                 throughput for hot re-execution loops where the same objects are reused.
	 *
	 * Default: SOFT.
	 */
	public var gc_kind:GcKind = SOFT;

	/** Object count threshold used by SOFT mode before flushing caches. Default: 512. */
	public var gc_softThreshold:Int = 512;

	var catchStack:Array<CatchHandler> = [];
	var globalSlotValues:Array<Value>;
	var globalSlotNames:Array<String>;
	var globalSlotByName:Map<String, Int>;
	var globalSlotIsConst:Array<Bool>;
	var globalSlotConstInit:Array<Bool>;
	var arrayMethodCache:ObjectMap<Dynamic, Map<String, Value>>;
	var instanceMethodCache:ObjectMap<Dynamic, Map<String, Value>>;
	var nativeArgBuffers:Map<Int, Array<Value>>;

	/** Script name shown in runtime error messages. Set to a file path for useful stack traces. */
	public var scriptName:String = "script";

	/** The instruction currently executing. Only populated when compiled with -D NXDEBUG. */
	public var currentInstruction:Instruction = null;

	/** Kept for API compat. No effect on hot loop without -D NXDEBUG. */
	public var debug(get, set):Bool;
	var _debug:Bool = false;
	function get_debug() return _debug;
	function set_debug(v:Bool):Bool {
		_debug = v;
		#if !NXDEBUG
		if (v) trace("[NxScript] Warning: debug=true has no effect without -D NXDEBUG compile flag");
		#end
		return v;
	}

	/**
	 * Preallocated frame + frames array for host->script calls (callFunction/callResolved).
	 * Mutated in-place every call — zero heap allocation per frame in the hot path.
	 */
	var _hostFrame:CallFrame;
	var _hostFrames:Array<CallFrame>;

	/**
	 * Creates a VM. Optionally pass debug=true to get a trace per instruction.
	 * Don't pass debug=true in production unless you enjoy reading walls of text.
	 */


	/**
	 * Creates a new VM instance.
	 *
	 * @param debug  When `true`, emits a trace line per instruction (very slow — dev only).
	 */
	public function new(debug:Bool = false) {
		this._debug = debug;
		stack = [for (_ in 0...512) VNull]; // pre-allocated — resizing at runtime would be embarrassing
		sp = 0;
		globals = new Map();
		scopeVars = new Map();
		constVars = new Map();
		scopeStack = []; // Array<Array<String>>
		natives = new Map();
		classes = new Map();
		catchStack = [];
		globalSlotValues = [];
		globalSlotNames = [];
		globalSlotByName = new Map();
		globalSlotIsConst = [];
		globalSlotConstInit = [];
		arrayMethodCache = new ObjectMap();
		instanceMethodCache = new ObjectMap();
		nativeArgBuffers = new Map();

// usingExtensions init removed
		initializeNativeFunctions();
		NativeClasses.registerAll(this);
	}

	/**
	 * Runs a compiled Chunk from the top level.
	 * Resets all execution state — don't call this mid-execution expecting continuity.
	 * Builds the flat [op, arg, op, arg...] dispatch array on first run (cached forever after).
	 */


	/**
	 * Runs a top-level compiled `Chunk` and returns the last evaluated value.
	 *
	 * Resets the instruction counter and catch-stack, then calls `run()`.
	 * Throws on runtime errors (uncaught script exceptions, stack overflow, etc.).
	 */
	public function execute(chunk:Chunk):Value {
		sp = 0;
		frames = [];
		catchStack = [];
		usingClasses = []; // reset per-run so using declarations don't bleed between scripts
		applyGcPolicy();
		bindGlobalSlots(chunk);

		if (chunk.code == null)
			buildFlatCode(chunk);

		var frame = new CallFrame(chunk, 0, 0, new Map(), [], "<main>");
		currentFrame = frame;
		frames.push(frame);

		try {
			return run();
		} catch (e:Dynamic) {
			var msg = if (Std.isOfType(e, ScriptException)) {
				var se:ScriptException = cast e;
				'Uncaught exception: ${valueToString(se.value)}';
			} else {
				Std.string(e);
			};
			var stack = formatStackTrace();
			if (stack != "")
				throw msg + "\n" + stack;
			throw msg;
		}
	}


	/**
	 * Returns a human-readable call-stack trace for the current execution state.
	 * Used by the error formatter in `Interpreter`.
	 */
	public function formatStackTrace():String {
		if (frames == null || frames.length == 0)
			return "";

		var lines:Array<String> = ["Stack trace (most recent call last):"];
		var shownScript = scriptName == null ? "script" : scriptName.replace("\\", "/");
		for (i in 0...frames.length) {
			var frame = frames[frames.length - 1 - i];
			var instIdx = frame.ip > 0 ? ((frame.ip - 1) >> 1) : 0;
			var chunk = frame.chunk;
			var loc = "?:?";
			if (chunk != null && chunk.instructions != null && instIdx >= 0 && instIdx < chunk.instructions.length) {
				var inst = chunk.instructions[instIdx];
				loc = inst.line + ":" + inst.col;
			}
			lines.push('  at ${frame.functionName} (${shownScript}:${loc})');
		}
		return lines.join("\n");
	}

	/** Flatten Instruction objects into [op, arg, op, arg...] to eliminate object indirection in hot loop */


	/**
	 * Flattens `chunk.instructions` into the `[op, arg, op, arg, …]` dispatch array.
	 * Also recurses into nested function chunks so the entire program is flat before
	 * `run()` starts. Called once per `execute()`.
	 */
	function buildFlatCode(chunk:Chunk) {
		var insts = chunk.instructions;
		var len = insts.length;

		var flat = new Array<Int>();
		flat.resize(len * 2);

		var fi = 0;

		for (inst in insts) {
			flat[fi++] = inst.op;
			flat[fi++] = inst.arg != null ? inst.arg : 0;
		}

		chunk.code = flat;

		var funcs = chunk.functions;
		for (fc in funcs)
			if (fc.chunk.code == null)
				buildFlatCode(fc.chunk);
	}


	function run():Value {
		// Cache hot fields as locals — eliminates repeated field-chain dereferences in the hot loop
		var chunk = currentFrame.chunk;
		var code = chunk.code;
		var constants = chunk.constants;
		var strings = chunk.strings;
		var ip = currentFrame.ip;

		var stack:Array<Value> = this.stack;
		var frames:Array<CallFrame> = this.frames;
		var catchStack:Array<CatchHandler> = this.catchStack;
		var scopeVars = this.scopeVars;
		var constVars = this.constVars;
		var globals = this.globals;
		var natives = this.natives;
		var currentFrame = this.currentFrame;
		var currentLocalVars = currentFrame.localVars;
		var currentUpvalues = currentFrame.upvalues;
		var frameBase = currentFrame.stackBase;
		var maxCallDepth = this.maxCallDepth;
		var sp = this.sp; // manual stack pointer — avoids Array.push/pop resize overhead

		while (true) {
			var op = code[ip++];
			var arg = code[ip++];

			if (debug) {
				var instIdx = (ip - 2) >> 1;
				currentInstruction = currentFrame.chunk.instructions[instIdx];
				var varInfo = [for (k in scopeVars.keys()) '$k=${scopeVars.get(k)}'].join(", ");
				trace('Stack: $sp | IP: $instIdx | Op: ${Op.getName(op)} | Vars: {$varInfo}');
			}

			switch (op) {
				case Op.LOAD_CONST:
					stack[sp++] = constants[arg];

				case Op.LOAD_LOCAL:
					stack[sp++] = stack[frameBase + arg];

				case Op.LOAD_GLOBAL:
					stack[sp++] = (arg >= 0 && arg < globalSlotValues.length) ? globalSlotValues[arg] : VNull;

				case Op.LOAD_UPVALUE:
					stack[sp++] = (arg >= 0 && arg < currentUpvalues.length) ? currentUpvalues[arg] : VNull;

				case Op.STORE_LOCAL:
					stack[frameBase + arg] = stack[sp - 1];

				case Op.STORE_GLOBAL:
					var value = stack[sp - 1];
					if (arg >= 0 && arg < globalSlotIsConst.length && globalSlotIsConst[arg] && globalSlotConstInit[arg]) {
						var cName = (arg >= 0 && arg < globalSlotNames.length) ? globalSlotNames[arg] : ('slot#' + arg);
						throw 'Cannot reassign constant: $cName';
					}
					if (arg >= globalSlotValues.length) {
						for (_ in globalSlotValues.length...arg + 1)
							globalSlotValues.push(VNull);
					}
					globalSlotValues[arg] = value;
					if (arg >= globalSlotConstInit.length) {
						for (_ in globalSlotConstInit.length...arg + 1)
							globalSlotConstInit.push(false);
					}
					if (arg >= 0 && arg < globalSlotIsConst.length && globalSlotIsConst[arg])
						globalSlotConstInit[arg] = true;
					if (arg >= 0 && arg < globalSlotNames.length) {
						var gName = globalSlotNames[arg];
						if (gName != null && gName != "")
							globals.set(gName, value);
					}

				case Op.STORE_UPVALUE:
					var upValue = stack[sp - 1];
					if (arg >= currentUpvalues.length) {
						for (_ in currentUpvalues.length...arg + 1)
							currentUpvalues.push(VNull);
					}
					currentUpvalues[arg] = upValue;

				//  Might want to change this nesting its somewhat expensive.
				case Op.LOAD_VAR:
					var name = strings[arg];
					// Inline getVariable with single .get() per map (no exists+get overhead)
					var value:Value = currentLocalVars != EMPTY_MAP ? currentLocalVars.get(name) : null;
					if (value == null) {
						value = scopeVars.get(name);
						if (value == null) {
							value = constVars.get(name);
							if (value == null) {
								// Sandbox check before globals/natives (inlined path must respect blocklist)
								if (sandboxed && sandboxBlocklist.exists(name))
									throw 'Sandbox: access to "$name" is not allowed';
								value = globals.get(name);
								if (value == null) {
									value = natives.get(name);
									if (value == null)
										throw 'Undefined variable: $name';
								}
							}
						}
					}
					stack[sp++] = value;

				case Op.STORE_VAR:
					var name = strings[arg];
					var value = stack[sp - 1];
					// Inline setVariable: update in-place if it's a scope var, otherwise global
					if (constVars.exists(name))
						throw 'Cannot reassign constant: $name';
					if (scopeVars.exists(name)) {
						scopeVars.set(name, value);
						if (currentLocalVars == EMPTY_MAP) {
							currentLocalVars = new Map<String, Value>();
							currentFrame.localVars = currentLocalVars;
						}
						currentLocalVars.set(name, value);
					} else {
						globals.set(name, value);
					}

				case Op.STORE_LET:
					var name = strings[arg];
					var value = stack[sp - 1];
					scopeVars.set(name, value);
					if (currentLocalVars == EMPTY_MAP) {
						currentLocalVars = new Map<String, Value>();
						currentFrame.localVars = currentLocalVars;
					}
					currentLocalVars.set(name, value);

				case Op.STORE_CONST:
					constVars.set(strings[arg], stack[sp - 1]);

				case Op.POP:
					sp--;

				case Op.DUP:
					var v = stack[sp - 1];
					stack[sp++] = v;

				case Op.ADD:
					var b = stack[--sp];
					var a = stack[--sp];

					switch (a) {
						case VNumber(x):
							switch (b) {
								case VNumber(y):
									stack[sp++] = VNumber(x + y);
								default:
									stack[sp++] = add(a, b);
							}
						default:
							stack[sp++] = add(a, b);
					}

				case Op.SUB:
					var b = stack[--sp];
					var a = stack[--sp];

					switch (a) {
						case VNumber(x):
							switch (b) {
								case VNumber(y):
									stack[sp++] = VNumber(x - y);
								default:
									throw 'Cannot subtract';
							}
						default:
							throw 'Cannot subtract';
					}

				case Op.MUL:
					var b = stack[--sp];
					var a = stack[--sp];

					switch (a) {
						case VNumber(x):
							switch (b) {
								case VNumber(y):
									stack[sp++] = VNumber(x * y);
								default:
									stack[sp++] = multiply(a, b);
							}
						default:
							stack[sp++] = multiply(a, b);
					}

				case Op.DIV:
					var b = stack[--sp];
					var a = stack[--sp];

					switch (a) {
						case VNumber(x):
							switch (b) {
								case VNumber(y):
									// IEEE 754: n/0 = Inf, 0/0 = NaN (match JS/Haxe float behaviour)
									stack[sp++] = VNumber(x / y);
								default:
									throw 'Cannot divide';
							}
						default:
							throw 'Cannot divide';
					}

				case Op.MOD:
					var b = stack[--sp];
					var a = stack[--sp];

					switch (a) {
						case VNumber(x):
							switch (b) {
								case VNumber(y):
									if (y == 0)
										throw 'Modulo by zero';
									stack[sp++] = VNumber(x % y);
								default:
									throw 'Cannot modulo';
							}
						default:
							throw 'Cannot modulo';
					}

				case Op.NEG:
					var a = stack[--sp];

					switch (a) {
						case VNumber(x):
							stack[sp++] = VNumber(-x);
						default:
							throw 'Cannot negate';
					}

				// Bitwise
				case Op.BIT_AND:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VNumber(toInt(a) & toInt(b));
				case Op.BIT_OR:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VNumber(toInt(a) | toInt(b));
				case Op.BIT_XOR:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VNumber(toInt(a) ^ toInt(b));
				case Op.BIT_NOT:
					stack[sp - 1] = VNumber(~toInt(stack[sp - 1]));
				case Op.SHIFT_LEFT:
					var b = toInt(stack[--sp]);
					var a = toInt(stack[--sp]);
					stack[sp++] = VNumber(a << b);
				case Op.SHIFT_RIGHT:
					var b = toInt(stack[--sp]);
					var a = toInt(stack[--sp]);
					stack[sp++] = VNumber(a >> b);

				// Comparison — inlined to avoid this.sp sync with comparisonOp()
				case Op.EQ:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(equals(a, b));
				case Op.NEQ:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(!equals(a, b));
				case Op.LT:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(compare(a, b) < 0);
				case Op.GT:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(compare(a, b) > 0);
				case Op.LTE:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(compare(a, b) <= 0);
				case Op.GTE:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(compare(a, b) >= 0);

				// Logical
				case Op.AND:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(isTruthy(a) && isTruthy(b));
				case Op.OR:
					var b = stack[--sp];
					var a = stack[--sp];
					stack[sp++] = VBool(isTruthy(a) || isTruthy(b));
				case Op.NOT:
					stack[sp - 1] = VBool(!isTruthy(stack[sp - 1]));

				// Control flow — operate on local ip
				case Op.JUMP:
					ip += arg * 2;

				case Op.JUMP_IF_FALSE:
					if (!isTruthy(stack[sp - 1]))
						ip += arg * 2;
					sp--;

				case Op.JUMP_IF_TRUE:
					if (isTruthy(stack[sp - 1]))
						ip += arg * 2;
					sp--;

				// JUMP_IF_NULL / JUMP_IF_NOT_NULL — used by ?? and ?.
				// Does NOT pop TOS — leaves it for the consuming instruction.
				case Op.JUMP_IF_NULL:
					switch (stack[sp - 1]) {
						case VNull: ip += arg * 2;
						default:
					}

				case Op.JUMP_IF_NOT_NULL:
					switch (stack[sp - 1]) {
						case VNull:
						default: ip += arg * 2;
					}

				// Functions
				case Op.CALL:
					var argc = arg;
					var calleeIndex = sp - argc - 1;
					var callee = stack[calleeIndex];

					switch (callee) {
						case VFunction(funcChunk, closure):
							currentFrame.ip = ip; // save continuation only when switching frames
							var paramCount = funcChunk.paramCount;
							if (argc != paramCount)
								throw 'Function ${funcChunk.name} expects $paramCount arguments, got $argc';

							var localCount = funcChunk.localCount;
							var localsBase = calleeIndex;

							// shift args over callee
							var src = localsBase + 1;
							for (i in 0...argc)
								stack[localsBase + i] = stack[src + i];

							// init remaining locals
							for (i in argc...localCount)
								stack[localsBase + i] = VNull;

							// closure injection for named locals that are still loaded via LOAD_LOCAL paths
							if (closure != EMPTY_MAP) {
								var localSlots = funcChunk.localSlots;
								if (localSlots != null) {
									for (key in closure.keys()) {
										var idx = localSlots.get(key);
										if (idx != null)
											stack[localsBase + idx] = closure.get(key);
									}
								}
							}

							var frameUpvalues = buildUpvalueArray(funcChunk, closure);

							// clone closure only if needed
							var localVars:Map<String, Value>;
							if (closure == EMPTY_MAP) {
								localVars = EMPTY_MAP;
							} else {
								localVars = new Map();
								for (key in closure.keys())
									localVars.set(key, closure.get(key));
							}

							sp = localsBase + localCount;

							var newFrame = new CallFrame(funcChunk.chunk, 0, localsBase, localVars, frameUpvalues, funcChunk.name);

							if (maxCallDepth > 0 && frames.length + 1 > maxCallDepth)
								throw 'Execution exceeded maximum call depth ($maxCallDepth) - possible infinite recursion';

							frames.push(newFrame);

							currentFrame = newFrame;
							this.currentFrame = newFrame;
							currentLocalVars = newFrame.localVars;
							currentUpvalues = newFrame.upvalues;
							frameBase = newFrame.stackBase;

							var newChunk = newFrame.chunk;

							chunk = newChunk;
							code = newChunk.code;
							constants = newChunk.constants;
							strings = newChunk.strings;

							ip = 0;

						case VNativeFunction(name, arity, fn):
							if (arity != -1 && argc != arity)
								throw 'Native function $name expects $arity arguments, got $argc';

							var start = sp - argc;
							var args = getNativeArgs(argc, start, stack);

							sp = start - 1;

							stack[sp++] = fn(args);

						default:
							throw 'Value is not callable: $callee';
					}

				case Op.CALL_MEMBER:
					var memberArgc = arg & 0xFFFF;
					var memberFieldIdx = arg >>> 16;
					var memberField = strings[memberFieldIdx];
					var objectIndex = sp - memberArgc - 1;
					var objectValue = stack[objectIndex];

					switch (objectValue) {
						case VArray(arr):
							// Delegate to getArrayMethod — single source of truth for all array ops.
												case VNativeObject(nobj) if (Std.isOfType(nobj, Array)):
							var narr:Array<Dynamic> = cast nobj;
							var argStart = objectIndex + 1;
							switch (memberField) {
								case "push":
									narr.push(valueToHaxe(stack[argStart]));
									sp = objectIndex;
									stack[sp++] = VNumber(narr.length);
									continue;
								case "pop":
									sp = objectIndex;
									stack[sp++] = narr.length == 0 ? VNull : haxeToValue(narr.pop());
									continue;
								case "shift":
									sp = objectIndex;
									stack[sp++] = narr.length == 0 ? VNull : haxeToValue(narr.shift());
									continue;
								case "unshift":
									narr.unshift(valueToHaxe(stack[argStart]));
									sp = objectIndex;
									stack[sp++] = VNull;
									continue;
								default:
							}
						default:
					}

					var memberCallee = getMember(objectValue, memberField);

					switch (memberCallee) {
						case VFunction(funcChunk, closure):
							currentFrame.ip = ip;
							var paramCount = funcChunk.paramCount;
							if (memberArgc != paramCount)
								throw 'Function ${funcChunk.name} expects $paramCount arguments, got $memberArgc';

							var localCount = funcChunk.localCount;
							var localsBase = objectIndex;

							var src = localsBase + 1;
							for (i in 0...memberArgc)
								stack[localsBase + i] = stack[src + i];

							for (i in memberArgc...localCount)
								stack[localsBase + i] = VNull;

							if (closure != EMPTY_MAP) {
								var localSlots = funcChunk.localSlots;
								if (localSlots != null) {
									for (key in closure.keys()) {
										var idx = localSlots.get(key);
										if (idx != null)
											stack[localsBase + idx] = closure.get(key);
									}
								}
							}

							var frameUpvalues = buildUpvalueArray(funcChunk, closure);
							var localVars:Map<String, Value>;
							if (closure == EMPTY_MAP) {
								localVars = EMPTY_MAP;
							} else {
								localVars = new Map();
								for (key in closure.keys())
									localVars.set(key, closure.get(key));
							}

							sp = localsBase + localCount;

							var newFrame = new CallFrame(funcChunk.chunk, 0, localsBase, localVars, frameUpvalues, funcChunk.name);

							if (maxCallDepth > 0 && frames.length + 1 > maxCallDepth)
								throw 'Execution exceeded maximum call depth ($maxCallDepth) - possible infinite recursion';

							frames.push(newFrame);
							currentFrame = newFrame;
							this.currentFrame = newFrame;
							currentLocalVars = newFrame.localVars;
							currentUpvalues = newFrame.upvalues;
							frameBase = newFrame.stackBase;

							var newChunk = newFrame.chunk;
							chunk = newChunk;
							code = newChunk.code;
							constants = newChunk.constants;
							strings = newChunk.strings;
							ip = 0;

						case VNativeFunction(name, arity, fn):
							if (arity != -1 && memberArgc != arity)
								throw 'Native function $name expects $arity arguments, got $memberArgc';

							var start = objectIndex + 1;
							var memberArgs = getNativeArgs(memberArgc, start, stack);

							sp = objectIndex;
							stack[sp++] = fn(memberArgs);

						default:
							throw 'Member is not callable: $memberField';
					}

				case Op.RETURN:
					var result = stack[--sp];
					var savedBase = frameBase; // restore sp here after the frame exits
					frames.pop();
					if (frames.length == 0) {
						this.sp = savedBase;
						return result;
					}
					// Restore outer frame and refresh all locals
					this.currentFrame = frames[frames.length - 1];
					currentFrame = this.currentFrame;
					currentLocalVars = currentFrame.localVars;
					currentUpvalues = currentFrame.upvalues;
					frameBase = currentFrame.stackBase;
					chunk = currentFrame.chunk;
					code = chunk.code;
					constants = chunk.constants;
					strings = chunk.strings;
					ip = currentFrame.ip;
					sp = savedBase; // unwind callee's locals from the shared stack
					stack[sp++] = result;

				case Op.MAKE_FUNC:
					var funcChk = chunk.functions[arg];
					// Avoid allocating a Map when scopeVars is empty (common for top-level funcs)
					var hasScopeVars = scopeVars.iterator().hasNext();
					if (hasScopeVars) {
						var closure = new Map<String, Value>();
						for (key in scopeVars.keys())
							closure.set(key, scopeVars.get(key));
						stack[sp++] = VFunction(funcChk, closure);
					} else {
						// Cache VFunction(chunk, EMPTY_MAP) per function index —
						// eliminates repeated VFunction alloc for inner functions with no captures.
						var fc = chunk.funcCache;
						if (fc == null) {
							fc = [for (_ in 0...chunk.functions.length) null];
							chunk.funcCache = fc;
						}
						var cv = fc[arg];
						if (cv == null) {
							cv = VFunction(funcChk, EMPTY_MAP);
							fc[arg] = cv;
						}
						stack[sp++] = cv;
					}

				case Op.MAKE_LAMBDA:
					var funcChunk = chunk.functions[arg];
					var closure = new Map<String, Value>();
					for (key in scopeVars.keys())
						closure.set(key, scopeVars.get(key));
					// Capture named local slots from the stack (stack-based locals)
					var localNames = chunk.localNames;
					if (localNames != null) {
						for (i in 0...localNames.length)
							if (localNames[i] != "")
								closure.set(localNames[i], stack[frameBase + i]);
					}
					// Also copy any localVars (like 'this') not covered by slots
					if (currentFrame.localVars != EMPTY_MAP)
						for (key in currentFrame.localVars.keys())
							closure.set(key, currentFrame.localVars.get(key));
					stack[sp++] = VFunction(funcChunk, closure);

				// Data structures
				case Op.MAKE_ARRAY:
					var elements:Array<Value> = [for (_ in 0...arg) VNull];
					var ei = arg;
					while (ei > 0) {
						ei--;
						elements[ei] = stack[--sp];
					}
					stack[sp++] = VArray(elements);

				case Op.MAKE_DICT:
					var map = new Map<String, Value>();
					for (i in 0...arg) {
						var value = stack[--sp];
						var key = valueToString(stack[--sp]);
						map.set(key, value);
					}
					stack[sp++] = VDict(map);

				case Op.GET_MEMBER:
					var field = strings[arg];
					var object = stack[--sp];
					#if NXDEBUG
					trace('GET_MEMBER: field=$field, object type=${Type.enumConstructor(object)}');
					#end
					stack[sp++] = getMember(object, field);

				case Op.SET_MEMBER:
					var field = strings[arg];
					var object = stack[--sp];
					var value = stack[--sp];
					setMember(object, field, value);
					stack[sp++] = value;

				case Op.GET_INDEX:
					var index = stack[--sp];
					var object = stack[--sp];
					stack[sp++] = getIndex(object, index);

				case Op.SET_INDEX:
					var value = stack[--sp];
					var index = stack[--sp];
					var object = stack[--sp];
					setIndex(object, index, value);
					stack[sp++] = value;

				// Classes
				case Op.MAKE_CLASS:
					this.sp = sp;
					handleMakeClass(arg);
					sp = this.sp;

				case Op.MAKE_CLASS_STATICS:
					this.sp = sp;
					handleMakeClassStatics(arg);
					sp = this.sp;

				case Op.INSTANTIATE:
					currentFrame.ip = ip; // handleInstantiate may run nested code and restore via frame ip
					this.sp = sp;
					try {
						handleInstantiate(arg);
					} catch (e:ScriptException) {
						handleThrownValue(e.value, this.sp);
						this.currentFrame = this.frames[this.frames.length - 1];
						currentFrame = this.currentFrame;
						currentLocalVars = currentFrame.localVars;
						currentUpvalues = currentFrame.upvalues;
						frameBase = currentFrame.stackBase;
						chunk = currentFrame.chunk;
						code = chunk.code;
						constants = chunk.constants;
						strings = chunk.strings;
					}
					sp = this.sp;
					ip = currentFrame.ip;

				case Op.GET_THIS:
					var thisValue = getVariable("this");
					if (thisValue == null) {
						throw "'this' is not defined in this context";
					}
					stack[sp++] = thisValue;

				// Exception handling
				case Op.THROW:
					var throwVal = stack[--sp];
					handleThrownValue(throwVal, sp);
					// Exception was caught — resync all locals
					this.currentFrame = this.frames[this.frames.length - 1];
					currentFrame = this.currentFrame;
					currentLocalVars = currentFrame.localVars;
					currentUpvalues = currentFrame.upvalues;
					frameBase = currentFrame.stackBase;
					chunk = currentFrame.chunk;
					code = chunk.code;
					constants = chunk.constants;
					strings = chunk.strings;
					sp = this.sp;
					ip = currentFrame.ip;

				case Op.SETUP_TRY:
					catchStack.push({
						stackDepth: sp,
						framesDepth: frames.length,
						catchIP: ip + arg * 2 // ip already advanced past this opcode
					});

				case Op.POP_TRY:
					catchStack.pop();

				case Op.REGISTER_USING:
					var className = strings[arg];
					if (!usingClasses.contains(className))
						usingClasses.push(className);

				case Op.ENTER_SCOPE:
					// Snapshot existing keys as a lookup set — O(1) removal on EXIT_SCOPE.
					var snap = new Map<String,Bool>();
					for (k in scopeVars.keys()) snap.set(k, true);
					scopeStack.push(snap);

				case Op.EXIT_SCOPE:
					// Remove any key not present in the snapshot (introduced inside this scope).
					if (scopeStack.length > 0) {
						var keysBefore = scopeStack.pop();
						for (k in scopeVars.keys())
							if (!keysBefore.exists(k))
								scopeVars.remove(k);
					}

				// Iteration
				case Op.GET_ITER:
					stack[sp - 1] = getIterator(stack[sp - 1]);

				case Op.FOR_ITER:
					var iterator = stack[sp - 1];
					var next = iteratorNext(iterator);
					if (next == null) {
						sp--;
						ip += arg * 2;
					} else {
						stack[sp++] = next;
					}

				case Op.FOR_RANGE_SETUP:
					// No-op at runtime — slots are encoded in arg, read by FOR_RANGE below.
					// ip already advanced past this pair by the main loop.

				case Op.FOR_RANGE:
					// Read varSlot|endSlot from the FOR_RANGE_SETUP word immediately before us.
					// flat layout: [..., SETUP_OP, setupArg, FOR_RANGE_OP, jumpArg, ...]
					// ip now points to the instruction AFTER FOR_RANGE (already advanced).
					// So the SETUP arg is at code[ip - 4].
					var setupArg = code[ip - 3]; // ← was ip-4, should be ip-3
					var varSlot = setupArg & 0xFFFF;
					var endSlot = setupArg >>> 16;
					var cur = stack[frameBase + varSlot];
					var lend = stack[frameBase + endSlot];
					switch [cur, lend] {
						case [VNumber(c), VNumber(e)]:
							if (c >= e) ip += arg * 2;
						default:
							throw 'FOR_RANGE expects numbers';
					}

				case Op.INC_LOCAL:
					var val = stack[frameBase + arg];
					stack[frameBase + arg] = VNumber(toNum(val) + 1);
					stack[sp++] = val;

				case Op.DEC_LOCAL:
					var val = stack[frameBase + arg];
					stack[frameBase + arg] = VNumber(toNum(val) - 1);
					stack[sp++] = val;

				case Op.INC_GLOBAL:
					var val = (arg >= 0 && arg < globalSlotValues.length) ? globalSlotValues[arg] : VNull;
					globalSlotValues[arg] = VNumber(toNum(val) + 1);
					stack[sp++] = val;

				case Op.DEC_GLOBAL:
					var val = (arg >= 0 && arg < globalSlotValues.length) ? globalSlotValues[arg] : VNull;
					globalSlotValues[arg] = VNumber(toNum(val) - 1);
					stack[sp++] = val;

				case Op.INC_MEMBER:
					var field = strings[arg];
					var obj = stack[sp - 1];
					var val = getMember(obj, field);
					setMember(obj, field, VNumber(toNum(val) + 1));
					stack[sp - 1] = val;

				case Op.DEC_MEMBER:
					var field = strings[arg];
					var obj = stack[sp - 1];
					var val = getMember(obj, field);
					setMember(obj, field, VNumber(toNum(val) - 1));
					stack[sp - 1] = val;

				case Op.INC_INDEX:
					var idx = stack[--sp];
					var obj = stack[sp - 1];
					var val = getIndex(obj, idx);
					setIndex(obj, idx, VNumber(toNum(val) + 1));
					stack[sp - 1] = val;

				case Op.DEC_INDEX:
					var idx = stack[--sp];
					var obj = stack[sp - 1];
					var val = getIndex(obj, idx);
					setIndex(obj, idx, VNumber(toNum(val) - 1));
					stack[sp - 1] = val;
				// Special
				case Op.LOAD_NULL:
					stack[sp++] = VNull;
				case Op.LOAD_TRUE:
					stack[sp++] = VBool(true);
				case Op.LOAD_FALSE:
					stack[sp++] = VBool(false);

				default:
					throw 'Unknown opcode: 0x${StringTools.hex(op, 2)}';
			}
		}

		// Unreachable: loop exits via returns in RETURN/opcode or implicit frame end above.
		return VNull;
	}



	/**
	 * Handles the `MAKE_CLASS` opcode — pops method/field descriptors from the stack
	 * and builds a `ClassData` registered in `vm.classes` and `vm.globals`.
	 *
	 * @param counts  Packed Int: high 16 bits = method count, low 16 bits = field count.
	 */
	function handleMakeClass(counts:Int) {
		// Decode counts: methods = high 16 bits, fields = low 16 bits
		var methodCount = counts >> 16;
		var fieldCount = counts & 0xFFFF;

		// Pop fields (name, value pairs)
		var fields = new Map<String, Value>();
		for (i in 0...fieldCount) {
			var value = pop();
			var name = switch (pop()) {
				case VString(s): s;
				default: throw "Field name must be a string";
			}
			fields.set(name, value);
		}

		// Pop methods (name, function, isConstructor triples)
		var methods = new Map<String, FunctionChunk>();
		var constructor:Null<FunctionChunk> = null;
		for (i in 0...methodCount) {
			var isConstructor = switch (pop()) {
				case VBool(b): b;
				default: false;
			}
			var func = switch (pop()) {
				case VFunction(f, _): f;
				default: throw "Method must be a function";
			}
			var name = switch (pop()) {
				case VString(s): s;
				default: throw "Method name must be a string";
			}
			methods.set(name, func);
			if (isConstructor) {
				constructor = func;
			}
		}

		// Pop super class / native base
		var superValue = pop();
		var superClass:Null<String> = switch (superValue) {
			case VNull: null;
			case VClass(c): c.name;
			case VNativeObject(_), VNativeFunction(_, _, _): null;
			default: throw "Super class must be null, a class, or a native class value";
		}
		var nativeSuper:Null<Value> = switch (superValue) {
			case VNativeObject(_), VNativeFunction(_, _, _): superValue;
			default: null;
		}

		// Pop class name
		var className = switch (pop()) {
			case VString(s): s;
			default: throw "Class name must be a string";
		}

		// Create class data
		var classData:ClassData = {
			name: className,
			superClass: superClass,
			nativeSuper: nativeSuper,
			methods: methods,
			fields: fields,
			constructor: constructor,
			staticFields:  new Map(),
			staticMethods: new Map()
		};

		// Register class in global registry
		classes.set(className, classData);

		push(VClass(classData));
	}


	/**
	 * Handles `MAKE_CLASS_STATICS` — pops static method/field pairs and installs them
	 * into the class that was just registered by `MAKE_CLASS`.
	 */
	function handleMakeClassStatics(counts:Int) {
		var staticMethodCount = counts >> 16;
		var staticFieldCount  = counts & 0xFFFF;

		// Pop static fields (name, value pairs) — popped in reverse
		var sFields = new Map<String, Value>();
		for (i in 0...staticFieldCount) {
			var value = pop();
			var name = switch (pop()) { case VString(s): s; default: throw "Static field name must be string"; };
			sFields.set(name, value);
		}

		// Pop static methods (name, function pairs)
		var sMethods = new Map<String, FunctionChunk>();
		for (i in 0...staticMethodCount) {
			var func = switch (pop()) { case VFunction(f, _): f; default: throw "Static method must be function"; };
			var name = switch (pop()) { case VString(s): s; default: throw "Static method name must be string"; };
			sMethods.set(name, func);
		}

		// Attach to the VClass sitting on top of stack
		switch (stack[sp - 1]) {
			case VClass(classData):
				for (k in sFields.keys())  classData.staticFields.set(k, sFields.get(k));
				for (k in sMethods.keys()) classData.staticMethods.set(k, sMethods.get(k));
			default:
				throw "MAKE_CLASS_STATICS: top of stack must be a VClass";
		}
	}



	/**
	 * Unwinds the call stack until a matching `SETUP_TRY` handler is found,
	 * then jumps to the catch block with `val` bound to the catch variable.
	 * If no handler exists, rethrows as a Haxe exception.
	 */
	function handleThrownValue(val:Value, sp:Int) {
		if (catchStack.length > 0) {
			var handler = catchStack.pop();
			while (frames.length > handler.framesDepth)
				frames.pop();
			if (frames.length > 0)
				currentFrame = frames[frames.length - 1];
			var newSp = handler.stackDepth;
			stack[newSp] = val;
			this.sp = newSp + 1;
			currentFrame.ip = handler.catchIP;
		} else {
			this.sp = sp;
			throw new ScriptException(val);
		}
	}


	/**
	 * Handles the `INSTANTIATE` opcode — pops the class value and `argCount` arguments,
	 * calls the constructor, and pushes the new instance onto the stack.
	 */
	function handleInstantiate(argCount:Int) {
		var args:Array<Value> = [];
		var ai = argCount;
		while (ai > 0) {
			ai--;
			args[ai] = pop();
		}

		var classValue = pop();

		var instance = switch (classValue) {
			case VClass(classData):
				instantiateFromClassData(classData, args);
			case VNativeObject(_), VNativeFunction(_, _, _):
				var nativeObj = instantiateNativeBase(classValue, args);
				if (nativeObj == null)
					throw 'Cannot instantiate native class value';
				VNativeObject(nativeObj);
			default:
				throw 'Cannot instantiate non-class value';
		}

		push(instance);
	}


	/**
	 * Creates a new script class instance from a `ClassData` descriptor.
	 * Allocates the fields map, runs the constructor (if any), and returns `VInstance`.
	 *
	 * Handles native superclass instantiation via `nativeSuper` if present.
	 */
	function instantiateFromClassData(classData:ClassData, args:Array<Value>):Value {
		// Create instance with fields from the entire inheritance chain
		var instanceFields = new Map<String, Value>();

		// Fast path: no script inheritance (common case) avoids class-chain allocations.
		if (classData.superClass == null) {
			for (field in classData.fields.keys())
				instanceFields.set(field, classData.fields.get(field));
		} else {
			// Collect child->parent then apply in reverse so child overrides parent fields.
			var currentClass = classData;
			var classChain:Array<ClassData> = [];
			while (currentClass != null) {
				classChain.push(currentClass);
				if (currentClass.superClass != null && classes.exists(currentClass.superClass))
					currentClass = classes.get(currentClass.superClass);
				else
					currentClass = null;
			}

			var ci = classChain.length;
			while (ci > 0) {
				ci--;
				var cls = classChain[ci];
				for (field in cls.fields.keys())
					instanceFields.set(field, cls.fields.get(field));
			}
		}

		// If this class extends a native Haxe class, create and attach that native instance.
		var nativeBase = instantiateNativeBase(classData.nativeSuper, args);
		if (nativeBase != null)
			instanceFields.set(NATIVE_SUPER_INSTANCE_FIELD, VNativeObject(nativeBase));

		var inst = VInstance(classData.name, instanceFields, classData);

		// Call constructor if it exists
		if (classData.constructor != null) {
			if (args.length != classData.constructor.paramCount) {
				throw 'Constructor expects ${classData.constructor.paramCount} arguments, got ${args.length}';
			}

			var savedFrames = this.frames;
			var savedCurrentFrame = this.currentFrame;
			var savedScopeVars = this.scopeVars;
			var savedConstVars = this.constVars;
			var savedCatchStack = this.catchStack;

			var ctor = classData.constructor;
			var localCount = ctor.localCount;
			for (i in 0...localCount)
				stack[i] = VNull;
			for (i in 0...args.length)
				stack[i] = args[i];

			var ctorVars = new Map<String, Value>();
			ctorVars.set("this", inst);
			if (classData.superClass != null && classes.exists(classData.superClass))
				ctorVars.set("super", VClass(classes.get(classData.superClass)));
			var ctorFrame:CallFrame = {
				chunk: ctor.chunk,
				ip: 0,
				stackBase: 0,
				localVars: ctorVars,
				upvalues: [],
				functionName: classData.name + ".new"
			};

			var savedSp = this.sp;
			this.frames = [ctorFrame];
			this.currentFrame = ctorFrame;
			this.scopeVars = new Map();
			this.constVars = new Map();
			this.catchStack = [];
			this.sp = localCount;

			// constructor result is ignored
			run();

			this.frames = savedFrames;
			this.currentFrame = savedCurrentFrame;
			this.scopeVars = savedScopeVars;
			this.constVars = savedConstVars;
			this.catchStack = savedCatchStack;
			this.sp = savedSp;
		}

		return inst;
	}

	// Internal helper — direct dispatch, no indirection.
	// Only used by callInstanceMethod. Hot host paths use callResolved directly.

	inline function call(callee:Value, args:Array<Value>):Value {
		return callResolved(callee, args);
	}

	// Returns EMPTY_UPVALUES sentinel for functions with no upvalue names — zero allocation
	// on the vast majority of calls which have no upvalues.

	/**
	 * Builds the upvalue array for a function call from the captured closure map.
	 * Returns `EMPTY_UPVALUES` when the function captures nothing.
	 */
	function buildUpvalueArray(funcChunk:FunctionChunk, closure:Map<String, Value>):Array<Value> {
		var names = funcChunk.upvalueNames;
		if (names == null || names.length == 0)
			return EMPTY_UPVALUES;

		var values:Array<Value> = [for (_ in 0...names.length) VNull];
		if (closure != null && closure != EMPTY_MAP) {
			for (i in 0...names.length) {
				var key = names[i];
				var v = closure.get(key);
				if (v != null)
					values[i] = v;
			}
		}
		return values;
	}


	/**
	 * Slices `argc` arguments off the stack starting at `start`.
	 * Allocates a fresh Array — only called for native functions, not script functions.
	 */
	inline function getNativeArgs(argc:Int, start:Int, stack:Array<Value>):Array<Value> {
		var args = nativeArgBuffers.get(argc);
		if (args == null) {
			args = [for (_ in 0...argc) VNull];
			nativeArgBuffers.set(argc, args);
		}
		for (i in 0...argc)
			args[i] = stack[start + i];
		return args;
	}



	/**
	 * Resolves a variable name through the full scope chain:
	 * local frame vars → upvalues → scope vars → const vars → globals → natives.
	 * Returns `null` (not `VNull`) if not found.
	 */
	function getVariable(name:String):Value {
		if (currentFrame.localVars != EMPTY_MAP && currentFrame.localVars.exists(name))
			return currentFrame.localVars.get(name);
		if (scopeVars.exists(name))
			return scopeVars.get(name);
		if (constVars.exists(name))
			return constVars.get(name);
		if (sandboxed && sandboxBlocklist.exists(name))
			throw 'Sandbox: access to "$name" is not allowed';
		if (globals.exists(name))
			return globals.get(name);
		if (natives.exists(name))
			return natives.get(name);
		return null;
	}


	/**
	 * Assigns a value to a named variable, respecting const protection.
	 * Writes to the first matching tier: scope vars → globals.
	 * Creates a new global if the name is not found anywhere.
	 */
	function setVariable(name:String, value:Value, isConst:Bool) {
		if (constVars.exists(name))
			throw 'Cannot reassign constant: $name';

		// Check if it's a let variable first
		if (scopeVars.exists(name)) {
			scopeVars.set(name, value);
			// Lazy-alloc localVars if it was the shared EMPTY_MAP sentinel
			if (currentFrame.localVars == EMPTY_MAP)
				currentFrame.localVars = new Map<String, Value>();
			currentFrame.localVars.set(name, value);
			return;
		}

		if (isConst)
			constVars.set(name, value);
		else
			globals.set(name, value);
	}


	inline function push(value:Value)
		stack[sp++] = value;

	inline function pop():Value {
		return stack[--sp];
	}

	inline function peek():Value {
		return stack[sp - 1];
	}

	// Conversion between Haxe and Script values



	/**
	 * Converts a Haxe `Dynamic` value to the script's `Value` type.
	 *
	 * Handles: `null`, `Bool`, `Int`, `Float`, `String`, `Array<Dynamic>`,
	 * `Map<String,Dynamic>`, and any other object as `VNativeObject`.
	 */
	public function haxeToValue(value:Dynamic):Value {
		// hxcpp guard.. dynamic can be of type bool as null !?tM
		if(value == true)
			return VBool(true);
		if(value == false)
			return VBool(false);
		return switch (Type.typeof(value)) {
			case TNull: VNull;
			case TBool: VBool(value);
			case TInt: VNumber(value);
			case TFloat: VNumber(value);
			case TClass(String): VString(value);
			case TClass(Array):
				// Return a live VArray wrapping the SAME Array<Dynamic>.
				// Script push/pop/[] operate on the original array — no copy.
				// Each element is lazily converted via haxeToValue per access.
				// We store a shared reference by aliasing Array<Dynamic> as Array<Value>
				// using a thin adapter stored in a VNativeArray wrapper.
				//
				// Implementation: build a VArray backed by a proxy Array<Value>
				// that syncs both ways with the original.
				// Simpler approach that works: keep the original array as VNativeObject
				// and handle push/length/[] on VNativeObject(Array) specially in getMember.
				VNativeObject(value);
			case TFunction: VNativeFunction("", -1, (args:Array<Value>) -> {
					var haxeArgs = [for (a in args) valueToHaxe(a)];
					return haxeToValue(Reflection.callMethod(null, value, haxeArgs));

				});
			default: VNativeObject(value);
		}
	}


	/**
	 * Converts a script `Value` back to a Haxe `Dynamic`.
	 *
	 * `VNull` → `null`, `VBool` → `Bool`, `VNumber` → `Float`,
	 * `VString` → `String`, `VArray` → `Array<Dynamic>`,
	 * `VDict` → `Map<String,Dynamic>`, everything else → `Dynamic`.
	 */
	public function valueToHaxe(value:Value):Dynamic {
		return switch (value) {
			case VNumber(n): n;
			case VString(s): s;
			case VBool(b): b;
			case VNull: null;
			case VArray(arr): [for (v in arr) valueToHaxe(v)];
			case VNativeObject(obj): obj;
			case VEnumValue(_, _, _): valueToString(value); // "Color.Red" or "Result.Ok(hello)"
			// unwrap VInstance to native base if it has one
			case VInstance(_, fields, _):
				var nativeBase = fields.get(NATIVE_SUPER_INSTANCE_FIELD);
				switch (nativeBase) {
					case VNativeObject(obj): obj; // return the actual FlxSprite
					default: null;
				}
			default: null;
		}
	}

	/**
	 * Calls a script function from Haxe host code.
	 *
	 * Pushes the frame directly onto the idle stack at position 0 and lets the
	 * trampoline RETURN handler pop it naturally. No VM state save/restore needed —
	 * the stack is always empty between host calls, so we just place the frame,
	 * run, and return the result. Eliminates ~12 field writes per call vs the old
	 * save/restore approach.
	 *
	 * Precondition: no script is currently executing (frames must be empty).
	 */


	/**
	 * Calls a script function from Haxe host code.
	 *
	 * Pushes a pre-built `CallFrame` directly onto the idle stack and lets `RETURN`
	 * pop it naturally — no save/restore overhead. Safe to call from inside a
	 * native callback registered via `Interpreter.register()`.
	 *
	 * @param func     The compiled function chunk to invoke.
	 * @param closure  Captured variables (use `EMPTY_MAP` for non-closures).
	 * @param args     Arguments to pass (converted to local slots 0…n-1).
	 * @return         The value returned by the script function.
	 */
	public function callFunction(func:FunctionChunk, closure:Map<String, Value>, args:Array<Value>):Value {
		if (func.chunk.code == null)
			buildFlatCode(func.chunk);

		var localCount = func.localCount;
		var paramCount = func.paramCount;

		// Init locals then fill params — stack is idle so we always start at 0
		var i = 0;
		while (i < localCount) { stack[i] = VNull; i++; }
		i = 0;
		while (i < args.length && i < paramCount) { stack[i] = args[i]; i++; }

		// Closure → local slots (O(1) with localSlots, O(n) fallback)
		if (closure != EMPTY_MAP && closure != null) {
			var localSlots = func.localSlots;
			if (localSlots != null) {
				for (key in closure.keys()) {
					var idx = localSlots.get(key);
					if (idx != null)
						stack[idx] = closure.get(key);
				}
			} else {
				var localNames = func.localNames;
				if (localNames != null) {
					for (key in closure.keys()) {
						var idx = localNames.indexOf(key);
						if (idx >= 0)
							stack[idx] = closure.get(key);
					}
				}
			}
		}

		// localVars: reuse EMPTY_MAP when no closure, copy otherwise
		var localVars:Map<String, Value>;
		if (closure == EMPTY_MAP || closure == null) {
			localVars = EMPTY_MAP;
		} else {
			localVars = closure.copy();
			// Write param names into localVars for LOAD_VAR fallback (rare path)
			var pnames = func.paramNames;
			i = 0;
			while (i < args.length && i < pnames.length) {
				localVars.set(pnames[i], args[i]);
				i++;
			}
		}

		var upvalues = buildUpvalueArray(func, closure);

		// Push frame directly — no save/restore of VM state
		var funcFrame = new CallFrame(func.chunk, 0, 0, localVars, upvalues, func.name);
		frames = [funcFrame];
		currentFrame = funcFrame;
		this.currentFrame = funcFrame;
		this.sp = localCount;

		// run() exits when RETURN pops the last frame (frames.length == 0)
		return run();
	}

	/**
	 * Call a previously resolved callable value.
	 * VFunction: routes through the zero-save/restore callFunction path.
	 * VNativeFunction: direct dispatch, no frame overhead at all.
	 */

	/**
	 * Calls any callable `Value` from Haxe host code.
	 *
	 * Routes `VFunction` through `callFunction` and `VNativeFunction` directly.
	 * Throws if `callee` is not callable.
	 */
	public function callResolved(callee:Value, args:Array<Value>):Value {
		return switch (callee) {
			case VFunction(funcChunk, closure):
				callFunction(funcChunk, closure, args);
			case VNativeFunction(name, arity, fn):
				if (arity != -1 && args.length != arity)
					throw 'Native function $name expects $arity arguments, got ${args.length}';
				fn(args);
			default:
				throw 'Value is not callable: $callee';
		}
	}

	// Arithmetic operations


	function binaryOp(op:(Value, Value) -> Value) {
		var b = pop();
		var a = pop();
		push(op(a, b));
	}

	function comparisonOp(op:(Int, Int) -> Bool) {
		var b = pop();
		var a = pop();
		push(VBool(op(compare(a, b), 0)));
	}

	function add(a:Value, b:Value):Value {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: VNumber(x + y);
			case [VString(x), VString(y)]: VString(x + y);
			case [VString(x), _]: VString(x + valueToString(b));
			case [_, VString(y)]: VString(valueToString(a) + y);
			case [VArray(x), VArray(y)]: VArray(x.concat(y));
			default: throw 'Cannot add ${valueToString(a)} and ${valueToString(b)}';
		}
	}

	function subtract(a:Value, b:Value):Value {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: VNumber(x - y);
			default: throw 'Cannot subtract';
		}
	}

	function multiply(a:Value, b:Value):Value {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: VNumber(x * y);
			case [VString(s), VNumber(n)] | [VNumber(n), VString(s)]:
				var count = Std.int(n);
				var result = "";
				for (i in 0...count)
					result += s;
				VString(result);
			default: throw 'Cannot multiply';
		}
	}

	function divide(a:Value, b:Value):Value {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]:
				// IEEE 754: n/0 = Inf, 0/0 = NaN
				VNumber(x / y);
			default: throw 'Cannot divide';
		}
	}

	function modulo(a:Value, b:Value):Value {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]:
				if (y == 0)
					throw 'Modulo by zero';
				VNumber(x % y);
			default: throw 'Cannot modulo';
		}
	}

	function negate(a:Value):Value {
		return switch (a) {
			case VNumber(x): VNumber(-x);
			default: throw 'Cannot negate';
		}
	}

	// Comparison
	inline function equals(a:Value, b:Value):Bool {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: x == y;
			case [VString(x), VString(y)]: x == y;
			case [VBool(x), VBool(y)]: x == y;
			case [VNull, VNull]: true;
			case [VEnumValue(e1,v1,_), VEnumValue(e2,v2,_)]: e1 == e2 && v1 == v2;
			default: false;
		}
	}

	inline function compare(a:Value, b:Value):Int {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: if (x < y) -1 else if (x > y) 1 else 0;
			case [VString(x), VString(y)]: if (x < y) -1 else if (x > y) 1 else 0;
			default: throw 'Cannot compare';
		}
	}


	/**
	 * Truthiness rule: `null` and `false` are falsy; `0` and `""` are truthy.
	 * (NxScript uses JavaScript-style truthiness for null/bool only, not for 0/"").
	 */
	inline function isTruthy(value:Value):Bool {
		return switch (value) {
			case VNull:       false;
			case VBool(b):    b;
			case VNumber(n):  n != 0 && !Math.isNaN(n);
			case VString(s):  s.length > 0;
			case VArray(a):   a.length > 0;
			case VDict(m):    Lambda.count(m) > 0;
			default: true;
		}
	}

	// Member access


	/**
	 * Searches extension method registries (`using ClassName`) for a matching method.
	 * Returns the bound `VNativeFunction` if found, or `null` if not.
	 */
	function tryUsingMethod(object:Value, field:String):Value {
		for (className in usingClasses) {
			var cd = classes.get(className);
			if (cd == null) continue;
			var method = cd.methods.get(field);
			if (method == null) continue;
			return VNativeFunction(field, -1, function(args:Array<Value>):Value {
				var fullArgs = [object].concat(args);
				return callFunction(method, new Map(), fullArgs);
			});
		}
		return null;
	}


	/**
	 * Reads a field or method from a script value.
	 *
	 * Dispatch order:
	 * - `VNumber`  → `getNumberMethod`
	 * - `VString`  → `getStringMethod`
	 * - `VArray`   → `getArrayMethod`
	 * - `VDict`    → built-in dict methods (`keys`, `values`, `has`, `remove`, `set`, `size`, `clear`) or map lookup
	 * - `VInstance` → instance fields → class method chain → native super fallback
	 * - `VClass`   → static methods → static fields → constructor
	 * - `VEnumValue` → `variant`, `name`, `enum`, `values`, `valueN`
	 * - `VNativeObject` → native Array fast-path → `Reflection.getField`
	 */
	public function getMember(object:Value, field:String):Value {
		return switch (object) {
			case VNumber(n):
				getNumberMethod(n, field);

			case VString(s):
				getStringMethod(s, field);

			case VArray(arr):
				getArrayMethod(arr, field);

			case VDict(map):
				switch (field) {
					case "keys":   return VNativeFunction("keys",   0, (_) -> VArray([for (k in map.keys()) VString(k)]));
					case "values": return VNativeFunction("values", 0, (_) -> VArray([for (k in map.keys()) map.get(k)]));
					case "has":    return VNativeFunction("has",    1, (args) -> VBool(switch (args[0]) {
						case VString(k): map.exists(k);
						default: map.exists(valueToString(args[0]));
					}));
					case "remove": return VNativeFunction("remove", 1, (args) -> {
						var k = switch (args[0]) { case VString(s): s; default: valueToString(args[0]); };
						map.remove(k); return VNull;
					});
					case "set":    return VNativeFunction("set",    2, (args) -> {
						var k = switch (args[0]) { case VString(s): s; default: valueToString(args[0]); };
						map.set(k, args[1]); return VNull;
					});
					case "size":   return VNativeFunction("size",   0, (_) -> VNumber(Lambda.count(map)));
					case "clear":  return VNativeFunction("clear",  0, (_) -> { map.clear(); return VNull; });
					default:
						map.exists(field) ? map.get(field) : VNull;
				}

			case VInstance(className, fields, classData):
				if (fields.exists(field))
					return fields.get(field);

				var cachedInstanceMethods = instanceMethodCache.get(fields);
				if (cachedInstanceMethods != null && cachedInstanceMethods.exists(field))
					return cachedInstanceMethods.get(field);

				var currentClass = classData;
				while (currentClass != null) {
					if (currentClass.methods.exists(field)) {
						var method = currentClass.methods.get(field);
						var superVal2:Value = VNull;
						if (classData.superClass != null && classes.exists(classData.superClass))
							superVal2 = VClass(classes.get(classData.superClass));
						var bound = VFunction(method, ["this" => object, "super" => superVal2]);
						if (cachedInstanceMethods == null) {
							cachedInstanceMethods = new Map<String, Value>();
							instanceMethodCache.set(fields, cachedInstanceMethods);
						}
						cachedInstanceMethods.set(field, bound);
						return bound;
					}
					if (currentClass.superClass != null && classes.exists(currentClass.superClass))
						currentClass = classes.get(currentClass.superClass);
					else
						currentClass = null;
				}

				var nativeBase = fields.get(NATIVE_SUPER_INSTANCE_FIELD);
				switch (nativeBase) {
					case VNativeObject(_): return getMember(nativeBase, field);
					default: return VNull;
				}

			case VClass(classData):
				// Static methods first
				var sMethod = classData.staticMethods.get(field);
				if (sMethod != null)
					return VFunction(sMethod, ["__class__" => VClass(classData)]);
				// Static fields
				if (classData.staticFields.exists(field))
					return classData.staticFields.get(field);
				// super.new() or super.method() — inject current this so the parent method runs on this instance
				if (field == "new" && classData.constructor != null) {
					var thisVal = getVariable("this") ?? VNull;
					return VFunction(classData.constructor, ["this" => thisVal, "__super_ctor__" => VBool(true)]);
				}
				var method = classData.methods.get(field);
				if (method != null) {
					var thisVal = getVariable("this") ?? VNull;
					return VFunction(method, ["this" => thisVal]);
				}
				return VNull;


			case VEnumValue(eName, variant, vals):
				switch (field) {
					case "variant": return VString(variant);
					case "name":    return VString(variant);
					case "enum":    return VString(eName);
					case "values":  return VArray(vals.copy());
					default:
						var idxStr = field;
						if (StringTools.startsWith(idxStr, "value")) {
							var i = Std.parseInt(idxStr.substr(5));
							if (i != null && i >= 0 && i < vals.length) return vals[i];
						}
						return VNull;
				}

			case VNativeObject(obj):
				// Live Array<Dynamic> — handle ops directly
				if (Std.isOfType(obj, Array)) {
					var arr:Array<Dynamic> = cast obj;
					switch (field) {
						case "length": return VNumber(arr.length);
						case "push":   return VNativeFunction("push",   1, (args) -> { arr.push(valueToHaxe(args[0])); return VNumber(arr.length); });
						case "pop":    return VNativeFunction("pop",    0, (_)    -> arr.length == 0 ? VNull : haxeToValue(arr.pop()));
						case "shift":  return VNativeFunction("shift",  0, (_)    -> arr.length == 0 ? VNull : haxeToValue(arr.shift()));
						case "unshift":return VNativeFunction("unshift",1, (args) -> { arr.unshift(valueToHaxe(args[0])); return VNull; });
						case "first":  return arr.length > 0 ? haxeToValue(arr[0]) : VNull;
						case "last":   return arr.length > 0 ? haxeToValue(arr[arr.length-1]) : VNull;
						case "join":   return VNativeFunction("join", 1, (args) -> {
								var sep = switch(args[0]) { case VString(s): s; default: ""; };
								return VString(arr.map(v -> Std.string(v)).join(sep));
							});
						case "reverse":return VNativeFunction("reverse",0,(_) -> { arr.reverse(); return VNativeObject(arr); });
						case "indexOf":return VNativeFunction("indexOf",1,(args) -> VNumber(arr.indexOf(valueToHaxe(args[0]))));
						case "contains" | "includes": return VNativeFunction(field,1,(args)->VBool(arr.indexOf(valueToHaxe(args[0]))>=0));
						case "copy":   return VNativeObject(arr.copy());
						default: // fall through to Reflection
					}
				}
				// Standard native object — direct Reflection, no cache
				var raw:Dynamic = Reflection.getField(obj, field);
				if (raw == null) return VNull;
				if (!Reflection.isFunction(raw)) return haxeToValue(raw);
				var capturedObj = obj; var capturedFn = raw;
				return VNativeFunction(field, -1, (args:Array<Value>) -> {
					var haxeArgs = [for (a in args) valueToHaxe(a)];
					return haxeToValue(Reflection.callMethod(capturedObj, capturedFn, haxeArgs));
				});

			default:
				throw 'Cannot access member $field on $object';
		}
	}


	/**
	 * Writes a value to a field on a script object.
	 * Supports `VDict`, `VInstance`, `VClass` (static fields), and `VNativeObject`.
	 */
	public function setMember(object:Value, field:String, value:Value) {
		switch (object) {
			case VDict(map):
				map.set(field, value);
			case VInstance(className, fields, classData):
				if (fields.exists(field)) {
					fields.set(field, value);
				} else {
					// Fallback to native base object when present (e.g. this.angle on FlxSprite)
					var nativeBase = fields.get(NATIVE_SUPER_INSTANCE_FIELD);
					switch (nativeBase) {
						case VNativeObject(_):
							setMember(nativeBase, field, value);
						default:
							fields.set(field, value);
					}
				}
			case VClass(classData):
				// Write to static field (creates it if needed)
				classData.staticFields.set(field, value);
			case VNativeObject(obj):
				Reflection.setField(obj, field, valueToHaxe(value));
			default:
				throw 'Cannot set member $field';
		}
	}

	// nativeSet removed — inlined to Reflection.setField directly

	// nativeClassName removed with NativeFieldCache



	/**
	 * Handles the `GET_INDEX` opcode — `obj[index]`.
	 * Supports `VArray` (integer index), `VDict` (string key), `VString` (char at),
	 * and `VNativeObject` (reflection or Array index).
	 */
	function getIndex(object:Value, index:Value):Value {
		return switch [object, index] {
			case [VArray(arr), VNumber(i)]:
				var idx = Std.int(i);
				if (idx < 0 || idx >= arr.length)
					throw 'Index out of bounds: $idx';
				arr[idx];
			case [VNativeObject(obj), VNumber(i)] if (Std.isOfType(obj, Array)):
				var arr:Array<Dynamic> = cast obj;
				var idx = Std.int(i);
				if (idx < 0 || idx >= arr.length)
					throw 'Index out of bounds: $idx';
				haxeToValue(arr[idx]);
			case [VDict(map), _]:
				var key = valueToString(index);
				map.exists(key) ? map.get(key) : VNull;
			case [VString(s), VNumber(i)]:
				var idx = Std.int(i);
				if (idx < 0 || idx >= s.length)
					throw 'Index out of bounds: $idx';
				VString(s.charAt(idx));
			default: throw 'Cannot index';
		}
	}

	public function instantiateNativeBase(nativeSuper:Null<Value>, args:Array<Value>):Dynamic {
		if (nativeSuper == null)
			return null;

		var haxeArgs = [for (a in args) valueToHaxe(a)];

		return switch (nativeSuper) {
			case VNativeObject(clsOrObj):
				try {
					Type.createInstance(cast clsOrObj, haxeArgs);
				} catch (_:Dynamic) {
					try {
						Type.createInstance(cast clsOrObj, []);
					} catch (_:Dynamic) {
						if(Reflection.isFunction(clsOrObj))
							Reflection.callMethod(null, clsOrObj, haxeArgs);
						else
							clsOrObj;
					}
				}

			case VNativeFunction(_, _, fn):
				valueToHaxe(fn(args));

			default:
				null;
		}
	}


	/**
	 * Handles the `SET_INDEX` opcode — `obj[index] = value`.
	 * Supports `VArray` (integer index), `VDict` (string key), and `VNativeObject`.
	 */
	function setIndex(object:Value, index:Value, value:Value) {
		switch [object, index] {
			case [VArray(arr), VNumber(i)]:
				var idx = Std.int(i);
				if (idx < 0 || idx >= arr.length)
					throw 'Index out of bounds: $idx';
				arr[idx] = value;
			case [VNativeObject(obj), VNumber(i)] if (Std.isOfType(obj, Array)):
				var arr:Array<Dynamic> = cast obj;
				var idx = Std.int(i);
				if (idx < 0 || idx >= arr.length)
					throw 'Index out of bounds: $idx';
				arr[idx] = valueToHaxe(value);
			case [VDict(map), _]:
				map.set(valueToString(index), value);
			default:
				throw 'Cannot set index';
		}
	}

	// Iterator support


	/**
	 * Wraps an iterable value in a `VIterator` for use by `FOR_ITER`.
	 * Supports `VArray`, `VDict` (iterates keys), `VString` (iterates chars),
	 * and `VNativeObject` that is an `Array<Dynamic>`.
	 */
	function getIterator(iterable:Value):Value {
		return switch (iterable) {
			case VArray(arr):
				VDict([
					"_iter_type" => VString("array"),
					"_iter_data" => VArray(arr),
					"_iter_index" => VNumber(0)
				]);
			case VNativeObject(obj) if (Std.isOfType(obj, Array)):
				// Wrap the native array as a VArray for iteration (snapshot is OK for for-in)
				var arr:Array<Dynamic> = cast obj;
				VDict([
					"_iter_type" => VString("array"),
					"_iter_data" => VArray([for (v in arr) haxeToValue(v)]),
					"_iter_index" => VNumber(0)
				]);
			default: throw 'Value is not iterable';
		}
	}


	/**
	 * Advances a `VIterator` and returns the next value, or `null` when exhausted.
	 * `null` (not `VNull`) signals the `FOR_ITER` opcode to exit the loop.
	 */
	function iteratorNext(iterator:Value):Value {
		return switch (iterator) {
			case VDict(map):
				var type = map.get("_iter_type");
				if (type == null)
					return null;
				switch (type) {
					case VString("array"):
						var data = map.get("_iter_data");
						var index = map.get("_iter_index");
						switch [data, index] {
							case [VArray(arr), VNumber(i)]:
								var idx = Std.int(i);
								if (idx >= arr.length)
									return null;
								map.set("_iter_index", VNumber(idx + 1));
								return arr[idx];
							default: return null;
						}
					default: return null;
				}
			default: return null;
		}
	}

	// Native method helpers


	/**
	 * Returns a bound method `VNativeFunction` for a numeric value.
	 *
	 * Supported: `floor`, `ceil`, `round`, `abs`, `sqrt`, `sin`, `cos`, `tan`,
	 * `toInt`, `toFloat`, `toString`, `clamp`, `lerp`, `min`, `max`, `pow`,
	 * `isNaN`, `isFinite`, `sign`, `log`, `log2`, `log10`, `exp`.
	 */
	function getNumberMethod(n:Float, method:String):Value {
		return switch (method) {
			// Rounding
			case "floor": VNativeFunction("floor", 0, (_) -> VNumber(Math.floor(n)));
			case "ceil": VNativeFunction("ceil", 0, (_) -> VNumber(Math.ceil(n)));
			case "round": VNativeFunction("round", 0, (_) -> VNumber(Math.round(n)));
			case "abs": VNativeFunction("abs", 0, (_) -> VNumber(Math.abs(n)));

			// Roots & Powers
			case "sqrt": VNativeFunction("sqrt", 0, (_) -> VNumber(Math.sqrt(n)));
			case "pow": VNativeFunction("pow", 1, (args) -> switch (args[0]) {
					case VNumber(exp): VNumber(Math.pow(n, exp));
					default: throw 'Expected number';
				});

			// Trigonometry
			case "sin": VNativeFunction("sin", 0, (_) -> VNumber(Math.sin(n)));
			case "cos": VNativeFunction("cos", 0, (_) -> VNumber(Math.cos(n)));
			case "tan": VNativeFunction("tan", 0, (_) -> VNumber(Math.tan(n)));
			case "asin": VNativeFunction("asin", 0, (_) -> VNumber(Math.asin(n)));
			case "acos": VNativeFunction("acos", 0, (_) -> VNumber(Math.acos(n)));
			case "atan": VNativeFunction("atan", 0, (_) -> VNumber(Math.atan(n)));

			// Type conversions
			case "int": VNativeFunction("int", 0, (_) -> VNumber(Math.floor(n)));
			case "float": VNativeFunction("float", 0, (_) -> VNumber(n));
			case "str": VNativeFunction("str", 0, (_) -> VString(Std.string(n)));
			case "bool": VNativeFunction("bool", 0, (_) -> VBool(n != 0));

			// Basic arithmetic
			case "add": VNativeFunction("add", 1, (args) -> switch (args[0]) {
					case VNumber(x): VNumber(n + x);
					default: throw 'Expected number';
				});
			case "sub": VNativeFunction("sub", 1, (args) -> switch (args[0]) {
					case VNumber(x): VNumber(n - x);
					default: throw 'Expected number';
				});
			case "mul": VNativeFunction("mul", 1, (args) -> switch (args[0]) {
					case VNumber(x): VNumber(n * x);
					default: throw 'Expected number';
				});
			case "div": VNativeFunction("div", 1, (args) -> switch (args[0]) {
					case VNumber(x): VNumber(n / x);
					default: throw 'Expected number';
				});
			case "mod": VNativeFunction("mod", 1, (args) -> switch (args[0]) {
					case VNumber(x): VNumber(n % x);
					default: throw 'Expected number';
				});

			// Comparison
			case "min": VNativeFunction("min", 1, (args) -> switch (args[0]) {
					case VNumber(x): VNumber(Math.min(n, x));
					default: throw 'Expected number';
				});
			case "max": VNativeFunction("max", 1, (args) -> switch (args[0]) {
					case VNumber(x): VNumber(Math.max(n, x));
					default: throw 'Expected number';
				});

			default:
				var ext = tryUsingMethod(VNumber(n), method);
				if (ext != null) return ext;
				throw 'Unknown Number method: $method';
		}
	}


	/**
	 * Returns a bound method `VNativeFunction` for a string value.
	 *
	 * Supported: `length`, `upper`, `lower`, `trim`, `int`, `float`, `bool`,
	 * `contains`, `indexOf`, `charAt`, `substr`, `split`, `startsWith`, `endsWith`,
	 * `replace`, `repeat`, `padStart`, `padEnd`.
	 */
	function getStringMethod(s:String, method:String):Value {
		return switch (method) {
			// Properties
			case "length": VNumber(s.length);

			// Case conversion
			case "upper": VNativeFunction("upper", 0, (_) -> VString(s.toUpperCase()));
			case "lower": VNativeFunction("lower", 0, (_) -> VString(s.toLowerCase()));

			// Trimming
			case "trim": VNativeFunction("trim", 0, (_) -> VString(StringTools.trim(s)));

			// Type conversion
			case "int": VNativeFunction("int", 0, (_) -> { var n = Std.parseInt(s); VNumber(n != null ? n : 0); });
			case "float": VNativeFunction("float", 0, (_) -> VNumber(Std.parseFloat(s)));
			case "bool": VNativeFunction("bool", 0, (_) -> VBool(s.length > 0));

			// Search
			case "contains": VNativeFunction("contains", 1, (args) -> switch (args[0]) {
					case VString(search): VBool(s.indexOf(search) >= 0);
					default: throw 'Expected string';
				});
			case "indexOf": VNativeFunction("indexOf", 1, (args) -> switch (args[0]) {
					case VString(search): VNumber(s.indexOf(search));
					default: throw 'Expected string';
				});

			// Substrings
			case "charAt": VNativeFunction("charAt", 1, (args) -> switch (args[0]) {
					case VNumber(i): VString(s.charAt(Std.int(i)));
					default: throw 'Expected number';
				});
			case "substr": VNativeFunction("substr", 2, (args) -> {
					var start = switch (args[0]) {
						case VNumber(n): Std.int(n);
						default: 0;
					}
					var len = switch (args[1]) {
						case VNumber(n): Std.int(n);
						default: s.length;
					}
					VString(s.substr(start, len));
				});

			// Split/Join
			case "split": VNativeFunction("split", 1, (args) -> switch (args[0]) {
					case VString(delim): VArray([for (part in s.split(delim)) VString(part)]);
					default: throw 'Expected string';
				});

			// Search extras
			case "startsWith": VNativeFunction("startsWith", 1, (args) -> switch (args[0]) {
					case VString(prefix): VBool(s.length >= prefix.length && s.substr(0, prefix.length) == prefix);
					default: throw 'Expected string';
				});
			case "endsWith": VNativeFunction("endsWith", 1, (args) -> switch (args[0]) {
					case VString(suffix): VBool(s.length >= suffix.length && s.substr(s.length - suffix.length) == suffix);
					default: throw 'Expected string';
				});

			// Modification
			case "replace": VNativeFunction("replace", 2, (args) -> {
					var from = switch (args[0]) { case VString(x): x; default: throw 'Expected string'; };
					var to   = switch (args[1]) { case VString(x): x; default: throw 'Expected string'; };
					VString(StringTools.replace(s, from, to));
				});
			case "repeat": VNativeFunction("repeat", 1, (args) -> switch (args[0]) {
					case VNumber(n):
						var count = Std.int(n);
						if (count < 0) throw 'repeat count must be >= 0';
						var sb = new StringBuf();
						for (_ in 0...count) sb.add(s);
						VString(sb.toString());
					default: throw 'Expected number';
				});
			case "padStart": VNativeFunction("padStart", 2, (args) -> {
					var len = switch (args[0]) { case VNumber(n): Std.int(n); default: throw 'Expected number'; };
					var pad = switch (args[1]) { case VString(x): x; default: " "; };
					if (pad.length == 0) pad = " ";
					var result = s;
					while (result.length < len) result = pad + result;
					VString(result.substr(result.length - Std.int(Math.max(len, s.length))));
				});
			case "padEnd": VNativeFunction("padEnd", 2, (args) -> {
					var len = switch (args[0]) { case VNumber(n): Std.int(n); default: throw 'Expected number'; };
					var pad = switch (args[1]) { case VString(x): x; default: " "; };
					if (pad.length == 0) pad = " ";
					var result = s;
					while (result.length < len) result = result + pad;
					VString(result.substr(0, Std.int(Math.max(len, s.length))));
				});

			default:
				var ext = tryUsingMethod(VString(s), method);
				if (ext != null) return ext;
				throw 'Unknown String method: $method';
		}
	}


	/**
	 * Returns a bound method `VNativeFunction` for an array value.
	 * Results are cached per array instance in `arrayMethodCache`.
	 *
	 * Supported: `length`, `push`, `pop`, `shift`, `unshift`, `first`, `last`,
	 * `contains`/`includes`, `indexOf`, `reverse`, `join`, `map`, `filter`,
	 * `reduce`, `forEach`, `find`, `findIndex`, `every`, `some`,
	 * `slice`, `concat`, `flat`, `copy`, `sort`, `sortBy`.
	 */
	function getArrayMethod(arr:Array<Value>, method:String):Value {
		if (method == "length")
			return VNumber(arr.length);

		var cachedMethods = arrayMethodCache.get(arr);
		if (cachedMethods != null && cachedMethods.exists(method))
			return cachedMethods.get(method);

		var bound = switch (method) {
			// Add/Remove
			case "push": VNativeFunction("push", 1, (args) -> {
					arr.push(args[0]);
					VNull;
				});
			case "pop": VNativeFunction("pop", 0, (_) -> arr.length == 0 ? VNull : arr.pop());
			case "shift": VNativeFunction("shift", 0, (_) -> arr.length == 0 ? VNull : arr.shift());
			case "unshift": VNativeFunction("unshift", 1, (args) -> {
					arr.unshift(args[0]);
					VNull;
				});

			// Access
			case "first": VNativeFunction("first", 0, (_) -> arr.length > 0 ? arr[0] : VNull);
			case "last": VNativeFunction("last", 0, (_) -> arr.length > 0 ? arr[arr.length - 1] : VNull);

			// Search
			case "contains": VNativeFunction("contains", 1, (args) -> {
					var searchValue = args[0];
					var found = false;
					for (item in arr) {
						if (valuesEqual(item, searchValue)) {
							found = true;
							break;
						}
					}
					VBool(found);
				});
			case "indexOf": VNativeFunction("indexOf", 1, (args) -> {
					var searchValue = args[0];
					var index = -1;
					for (i in 0...arr.length) {
						if (valuesEqual(arr[i], searchValue)) {
							index = i;
							break;
						}
					}
					VNumber(index);
				});

			// Transform
			case "reverse": VNativeFunction("reverse", 0, (_) -> {
					arr.reverse();
					VArray(arr);
				});
			case "join": VNativeFunction("join", 1, (args) -> {
					var delim = switch (args[0]) {
						case VString(s): s;
						default: ",";
					}
					var parts = [for (v in arr) valueToString(v)];
					VString(parts.join(delim));
				});

			// Higher-order
		case "map": VNativeFunction("map", 1, (args) -> {
				var fn = args[0];
				VArray([for (item in arr) callResolved(fn, [item])]);
			});
		case "filter": VNativeFunction("filter", 1, (args) -> {
				var fn = args[0];
				VArray([for (item in arr) if (isTruthy(callResolved(fn, [item]))) item]);
			});
		case "reduce": VNativeFunction("reduce", 2, (args) -> {
				var fn = args[0];
				var acc = args[1];
				for (item in arr) acc = callResolved(fn, [acc, item]);
				acc;
			});
		case "forEach": VNativeFunction("forEach", 1, (args) -> {
				var fn = args[0];
				for (item in arr) callResolved(fn, [item]);
				VNull;
			});
		case "find": VNativeFunction("find", 1, (args) -> {
				var fn = args[0];
				for (item in arr) if (isTruthy(callResolved(fn, [item]))) return item;
				VNull;
			});
		case "findIndex": VNativeFunction("findIndex", 1, (args) -> {
				var fn = args[0];
				for (i in 0...arr.length) if (isTruthy(callResolved(fn, [arr[i]]))) return VNumber(i);
				VNumber(-1);
			});
		case "every": VNativeFunction("every", 1, (args) -> {
				var fn = args[0];
				for (item in arr) if (!isTruthy(callResolved(fn, [item]))) return VBool(false);
				VBool(true);
			});
		case "some": VNativeFunction("some", 1, (args) -> {
				var fn = args[0];
				for (item in arr) if (isTruthy(callResolved(fn, [item]))) return VBool(true);
				VBool(false);
			});

		// Slicing / copying
		case "slice": VNativeFunction("slice", 2, (args) -> {
				var start = switch (args[0]) { case VNumber(n): Std.int(n); default: 0; };
				var end_  = switch (args[1]) { case VNumber(n): Std.int(n); case VNull: arr.length; default: arr.length; };
				if (start < 0) start = Std.int(Math.max(0, arr.length + start));
				if (end_  < 0) end_  = Std.int(Math.max(0, arr.length + end_));
				VArray(arr.slice(start, end_));
			});
		case "concat": VNativeFunction("concat", 1, (args) -> {
				switch (args[0]) {
					case VArray(other): VArray(arr.concat(other));
					default: throw 'concat expects an array';
				}
			});
		case "flat": VNativeFunction("flat", 0, (_) -> {
				var result:Array<Value> = [];
				for (item in arr) switch (item) {
					case VArray(inner): for (v in inner) result.push(v);
					default: result.push(item);
				}
				VArray(result);
			});
		case "copy": VNativeFunction("copy", 0, (_) -> VArray(arr.copy()));

		// Sorting
		case "sort": VNativeFunction("sort", 1, (args) -> {
				var fn = args[0];
				var sorted = arr.copy();
				sorted.sort((a, b) -> {
					switch (callResolved(fn, [a, b])) {
						case VNumber(n): Std.int(n);
						case VBool(true): 1;
						case VBool(false): -1;
						default: 0;
					}
				});
				VArray(sorted);
			});
		case "sortBy": VNativeFunction("sortBy", 1, (args) -> {
				var keyFn = args[0];
				var sorted = arr.copy();
				sorted.sort((a, b) -> compare(callResolved(keyFn, [a]), callResolved(keyFn, [b])));
				VArray(sorted);
			});

		default:
			var ext = tryUsingMethod(VArray(arr), method);
			if (ext != null) return ext;
			throw 'Unknown Array method: $method';
		}

		if (cachedMethods == null) {
			cachedMethods = new Map<String, Value>();
			arrayMethodCache.set(arr, cachedMethods);
		}
		cachedMethods.set(method, bound);
		return bound;
	}

	inline function toNum(value:Value):Float {
		return switch (value) {
			case VNumber(n): n;
			case VBool(b): b ? 1.0 : 0.0;
			case VNull: 0.0;
			default: throw 'Expected number';
		}
	}

	// Helper to compare two Values for equality


	/**
	 * Structural equality for script values.
	 * Numbers, strings, and booleans compare by value; everything else is `false`
	 * (no deep equality for arrays/dicts — use explicit loops for that).
	 */
	function valuesEqual(a:Value, b:Value):Bool {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: x == y;
			case [VString(x), VString(y)]: x == y;
			case [VBool(x), VBool(y)]: x == y;
			case [VNull, VNull]: true;
			default: false;
		}
	}

	// Helper functions
	inline function toInt(value:Value):Int {
		return switch (value) {
			case VNumber(n): Std.int(n);
			default: throw 'Expected number';
		}
	}

	// Public API


	/**
	 * Instantiates a script class by name. Throws if the name is not a registered class.
	 * Prefer `callResolved` with a `VClass` value when the class is already resolved.
	 */
	public function instantiateClassByName(name:String, args:Array<Value>):Value {
		var classValue = getVariable(name);
		return switch (classValue) {
			case VClass(classData): instantiateFromClassData(classData, args);
			default: throw 'Value $name is not a class';
		}
	}


	/**
	 * Resolves and calls a method on a script instance.
	 * Equivalent to `callResolved(getMember(instance, methodName), args)`.
	 */
	public function callInstanceMethod(instance:Value, methodName:String, args:Array<Value>):Value {
		return callResolved(getMember(instance, methodName), args);
	}

	public function getNativeBaseInstance(instance:Value):Dynamic {
		return switch (instance) {
			case VInstance(_, fields, _):
				switch (fields.get(NATIVE_SUPER_INSTANCE_FIELD)) {
					case VNativeObject(obj): obj;
					default: null;
				}
			default: null;
		}
	}


	/**
	 * Calls a named global function. Throws `"Undefined function: name"` if not found.
	 */
	public function callMethod(name:String, args:Array<Value>):Value {
		var func = getVariable(name);
		if (func == null)
			throw 'Undefined function: $name';
		return callResolved(func, args);
	}

	/**
	 * Safe wrapper around callMethod — catches script errors and returns null instead of throwing.
	 * Useful for optional script hooks in game objects where a missing/broken function
	 * should degrade gracefully rather than crash the host.
	 *
	 *   var result = vm.safeCall("onUpdate", [VNumber(dt)]);
	 *   if (result == null) { /* script had an error or function not found  }
	 */

	/**
	 * Calls a script function by name, returning `null` on any error instead of
	 * throwing. Useful for optional script hooks in game objects where a missing or
	 * broken function should degrade gracefully.
	 */
	public function safeCall(name:String, ?args:Array<Value>):Null<Value> {
		try {
			var func = getVariable(name);
			if (func == null) return null;
			return callResolved(func, args != null ? args : []);
		} catch (e:Dynamic) {
			#if NXDEBUG
			trace('[NxScript] safeCall("$name") caught: $e');
			#end
			return null;
		}
	}

	/**
	 * Safe wrapper around callResolved — catches script errors and returns null.
	 * Use when you already have a resolved Value (from resolveCallable).
	 */

	/**
	 * Like `safeCall` but takes a pre-resolved `Value` instead of a name string.
	 * Cache the callable with `resolveCallable()` to avoid repeated name lookups.
	 */
	public function safeCallResolved(fn:Value, ?args:Array<Value>):Null<Value> {
		try {
			return callResolved(fn, args != null ? args : []);
		} catch (e:Dynamic) {
			#if NXDEBUG
			trace('[NxScript] safeCallResolved caught: $e');
			#end
			return null;
		}
	}

	/**
	 * Get a global variable safely — returns null instead of throwing if missing.
	 */
	public function safeGet(name:String):Null<Value> {
		try { return getVariable(name); } catch (_:Dynamic) { return null; }
	}

	/** Resolve a callable by name once, then reuse it with callResolved in host hot loops. */

	/**
	 * Resolves a script function by name for repeated host calls.
	 * Cache the returned `Value` and pass it to `callResolved` or `safeCallResolved`
	 * to avoid hash lookup overhead on every frame.
	 */
	public function resolveCallable(name:String):Value {
		syncGlobalSlotsFromMap();
		var func = getVariable(name);
		if (func == null)
			throw 'Undefined function: $name';
		return func;
	}

	/**
	 * Host-driven forEach — the loop runs in Haxe, not in script bytecode.
	 *
	 * This is the correct way to update 10k+ native objects from a script function.
	 * Instead of writing `while(j < sprites.length)` in NxScript (which pays full
	 * VM overhead per iteration), register a per-item script function and call this
	 * from your Haxe update loop:
	 *
	 *   var fn = vm.resolveCallable("updateSprite");
	 *   vm.nativeForEach(sprites, fn, [VNumber(dt)]);
	 *
	 * The script function receives (item, index, ...extraArgs).
	 * Extra args are passed as-is after index — pre-box them with haxeToValue().
	 *
	 * Zero script-loop overhead: no LOAD_VAR, no LT, no JUMP, no stack churn
	 * for the iteration itself. Only the function body runs in the VM.
	 */

	/**
	 * Calls a script function once per item in a Haxe array, with Haxe driving the loop.
	 *
	 * This eliminates VM loop overhead for large collections. The function receives
	 * `(item, index, ...extraArgs)`. See `Interpreter.nativeForEach` for usage examples.
	 */
	public function nativeForEach(items:Array<Dynamic>, fn:Value, ?extraArgs:Array<Value>):Void {
		if (extraArgs == null) extraArgs = [];
		var args = [VNull, VNull].concat(extraArgs); // pre-allocate: [item, index, ...extra]
		for (i in 0...items.length) {
			args[0] = haxeToValue(items[i]);
			args[1] = VNumber(i);
			callResolved(fn, args);
		}
	}

	/**
	 * Same as nativeForEach but items are already boxed as Value[].
	 * Use when your array is already a script VArray (e.g. from a script variable).
	 */
	public function scriptForEach(items:Array<Value>, fn:Value, ?extraArgs:Array<Value>):Void {
		if (extraArgs == null) extraArgs = [];
		var args = [VNull, VNull].concat(extraArgs);
		for (i in 0...items.length) {
			args[0] = items[i];
			args[1] = VNumber(i);
			callResolved(fn, args);
		}
	}

	/**
	 * Applies the current gc_kind policy.
	 * Called automatically at the start of every execute().
	 * You can also call gc() manually at any time to force a flush.
	 */
	function applyGcPolicy():Void {
		switch (gc_kind) {
			case AGGRESSIVE:
				flushCaches();
			case SOFT:
				// Count tracked objects across both caches
				var count = 0;
				for (_ in arrayMethodCache.keys()) count++;
				for (_ in instanceMethodCache.keys()) count++;
				if (count >= gc_softThreshold)
					flushCaches();
			case VERY_SOFT:
				// Never flush — trust the host GC entirely.
				// Still allocate fresh caches on first execute if null.
				if (arrayMethodCache == null)    arrayMethodCache    = new ObjectMap();
				if (instanceMethodCache == null) instanceMethodCache = new ObjectMap();
		}
	}

	/**
	 * Manually flushes all internal VM caches, regardless of gc_kind.
	 * Useful after a large batch of script executions to let the GC reclaim memory.
	 */

	/**
	 * Manually flushes all VM internal caches regardless of `gc_kind`.
	 * Use after loading a large batch of scripts to free method-binding memory.
	 */
	public function gc():Void {
		flushCaches();
	}

	inline function flushCaches():Void {
		arrayMethodCache    = new ObjectMap();
		instanceMethodCache = new ObjectMap();
		nativeArgBuffers    = new Map();
	}

	function bindGlobalSlots(chunk:Chunk):Void {
		if (chunk == null || chunk.globalNames == null)
			return;

		var names = chunk.globalNames;
		if (globalSlotValues.length < names.length) {
			for (_ in globalSlotValues.length...names.length)
				globalSlotValues.push(VNull);
		}
		if (globalSlotNames.length < names.length) {
			for (_ in globalSlotNames.length...names.length)
				globalSlotNames.push("");
		}
		if (globalSlotIsConst.length < names.length) {
			for (_ in globalSlotIsConst.length...names.length)
				globalSlotIsConst.push(false);
		}
		if (globalSlotConstInit.length < names.length) {
			for (_ in globalSlotConstInit.length...names.length)
				globalSlotConstInit.push(false);
		}

		var constMask = chunk.globalConstMask;

		for (i in 0...names.length) {
			var name = names[i];
			globalSlotNames[i] = name;
			globalSlotByName.set(name, i);
			var hasGlobal = globals.exists(name);
			globalSlotValues[i] = hasGlobal ? globals.get(name) : VNull;
			globalSlotIsConst[i] = constMask != null && i < constMask.length ? constMask[i] : false;
			globalSlotConstInit[i] = globalSlotIsConst[i] && hasGlobal;
		}
	}

	function syncGlobalSlotsFromMap():Void {
		for (i in 0...globalSlotNames.length) {
			var name = globalSlotNames[i];
			if (name == null || name == "")
				continue;
			globalSlotValues[i] = globals.exists(name) ? globals.get(name) : VNull;
		}
	}


	/**
	 * Converts a script `Value` to its string representation (used by `trace`, `join`, etc.).
	 * `VNull` → `"null"`, `VBool` → `"true"`/`"false"`, `VNumber` → decimal string,
	 * `VArray` → `"[a, b, c]"`, `VDict` → `"{k: v}"`, instances → `"ClassName {...}"`.
	 */
	public function valueToString(value:Value):String {
		if (value == null) return "null";
		return switch (value) {
			case VNumber(n): Std.string(n);
			case VString(s): s;
			case VBool(b): b ? "true" : "false";
			case VNull: "null";
			case VArray(arr): "[" + [for (v in arr) valueToString(v)].join(", ") + "]";
			case VDict(map):
				var pairs = [for (k in map.keys()) '$k: ${valueToString(map.get(k))}'];
				"{" + pairs.join(", ") + "}";
			case VFunction(f, _): '<function ${f.name}>';
			case VNativeFunction(name, _, _): '<native $name>';
			case VNativeObject(obj): '<object ${Type.getClassName(Type.getClass(obj))}>';
			case VClass(classData): '<class ${classData.name}>';
			case VInstance(className, _, _): '<instance of $className>';
			case VIterator(_, idx): '<iterator @${idx[0]}>';
			case VEnumValue(eName, variant, vals):
				vals.length == 0 ? '$eName.$variant' : '$eName.$variant(${[for(v in vals) valueToString(v)].join(", ")})';
		}
	}

	// Initialize native functions
	function initializeNativeFunctions() {
		natives.set("len", VNativeFunction("len", 1, (args) -> {
			return switch (args[0]) {
				case VString(s): VNumber(s.length);
				case VArray(arr): VNumber(arr.length);
				case VDict(map): VNumber(Lambda.count(map));
				default: throw 'len() not supported';
			}
		}));

		natives.set("type", VNativeFunction("type", 1, (args) -> {
			var typeName = switch (args[0]) {
				case VNumber(_): "Number";
				case VString(_): "String";
				case VBool(_): "Bool";
				case VNull: "Null";
				case VArray(_): "Array";
				case VDict(_): "Dict";
				case VFunction(_, _): "Function";
				case VNativeFunction(_, _, _): "NativeFunction";
				case VNativeObject(obj): Type.getClassName(Type.getClass(obj));
				case VClass(classData): "Class<" + classData.name + ">";
				case VInstance(className, _, _): className;
				case VIterator(_, _): "Iterator";
				case VEnumValue(eName, variant, _): eName;
			}
			return VString(typeName);
		}));

		// print / println
		natives.set("print", VNativeFunction("print", -1, (args) -> {
			var parts = [for (a in args) valueToString(a)];
			trace(parts.join(" "));
			VNull;
		}));
		natives.set("println", VNativeFunction("println", -1, (args) -> {
			var parts = [for (a in args) valueToString(a)];
			trace(parts.join(" "));
			VNull;
		}));

		// range(n) -> [0..n-1],  range(from, to) -> [from..to-1]
		natives.set("range", VNativeFunction("range", -1, (args) -> {
			var from = 0;
			var to = 0;
			if (args.length == 1) {
				to = switch (args[0]) { case VNumber(n): Std.int(n); default: throw 'range expects numbers'; };
			} else if (args.length == 2) {
				from = switch (args[0]) { case VNumber(n): Std.int(n); default: throw 'range expects numbers'; };
				to   = switch (args[1]) { case VNumber(n): Std.int(n); default: throw 'range expects numbers'; };
			} else {
				throw 'range expects 1 or 2 arguments';
			}
			VArray([for (i in from...to) VNumber(i)]);
		}));

		// keys(dict) / values(dict) — global convenience wrappers
		natives.set("keys", VNativeFunction("keys", 1, (args) -> switch (args[0]) {
			case VDict(map): VArray([for (k in map.keys()) VString(k)]);
			default: throw 'keys() expects a dict';
		}));
		natives.set("values", VNativeFunction("values", 1, (args) -> switch (args[0]) {
			case VDict(map): VArray([for (k in map.keys()) map.get(k)]);
			default: throw 'values() expects a dict';
		}));

		// str(x) — explicit to-string
		natives.set("str", VNativeFunction("str", 1, (args) -> VString(valueToString(args[0]))));

		// int(x) / float(x) — explicit numeric conversions
		natives.set("int", VNativeFunction("int", 1, (args) -> switch (args[0]) {
			case VNumber(n): VNumber(Math.floor(n));
			case VString(s): var n = Std.parseInt(s); VNumber(n != null ? n : 0);
			case VBool(b): VNumber(b ? 1 : 0);
			default: VNumber(0);
		}));
		natives.set("float", VNativeFunction("float", 1, (args) -> switch (args[0]) {
			case VNumber(n): VNumber(n);
			case VString(s): VNumber(Std.parseFloat(s));
			case VBool(b): VNumber(b ? 1.0 : 0.0);
			default: VNumber(0.0);
		}));

		// Enum construction — called by SEnum compilation
		natives.set("__make_enum__", VNativeFunction("__make_enum__", 2, (args) -> {
			var enumName = switch (args[0]) { case VString(s): s; default: throw "enum name must be string"; };
			var variantArr = switch (args[1]) { case VArray(a): a; default: throw "enum variants must be array"; };
			// Build a dict: Color -> { Red: VEnumValue, Green: VEnumValue, Ok: VNativeFunction(...) }
			var enumDict = new Map<String, Value>();
			var i = 0;
			while (i < variantArr.length) {
				var vname = switch (variantArr[i]) { case VString(s): s; default: throw "variant name must be string"; };
				var arity = switch (variantArr[i+1]) { case VNumber(n): Std.int(n); default: 0; };
				i += 2;
				if (arity == 0) {
					enumDict.set(vname, VEnumValue(enumName, vname, []));
				} else {
					var capturedEName = enumName;
					var capturedVName = vname;
					var capturedArity  = arity;
					enumDict.set(vname, VNativeFunction(vname, capturedArity, (fargs) -> {
						return VEnumValue(capturedEName, capturedVName, fargs.copy());
					}));
				}
			}
			return VDict(enumDict);
		}));

		// `is` type check — called by EIs compilation: __is__(value, "TypeName")
		natives.set("__is__", VNativeFunction("__is__", 2, (args) -> {
			var val = args[0];
			var typeName = switch (args[1]) { case VString(s): s; default: throw "__is__: type name must be string"; };
			return VBool(switch (val) {
				case VNumber(_):       typeName == "Number" || typeName == "Int" || typeName == "Float";
				case VString(_):       typeName == "String";
				case VBool(_):         typeName == "Bool";
				case VNull:            typeName == "Null";
				case VArray(_):        typeName == "Array";
				case VDict(_):         typeName == "Dict";
				case VFunction(_, _) | VNativeFunction(_, _, _): typeName == "Function";
				case VInstance(cls, _, _): cls == typeName;
				case VEnumValue(eName, variant, _): typeName == eName || typeName == variant || typeName == (eName + "." + variant);
				default: false;
			});
		}));

		// Range matching — called by MPRange: __range_match__(subject, from, to) -> Bool
		natives.set("__range_match__", VNativeFunction("__range_match__", 3, (args) -> {
			var subject = switch (args[0]) { case VNumber(n): n; default: return VBool(false); };
			var from    = switch (args[1]) { case VNumber(n): n; default: return VBool(false); };
			var to      = switch (args[2]) { case VNumber(n): n; default: return VBool(false); };
			return VBool(subject >= from && subject <= to);
		}));

		// Enum variant matching — called by MPEnum in compileMatch
		// __enum_variant_match__(subject, variantName) -> Bool
		// Returns true if subject is VEnumValue with matching variant name.
		// Used to distinguish enum case vs variable bind in match.
		natives.set("__enum_variant_match__", VNativeFunction("__enum_variant_match__", 2, (args) -> {
			return switch (args[0]) {
				case VEnumValue(_, variant, _):
					VBool(variant == switch (args[1]) { case VString(s): s; default: ""; });
				default: VBool(false); // not an enum value — fall through to bind
			};
		}));

		// __using_register__ removed

		// math constants
		natives.set("PI",  VNumber(Math.PI));
		natives.set("INF", VNumber(Math.POSITIVE_INFINITY));
		natives.set("NAN", VNumber(Math.NaN));

		// math functions
		natives.set("abs",   VNativeFunction("abs",   1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.abs(n));   default: throw 'Expected number'; }));
		natives.set("floor", VNativeFunction("floor", 1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.floor(n)); default: throw 'Expected number'; }));
		natives.set("ceil",  VNativeFunction("ceil",  1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.ceil(n));  default: throw 'Expected number'; }));
		natives.set("round", VNativeFunction("round", 1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.round(n)); default: throw 'Expected number'; }));
		natives.set("sqrt",  VNativeFunction("sqrt",  1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.sqrt(n));  default: throw 'Expected number'; }));
		natives.set("pow",   VNativeFunction("pow",   2, (args) -> switch [args[0], args[1]] { case [VNumber(a), VNumber(b)]: VNumber(Math.pow(a, b)); default: throw 'Expected numbers'; }));
		natives.set("min",   VNativeFunction("min",   2, (args) -> switch [args[0], args[1]] { case [VNumber(a), VNumber(b)]: VNumber(Math.min(a, b)); default: throw 'Expected numbers'; }));
		natives.set("max",   VNativeFunction("max",   2, (args) -> switch [args[0], args[1]] { case [VNumber(a), VNumber(b)]: VNumber(Math.max(a, b)); default: throw 'Expected numbers'; }));
		natives.set("random", VNativeFunction("random", 0, (_) -> VNumber(Math.random())));
		natives.set("sin",   VNativeFunction("sin",   1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.sin(n));   default: throw 'Expected number'; }));
		natives.set("cos",   VNativeFunction("cos",   1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.cos(n));   default: throw 'Expected number'; }));
		natives.set("tan",   VNativeFunction("tan",   1, (args) -> switch (args[0]) { case VNumber(n): VNumber(Math.tan(n));   default: throw 'Expected number'; }));
	}
}

// Switch to Types, Structures are Dynamic and for properties expensive.

@:structInit
class CallFrame {
	public var chunk:Chunk;
	public var ip:Int;
	public var stackBase:Int;
	public var localVars:Map<String, Value>;
	public var upvalues:Array<Value>;
	public var functionName:String;

	public function new(chunk, ip, stackBase, localVars, upvalues, functionName) {
		this.chunk = chunk;
		this.ip = ip;
		this.stackBase = stackBase;
		this.localVars = localVars;
		this.upvalues = upvalues;
		this.functionName = functionName;
	}
}

@:structInit
class CatchHandler {
	public var stackDepth:Int;
	public var framesDepth:Int;
	public var catchIP:Int;
}

class ScriptException {
	public var value:Value;

	public function new(v:Value) {
		value = v;
	}
}

/**
 * Describes how a native Haxe object field is accessed.
 * NativeFieldCache removed — direct Reflection used instead.
 */
// NativeFieldKind removed


/**
 * Controls how aggressively the VM flushes its internal object caches.
 * See VM.gc_kind for full documentation.
 */
enum GcKind {
	/** Flush all caches on every execute() call. Lowest memory, highest re-warm cost. */
	AGGRESSIVE;
	/** Flush caches when tracked object count exceeds the soft threshold (default 512). */
	SOFT;
	/** Never flush caches proactively. Maximum throughput for hot re-execution. */
	VERY_SOFT;
}
