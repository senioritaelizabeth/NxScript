package nz.script;

import nz.script.Bytecode.Value;
import nz.script.Bytecode.ClassData;
import nz.script.Bytecode.FunctionChunk;

/**
 * Built-in native classes for the script runtime.
 * These classes provide methods for primitive types like String, Number, Bool, etc.
 */
class NativeClasses {
	/**
	 * Register all native classes in the VM
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
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Object", classData);
		vm.variables.set("Object", VClass(classData));
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
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("String", classData);
		vm.variables.set("String", VClass(classData));
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
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Number", classData);
		vm.variables.set("Number", VClass(classData));
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
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Bool", classData);
		vm.variables.set("Bool", VClass(classData));
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
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Array", classData);
		vm.variables.set("Array", VClass(classData));
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
			methods: methods,
			fields: fields,
			constructor: null
		};

		vm.classes.set("Function", classData);
		vm.variables.set("Function", VClass(classData));
	}
}
