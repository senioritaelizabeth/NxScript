package nz.script;

import nz.script.Bytecode;

using StringTools;

/**
 * Virtual Machine that executes bytecode
 */
class VM {
	// Stack for execution
	var stack:Array<Value> = [];

	// Variables storage
	public var variables:Map<String, Value>;

	var letVariables:Map<String, Value>;
	var constVariables:Map<String, Value>;

	// Call frames for function calls
	var frames:Array<CallFrame> = [];
	var currentFrame:CallFrame;

	// Native functions
	public var methods:Map<String, Value>;

	// Classes registry (for inheritance lookup)
	public var classes:Map<String, ClassData>;

	public var debug:Bool = false;

	public var maxInstructions:Int = 1000000; // Safety limit

	var instructionCount:Int = 0;

	// Script information for debugging
	public var scriptName:String = "script";

	public var currentInstruction:Instruction = null;

	public function new(debug:Bool = false) {
		this.debug = debug;
		variables = new Map();
		letVariables = new Map();
		constVariables = new Map();
		methods = new Map();
		classes = new Map();

		initializeNativeFunctions();
		NativeClasses.registerAll(this);
	}

	public function execute(chunk:Chunk):Value {
		// Create initial frame
		currentFrame = {
			chunk: chunk,
			ip: 0,
			stackStart: 0,
			localVars: new Map()
		};
		frames.push(currentFrame);

		return run();
	}

