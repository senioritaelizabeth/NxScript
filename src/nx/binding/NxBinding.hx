package nx.binding;

import nx.script.Interpreter;
import nx.script.Bytecode.Value;

/**
 * NxBinding — compiled to JS via `haxe build_js.hxml`
 *
 * JS usage (see bin/nxscript-api.js for the clean wrapper):
 *
 *   const { create } = require('./nxscript-api.js');
 *   const vm = create();
 *   vm.run('func hi() { return 42 }', 'test.nx');
 *   console.log(vm.call('hi', []));  // 42
 *   vm.free();
 */
@:expose
class NxBinding {

	static var vms:Map<Int, NxBinding> = new Map();
	static var nextId:Int = 1;

	public var interp(default, null):Interpreter;
	public var lastError:String = "";

	public function new() {
		interp = new Interpreter();
	}

	@:expose("nxs_create")
	public static function allocate():Int {
		var id = nextId++;
		vms.set(id, new NxBinding());
		return id;
	}

	@:expose("nxs_get")
	public static function get(id:Int):NxBinding
		return vms.get(id);

	@:expose("nxs_free")
	public static function release(id:Int):Void
		vms.remove(id);

	// ── Execution ────────────────────────────────────────────────────────

	@:expose("nxs_run")
	public static function run(id:Int, source:String, name:String):String {
		var b = vms.get(id);
		if (b == null) return "VM not found";
		try { b.interp.run(source, name); return ""; }
		catch (e:Dynamic) { return Std.string(e); }
	}

	@:expose("nxs_reset")
	public static function reset(id:Int):Void {
		var b = vms.get(id);
		if (b != null) b.interp.reset_context();
	}

	// ── Globals (primitives only — safe across JS boundary) ───────────────

	@:expose("nxs_set_number")
	public static function setNumber(id:Int, name:String, v:Float):Void {
		var b = vms.get(id);
		if (b != null) b.interp.vm.globals.set(name, VNumber(v));
	}

	@:expose("nxs_set_string")
	public static function setString(id:Int, name:String, v:String):Void {
		var b = vms.get(id);
		if (b != null) b.interp.vm.globals.set(name, VString(v));
	}

	@:expose("nxs_set_bool")
	public static function setBool(id:Int, name:String, v:Bool):Void {
		var b = vms.get(id);
		if (b != null) b.interp.vm.globals.set(name, VBool(v));
	}

	@:expose("nxs_set_null")
	public static function setNull(id:Int, name:String):Void {
		var b = vms.get(id);
		if (b != null) b.interp.vm.globals.set(name, VNull);
	}

	@:expose("nxs_get_number")
	public static function getNumber(id:Int, name:String):Float {
		var b = vms.get(id);
		if (b == null) return 0.0;
		return switch (b.interp.vm.globals.get(name)) {
			case VNumber(n): n;
			case VBool(v): v ? 1.0 : 0.0;
			default: 0.0;
		};
	}

	@:expose("nxs_get_string")
	public static function getString(id:Int, name:String):String {
		var b = vms.get(id);
		if (b == null) return "";
		return switch (b.interp.vm.globals.get(name)) {
			case VString(s): s;
			case VNumber(n): Std.string(n);
			default: "";
		};
	}

	@:expose("nxs_get_bool")
	public static function getBool(id:Int, name:String):Bool {
		var b = vms.get(id);
		if (b == null) return false;
		return switch (b.interp.vm.globals.get(name)) {
			case VBool(v): v;
			case VNumber(n): n != 0;
			case VNull: false;
			default: true;
		};
	}

	// ── Function calls — returns JSON string for JS to parse ──────────────

	/**
	 * Call a script function. Args passed as JSON string, result returned as JSON string.
	 * Returns "__error__:<message>" on failure.
	 *
	 * JS side: JSON.parse(nxs_call(id, "myFunc", JSON.stringify([1, "hello", true])))
	 */
	@:expose("nxs_call")
	public static function call(id:Int, name:String, argsJson:String):String {
		var b = vms.get(id);
		if (b == null) return "__error__:VM not found";
		try {
			var parsed:Array<Dynamic> = haxe.Json.parse(argsJson);
			var args:Array<Value> = parsed.map(function(v) return jsValToValue(b, v));
			var result = b.interp.safeCall(name, args);
			return haxe.Json.stringify(valueToJsVal(result ?? VNull));
		} catch (e:Dynamic) {
			return "__error__:" + Std.string(e);
		}
	}

	// ── Defines ───────────────────────────────────────────────────────────

	@:expose("nxs_define")
	public static function define(id:Int, name:String, value:Bool):Void {
		var b = vms.get(id);
		if (b != null) b.interp.defines.set(name, value);
	}

	@:expose("nxs_sandbox")
	public static function sandbox(id:Int):Void {
		var b = vms.get(id);
		if (b != null) b.interp.enableSandbox();
	}

	// ── Register JS callback callable from script ─────────────────────────

	/**
	 * Register a callback. The callback receives args as a JSON string and
	 * must return a JSON string.
	 *
	 * JS: nxs_register(id, "add", 2, (argsJson) => {
	 *   const [a, b] = JSON.parse(argsJson);
	 *   return JSON.stringify(a + b);
	 * });
	 */
	@:expose("nxs_register")
	public static function register(id:Int, name:String, arity:Int, fn:String->String):Void {
		var b = vms.get(id);
		if (b == null) return;
		b.interp.register(name, arity, function(args:Array<Value>):Value {
			var jsVals = args.map(v -> valueToJsVal(v));
			var argsJson = haxe.Json.stringify(jsVals);
			var resultJson = fn(argsJson);
			if (resultJson == null || resultJson == "") return VNull;
			try {
				var parsed:Dynamic = haxe.Json.parse(resultJson);
				return jsValToValue(b, parsed);
			} catch (_:Dynamic) {
				return VString(resultJson);
			}
		});
	}

	// ── Helpers ───────────────────────────────────────────────────────────

	static function valueToJsVal(v:Value):Dynamic {
		return switch (v) {
			case VNumber(n): n;
			case VString(s): s;
			case VBool(b):   b;
			case VNull:      null;
			case VArray(a):  a.map(x -> valueToJsVal(x));
			case VDict(m):
				var obj:Dynamic = {};
				for (k in m.keys()) Reflect.setField(obj, k, valueToJsVal(m.get(k)));
				obj;
			default: null;
		};
	}

	static function jsValToValue(b:NxBinding, v:Dynamic):Value {
		if (v == null) return VNull;
		if (Std.isOfType(v, Bool))   return VBool(v);
		if (Std.isOfType(v, Float))  return VNumber(v);
		if (Std.isOfType(v, String)) return VString(v);
		if (Std.isOfType(v, Array)) {
			var arr:Array<Dynamic> = v;
			return VArray(arr.map(x -> jsValToValue(b, x)));
		}
		return VNull;
	}

	public static function main() {}
}
