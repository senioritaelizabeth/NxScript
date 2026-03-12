package nx.script;

import nx.script.Bytecode;
import nx.script.nativeReflection.NxReflect;
import haxe.ds.ObjectMap;

using StringTools;

/**
 * The VM. It runs bytecode. That's literally the whole job.
 *
 * Architecture notes for the brave:
 * - Pre-allocated 512-slot stack. No Array.push(), no realloc, no crying.
 * - Locals live directly on the stack (stackBase..stackBase+localCount-1).
 *   Allocating a fresh array per call was cute. We don't do that anymore.
 * - EMPTY_MAP is a shared sentinel for closures that capture nothing.
 *   Avoids `new Map()` on every single function call. You're welcome.
 * - RETURN restores `sp = savedBase`, unwinding the callee's locals without touching a GC.
 * - MAKE_FUNC caches VFunction(chunk, EMPTY_MAP) per function index.
 *   Because creating the same object 100,000 times per second is a cry for help.
 * - Trampoline architecture: RETURN with frames.length > 0 restores the outer frame
 *   and CONTINUES in the same run() invocation. Do not call run() twice. You'll know why.
 */
class VM {
	// One Map to rule them all — shared across every zero-capture function. Never write to this.
	static var EMPTY_MAP:Map<String, Value> = new Map<String, Value>();
	static inline var NATIVE_SUPER_INSTANCE_FIELD = "__native_super_instance";

	// The stack. 512 slots, pre-allocated, sp is the logical top.
	// If you overflow this, you wrote infinite recursion. That's on you.
	var stack:Array<Value>;
	var sp:Int = 0;

	/** Global variables. Set from Haxe with `vm.globals.set(name, value)`, or via top-level script assignments. */
	public var globals:Map<String, Value>;

	// Let-scoped variables (block-level) and compile-time constants
	var scopeVars:Map<String, Value>;
	var constVars:Map<String, Value>;

	// The call stack. frames[last] is currentFrame. Don't touch frames directly in hot code.
	var frames:Array<CallFrame> = [];
	var currentFrame:CallFrame;

	/** Externally-registered native Haxe functions. Prefer `Interpreter.register()` over writing to this directly. */
	public var natives:Map<String, Value>;

	/** Class registry. Populated by MAKE_CLASS instructions and NativeClasses.registerAll(). Used for inheritance lookups during instantiation. */
	public var classes:Map<String, ClassData>;

	public var debug:Bool = false;

	/** Maximum instructions before the VM throws. Default 10,000,000. Raise it if you have a very long-running script; lower it if you want a tighter sandbox. */
	public var maxInstructions:Int = 10000000;

	/** Maximum call depth before the VM throws. Default 10,000. Set <= 0 to disable this guard. */
	public var maxCallDepth:Int = 10000;

	var catchStack:Array<CatchHandler> = [];
	var globalSlotValues:Array<Value>;
	var globalSlotNames:Array<String>;
	var globalSlotByName:Map<String, Int>;
	var globalSlotIsConst:Array<Bool>;
	var globalSlotConstInit:Array<Bool>;
	var arrayMethodCache:ObjectMap<Dynamic, Map<String, Value>>;
	var instanceMethodCache:ObjectMap<Dynamic, Map<String, Value>>;
	var nativeArgBuffers:Map<Int, Array<Value>>;

	// Per-class cache: className -> fieldName -> isMethod (true = method, false = plain field)
	// Avoids repeated Reflect.isFunction checks for the same class+field pair in hot loops.
	static var nativeFieldIsMethod:Map<String, Map<String, Bool>> = new Map();

	/** Script name shown in runtime error messages. Set to a file path for useful stack traces. */
	public var scriptName:String = "script";

	/** The instruction currently executing. Only populated when `debug = true`. Null otherwise. */
	public var currentInstruction:Instruction = null;

	/**
	 * Creates a VM. Optionally pass debug=true to get a trace per instruction.
	 * Don't pass debug=true in production unless you enjoy reading walls of text.
	 */
	public function new(debug:Bool = false) {
		this.debug = debug;
		stack = [for (_ in 0...512) VNull]; // pre-allocated — resizing at runtime would be embarrassing
		sp = 0;
		globals = new Map();
		scopeVars = new Map();
		constVars = new Map();
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

		initializeNativeFunctions();
		NativeClasses.registerAll(this);
	}

