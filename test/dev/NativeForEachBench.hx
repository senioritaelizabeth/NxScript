package;

import nx.script.Interpreter;
import nx.script.VM;
import nx.script.Bytecode.Value;

class NativeForEachBench {

	static var SPRITE_COUNT = 10000;
	static var FRAMES       = 60;

	static function main() {
		trace('=== NativeForEach Benchmark ===');
		trace('Sprites: $SPRITE_COUNT  |  Frames: $FRAMES\n');

		var sprites = [for (_ in 0...SPRITE_COUNT) new MockSprite()];
		var dtVal   = VNumber(1.0 / FRAMES);
		var timeA = 0.0; var timeB = 0.0; var timeC = 0.0;
		var timeD = 0.0; var timeE = 0.0;

		// ── A: script loop ───────────────────────────────────────────────
		trace("[ A ] Script loop  (while j < sprites.length)");
		{
			var interp = new Interpreter();
			interp.vm.globals.set("sprites", interp.vm.haxeToValue(sprites));
			interp.vm.globals.set("counter", VNumber(0));
			interp.vm.globals.set("color",   VNumber(0xFF0000));
			interp.run('
				func runLoop(dt) {
					var j = 0
					while (j < sprites.length) {
						var spr = sprites[j]
						spr.angle += 120 * dt
						var phase = counter + j
						spr.x += 60 * dt * sin(phase)
						spr.y += 30 * dt * cos(phase)
						spr.color = color
						j++
					}
					counter = counter + dt
				}
			');
			var fn = interp.resolveCallable("runLoop");
			resetSprites(sprites);
			var t = haxe.Timer.stamp();
			for (_ in 0...FRAMES) interp.vm.callResolved(fn, [dtVal]);
			timeA = haxe.Timer.stamp() - t;
		}
		trace('    ${fmtMs(timeA)}  /  ${fmt(FRAMES/timeA)} fps\n');

		// ── B: nativeForEach ─────────────────────────────────────────────
		trace("[ B ] nativeForEach  (loop in Haxe, reflection per field)");
		{
			var interp = new Interpreter();
			interp.vm.globals.set("counter", VNumber(0));
			interp.vm.globals.set("color",   VNumber(0xFF0000));
			interp.run('
				func updateSprite(spr, i, dt) {
					spr.angle += 120 * dt
					var phase = counter + i
					spr.x += 60 * dt * sin(phase)
					spr.y += 30 * dt * cos(phase)
					spr.color = color
				}
			');
			var fn = interp.resolveCallable("updateSprite");
			var ctr = 0.0; var dt = 1.0 / FRAMES;
			resetSprites(sprites);
			var t = haxe.Timer.stamp();
			for (_ in 0...FRAMES) {
				interp.nativeForEach(sprites, fn, [dtVal]);
				ctr += dt;
				interp.vm.globals.set("counter", VNumber(ctr));
			}
			timeB = haxe.Timer.stamp() - t;
		}
		trace('    ${fmtMs(timeB)}  /  ${fmt(FRAMES/timeB)} fps\n');

		// ── C: pure Haxe ─────────────────────────────────────────────────
		trace("[ C ] Pure Haxe  (no VM, ceiling reference)");
		{
			var counter = 0.0; var dt = 1.0 / FRAMES; var color = 0xFF0000;
			resetSprites(sprites);
			var t = haxe.Timer.stamp();
			for (_ in 0...FRAMES) {
				for (j in 0...sprites.length) {
					var spr = sprites[j]; var phase = counter + j;
					spr.angle += 120 * dt;
					spr.x     += 60  * dt * Math.sin(phase);
					spr.y     += 30  * dt * Math.cos(phase);
					spr.color  = color;
				}
				counter += dt;
			}
			timeC = haxe.Timer.stamp() - t;
		}
		trace('    ${fmtMs(timeC)}  /  ${fmt(FRAMES/timeC)} fps\n');

		// ── D: native wrapper — script does math, Haxe writes fields ─────
		trace("[ D ] Native wrapper  (script does sin/cos, Haxe writes fields)");
		{
			var interp = new Interpreter();
			interp.vm.globals.set("counter", VNumber(0));
			interp.vm.globals.set("color",   VNumber(0xFF0000));
			interp.vm.natives.set("spriteApply", VNativeFunction("spriteApply", 5, (args) -> {
				var spr:MockSprite = cast interp.vm.valueToHaxe(args[0]);
				var dt  = switch (args[1]) { case VNumber(n): n; default: 0.0; };
				var s   = switch (args[2]) { case VNumber(n): n; default: 0.0; };
				var c   = switch (args[3]) { case VNumber(n): n; default: 0.0; };
				var col = switch (args[4]) { case VNumber(n): Std.int(n); default: 0; };
				spr.angle += 120 * dt;
				spr.x     += 60  * dt * s;
				spr.y     += 30  * dt * c;
				spr.color  = col;
				return VNull;
			}));
			interp.run('
				func updateSprite(spr, i, dt) {
					var phase = counter + i
					spriteApply(spr, dt, sin(phase), cos(phase), color)
				}
			');
			var fn = interp.resolveCallable("updateSprite");
			var ctr = 0.0; var dt = 1.0 / FRAMES;
			resetSprites(sprites);
			var t = haxe.Timer.stamp();
			for (_ in 0...FRAMES) {
				interp.nativeForEach(sprites, fn, [dtVal]);
				ctr += dt;
				interp.vm.globals.set("counter", VNumber(ctr));
			}
			timeD = haxe.Timer.stamp() - t;
		}
		trace('    ${fmtMs(timeD)}  /  ${fmt(FRAMES/timeD)} fps\n');

		// ── E: full Haxe loop — script only defines constants ─────────────
		// Script is used only to read config values (color, counter).
		// Haxe does ALL the math AND the writes.
		// This shows the floor: minimum possible overhead when the script
		// contributes zero computation per sprite.
		trace("[ E ] Haxe loop + script config  (Haxe does everything per sprite)");
		{
			var interp = new Interpreter();
			interp.vm.globals.set("counter", VNumber(0));
			interp.vm.globals.set("color",   VNumber(0xFF0000));

			// Register a batch update function: Haxe does the full loop
			interp.vm.natives.set("runBatch", VNativeFunction("runBatch", 3, (args) -> {
				var spritesVal = args[0];
				var dt   = switch (args[1]) { case VNumber(n): n; default: 0.0; };
				var ctr  = switch (args[2]) { case VNumber(n): n; default: 0.0; };
				var color = 0xFF0000;
				switch (spritesVal) {
					case VArray(arr):
						for (j in 0...arr.length) {
							var spr:MockSprite = cast switch (arr[j]) {
								case VNativeObject(o): o;
								default: null;
							};
							if (spr == null) continue;
							var phase = ctr + j;
							spr.angle += 120 * dt;
							spr.x     += 60  * dt * Math.sin(phase);
							spr.y     += 30  * dt * Math.cos(phase);
							spr.color  = color;
						}
					default:
				}
				return VNull;
			}));

			interp.run('
				func runLoop(sprites, dt) {
					runBatch(sprites, dt, counter)
					counter = counter + dt
				}
			');

			// Pre-box the sprite array once
			var spritesVal = interp.vm.haxeToValue(sprites);
			var fn = interp.resolveCallable("runLoop");
			resetSprites(sprites);
			var t = haxe.Timer.stamp();
			for (_ in 0...FRAMES)
				interp.vm.callResolved(fn, [spritesVal, dtVal]);
			timeE = haxe.Timer.stamp() - t;
		}
		trace('    ${fmtMs(timeE)}  /  ${fmt(FRAMES/timeE)} fps\n');

		// ── Summary ───────────────────────────────────────────────────────
		trace("=== Summary ===");
		trace('  A  script loop          : ${pad(fmtMs(timeA))}  ${fmt(FRAMES/timeA)} fps');
		trace('  B  nativeForEach        : ${pad(fmtMs(timeB))}  ${fmt(FRAMES/timeB)} fps');
		trace('  C  pure Haxe            : ${pad(fmtMs(timeC))}  ${fmt(FRAMES/timeC)} fps');
		trace('  D  native wrapper       : ${pad(fmtMs(timeD))}  ${fmt(FRAMES/timeD)} fps');
		trace('  E  Haxe batch + config  : ${pad(fmtMs(timeE))}  ${fmt(FRAMES/timeE)} fps');
		trace('');
		trace('  D speedup over A        : ${fmt(timeA/timeD)}x');
		trace('  E speedup over D        : ${fmt(timeD/timeE)}x');
		trace('  C speedup over E        : ${fmt(timeE/timeC)}x  (minimum VM overhead)');
	}

	static function resetSprites(s:Array<MockSprite>)
		for (sp in s) { sp.angle = 0; sp.x = 0; sp.y = 0; sp.color = 0; }

	static inline function fmtMs(t:Float):String return '${Std.int(t*1000)}ms';
	static inline function fmt(v:Float):String   return Std.string(Math.round(v*100)/100);
	static inline function pad(s:String):String  return StringTools.rpad(s, " ", 10);
}

class MockSprite {
	public var angle:Float = 0;
	public var x:Float     = 0;
	public var y:Float     = 0;
	public var color:Int   = 0;
	public var scale:MockPoint;
	public function new() scale = new MockPoint(1, 1);
}

class MockPoint {
	public var x:Float; public var y:Float;
	public function new(x, y) { this.x = x; this.y = y; }
	public function set(x:Float, y:Float) { this.x = x; this.y = y; }
}
