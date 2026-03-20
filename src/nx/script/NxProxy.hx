package nx.script;

import nx.script.Bytecode.Value;
import nx.script.Bytecode.ClassData;

/**
 * Creates a Dynamic proxy around a VInstance so you can access fields and call methods
 * without writing `switch (instance) { case VInstance(...) }` everywhere.
 *
 * Fields are auto-synced from Haxe to script before every method call.
 * If you modify a field and then read it from inside script code without calling a method first,
 * use `__syncToScript__()`. Yes that's what it's for.
 *
 * Use `NxProxy.get()` for class instances with no constructor args.
 * Use `NxProxy.instantiate()` to call the constructor.
 */
class NxProxy {
	static inline var NATIVE_SUPER_INSTANCE_FIELD = "__native_super_instance";

	// ========================================
	// Public API
	// ========================================

	/**
	 * Gets (or re-gets) a script class instance without calling its constructor.
	 * Useful for singleton-style classes or when the script already created the instance.
	 */
	public static function get(interp:Interpreter, className:String):Dynamic {
		var vm = interp.vm;
		var classValue = vm.globals.get(className);
		if (classValue == null)
			throw 'Class $className not found in script';

		var instance = switch (classValue) {
			case VClass(classData): instantiateClass(classData, [], vm);
			case VInstance(_, _, _): classValue;
			default: throw '$className is not a class';
		}

		return createProxy(instance, vm);
	}

	/**
	 * Instantiates a script class and calls its constructor with the given args.
	 * args are Haxe-side values — they'll be converted to script Values automatically.
	 */
	public static function instantiate(interp:Interpreter, className:String, args:Array<Dynamic>):Dynamic {
		var vm = interp.vm;
		var classValue = vm.globals.get(className);
		if (classValue == null)
			throw 'Class $className not found in script';

		var instance = switch (classValue) {
			case VClass(classData): instantiateClass(classData, args, vm);
			default: throw '$className is not a class';
		}

		return createProxy(instance, vm);
	}

	// ========================================
	// Internal Implementation
	// ========================================
	// Helper to create auto-syncing field properties
	private static function createFieldProperty(proxy:Dynamic, fieldName:String, fieldStorage:Map<String, Dynamic>, scriptFields:Map<String, Value>,
			vm:VM):Void {
		// For Neko/HL, we can use Reflect.setField with direct assignment
		// The sync happens in __syncToScript__ which we'll call periodically
		var value = fieldStorage.get(fieldName);

		// TODO: use platform-specific property descriptors for reactive sync
		Reflect.setField(proxy, fieldName, value);
	}

	// Sync Haxe proxy fields → Script instance fields
	private static function syncToScript(proxy:Dynamic, instance:Value, vm:VM):Void {
		switch (instance) {
			case VInstance(_, fields, _):
				for (fieldName in fields.keys()) {
					if (fieldName == NATIVE_SUPER_INSTANCE_FIELD)
						continue;
					if (Reflect.hasField(proxy, fieldName)) {
						var haxeValue = Reflect.field(proxy, fieldName);
						// Skip functions
						if (!Reflect.isFunction(haxeValue)) {
							var scriptValue = vm.haxeToValue(haxeValue);
							fields.set(fieldName, scriptValue);
						}
					}
				}
			default:
		}
	}

	// Sync Script instance fields → Haxe proxy fields
	private static function syncFromScript(proxy:Dynamic, instance:Value, vm:VM):Void {
		switch (instance) {
			case VInstance(_, fields, _):
				for (fieldName in fields.keys()) {
					if (fieldName == NATIVE_SUPER_INSTANCE_FIELD)
						continue;
					if (!Reflect.hasField(proxy, fieldName))
						continue;
					var scriptValue = fields.get(fieldName);
					var haxeValue = vm.valueToHaxe(scriptValue);
					// Only update if it's not a function
					if (!Reflect.isFunction(Reflect.field(proxy, fieldName))) {
						Reflect.setField(proxy, fieldName, haxeValue);
					}
				}
			default:
		}
	}