	function run():Value {
		while (true) {
			// Safety check
			instructionCount++;
			if (instructionCount > maxInstructions) {
				throw 'Execution exceeded maximum instruction limit ($maxInstructions) - possible infinite loop';
			}

			if (currentFrame.ip >= currentFrame.chunk.instructions.length) {
				break;
			}

			var inst = currentFrame.chunk.instructions[currentFrame.ip];
			currentInstruction = inst; // Store current instruction for native functions
			currentFrame.ip++;

			if (debug) {
				var varInfo = [for (k in letVariables.keys()) '$k=${letVariables.get(k)}'].join(", ");
				trace('Stack: ${stack.length} | IP: ${currentFrame.ip - 1} | Op: ${Op.getName(inst.op)} | Vars: {$varInfo}');
			}

			switch (inst.op) {
				case Op.LOAD_CONST:
					push(currentFrame.chunk.constants[inst.arg]);

				case Op.LOAD_VAR:
					var name = currentFrame.chunk.strings[inst.arg];
					var value = getVariable(name);
					if (value == null)
						throw 'Undefined variable: $name';
					push(value);

				case Op.STORE_VAR:
					var name = currentFrame.chunk.strings[inst.arg];
					setVariable(name, peek(), false);

				case Op.STORE_LET:
					var name = currentFrame.chunk.strings[inst.arg];
					var value = peek();
					letVariables.set(name, value);
					currentFrame.localVars.set(name, value);

				case Op.STORE_CONST:
					var name = currentFrame.chunk.strings[inst.arg];
					constVariables.set(name, peek());

				case Op.POP:
					pop();

				case Op.DUP:
					push(peek());

				// Arithmetic
				case Op.ADD:
					binaryOp(add);
				case Op.SUB:
					binaryOp(subtract);
				case Op.MUL:
					binaryOp(multiply);
				case Op.DIV:
					binaryOp(divide);
				case Op.MOD:
					binaryOp(modulo);
				case Op.NEG:
					push(negate(pop()));

				// Bitwise
				case Op.BIT_AND:
					push(VNumber(toInt(pop()) & toInt(pop())));
				case Op.BIT_OR:
					push(VNumber(toInt(pop()) | toInt(pop())));
				case Op.BIT_XOR:
					push(VNumber(toInt(pop()) ^ toInt(pop())));
				case Op.BIT_NOT:
					push(VNumber(~toInt(pop())));
				case Op.SHIFT_LEFT:
					var b = toInt(pop());
					var a = toInt(pop());
					push(VNumber(a << b));
				case Op.SHIFT_RIGHT:
					var b = toInt(pop());
					var a = toInt(pop());
					push(VNumber(a >> b));

				// Comparison
				case Op.EQ:
					var b = pop();
					var a = pop();
					push(VBool(equals(a, b)));
				case Op.NEQ:
					var b = pop();
					var a = pop();
					push(VBool(!equals(a, b)));
				case Op.LT:
					comparisonOp((a, b) -> a < b);
				case Op.GT:
					comparisonOp((a, b) -> a > b);
				case Op.LTE:
					comparisonOp((a, b) -> a <= b);
				case Op.GTE:
					comparisonOp((a, b) -> a >= b);

				// Logical
				case Op.AND:
					var b = pop();
					var a = pop();
					push(VBool(isTruthy(a) && isTruthy(b)));
				case Op.OR:
					var b = pop();
					var a = pop();
					push(VBool(isTruthy(a) || isTruthy(b)));
				case Op.NOT:
					push(VBool(!isTruthy(pop())));

				// Control flow
				case Op.JUMP:
					currentFrame.ip += inst.arg;
				case Op.JUMP_IF_FALSE:
					if (!isTruthy(peek()))
						currentFrame.ip += inst.arg;
					pop();
				case Op.JUMP_IF_TRUE:
					if (isTruthy(peek()))
						currentFrame.ip += inst.arg;
					pop();

				// Functions
				case Op.CALL:
					var args:Array<Value> = [];
					for (i in 0...inst.arg)
						args.unshift(pop());
					var callee = pop();
					push(call(callee, args));

				case Op.RETURN:
					var result = pop();
					frames.pop();
					if (frames.length == 0)
						return result;
					currentFrame = frames[frames.length - 1];
					push(result);

				case Op.MAKE_FUNC:
					var funcChunk = currentFrame.chunk.functions[inst.arg];
					var closure = new Map<String, Value>();
					for (key in letVariables.keys())
						closure.set(key, letVariables.get(key));
					push(VFunction(funcChunk, closure));

				case Op.MAKE_LAMBDA:
					var funcChunk = currentFrame.chunk.functions[inst.arg];
					var closure = new Map<String, Value>();
					for (key in letVariables.keys())
						closure.set(key, letVariables.get(key));
					for (key in currentFrame.localVars.keys())
						closure.set(key, currentFrame.localVars.get(key));
					push(VFunction(funcChunk, closure));

				// Data structures
				case Op.MAKE_ARRAY:
					var elements:Array<Value> = [];
					for (i in 0...inst.arg)
						elements.unshift(pop());
					push(VArray(elements));

				case Op.MAKE_DICT:
					var map = new Map<String, Value>();
					for (i in 0...inst.arg) {
						var value = pop();
						var key = valueToString(pop());
						map.set(key, value);
					}
					push(VDict(map));

				case Op.GET_MEMBER:
					var field = currentFrame.chunk.strings[inst.arg];
					var object = pop();
					if (debug)
						trace('GET_MEMBER: field=$field, object type=${Type.enumConstructor(object)}');
					push(getMember(object, field));

				case Op.SET_MEMBER:
					var field = currentFrame.chunk.strings[inst.arg];
					var object = pop(); // El objeto está arriba
					var value = pop(); // El valor está debajo
					setMember(object, field, value);
					push(value);

				case Op.GET_INDEX:
					var index = pop();
					var object = pop();
					push(getIndex(object, index));

				case Op.SET_INDEX:
					var value = pop();
					var index = pop();
					var object = pop();
					setIndex(object, index, value);
					push(value);

				// Classes
				case Op.MAKE_CLASS:
					// Decode counts: methods = high 16 bits, fields = low 16 bits
					var counts = inst.arg;
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

					// Pop super class
					var superClass:Null<String> = switch (pop()) {
						case VNull: null;
						case VNativeObject(_): "HaxeNative"; // Placeholder for native inheritance
						case VClass(c): c.name;
						default: throw "Super class must be null or a class";
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
						methods: methods,
						fields: fields,
						constructor: constructor
					};

					// Register class in global registry
					classes.set(className, classData);

					push(VClass(classData));

				case Op.INSTANTIATE:
					var argCount = inst.arg;
					var args:Array<Value> = [];
					for (i in 0...argCount) {
						args.unshift(pop());
					}

					var classValue = pop();

					var instance = switch (classValue) {
						case VClass(classData):
							// Create instance with fields from the entire inheritance chain
							var instanceFields = new Map<String, Value>();

							// Collect fields from parent classes first
							var currentClass = classData;
							var classChain:Array<ClassData> = [];
							while (currentClass != null) {
								classChain.unshift(currentClass); // Add to front
								if (currentClass.superClass != null && classes.exists(currentClass.superClass)) {
									currentClass = classes.get(currentClass.superClass);
								} else {
									currentClass = null;
								}
							}

							// Apply fields from parent to child (so child overrides parent)
							for (cls in classChain) {
								for (field in cls.fields.keys()) {
									instanceFields.set(field, cls.fields.get(field));
								}
							}

							var inst = VInstance(classData.name, instanceFields, classData);

							// Call constructor if it exists
							if (classData.constructor != null) {
								// Check argument count
								if (args.length != classData.constructor.paramCount) {
									throw 'Constructor expects ${classData.constructor.paramCount} arguments, got ${args.length}';
								}

								// Execute constructor by creating a temporary VM instance
								// This is a hack to avoid frame management issues
								var tempVM = new VM(debug);
								tempVM.variables = this.variables;
								tempVM.methods = this.methods;
								tempVM.classes = this.classes;
								tempVM.letVariables = new Map();
								tempVM.constVariables = new Map();

								// Create frame for constructor
								tempVM.frames = [
									{
										chunk: classData.constructor.chunk,
										ip: 0,
										stackStart: 0,
										localVars: new Map()
									}
								];
								tempVM.currentFrame = tempVM.frames[0];

								// Set 'this' and parameters
								tempVM.currentFrame.localVars.set("this", inst);
								for (i in 0...args.length) {
									tempVM.currentFrame.localVars.set(classData.constructor.paramNames[i], args[i]);
								}

								// Run constructor (result is ignored)
								tempVM.run();
							}

							inst;
						default:
							throw 'Cannot instantiate non-class value';
					}

					push(instance);

				case Op.GET_THIS:
					var thisValue = getVariable("this");
					if (thisValue == null) {
						throw "'this' is not defined in this context";
					}
					push(thisValue);

				// Iteration
				case Op.GET_ITER:
					push(getIterator(pop()));

				case Op.FOR_ITER:
					var iterator = peek();
					var next = iteratorNext(iterator);
					if (next == null) {
						pop();
						currentFrame.ip += inst.arg;
					} else {
						push(next);
					}

				// Special
				case Op.LOAD_NULL:
					push(VNull);
				case Op.LOAD_TRUE:
					push(VBool(true));
				case Op.LOAD_FALSE:
					push(VBool(false));

				default:
					throw 'Unknown opcode: 0x${StringTools.hex(inst.op, 2)}';
			}
		}

		return stack.length > 0 ? pop() : VNull;
	}

