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
		registerBool(vm);
		registerArray(vm);
		registerFunction(vm);
	}

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

		// Number extends Object
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