	/**
	 * Runs a compiled Chunk from the top level.
	 * Resets all execution state — don't call this mid-execution expecting continuity.
	 * Builds the flat [op, arg, op, arg...] dispatch array on first run (cached forever after).
	 */
	public function execute(chunk:Chunk):Value {
		sp = 0;
		frames = [];
		catchStack = [];
		arrayMethodCache = new ObjectMap();
		instanceMethodCache = new ObjectMap();
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
		var sp = this.sp; // manual stack pointer — avoids Array.push/pop resize overhead*/

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
									if (y == 0)
										throw 'Division by zero';
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
							var argStart = objectIndex + 1;
							switch (memberField) {
								case "push":
									if (memberArgc != 1)
										throw 'Native function push expects 1 arguments, got $memberArgc';
									arr.push(stack[argStart]);
									sp = objectIndex;
									stack[sp++] = VNull;
									continue;
								case "pop":
									if (memberArgc != 0)
										throw 'Native function pop expects 0 arguments, got $memberArgc';
									sp = objectIndex;
									stack[sp++] = arr.length == 0 ? VNull : arr.pop();
									continue;
								case "shift":
									if (memberArgc != 0)
										throw 'Native function shift expects 0 arguments, got $memberArgc';
									sp = objectIndex;
									stack[sp++] = arr.length == 0 ? VNull : arr.shift();
									continue;
								case "unshift":
									if (memberArgc != 1)
										throw 'Native function unshift expects 1 arguments, got $memberArgc';
									arr.unshift(stack[argStart]);
									sp = objectIndex;
									stack[sp++] = VNull;
									continue;
								case "first":
									if (memberArgc != 0)
										throw 'Native function first expects 0 arguments, got $memberArgc';
									sp = objectIndex;
									stack[sp++] = arr.length > 0 ? arr[0] : VNull;
									continue;
								case "last":
									if (memberArgc != 0)
										throw 'Native function last expects 0 arguments, got $memberArgc';
									sp = objectIndex;
									stack[sp++] = arr.length > 0 ? arr[arr.length - 1] : VNull;
									continue;
								case "contains":
									if (memberArgc != 1)
										throw 'Native function contains expects 1 arguments, got $memberArgc';
									var searchValue = stack[argStart];
									var found = false;
									for (item in arr) {
										if (valuesEqual(item, searchValue)) {
											found = true;
											break;
										}
									}
									sp = objectIndex;
									stack[sp++] = VBool(found);
									continue;
								case "indexOf":
									if (memberArgc != 1)
										throw 'Native function indexOf expects 1 arguments, got $memberArgc';
									var idxValue = stack[argStart];
									var idx = -1;
									for (i in 0...arr.length) {
										if (valuesEqual(arr[i], idxValue)) {
											idx = i;
											break;
										}
									}
									sp = objectIndex;
									stack[sp++] = VNumber(idx);
									continue;
								case "reverse":
									if (memberArgc != 0)
										throw 'Native function reverse expects 0 arguments, got $memberArgc';
									arr.reverse();
									sp = objectIndex;
									stack[sp++] = VArray(arr);
									continue;
								case "join":
									if (memberArgc != 1)
										throw 'Native function join expects 1 arguments, got $memberArgc';
									var delim = switch (stack[argStart]) {
										case VString(s): s;
										default: ",";
									}
									var parts = [for (v in arr) valueToString(v)];
									sp = objectIndex;
									stack[sp++] = VString(parts.join(delim));
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
					if (debug)
						trace('GET_MEMBER: field=$field, object type=${Type.enumConstructor(object)}');
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
					var setupArg = code[ip - 4];
					var varSlot = setupArg & 0xFFFF;
					var endSlot = setupArg >>> 16;
					var cur = stack[frameBase + varSlot];
					var lend = stack[frameBase + endSlot];
					switch [cur, lend] {
						case [VNumber(c), VNumber(e)]:
							if (c >= e)
								ip += arg * 2;
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
			constructor: constructor
		};

		// Register class in global registry
		classes.set(className, classData);

		push(VClass(classData));
	}

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

	function call(callee:Value, args:Array<Value>):Value {
		return switch (callee) {
			case VFunction(funcChunk, closure):
				if (args.length != funcChunk.paramCount) {
					throw 'Function ${funcChunk.name} expects ${funcChunk.paramCount} arguments, got ${args.length}';
				}

				// Stack-based locals: reserve stack[localsBase..localsBase+localCount-1]
				var localCount = funcChunk.localCount;
				var localsBase = this.sp;
				for (i in 0...localCount)
					stack[localsBase + i] = VNull;
				// Params occupy slots 0..paramCount-1
				for (i in 0...args.length)
					stack[localsBase + i] = args[i];
				// Closure vars → slots: O(1) with localSlots map, O(n) fallback with indexOf
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

				// Avoid new Map() when closure is empty — reuse EMPTY_MAP sentinel.
				// setVariable will lazy-alloc if a 'let' binding is ever written.
				var localVars:Map<String, Value>;
				if (closure == EMPTY_MAP) {
					localVars = EMPTY_MAP;
				} else {
					localVars = new Map<String, Value>();
					for (key in closure.keys())
						localVars.set(key, closure.get(key));
				}

				this.sp = localsBase + localCount;
				var newFrame:CallFrame = {
					chunk: funcChunk.chunk,
					ip: 0,
					stackBase: localsBase,
					localVars: localVars,
					upvalues: frameUpvalues,
					functionName: funcChunk.name
				};

				if (maxCallDepth > 0 && frames.length + 1 > maxCallDepth)
					throw 'Execution exceeded maximum call depth ($maxCallDepth) - possible infinite recursion';

				frames.push(newFrame);
				currentFrame = newFrame;

				return run();

			case VNativeFunction(name, arity, fn):
				// -1 arity means variadic (no argument count check)
				if (arity != -1 && args.length != arity) {
					throw 'Native function $name expects $arity arguments, got ${args.length}';
				}
				return fn(args);

			default:
				throw 'Value is not callable: $callee';
		}
	}

	function buildUpvalueArray(funcChunk:FunctionChunk, closure:Map<String, Value>):Array<Value> {
		var names = funcChunk.upvalueNames;
		if (names == null || names.length == 0)
			return [];

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

	function getVariable(name:String):Value {
		if (currentFrame.localVars != EMPTY_MAP && currentFrame.localVars.exists(name))
			return currentFrame.localVars.get(name);
		if (scopeVars.exists(name))
			return scopeVars.get(name);
		if (constVars.exists(name))
			return constVars.get(name);
		if (globals.exists(name))
			return globals.get(name);
		if (natives.exists(name))
			return natives.get(name);
		return null;
	}

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

	public function haxeToValue(value:Dynamic):Value {
		if (value == null)
			return VNull;
		if (Std.isOfType(value, Bool))
			return VBool(value);
		if (Std.isOfType(value, Int) || Std.isOfType(value, Float))
			return VNumber(value);
		if (Std.isOfType(value, String))
			return VString(value);
		if (Std.isOfType(value, Array)) {
			var arr:Array<Dynamic> = value;
			return VArray([for (v in arr) haxeToValue(v)]);
		}
		// For other objects, wrap as native object
		return VNativeObject(value);
	}

	public function valueToHaxe(value:Value):Dynamic {
		if (value == null) {
			return null;
		}
		return switch (value) {
			case VNumber(n): n;
			case VString(s): s;
			case VBool(b): b;
			case VNull: null;
			case VArray(arr): [for (v in arr) valueToHaxe(v)];
			case VDict(map):
				var obj = {};
				for (key in map.keys()) {
					Reflect.setField(obj, key, valueToHaxe(map.get(key)));
				}
				obj;
			case VNativeObject(obj): obj;
			default: null;
		}
	}

	/**
	 * Calls a script function from Haxe. Saves and restores all VM state around the call,
	 * so you don't spin up a fresh VM (which was the old approach, and it was bad).
	 * Locals go directly onto stack[0..localCount-1]; expression stack starts above them.
	 */
	public function callFunction(func:FunctionChunk, closure:Map<String, Value>, args:Array<Value>):Value {
		// Stack-based locals: reserve stack[0..localCount-1] for func frame
		var localCount = func.localCount;
		for (i in 0...localCount)
			stack[i] = VNull;
		for (i in 0...args.length)
			stack[i] = args[i];
		// O(1) closure-to-slot mapping with localSlots, O(n) fallback
		if (closure != EMPTY_MAP) {
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

		// Avoid closure.copy() when closure is empty
		var localVars:Map<String, Value>;
		if (closure == EMPTY_MAP) {
			localVars = EMPTY_MAP;
		} else {
			localVars = closure.copy();
		}
		for (i in 0...args.length)
			if (i < func.paramNames.length)
				localVars.set(func.paramNames[i], args[i]);

		var savedFrames = this.frames;
		var savedCurrentFrame = this.currentFrame;
		var savedScopeVars = this.scopeVars;
		var savedConstVars = this.constVars;
		var savedCatchStack = this.catchStack;
		var savedSp = this.sp;
		var frameUpvalues = buildUpvalueArray(func, closure);

		var funcFrame:CallFrame = {
			chunk: func.chunk,
			ip: 0,
			stackBase: 0,
			localVars: localVars,
			upvalues: frameUpvalues,
			functionName: func.name
		};

		this.frames = [funcFrame];
		this.currentFrame = funcFrame;
		this.scopeVars = new Map();
		this.constVars = new Map();
		this.catchStack = [];
		this.sp = localCount;

		var result = run();

		this.frames = savedFrames;
		this.currentFrame = savedCurrentFrame;
		this.scopeVars = savedScopeVars;
		this.constVars = savedConstVars;
		this.catchStack = savedCatchStack;
		this.sp = savedSp;

		return result;
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
				if (y == 0)
					throw 'Division by zero';
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
	function equals(a:Value, b:Value):Bool {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: x == y;
			case [VString(x), VString(y)]: x == y;
			case [VBool(x), VBool(y)]: x == y;
			case [VNull, VNull]: true;
			default: false;
		}
	}

	function compare(a:Value, b:Value):Int {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: if (x < y) -1 else if (x > y) 1 else 0;
			case [VString(x), VString(y)]: if (x < y) -1 else if (x > y) 1 else 0;
			default: throw 'Cannot compare';
		}
	}

	function isTruthy(value:Value):Bool {
		return switch (value) {
			case VNull: false;
			case VBool(b): b;
			case VNumber(n): n != 0;
			case VString(s): s.length > 0;
			default: true;
		}
	}

	// Member access
	public function getMember(object:Value, field:String):Value {
		return switch (object) {
			case VNumber(n): getNumberMethod(n, field);
			case VString(s): getStringMethod(s, field);
			case VArray(arr): getArrayMethod(arr, field);
			case VDict(map): map.exists(field) ? map.get(field) : VNull;
			case VInstance(className, fields, classData):
				// Check instance fields first
				if (fields.exists(field)) {
					return fields.get(field);
				}

				var cachedInstanceMethods = instanceMethodCache.get(fields);
				if (cachedInstanceMethods != null && cachedInstanceMethods.exists(field)) {
					return cachedInstanceMethods.get(field);
				}

				// Check methods in class hierarchy
				var currentClass = classData;
				while (currentClass != null) {
					if (currentClass.methods.exists(field)) {
						var method = currentClass.methods.get(field);
						// Return a bound method (closure with 'this')
						var bound = VFunction(method, ["this" => object]);
						if (cachedInstanceMethods == null) {
							cachedInstanceMethods = new Map<String, Value>();
							instanceMethodCache.set(fields, cachedInstanceMethods);
						}
						cachedInstanceMethods.set(field, bound);
						return bound;
					}
					// Look in parent class
					if (currentClass.superClass != null && classes.exists(currentClass.superClass)) {
						currentClass = classes.get(currentClass.superClass);
					} else {
						currentClass = null;
					}
				}

				// Fallback to native base object when this script class extends a native class.
				var nativeBase = fields.get(NATIVE_SUPER_INSTANCE_FIELD);
				switch (nativeBase) {
					case VNativeObject(_):
						return getMember(nativeBase, field);
					default:
				}

				throw 'Field $field not found in class $className';
			case VNativeObject(obj):
				// Per-class cache: first access probes + caches whether field is method or value.
				// Hot path (already cached): one Map.get + one NxReflect.get, no try/catch, no
				// isFunction check.
				var cls = Type.getClass(obj);
				if (cls != null) {
					var className = Type.getClassName(cls);
					var classDescs = nativeFieldIsMethod.get(className);
					if (classDescs == null) {
						classDescs = new Map();
						nativeFieldIsMethod.set(className, classDescs);
					}
					var isMethod = classDescs.get(field);
					if (isMethod == null) {
						// Cold path — probe field once, cache result.
						var raw:Any = NxReflect.probe(obj, field);
						isMethod = !!(raw != null && NxReflect.isFunction(raw));
						classDescs.set(field, isMethod);
						if (isMethod) {
							// Also cache the VNativeFunction so we don't alloc a closure next time
							var cachedMethods = instanceMethodCache.get(obj);
							if (cachedMethods == null) {
								cachedMethods = new Map();
								instanceMethodCache.set(obj, cachedMethods);
							}
							final capturedFn = raw;
							var bound = VNativeFunction(field, -1, (args:Array<Value>) -> {
								return haxeToValue(NxReflect.callMethod(obj, capturedFn, [for (a in args) valueToHaxe(a)]));
							});
							cachedMethods.set(field, bound);
							return bound;
						}
						return raw == null ? VNull : haxeToValue(raw);
					}
					if (isMethod) {
						// Hot method path — return cached VNativeFunction, no closure alloc.
						var cachedMethods = instanceMethodCache.get(obj);
						if (cachedMethods != null) {
							var cached = cachedMethods.get(field);
							if (cached != null)
								return cached;
						}
						// Miss (e.g. first call after cache cleared): build and cache
						if (cachedMethods == null) {
							cachedMethods = new Map();
							instanceMethodCache.set(obj, cachedMethods);
						}
						var fn:Dynamic = NxReflect.get(obj, field);
						var bound = VNativeFunction(field, -1, (args:Array<Value>) -> {
							return haxeToValue(NxReflect.callMethod(obj, fn, [for (a in args) valueToHaxe(a)]));
						});
						cachedMethods.set(field, bound);
						return bound;
					}
					// Hot plain-field path — single NxReflect.get, no overhead.
					return haxeToValue(NxReflect.get(obj, field));
				} else {
					// Anonymous object (no class) — skip class cache.
					var raw:Dynamic = NxReflect.probe(obj, field);
					if (raw != null && NxReflect.isFunction(raw)) {
						return VNativeFunction(field, -1, (args:Array<Value>) -> {
							return haxeToValue(NxReflect.callMethod(obj, raw, [for (a in args) valueToHaxe(a)]));
						});
					}
					return raw == null ? VNull : haxeToValue(raw);
				}
			default: throw 'Cannot access member $field';
		}
	}

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
			case VNativeObject(obj):
				// Inline unbox common types to avoid full valueToHaxe() call,
				// then use NxReflect.set for the fastest platform write path.
				var raw:Dynamic = switch (value) {
					case VNumber(n): n;
					case VString(s): s;
					case VBool(b): b;
					case VNull: null;
					case VNativeObject(o): o;
					default: valueToHaxe(value);
				};
				NxReflect.set(obj, field, raw);
			default:
				throw 'Cannot set member $field';
		}
	}

