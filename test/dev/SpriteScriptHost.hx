// ─────────────────────────────────────────────────────────────────────────
// Haxe host side — how to use NativeProxy with FlxSprite
// ─────────────────────────────────────────────────────────────────────────
//
// Drop this into your HaxeFlixel game class or a ScriptManager class.

import nx.script.Interpreter;
import nx.script.NativeProxy;
import nx.script.Bytecode.Value;
import flixel.FlxSprite;
import flixel.group.FlxTypedSpriteGroup;
import flixel.FlxG;

class SpriteScriptHost {

	var interp     : Interpreter;
	var proxies    : Array<NativeProxy>;
	var updateFn   : Value;
	var dtValue    : Array<Value> = [VNumber(0)];

	// Which FlxSprite fields the script can read/write.
	// Keep this list small — every field in the list costs one Reflect.setField
	// per sprite per frame in the flush() call.
	static final SPRITE_FIELDS = ["x", "y", "angle", "color"];

	public function new(scriptPath:String, sprites:Array<FlxSprite>) {
		interp = new Interpreter();
		interp.runFile(scriptPath);  // loads sprites_proxy.nx

		// Wrap all sprites ONCE — field detection runs once per class, not per instance
		var result = NativeProxy.wrapMany(interp.vm, cast sprites, SPRITE_FIELDS);
		proxies = result.proxies;

		// Give the script a global "proxies" array (VArray of VDicts)
		interp.vm.globals.set("proxies", result.value);

		// Resolve "update" function once — avoid globals.get() every frame
		updateFn = interp.vm.resolveCallable("update");
	}

	/**
	 * Call this from your FlxState.update(elapsed).
	 *
	 * Cost breakdown for 10k sprites:
	 *   - Script loop:   10k x Map.get + Map.set per field  (~O(1) per op)
	 *   - NativeProxy.flushAll: 10k x Reflect.setField x 4 fields = 40k reflect calls
	 *
	 * vs old approach: 10k x Reflect.getField + Reflect.setField x 5 fields = 100k calls
	 */
	public function update(elapsed:Float):Void {
		// Reuse the array to avoid allocation per frame
		dtValue[0] = VNumber(elapsed);

		// Run the script update — pure Map<String,Value> ops inside
		interp.vm.callResolved(updateFn, [interp.vm.globals.get("proxies"), dtValue[0]]);

		// Write shadow maps → FlxSprite fields (one Reflect.setField per tracked field)
		NativeProxy.flushAll(proxies);
	}

	/**
	 * If Haxe code moves a sprite (e.g. screen center reset), call pull()
	 * so the script sees the updated position.
	 */
	public function pullAll():Void {
		NativeProxy.pullAll(proxies);
	}
}

// ─── Drop-in FlxState usage ───────────────────────────────────────────────
//
// class PlayState extends FlxState {
//     var scriptHost : SpriteScriptHost;
//
//     override function create() {
//         var sprites = [for (i in 0...10000) {
//             var s = new FlxSprite(FlxG.width / 2, FlxG.height / 2);
//             s.makeGraphic(4, 4, 0xFFFFFFFF);
//             add(s);
//             s;
//         }];
//         scriptHost = new SpriteScriptHost("assets/scripts/sprites_proxy.nx", sprites);
//     }
//
//     override function update(elapsed:Float) {
//         super.update(elapsed);
//         scriptHost.update(elapsed);
//     }
// }
