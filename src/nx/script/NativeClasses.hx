package nx.script;

import nx.script.Bytecode.Value;
import nx.script.Bytecode.ClassData;
import nx.script.Bytecode.FunctionChunk;

// NativeClasses.hx — Built-in class stubs for the VM class registry
//
// Registers the built-in type hierarchy into `VM.classes` and `VM.globals`:
//
//   Object → String, Number (→ Int, Float), Bool, Array, Function
//
// ## Why these are empty shells
//
//   NxScript's primitive method dispatch (`"hi".upper()`, `arr.push(x)`,
//   `(3.5).floor()`) lives entirely in `VM.getStringMethod`,
//   `VM.getArrayMethod`, and `VM.getNumberMethod` — not in `ClassData.methods`.
//
//   These stubs exist so that:
//     1. `import String` / `import Array` resolve to something in globals.
//     2. Script classes can write `class Foo extends Array { … }` and the
//        inheritance chain finds a ClassData to walk up to.
//     3. `x is String`, `x is Array` type checks have a registered class to
//        match against.
//
// ## Known limitation
//
//   Because `String`, `Array`, etc. have empty `methods` maps, inheriting from
//   them and calling a primitive method via `super.push(x)` will silently
//   return `null` instead of dispatching to the VM's built-in implementation.
//   This is a known gap — a proper fix requires bridging ClassData methods
//   to the VM's `getArrayMethod` / `getStringMethod` dispatchers.

/**
 * Registers the built-in type hierarchy into `VM.classes` and `VM.globals`.
 *
 *     Object → String, Number (→ Int, Float), Bool, Array, Function
 *
 * ### Why these are empty shells
 *
 * NxScript's primitive method dispatch (`"hi".upper()`, `arr.push(x)`,
 * `(3.5).floor()`) lives in `VM.getStringMethod`, `VM.getArrayMethod`, and
 * `VM.getNumberMethod` — not in `ClassData.methods`.
 *
 * These stubs exist so that:
 * - `import String` / `import Array` resolve to something in globals.
 * - Script classes can write `class Foo extends Array { … }` and the
 *   inheritance chain finds a `ClassData` to walk.
 * - `x is String`, `x is Array` type checks have a registered class to match.
 *
 * ### Known limitation
 *
 * Because `String`, `Array`, etc. have empty `methods` maps, calling a primitive
 * method via `super.push(x)` from a subclass will silently return `null`. A proper
 * fix requires bridging `ClassData.methods` to the VM's built-in dispatchers.
 */
class NativeClasses {
	/**
	 * Registers all native classes. Call once per VM. Calling it twice will overwrite the first
	 * registration and waste a few microseconds. Don't do that.
	 */
	/**
	 * Registers all built-in classes into the VM. Call once per VM instance.
	 * Calling it twice will overwrite the first registration.
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

	/**
	 * Creates a ClassData shell with empty methods/fields — used for primitive
	 * types whose actual method dispatch happens in VM's getXxxMethod helpers.
	 */
	private static function makeShell(name:String, superClass:Null<String>):ClassData {
		return {
			name:          name,
			superClass:    superClass,
			nativeSuper:   null,
			methods:       new Map(),
			fields:        new Map(),
			constructor:   null,
			staticFields:  new Map(),
			staticMethods: new Map()
		};
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
		var classData = makeShell("Object", null);
		vm.classes.set("Object", classData);
		vm.globals.set("Object", VClass(classData));
	}

	// ========================================
	// String - String manipulation methods
	// ========================================

	private static function registerString(vm:VM):Void {
		var classData = makeShell("String", "Object");
		vm.classes.set("String", classData);
		vm.globals.set("String", VClass(classData));
	}

	// ========================================
	// Number - Numeric operations
	// ========================================

	private static function registerNumber(vm:VM):Void {
		var classData = makeShell("Number", "Object");
		vm.classes.set("Number", classData);
		vm.globals.set("Number", VClass(classData));
	}

	// ========================================
	// Int — integer subtype of Number
	// Accepts only whole numbers. Throws on fractional values.
	// ========================================

	private static function registerInt(vm:VM):Void {
		var classData = makeShell("Int", "Number");

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
		var classData = makeShell("Float", "Number");

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
		var classData = makeShell("Bool", "Object");
		vm.classes.set("Bool", classData);
		vm.globals.set("Bool", VClass(classData));
	}

	// ========================================
	// Array - Array manipulation
	// ========================================

	private static function registerArray(vm:VM):Void {
		var classData = makeShell("Array", "Object");
		vm.classes.set("Array", classData);
		vm.globals.set("Array", VClass(classData));
	}

	// ========================================
	// Function - Function wrapper
	// ========================================

	private static function registerFunction(vm:VM):Void {
		var classData = makeShell("Function", "Object");
		vm.classes.set("Function", classData);
		vm.globals.set("Function", VClass(classData));
	}
}