	function getIndex(object:Value, index:Value):Value {
		return switch [object, index] {
			case [VArray(arr), VNumber(i)]:
				var idx = Std.int(i);
				if (idx < 0 || idx >= arr.length)
					throw 'Index out of bounds: $idx';
				arr[idx];
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
						if (Reflect.isFunction(clsOrObj))
							Reflect.callMethod(null, clsOrObj, haxeArgs);
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

	function setIndex(object:Value, index:Value, value:Value) {
		switch [object, index] {
			case [VArray(arr), VNumber(i)]:
				var idx = Std.int(i);
				if (idx < 0 || idx >= arr.length)
					throw 'Index out of bounds: $idx';
				arr[idx] = value;
			case [VDict(map), _]:
				map.set(valueToString(index), value);
			default:
				throw 'Cannot set index';
		}
	}

	// Iterator support
	function getIterator(iterable:Value):Value {
		return switch (iterable) {
			case VArray(arr):
				// VIterator holds a direct ref to the array and a single-element
				// Array<Int> as a mutable index box — no Map allocation, no VDict overhead.
				VIterator(arr, [0]);
			default: throw 'Value is not iterable';
		}
	}

	function iteratorNext(iterator:Value):Value {
		return switch (iterator) {
			case VIterator(arr, idx):
				var i = idx[0];
				if (i >= arr.length)
					return null;
				idx[0] = i + 1;
				return arr[i];
			// Legacy VDict iterator kept for backwards compat if any external code creates one
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

			default: throw 'Unknown Number method: $method';
		}
	}

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
			case "int": VNativeFunction("int", 0, (_) -> VNumber(Std.parseInt(s) != null ? Std.parseInt(s) : 0));
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

			default: throw 'Unknown String method: $method';
		}
	}

