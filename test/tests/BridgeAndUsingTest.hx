package;

import nx.script.Interpreter;
import nx.script.VM;
import nx.script.Bytecode.Value;
import nx.bridge.NxStd;
import nx.bridge.NxDate;

/**
 * Tests for:
 *   1. `using` extension methods (NxScript class + native Haxe class)
 *   2. Int / Float subtypes of Number
 *   3. fromNumber / fromInt / fromFloat conversions
 *   4. NxStd bridge (Math, Std, Json, parseInt/parseFloat/isNaN)
 *   5. NxDate bridge (Date.now, dateFormat, timerStamp)
 *   6. Performance: ENTER_SCOPE only on blocks with let
 */
class BridgeAndUsingTest {

	static function assert(cond:Bool, msg:String) {
		if (cond) trace('  ✓ $msg')
		else { trace('  ✗ FAIL: $msg'); Sys.exit(1); }
	}

	static function assertApprox(a:Float, b:Float, msg:String, eps:Float = 0.01)
		assert(Math.abs(a - b) < eps, msg);

	static function main() {
		trace("========================================");
		trace("BRIDGE + USING TEST");
		trace("========================================\n");

		// 1. `using` with NxScript class
		trace("1. using — NxScript extension methods");

		var interp = new Interpreter();
		var r:Dynamic;

		r = interp.runDynamic('
			class MathUtils {
				func not_accept_zero(n) {
					if (n == 0) { return "zero not allowed!" }
					return n
				}
				func double(n) {
					return n * 2
				}
				func clamp(n, lo, hi) {
					if (n < lo) return lo
					if (n > hi) return hi
					return n
				}
			}

			using MathUtils

			var x = 5
			x.double()
		');
		assert(r == 10, "using: number.double()");

		r = interp.runDynamic('
			class MathUtils {
				func not_accept_zero(n) {
					if (n == 0) { return "zero not allowed!" }
					return n
				}
			}
			using MathUtils
			var x = 0
			x.not_accept_zero()
		');
		assert(r == "zero not allowed!", "using: not_accept_zero(0)");

		r = interp.runDynamic('
			class MathUtils {
				func not_accept_zero(n) {
					if (n == 0) { return "zero not allowed!" }
					return n
				}
			}
			using MathUtils
			var x = 42
			x.not_accept_zero()
		');
		assert(r == 42, "using: not_accept_zero(42) passes through");

		r = interp.runDynamic('
			class StringUtils {
				func shout(s) {
					return s.upper() + "!!!"
				}
				func wrap(s, ch) {
					return ch + s + ch
				}
			}
			using StringUtils
			"hello".shout()
		');
		assert(r == "HELLO!!!", "using: string extension shout()");

		r = interp.runDynamic('
			class StringUtils {
				func wrap(s, ch) {
					return ch + s + ch
				}
			}
			using StringUtils
			"world".wrap("*")
		');
		assert(r == "*world*", "using: string extension wrap() with arg");

		// Multiple using classes at once
		r = interp.runDynamic('
			class NumExt {
				func squared(n) { return n * n }
			}
			class StrExt {
				func exclaim(s) { return s + "!" }
			}
			using NumExt
			using StrExt
			var a = 4.squared()
			var b = "nice".exclaim()
			a + b.length
		');
		assert(r == 21, "using: multiple using classes");

		// 2. Int / Float subtypes
		trace("\n2. Int / Float / Number subtypes");

		r = interp.runDynamic('type(42)');
		assert(r == "Number", "42 is Number");

		r = interp.runDynamic('type(3.14)');
		assert(r == "Number", "3.14 is Number");

		// Int.from — accepts whole number
		r = interp.runDynamic('Int_from(7.0)');
		assert(r == 7, "Int_from(7.0) = 7");

		// Int.from — rejects fractional
		var threw = false;
		try { interp.runDynamic('Int_from(3.5)'); } catch (_:Dynamic) { threw = true; }
		assert(threw, "Int_from(3.5) throws");

		// Float.from — accepts any number
		r = interp.runDynamic('Float_from(5)');
		assert(r == 5, "Float_from(5) = 5");

		r = interp.runDynamic('Float_from(2.718)');
		assertApprox(r, 2.718, "Float_from(2.718)");

		// 3. fromNumber / fromInt / fromFloat
		trace("\n3. fromNumber / fromInt / fromFloat");

		r = interp.runDynamic('fromNumber(42)');
		assert(r == 42, "fromNumber(42)");

		r = interp.runDynamic('fromNumber(true)');
		assert(r == 1, "fromNumber(true) = 1");

		r = interp.runDynamic('fromNumber(false)');
		assert(r == 0, "fromNumber(false) = 0");

		r = interp.runDynamic('fromNumber("3.14")');
		assertApprox(r, 3.14, "fromNumber(\"3.14\")");

		r = interp.runDynamic('fromInt(10)');
		assert(r == 10, "fromInt(10)");

		r = interp.runDynamic('fromInt("7")');
		assert(r == 7, "fromInt(\"7\")");

		threw = false;
		try { interp.runDynamic('fromInt(2.5)'); } catch (_:Dynamic) { threw = true; }
		assert(threw, "fromInt(2.5) throws");

		r = interp.runDynamic('fromFloat(5)');
		assert(r == 5, "fromFloat(5)");

		r = interp.runDynamic('fromFloat("1.5")');
		assertApprox(r, 1.5, "fromFloat(\"1.5\")");

		// 4. NxStd bridge
		trace("\n4. NxStd bridge");

		var interp2 = new Interpreter();
		NxStd.registerAll(interp2.vm);

		r = interp2.runDynamic('parseInt("42")');
		assert(r == 42, "parseInt(\"42\")");

		r = interp2.runDynamic('parseFloat("3.14")');
		assertApprox(r, 3.14, "parseFloat(\"3.14\")");

		r = interp2.runDynamic('isNaN(0.0 / 0.0)');
		assert(r == true, "isNaN(0.0 / 0.0)");

		r = interp2.runDynamic('isNaN(NAN)');
		assert(r == true, "isNaN(NAN)");

		r = interp2.runDynamic('isNaN(42)');
		assert(r == false, "isNaN(42) = false");

		r = interp2.runDynamic('isFinite(42)');
		assert(r == true, "isFinite(42)");

		r = interp2.runDynamic('isFinite(INF)');
		assert(r == false, "isFinite(INF) = false");

		// Json via NxStd
		r = interp2.runDynamic('jsonStringify(42)');
		assert(r == "42", "jsonStringify(42)");

		r = interp2.runDynamic('var v = jsonParse("[1,2,3]")\nv.length');
		// haxeToValue of parsed JSON array
		assert(r == 3, "jsonParse array length");

		// 5. NxDate bridge
		trace("\n5. NxDate bridge");

		var interp3 = new Interpreter();
		NxDate.registerAll(interp3.vm);

		r = interp3.runDynamic('timerStamp() > 0');
		assert(r == true, "timerStamp() > 0");

		r = interp3.runDynamic('
			var d = dateNow()
			type(d)
		');
		// Date is a native object
		assert(r == "Date", "dateNow() type is Date");

		// 6. Perf: ENTER_SCOPE only on blocks with let
		trace("\n6. ENTER_SCOPE only when needed");

		// This loop should NOT emit ENTER/EXIT_SCOPE on each iteration
		// (no let inside while body) — just verify it runs correctly and fast
		var interpPerf = new Interpreter();
		var t0 = haxe.Timer.stamp();
		interpPerf.runDynamic('
			var i = 0
			var sum = 0
			while (i < 10000) {
				sum = sum + i
				i = i + 1
			}
			sum
		');
		var elapsed = haxe.Timer.stamp() - t0;
		assert(elapsed < 5.0, 'while loop 10k iters in < 5s (was ${elapsed}s)');

		// Block WITH let — ENTER/EXIT_SCOPE should work correctly
		r = interpPerf.runDynamic('
			var result = 0
			{
				let inner = 100
				result = inner + 1
			}
			result
		');
		assert(r == 101, "block with let: inner scoped correctly");

		r = interpPerf.runDynamic('
			var x = 1
			if (true) {
				var y = 2
				x = x + y
			}
			x
		');
		assert(r == 3, "if block without let: no scope overhead");

		// 7. Enums
		trace("\n7. Enums");

		r = interp.runDynamic('
			enum Color { Red, Green, Blue }
			Color["Red"]
		');
		assert(r == "Color.Red", "enum variant access Color.Red");

		r = interp.runDynamic('
			enum Direction { North, South, East, West }
			var d = Direction["North"]
			d.variant
		');
		assert(r == "North", "enum.variant property");

		r = interp.runDynamic('
			enum Direction { North, South, East, West }
			var d = Direction["East"]
			d.enum
		');
		assert(r == "Direction", "enum.enum property");

		// Enum with payload
		r = interp.runDynamic('
			enum Result { Ok(msg), Error(code) }
			var ok = Result["Ok"]("hello")
			ok.variant
		');
		assert(r == "Ok", "enum payload variant name");

		r = interp.runDynamic('
			enum Result { Ok(msg), Error(code) }
			var ok = Result["Ok"]("hello")
			ok.values[0]
		');
		assert(r == "hello", "enum payload value0");

		// match on enum
		r = interp.runDynamic('
			enum Color { Red, Green, Blue }
			var c = Color["Green"]
			match c {
				case Red   => "its red"
				case Green => "its green"
				case Blue  => "its blue"
			}
		');
		assert(r == "its green", "match on enum variant");

		// 8. `is` type check operator
		trace("\n8. is operator");

		r = interp.runDynamic('42 is Number');
		assert(r == true, "42 is Number");

		r = interp.runDynamic('"hello" is String');
		assert(r == true, "\"hello\" is String");

		r = interp.runDynamic('42 is String');
		assert(r == false, "42 is String = false");

		r = interp.runDynamic('true is Bool');
		assert(r == true, "true is Bool");

		r = interp.runDynamic('[1,2,3] is Array');
		assert(r == true, "[1,2,3] is Array");

		r = interp.runDynamic('null is Null');
		assert(r == true, "null is Null");

		// 9. Braceless if/while/for
		trace("\n9. Braceless control flow");

		r = interp.runDynamic('
			var x = 5
			if (x > 3) x = 99
			x
		');
		assert(r == 99, "braceless if body");

		r = interp.runDynamic('
			var x = 0
			if (x > 10) x = 1
			else x = 2
			x
		');
		assert(r == 2, "braceless if/else");

		r = interp.runDynamic('
			var i = 0
			while (i < 3) i++
			i
		');
		assert(r == 3, "braceless while");

		r = interp.runDynamic('
			var sum = 0
			for (x in [1,2,3]) sum = sum + x
			sum
		');
		assert(r == 6, "braceless for-in");

		// 10. Abstract types
		trace("\n10. Abstract types");

		r = interp.runDynamic('
			abstract Meters(Float) {
				func new(v) { this.value = v }
				func toKm() { return this.value * 0.001 }
			}
			var m = new Meters(1000)
			m.toKm()
		');
		assertApprox(r, 1.0, "abstract Meters.toKm()");

		trace("\n========================================");
		trace("ALL BRIDGE + USING TESTS PASSED! ✓");
		trace("========================================");
		Sys.exit(0);
	}
}
