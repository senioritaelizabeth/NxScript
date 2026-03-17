package;

import nx.script.Interpreter;
import nx.script.NativeProxy;
import nx.script.Bytecode.Value;

/**
 * Microbenchmark para aislar exactamente dónde está el costo.
 */
class NativeProxyBench {

	static final N      = 10000;
	static final FRAMES = 300;

	static function main() {
		Sys.println("Microbenchmark — N=" + N + " sprites, " + FRAMES + " frames\n");

		var spritesA = makeSprites();
		var interpA  = new Interpreter();
		interpA.run('
			func update(sprites, dt) {
				var j = 0
				while (j < sprites.length) {
					var spr = sprites[j]
					spr.angle = spr.angle + 120 * dt
					spr.x = spr.x + 60 * dt
					spr.y = spr.y + 30 * dt
					spr.color = 0xFF0000
					j++
				}
			}
		');
		interpA.vm.globals.set("sprites", VArray([for (s in spritesA) VNativeObject(s)]));
		var fnA = interpA.vm.resolveCallable("update");
		var t0 = stamp();
		for (_ in 0...FRAMES) interpA.vm.callResolved(fnA, [VNumber(0.016)]);
		var msA = ms(t0);
		Sys.println("A  script + VNativeObject (4 fields):     " + fmt(msA));

		var spritesB = makeSprites();
		var interpB  = new Interpreter();
		interpB.run('
			func update(sprites, dt) {
				var j = 0
				while (j < sprites.length) {
					var spr = sprites[j]
					spr.angle = spr.angle + 120 * dt
					spr.x = spr.x + 60 * dt
					spr.y = spr.y + 30 * dt
					spr.color = 0xFF0000
					j++
				}
			}
		');
		var res = NativeProxy.wrapMany(interpB.vm, cast spritesB, ["x","y","angle","color"]);
		interpB.vm.globals.set("sprites", VArray(res.values));
		var fnB = interpB.vm.resolveCallable("update");
		var t1 = stamp();
		for (_ in 0...FRAMES) {
			interpB.vm.callResolved(fnB, [VNumber(0.016)]);
			NativeProxy.flushAll(res.proxies);
		}
		var msB = ms(t1);
		Sys.println("B  script + VProxy + flushAll:            " + fmt(msB));

		var spritesC = makeSprites();
		var interpC  = new Interpreter();
		interpC.run('
			func update(sprites, dt) {
				var j = 0
				while (j < sprites.length) {
					var spr = sprites[j]
					j++
				}
			}
		');
		interpC.vm.globals.set("sprites", VArray([for (s in spritesC) VNativeObject(s)]));
		var fnC = interpC.vm.resolveCallable("update");
		var t2 = stamp();
		for (_ in 0...FRAMES) interpC.vm.callResolved(fnC, [VNumber(0.016)]);
		var msC = ms(t2);
		Sys.println("C  script + empty loop (VM overhead):     " + fmt(msC));

		var spritesD = makeSprites();
		var interpD  = new Interpreter();
		var resD = NativeProxy.wrapMany(interpD.vm, cast spritesD, ["x","y","angle","color"]);
		var t3 = stamp();
		for (_ in 0...FRAMES) NativeProxy.flushAll(resD.proxies);
		var msD = ms(t3);
		Sys.println("D  flushAll only (no script):             " + fmt(msD));

		var spritesE = makeSprites();
		var interpE  = new Interpreter();
		interpE.run('
			func perSprite(spr, dt) {
				spr.angle = spr.angle + 120 * dt
				spr.x = spr.x + 60 * dt
				spr.y = spr.y + 30 * dt
				spr.color = 0xFF0000
			}
		');
		var resE = NativeProxy.wrapMany(interpE.vm, cast spritesE, ["x","y","angle","color"]);
		var fnE  = interpE.vm.resolveCallable("perSprite");
		var dtV  = VNumber(0.016);
		var t4   = stamp();
		for (_ in 0...FRAMES) {
			NativeProxy.scriptForEach(interpE.vm, resE.proxies, fnE, [dtV]);
			NativeProxy.flushAll(resE.proxies);
		}
		var msE = ms(t4);
		Sys.println("E  scriptForEach (Haxe loop) + flushAll:  " + fmt(msE));

		var spritesF = makeSprites();
		var t5 = stamp();
		var dummy = 0.0;
		for (_ in 0...FRAMES) {
			for (j in 0...spritesF.length) {
				var s = spritesF[j];
				s.angle += 120 * 0.016;
				s.x += 60 * 0.016;
				s.y += 30 * 0.016;
				s.color = 0xFF0000;
			}
		}
		var msF = ms(t5);
		Sys.println("F  Pure Haxe (ceiling):                   " + fmt(msF));

		Sys.println("\n── Analysis ─────────────────────────────────────");
		Sys.println("  VM loop overhead (C-D):   " + fmt(msC - msD) + "  (script interpret cost alone)");
		Sys.println("  Reflection cost (A-C):    " + fmt(msA - msC) + "  (getField+setField x4 x10k)");
		Sys.println("  Shadow map cost (B-C-D):  " + fmt(msB - msC - msD) + "  (Map get+set x4 x10k)");
		Sys.println("  flushAll cost (D):        " + fmt(msD) + "  (setField x4 x10k, no script)");
		Sys.println("  A/F ratio:                " + r(msA, msF) + "x vs pure Haxe");
		Sys.println("  B/F ratio:                " + r(msB, msF) + "x vs pure Haxe");
		Sys.println("  E/F ratio:                " + r(msE, msF) + "x vs pure Haxe");
	}

	static function makeSprites() return [for (i in 0...N) new MockSprite(i * 0.1, i * 0.2)];
	static inline function stamp() return haxe.Timer.stamp();
	static function ms(t:Float) return (haxe.Timer.stamp() - t) * 1000;
	static function fmt(ms:Float) return Std.string(Math.round(ms)) + " ms";
	static function r(a:Float, b:Float) return Std.string(Math.round(a/b*10)/10);
}

class MockSprite {
	public var x:Float;
	public var y:Float;
	public var angle:Float = 0;
	public var color:Int   = 0xFFFFFFFF;
	public function new(x:Float, y:Float) { this.x = x; this.y = y; }
}