	function call(callee:Value, args:Array<Value>):Value {
		return switch (callee) {
			case VFunction(funcChunk, closure):
				if (args.length != funcChunk.paramCount) {
					throw 'Function ${funcChunk.name} expects ${funcChunk.paramCount} arguments, got ${args.length}';
				}

				var newFrame:CallFrame = {
					chunk: funcChunk.chunk,
					ip: 0,
					stackStart: stack.length,
					localVars: new Map()
				};

				for (i in 0...args.length) {
					newFrame.localVars.set(funcChunk.paramNames[i], args[i]);
				}

				for (key in closure.keys()) {
					newFrame.localVars.set(key, closure.get(key));
				}

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

	// Variable management
	function getVariable(name:String):Value {
		if (currentFrame.localVars.exists(name))
			return currentFrame.localVars.get(name);
		if (letVariables.exists(name))
			return letVariables.get(name);
		if (constVariables.exists(name))
			return constVariables.get(name);
		if (variables.exists(name))
			return variables.get(name);
		if (methods.exists(name))
			return methods.get(name);
		return null;
	}

	function setVariable(name:String, value:Value, isConst:Bool) {
		if (constVariables.exists(name))
			throw 'Cannot reassign constant: $name';

		// Check if it's a let variable first
		if (letVariables.exists(name)) {
			letVariables.set(name, value);
			currentFrame.localVars.set(name, value);
			return;
		}

		if (isConst)
			constVariables.set(name, value);
		else
			variables.set(name, value);
	}

	// Stack operations
	inline function push(value:Value)
		stack.push(value);

	inline function pop():Value {
		if (stack.length == 0) {
			throw "Stack underflow at IP: " + currentFrame.ip;
		}
		return stack.pop();
	}

	inline function peek():Value {
		if (stack.length == 0) {
			throw "Stack underflow (peek) at IP: " + currentFrame.ip;
		}
		return stack[stack.length - 1];
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
	 * Call a script function with arguments (helper for external code)
	 */
	public function callFunction(func:FunctionChunk, closure:Map<String, Value>, args:Array<Value>):Value {
		var tempVM = new VM(debug);
		tempVM.variables = this.variables;
		tempVM.methods = this.methods;
		tempVM.classes = this.classes;
		tempVM.letVariables = new Map();
		tempVM.constVariables = new Map();

		tempVM.frames = [
			{
				chunk: func.chunk,
				ip: 0,
				stackStart: 0,
				localVars: closure.copy()
			}
		];
		tempVM.currentFrame = tempVM.frames[0];

		// Set parameters
		for (i in 0...args.length) {
			if (i < func.paramNames.length) {
				tempVM.currentFrame.localVars.set(func.paramNames[i], args[i]);
			}
		}

		return tempVM.run();
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

				// Check methods in class hierarchy
				var currentClass = classData;
				while (currentClass != null) {
					if (currentClass.methods.exists(field)) {
						var method = currentClass.methods.get(field);
						// Return a bound method (closure with 'this')
						return VFunction(method, ["this" => object]);
					}
					// Look in parent class
					if (currentClass.superClass != null && classes.exists(currentClass.superClass)) {
						currentClass = classes.get(currentClass.superClass);
					} else {
						currentClass = null;
					}
				}

				throw 'Field $field not found in class $className';
			case VNativeObject(obj):
				// Access Haxe object field or method
				try {
					var value:Dynamic = Reflect.field(obj, field);

					// If it's a function, wrap it as a native function
					if (Reflect.isFunction(value)) {
						return VNativeFunction(field, -1, (args:Array<Value>) -> {
							// Convert script values to Haxe values
							var haxeArgs = [for (arg in args) valueToHaxe(arg)];
							// Call the method
							var result = Reflect.callMethod(obj, value, haxeArgs);
							// Convert result back to script value
							return haxeToValue(result);
						});
					}

					// Otherwise, convert the field value
					return haxeToValue(value);
				} catch (e:Dynamic) {
					throw 'Cannot access field $field on native object';
				}
			default: throw 'Cannot access member $field';
		}
	}

	public function setMember(object:Value, field:String, value:Value) {
		switch (object) {
			case VDict(map):
				map.set(field, value);
			case VInstance(className, fields, classData):
				// Set instance field
				fields.set(field, value);
			case VNativeObject(obj):
				// Set Haxe object field
				try {
					Reflect.setField(obj, field, valueToHaxe(value));
				} catch (e:Dynamic) {
					throw 'Cannot set field $field on native object: $e';
				}
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
				VDict([
					"_iter_type" => VString("array"),
					"_iter_data" => VArray(arr),
					"_iter_index" => VNumber(0)
				]);
			default: throw 'Value is not iterable';
		}
	}

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
		return switch (method) {
			// Properties
			case "length": VNumber(arr.length);

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

	// Public API
	public function callMethod(name:String, args:Array<Value>):Value {
		var func = getVariable(name);
		if (func == null)
			throw 'Undefined function: $name';
		return call(func, args);
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
		}
	}

	// Initialize native functions
	function initializeNativeFunctions() {
		methods.set("print", VNativeFunction("print", 1, (args) -> {
			var location = currentInstruction != null ? '[$scriptName - ${currentInstruction.line}:${currentInstruction.col}] ' : '';
			// Sys.println(location + valueToString(args[0]));
			return VNull;
		}));

		methods.set("len", VNativeFunction("len", 1, (args) -> {
			return switch (args[0]) {
				case VString(s): VNumber(s.length);
				case VArray(arr): VNumber(arr.length);
				case VDict(map): VNumber(Lambda.count(map));
				default: throw 'len() not supported';
			}
		}));

		methods.set("type", VNativeFunction("type", 1, (args) -> {
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
			}
			return VString(typeName);
		}));
	}
}

typedef CallFrame = {
	chunk:Chunk,
	ip:Int,
	stackStart:Int,
	localVars:Map<String, Value>
}