	function getArrayMethod(arr:Array<Value>, method:String):Value {
		if (method == "length")
			return VNumber(arr.length);

		var cachedMethods = arrayMethodCache.get(arr);
		if (cachedMethods != null && cachedMethods.exists(method))
			return cachedMethods.get(method);

		var bound = switch (method) {
			// Properties
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

			// Search - need to compare values properly
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

			default: throw 'Unknown Array method: $method';
		}

		if (cachedMethods == null) {
			cachedMethods = new Map<String, Value>();
			arrayMethodCache.set(arr, cachedMethods);
		}
		cachedMethods.set(method, bound);
		return bound;
	}

	// Helper to compare two Values for equality
	function valuesEqual(a:Value, b:Value):Bool {
		return switch [a, b] {
			case [VNumber(x), VNumber(y)]: x == y;
			case [VString(x), VString(y)]: x == y;
			case [VBool(x), VBool(y)]: x == y;
			case [VNull, VNull]: true;
			default: false; // Arrays, objects, etc need deep comparison
		}
	}

	// Helper functions
	function toInt(value:Value):Int {
		return switch (value) {
			case VNumber(n): Std.int(n);
			default: throw 'Expected number';
		}
	}

	function toNum(value:Value):Float {
		return switch (value) {
			case VNumber(n): n;
			case VBool(b): b ? 1.0 : 0.0;
			case VNull: 0.0;
			default: throw 'Expected number';
		}
	}

	// Public API
	public function instantiateClassByName(name:String, args:Array<Value>):Value {
		var classValue = getVariable(name);
		return switch (classValue) {
			case VClass(classData): instantiateFromClassData(classData, args);
			default: throw 'Value $name is not a class';
		}
	}

	public function callInstanceMethod(instance:Value, methodName:String, args:Array<Value>):Value {
		var callable = getMember(instance, methodName);
		return call(callable, args);
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

	public function callMethod(name:String, args:Array<Value>):Value {
		syncGlobalSlotsFromMap();
		var func = getVariable(name);
		if (func == null)
			throw 'Undefined function: $name';
		return call(func, args);
	}

	/** Resolve a callable by name once, then reuse it with callResolved/callResolved0 in host hot loops. */
	public function resolveCallable(name:String):Value {
		syncGlobalSlotsFromMap();
		var func = getVariable(name);
		if (func == null)
			throw 'Undefined function: $name';
		return func;
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

	/** Call a previously resolved callable value (avoids repeated global lookup by name). */
	public inline function callResolved(callee:Value, args:Array<Value>):Value {
		return call(callee, args);
	}

	public function valueToString(value:Value):String {
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
			}
			return VString(typeName);
		}));
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
