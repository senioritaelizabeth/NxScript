package nx.binding;

import nx.script.Interpreter;
import nx.script.Bytecode.Value;

@:expose
class NxBinding {

	static var vms:Map<Int, NxBinding> = new Map();
	static var nextId:Int = 1;

	public var interp(default, null):Interpreter;
	public var lastError:String = "";

	public function new() {
		interp = new Interpreter();
	}
	@:expose('nx_allocate')
	public static function allocate():Int {
		var id = nextId++;
		vms.set(id, new NxBinding());
		return id;
	}

	@:expose('nx_get')
	public static function get(id:Int):NxBinding
		return vms.get(id);

	@:expose('nx_release')
	public static function release(id:Int):Void
		vms.remove(id);
	
	@:expose('nx_run_source')
	public function runSource(source:String, name:String):Bool {
		try { interp.run(source, name); return true; }
		catch (e:Dynamic) { lastError = Std.string(e); return false; }
	}

	@:expose('nx_run_file')
	public function runFile(path:String):Bool {
		try { interp.loadScript(path); return true; }
		catch (e:Dynamic) { lastError = Std.string(e); return false; }
	}
	@:expose('nx_run_dir')
	public function runDir(dir:String, recursive:Bool):Int {
		var count = 0;
		try {
			for (f in sys.FileSystem.readDirectory(dir)) {
				var full = dir + "/" + f;
				if (sys.FileSystem.isDirectory(full)) {
					if (recursive) count += runDir(full, true);
				} else if (StringTools.endsWith(f, ".nx")) {
					try { interp.loadScript(full); count++; }
					catch (e:Dynamic) { lastError = Std.string(e); }
				}
			}
		} catch (e:Dynamic) { lastError = Std.string(e); }
		return count;
	}

	@:expose('nx_reset')
	public function reset():Void
		interp.reset_context();

	@:expose('nx_set_number')
	public function setNumber(name:String, v:Float):Void
		interp.vm.globals.set(name, VNumber(v));

	@:expose('nx_set_string')
	public function setString(name:String, v:String):Void
		interp.vm.globals.set(name, VString(v));

	@:expose('nx_set_bool')
	public function setBool(name:String, v:Bool):Void
		interp.vm.globals.set(name, VBool(v));

	@:expose('nx_set_null')
	public function setNull(name:String):Void
		interp.vm.globals.set(name, VNull);
	@:expose('nx_get_number')
	public function getNumber(name:String):Float
		return switch (interp.vm.globals.get(name)) {
			case VNumber(n): n;
			case VBool(b): b ? 1.0 : 0.0;
			default: 0.0;
		};

	@:expose('nx_get_string')
	public function getString(name:String):String
		return switch (interp.vm.globals.get(name)) {
			case VString(s): s;
			case VNumber(n): Std.string(n);
			default: "";
		};

	@:expose('nx_get_bool')	
	public function getBool(name:String):Bool
		return switch (interp.vm.globals.get(name)) {
			case VBool(b): b;
			case VNumber(n): n != 0;
			case VNull: false;
			default: true;
		};
	var valueCache:Map<Int, Value> = new Map();
	var nextValId:Int = 1;
	@:expose('nx_store_value')
	public function storeValue(v:Value):Int {
		var id = nextValId++;
		valueCache.set(id, v);
		return id;
	}

	@:expose('nx_load_value')
	public function loadValue(id:Int):Value
		return valueCache.exists(id) ? valueCache.get(id) : VNull;
	@:expose('nx_free_value')
	public function freeValue(id:Int):Void
		valueCache.remove(id);

	@:expose('nx_call')
	public function call(name:String, args:Array<Value>):Value {
		var r = interp.safeCall(name, args);
		return r != null ? r : VNull;
	}
	@:expose('nx_register_callback')
	public function registerCallback(name:String, arity:Int, fn:String->String):Void {
		interp.register(name, arity, function(args:Array<Value>):Value {
			var argStr = args.map(a -> interp.vm.valueToString(a)).join(" ");
			var result = fn(argStr);
			if (result == null || result == "null" || result == "") return VNull;
			if (result == "true") return VBool(true);
			if (result == "false") return VBool(false);
			var n = Std.parseFloat(result);
			if (!Math.isNaN(n)) return VNumber(n);
			return VString(result);
		});
	}

	@:expose('nx_define')
	public function define(name:String, value:Bool):Void
		interp.defines.set(name, value);
	@:expose('nx_enable_sandbox')
	public function enableSandbox():Void
		interp.enableSandbox();

	static function main() {}
}
