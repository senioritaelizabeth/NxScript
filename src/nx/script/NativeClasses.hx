package nx.script;

import nx.script.Bytecode.Value;
import nx.script.Bytecode.ClassData;
import nx.script.Bytecode.FunctionChunk;

/**
 * Registers the built-in class hierarchy (Object, String, Number, Bool, Array, Function)
 * into the VM's class/globals registry.
 *
 * These aren't full implementations — they're class shells so that method dispatch on
 * primitive values (`"hi".upper()`, `(3.5).floor()`, etc.) resolves correctly.
 * The actual method bodies live in VM's GET_MEMBER/CALL dispatch.
 *
 * Extending these from script code is technically allowed. Results may vary.
 */
class NativeClasses {
	/**
	 * Registers all native classes. Call once per VM. Calling it twice will overwrite the first
	 * registration and waste a few microseconds. Don't do that.
	 */
	public static function registerAll(vm:VM):Void {
		registerObject(vm);
		registerString(vm);
		registerNumber(vm);
		registerInt(vm);
		registerFloat(vm);
		registerBool(vm);
		registerArray(vm);
		registerFunction(vm);
		registerConversions(vm);
		#if sys
		registerSys(vm);
		#end
	}

	#if sys
	/**
	 * Exposes Haxe's Sys class as a native object in NxScript.
	 * Allows scripts to call: Sys.command("echo hi"), Sys.println("x"), etc.
	 * Only available on sys targets (HL, CPP, Neko, Node).
	 *
	 * Usage in script:
	 *   import Sys;
	 *   Sys.command('echo Hello');
	 *
	 * Or without import (it's a global):
	 *   Sys.println("hi")
	 */
	private static function registerSys(vm:VM):Void {
		vm.globals.set("Sys", VNativeObject(Sys));
	}
	#end

	// ========================================
	// Object - Base class for all classes
	// ========================================

	private static function registerObject(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields = new Map<String, Value>();

		// Object will be the base class, no methods for now
		// Could add: toString, equals, hashCode, etc.

		var classData:ClassData = {
			name: "Object",
			superClass: null,
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Object", classData);
		vm.globals.set("Object", VClass(classData));
	}

	// ========================================
	// String - String manipulation methods
	// ========================================

	private static function registerString(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields = new Map<String, Value>();

		// String extends Object
		var classData:ClassData = {
			name: "String",
			superClass: "Object",
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("String", classData);
		vm.globals.set("String", VClass(classData));
	}

	// ========================================
	// Number - Numeric operations
	// ========================================

	private static function registerNumber(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields = new Map<String, Value>();

		var classData:ClassData = {
			name: "Number",
			superClass: "Object",
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Number", classData);
		vm.globals.set("Number", VClass(classData));
	}

	// ========================================
	// Int — integer subtype of Number
	// Accepts only whole numbers. Throws on fractional values.
	// ========================================

	private static function registerInt(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields  = new Map<String, Value>();

		var classData:ClassData = {
			name: "Int",
			superClass: "Number",
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Int", classData);
		vm.globals.set("Int", VClass(classData));

		// Int.from(value) — converts Number/Float to Int, throws on non-integer
		vm.natives.set("Int_from", VNativeFunction("Int_from", 1, (args) -> {
			switch (args[0]) {
				case VNumber(n):
					if (n != Math.floor(n))
						throw 'Int.from: ${n} is not a whole number';
					return VNumber(Math.floor(n));
				default:
					throw 'Int.from expects a Number';
			}
		}));
	}

	// ========================================
	// Float — float subtype of Number
	// Accepts both integers and decimals. Coerces Int to Float.
	// ========================================

	private static function registerFloat(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields  = new Map<String, Value>();

		var classData:ClassData = {
			name: "Float",
			superClass: "Number",
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Float", classData);
		vm.globals.set("Float", VClass(classData));

		// Float.from(value) — converts Number/Int to Float
		vm.natives.set("Float_from", VNativeFunction("Float_from", 1, (args) -> {
			switch (args[0]) {
				case VNumber(n): return VNumber(n); // already a float internally
				default: throw 'Float.from expects a Number';
			}
		}));
	}

	// ========================================
	// Conversion natives: fromNumber, fromInt, fromFloat
	// ========================================

	private static function registerConversions(vm:VM):Void {
		// fromNumber(x) — identity, accepts VNumber, VBool, VString(numeric)
		vm.natives.set("fromNumber", VNativeFunction("fromNumber", 1, (args) -> {
			return switch (args[0]) {
				case VNumber(n): VNumber(n);
				case VBool(b): VNumber(b ? 1.0 : 0.0);
				case VString(s):
					var n = Std.parseFloat(s);
					Math.isNaN(n) ? throw 'fromNumber: cannot parse "${s}"' : VNumber(n);
				default: throw "fromNumber expects a Number, Bool, or numeric String";
			};
		}));

		// fromInt(x) — like fromNumber but enforces whole number
		vm.natives.set("fromInt", VNativeFunction("fromInt", 1, (args) -> {
			return switch (args[0]) {
				case VNumber(n):
					if (n != Math.floor(n))
						throw 'fromInt: ${n} is not a whole number';
					VNumber(Math.floor(n));
				case VString(s):
					var n = Std.parseInt(s);
					n == null ? throw 'fromInt: cannot parse "${s}"' : VNumber(n);
				default: throw "fromInt expects a Number or numeric String";
			};
		}));

		// fromFloat(x) — accepts any Number/Int, returns as float
		vm.natives.set("fromFloat", VNativeFunction("fromFloat", 1, (args) -> {
			return switch (args[0]) {
				case VNumber(n): VNumber(n);
				case VString(s):
					var n = Std.parseFloat(s);
					Math.isNaN(n) ? throw 'fromFloat: cannot parse "${s}"' : VNumber(n);
				default: throw "fromFloat expects a Number or numeric String";
			};
		}));
	}

	// ========================================
	// Bool - Boolean operations
	// ========================================

	private static function registerBool(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields = new Map<String, Value>();

		// Bool extends Object
		var classData:ClassData = {
			name: "Bool",
			superClass: "Object",
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Bool", classData);
		vm.globals.set("Bool", VClass(classData));
	}

	// ========================================
	// Array - Array manipulation
	// ========================================

	private static function registerArray(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields = new Map<String, Value>();

		// Array extends Object
		var classData:ClassData = {
			name: "Array",
			superClass: "Object",
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Array", classData);
		vm.globals.set("Array", VClass(classData));
	}

	// ========================================
	// Function - Function wrapper
	// ========================================

	private static function registerFunction(vm:VM):Void {
		var methods = new Map<String, FunctionChunk>();
		var fields = new Map<String, Value>();

		// Function extends Object
		var classData:ClassData = {
			name: "Function",
			superClass: "Object",
			nativeSuper: null,
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Function", classData);
		vm.globals.set("Function", VClass(classData));
	}
}
