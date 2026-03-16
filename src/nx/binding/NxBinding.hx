package nx.binding;

import nx.script.Interpreter;
import nx.script.Bytecode.Value;

/**
 * NxBinding — shared VM management logic for all native bindings.
 *
 * All targets (C, GDExtension, Unity) instantiate this class.
 * Each binding layer just wraps it with their platform's calling convention.
 *
 * You can also use this directly from Haxe if you don't need a native export.
 */
class NxBinding {

	// ── VM pool ───────────────────────────────────────────────────────────
	static var vms:Map<Int, NxBinding> = new Map();
	static var nextId:Int = 1;

	// ── Instance state ────────────────────────────────────────────────────
	public var interp(default, null):Interpreter;
	public var lastError:String = "";

	public function new() {
		interp = new Interpreter();
	}

	// ── Pool management ───────────────────────────────────────────────────

	/** Allocate a new binding, return its integer handle. */
	public static function allocate():Int {
		var id = nextId++;
		vms.set(id, new NxBinding());
		return id;
	}

	/** Get binding by handle. Returns null if not found. */
	public static function get(id:Int):NxBinding
		return vms.get(id);

	/** Destroy a binding by handle. */
	public static function release(id:Int):Void
		vms.remove(id);

	// ── Script execution ──────────────────────────────────────────────────

	public function runSource(source:String, name:String):Bool {
		try { interp.run(source, name); return true; }
		catch (e:Dynamic) { lastError = Std.string(e); return false; }
	}

	public function runFile(path:String):Bool {
		try { interp.loadScript(path); return true; }
		catch (e:Dynamic) { lastError = Std.string(e); return false; }
	}

	public function runDir(dir:String, recursive:Bool):Int {
		var count = 0;
		try {
			for (f in sys.FileSystem.readDirectory(dir)) {
				var full = dir + "/" + f;
				if (sys.FileSystem.isDirectory(full)) {
					if (recursive) count += runDir(full, true);
				} else if (f.endsWith(".nx")) {
					try { interp.loadScript(full); count++; }
					catch (e:Dynamic) { lastError = Std.string(e); }
				}
			}
		} catch (e:Dynamic) { lastError = Std.string(e); }
		return count;
	}

	public function reset():Void interp.reset_context();

	// ── Globals ───────────────────────────────────────────────────────────

	public function setNumber(name:String, v:Float):Void
		interp.vm.globals.set(name, VNumber(v));

	public function setString(name:String, v:String):Void
		interp.vm.globals.set(name, VString(v));

	public function setBool(name:String, v:Bool):Void
		interp.vm.globals.set(name, VBool(v));

	public function setNull(name:String):Void
		interp.vm.globals.set(name, VNull);

	public function getNumber(name:String):Float
		return switch (interp.vm.globals.get(name)) {
			case VNumber(n): n; case VBool(b): b ? 1.0 : 0.0; default: 0.0;
		};

	public function getString(name:String):String
		return switch (interp.vm.globals.get(name)) {
			case VString(s): s; case VNumber(n): Std.string(n); default: "";
		};

	public function getBool(name:String):Bool
		return switch (interp.vm.globals.get(name)) {
			case VBool(b): b; case VNumber(n): n != 0; case VNull: false; default: true;
		};

	// ── Value cache (for C boundary) ─────────────────────────────────────

	var valueCache:Map<Int, Value> = new Map();
	var nextValId:Int = 1;

	public function storeValue(v:Value):Int {
		var id = nextValId++;
		valueCache.set(id, v);
		return id;
	}
	public function loadValue(id:Int):Value
		return valueCache.exists(id) ? valueCache.get(id) : VNull;

	public function freeValue(id:Int):Void
		valueCache.remove(id);

	// ── Function calls ────────────────────────────────────────────────────

	public function call(name:String, args:Array<Value>):Value {
		var r = interp.safeCall(name, args);
		return r != null ? r : VNull;
	}

	// ── Register native callbacks ─────────────────────────────────────────

	public function registerStringCallback(name:String, arity:Int, fn:String->String):Void {
		interp.register(name, arity, function(args:Array<Value>):Value {
			var argStr = args.map(a -> interp.vm.valueToString(a)).join(" ");
			var result = fn(argStr);
			if (result == null || result == "null" || result == "") return VNull;
			if (result == "true")  return VBool(true);
			if (result == "false") return VBool(false);
			var n = Std.parseFloat(result);
			if (!Math.isNaN(n)) return VNumber(n);
			return VString(result);
		});
	}

	// ── Defines and sandbox ───────────────────────────────────────────────

	public function define(name:String, value:Bool):Void
		interp.defines.set(name, value);

	public function enableSandbox():Void
		interp.enableSandbox();
}