	private static function createProxy(instance:Value, vm:VM):Dynamic {
		var proxy:Dynamic = {};
		var nativeProxy = false;
		var instanceRef = {value: instance}; // Wrapper for closure

		switch (instance) {
			case VInstance(className, fields, classData):
				// For classes extending native Haxe classes, expose the native object directly.
				// This keeps compatibility with APIs that require concrete Flixel/OpenFL types.
				var nativeBase = fields.get(NATIVE_SUPER_INSTANCE_FIELD);
				switch (nativeBase) {
					case VNativeObject(nativeObj):
						proxy = nativeObj;
						nativeProxy = true;
					default:
				}

				// Create a storage object for field values (separate from proxy)
				var fieldStorage:Map<String, Dynamic> = new Map();

				// Set all fields with automatic synchronization
				for (fieldName in fields.keys()) {
					if (fieldName == NATIVE_SUPER_INSTANCE_FIELD)
						continue;
					if (nativeProxy && !Reflect.hasField(proxy, fieldName))
						continue;
					// Store initial value
					var initialValue = vm.valueToHaxe(fields.get(fieldName));
					fieldStorage.set(fieldName, initialValue);

					// Create getter/setter that auto-syncs
					createFieldProperty(proxy, fieldName, fieldStorage, fields, vm);
				}

				if (!nativeProxy) {
					// Set all methods from the class hierarchy
					var currentClass = classData;
					while (currentClass != null) {
						for (methodName in currentClass.methods.keys()) {
							// Skip constructor - it's not a regular method
							if (methodName == "new" || Reflect.hasField(proxy, methodName)) {
								continue;
							}

							var func = currentClass.methods.get(methodName);

							// Capture method name for debugging
							var capturedMethodName = methodName;

							var callable = Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
								// Auto-sync before calling method to ensure script has latest field values
								syncToScript(proxy, instanceRef.value, vm);

								try {
									var scriptArgs:Array<Value> = [];
									for (arg in args)
										scriptArgs.push(vm.haxeToValue(arg));
									var result = vm.callFunction(func, ["this" => instanceRef.value], scriptArgs);

									// Auto-sync after calling method in case the method modified fields
									syncFromScript(proxy, instanceRef.value, vm);

									return vm.valueToHaxe(result);
								} catch (e:Dynamic) {
									throw 'Error calling method $capturedMethodName: $e';
								}
							});

							Reflect.setField(proxy, methodName, callable);
						}

						if (currentClass.superClass != null && vm.classes.exists(currentClass.superClass)) {
							currentClass = vm.classes.get(currentClass.superClass);
						} else {
							currentClass = null;
						}
					}

					// Add a sync function to update the script instance when fields change (manual call)
					Reflect.setField(proxy, "__syncToScript__", function() {
						syncToScript(proxy, instanceRef.value, vm);
					});
				}

			default:
				throw "Cannot create proxy for non-instance value";
		}

		return proxy;
	}

	private static function instantiateClass(classData:ClassData, args:Array<Dynamic>, vm:VM):Value {
		var instanceFields = new Map<String, Value>();
		var currentClass = classData;
		var classChain:Array<ClassData> = [];

		while (currentClass != null) {
			classChain.unshift(currentClass);
			if (currentClass.superClass != null && vm.classes.exists(currentClass.superClass)) {
				currentClass = vm.classes.get(currentClass.superClass);
			} else {
				currentClass = null;
			}
		}

		for (cls in classChain) {
			for (field in cls.fields.keys()) {
				instanceFields.set(field, cls.fields.get(field));
			}
		}

		// Mirror VM.handleInstantiate behavior for classes that extend a native Haxe class.
		if (classData.nativeSuper != null) {
			var scriptArgs:Array<Value> = [];
			for (arg in args)
				scriptArgs.push(vm.haxeToValue(arg));
			var nativeBase = vm.instantiateNativeBase(classData.nativeSuper, scriptArgs);
			if (nativeBase != null)
				instanceFields.set(NATIVE_SUPER_INSTANCE_FIELD, VNativeObject(nativeBase));
		}

		var inst = VInstance(classData.name, instanceFields, classData);

		if (classData.constructor != null) {
			var scriptArgs:Array<Value> = [];
			for (arg in args)
				scriptArgs.push(vm.haxeToValue(arg));

			if (scriptArgs.length != classData.constructor.paramCount) {
				throw 'Constructor expects ${classData.constructor.paramCount} arguments, got ${scriptArgs.length}';
			}

			var closure = new Map<String, Value>();
			closure.set("this", inst);
			vm.callFunction(classData.constructor, closure, scriptArgs);
		}

		return inst;
	}
}
