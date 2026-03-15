package nx.script;

import nx.script.Bytecode.Value;
import nx.bridge.Reflection as NxReflection;

/**
 * NativeProxy — wraps a Haxe native object (e.g. FlxSprite) as VDict shadow so
 * NxScript can use it with IDENTICAL syntax to VNativeObject:
 *
 *   spr.x += 60 * dt          // reads/writes shadow Map — zero Reflection
 *   spr.angle += 120 * dt     // same
 *   spr.color = color         // same
 *   spr.screenCenter()        // native method — still via nativeGet/Reflection
 *
 * The script syntax is UNCHANGED. The speedup comes from the hot path:
 * GET_MEMBER / SET_MEMBER on a VDict hit the shadow Map<String,Value>
 * instead of Reflection.getField/setField.
 *
 * After the script update, call flush() ONCE to write the shadow map back
 * to the native object with one Reflection.setField per tracked field.
 *
 *   BEFORE: 10k sprites x 5 props x 2 reflection calls = 100k/frame
 *   AFTER:  10k sprites x 4 props x 1 reflection call  =  40k/frame (flush only)
 *           + zero Reflection calls during the script loop itself
 *
 * ─── Usage ────────────────────────────────────────────────────────────────
 *
 *   // Setup (once):
 *   var result = NativeProxy.wrapMany(vm, sprites, ["x","y","angle","color"]);
 *   vm.globals.set("sprites", VArray(result.values));
 *
 *   // Each frame:
 *   vm.callResolved(updateFn, [vm.globals.get("sprites"), VNumber(dt)]);
 *   NativeProxy.flushAll(result.proxies);
 *
 *   // Script (UNCHANGED syntax):
 *   func update(sprites, dt) {
 *       var j = 0
 *       while (j < sprites.length) {
 *           var spr = sprites[j]
 *           spr.angle += 120 * dt     // shadow Map op
 *           spr.x += 60 * dt          // shadow Map op
 *           spr.color = color         // shadow Map op
 *           j++
 *       }
 *   }
 */
class NativeProxy {

	/** The VDict value — pass this to the script as a global or function arg. */
	public var value(default, null):Value;

	/** The underlying Haxe native object. */
	public var native(default, null):Dynamic;

	/** Which fields are tracked in the shadow map. */
	public var fields(default, null):Array<String>;

	/** Direct access to the shadow map (same map that lives in value:VDict). */
	public var shadow(default, null):Map<String, Value>;

	var vm:VM;

	// ─── construction ──────────────────────────────────────────────────────

	/**
	 * Wrap a single native Haxe object as a VProxy.
	 *
	 * @param vm        The NxScript VM.
	 * @param obj       The Haxe object (FlxSprite, etc.).
	 * @param fieldList Fields to track in the shadow map.  Pass null to
	 *                  auto-detect via Type.getInstanceFields (slower init,
	 *                  fine for one-time setup).
	 */
	public static function wrap(vm:VM, obj:Dynamic, ?fieldList:Array<String>):NativeProxy {
		var p = new NativeProxy();
		p.vm     = vm;
		p.native = obj;
		p.shadow = new Map();

		if (fieldList == null)
			fieldList = detectFields(obj);

		p.fields = fieldList;
		p.pullFields(fieldList);
		p.value  = VDict(p.shadow);
		return p;
	}

	/**
	 * Wrap many objects at once with the same field list.
	 * Field detection runs once for the first object.
	 */
	public static function wrapMany(vm:VM, objects:Array<Dynamic>, ?fieldList:Array<String>):WrapManyResult {
		if (objects.length == 0)
			return { values: [], proxies: [] };

		if (fieldList == null)
			fieldList = detectFields(objects[0]);

		var proxies:Array<NativeProxy> = [];
		var values:Array<Value> = [];

		for (obj in objects) {
			var p = new NativeProxy();
			p.vm     = vm;
			p.native = obj;
			p.fields = fieldList;
			p.shadow = new Map();
			p.pullFields(fieldList);
			p.value  = VDict(p.shadow);
			proxies.push(p);
			values.push(p.value);
		}

		return { values: values, proxies: proxies };
	}

	// ─── sync ──────────────────────────────────────────────────────────────

	/**
	 * Write shadow map → native object.
	 * Call once after the script has finished updating this proxy.
	 */
	public function flush():Void {
		for (name in fields) {
			var v = shadow.get(name);
			if (v != null)
				Reflect.setField(native, name, vm.valueToHaxe(v));
		}
	}

	/** Flush only specific fields. */
	public function flushFields(names:Array<String>):Void {
		for (name in names) {
			var v = shadow.get(name);
			if (v != null)
				Reflect.setField(native, name, vm.valueToHaxe(v));
		}
	}

	/**
	 * Read native object → shadow map.
	 * Call if Haxe code modifies the object outside the script.
	 */
	public function pull():Void {
		pullFields(fields);
	}

	public static function flushAll(proxies:Array<NativeProxy>):Void {
		for (p in proxies) p.flush();
	}

	public static function pullAll(proxies:Array<NativeProxy>):Void {
		for (p in proxies) p.pull();
	}

	// ─── VM integration ────────────────────────────────────────────────────

	/**
	 * Run a script function over each proxy with Haxe driving the outer loop.
	 * Useful when you want to pass the index or extra per-frame args.
	 *
	 *   NativeProxy.scriptForEach(vm, proxies, updateFn, [VNumber(dt)]);
	 *   NativeProxy.flushAll(proxies);
	 */
	public static function scriptForEach(
		vm:VM,
		proxies:Array<NativeProxy>,
		scriptFn:Value,
		?extraArgs:Array<Value>
	):Void {
		if (extraArgs == null) extraArgs = [];
		var args = [for (_ in 0...2 + extraArgs.length) VNull];
		for (i in 0...proxies.length) {
			args[0] = proxies[i].value;
			args[1] = VNumber(i);
			for (j in 0...extraArgs.length) args[2 + j] = extraArgs[j];
			vm.callResolved(scriptFn, args);
		}
	}

	// ─── private ───────────────────────────────────────────────────────────

	function new() {}

	function pullFields(names:Array<String>):Void {
		for (name in names) {
			var raw:Dynamic = Reflect.field(native, name);
			if (raw != null)
				shadow.set(name, vm.haxeToValue(raw));
		}
	}

	static function detectFields(obj:Dynamic):Array<String> {
		var cls = Type.getClass(obj);
		var all = cls != null ? Type.getInstanceFields(cls) : Reflect.fields(obj);
		var result = [];
		for (name in all) {
			var raw:Dynamic = Reflect.field(obj, name);
			if (raw == null || !NxReflection.isFunction(raw))
				result.push(name);
		}
		return result;
	}
}

typedef WrapManyResult = {
	/** The VDict values — pass as a VArray to the script. */
	values: Array<Value>,
	/** The proxy objects — call flushAll(proxies) after the script runs. */
	proxies: Array<NativeProxy>
}
