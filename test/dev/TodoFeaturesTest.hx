package;

import nx.script.Interpreter;
import nx.script.VM.GcKind;

/**
 * Tests for all features implemented from TODO.md:
 *   - Trailing commas
 *   - Shorthand lambda (=> syntax)
 *   - Template strings (backticks with ${})
 *   - Array methods: map, filter, reduce, forEach, find, findIndex, every, some,
 *                    slice, concat, flat, copy, sort, sortBy
 *   - String methods: startsWith, endsWith, replace, repeat, padStart, padEnd
 *   - Dict methods:   keys(), values(), has(), remove(), set(), size()
 *   - Global natives: print, println, range, str, int, float,
 *                     abs, floor, ceil, round, sqrt, pow, min, max, random,
 *                     sin, cos, tan, PI, INF, NAN
 */
class TodoFeaturesTest {

	static function assert(cond:Bool, msg:String) {
		if (cond)
			trace('  ✓ $msg')
		else {
			trace('  ✗ FAIL: $msg');
			Sys.exit(1);
		}
	}

	static function assertApprox(a:Float, b:Float, msg:String, eps:Float = 0.0001) {
		assert(Math.abs(a - b) < eps, msg);
	}

	static function main() {
		trace("========================================");
		trace("TODO FEATURES TEST");
		trace("========================================\n");

		var interp = new Interpreter();
		var r:Dynamic;

		// 1. TRAILING COMMAS
		trace("1. Trailing commas");

		r = interp.runDynamic('
			var arr = [1, 2, 3,]
			arr.length
		');
		assert(r == 3, "trailing comma in array literal");

		r = interp.runDynamic('
			func add(a, b,) { return a + b }
			add(10, 20,)
		');
		assert(r == 30, "trailing comma in params and call");

		r = interp.runDynamic('
			var d = {"x": 1, "y": 2,}
			d["x"] + d["y"]
		');
		assert(r == 3, "trailing comma in dict literal");

		// 2. SHORTHAND LAMBDA  (=>)
		trace("\n2. Shorthand lambda (=>)");

		r = interp.runDynamic('
			var double = x => x * 2
			double(7)
		');
		assert(r == 14, "single-arg shorthand lambda x => expr");

		r = interp.runDynamic('
			var add = (a, b) => a + b
			add(3, 4)
		');
		assert(r == 7, "multi-arg shorthand lambda (a, b) => expr");

		r = interp.runDynamic('
			var greet = name => {
				return "Hello " + name
			}
			greet("World")
		');
		assert(r == "Hello World", "shorthand lambda with block body");

		r = interp.runDynamic('
			var nums = [1, 2, 3, 4, 5]
			nums.filter(x => x > 2).length
		');
		assert(r == 3, "shorthand lambda passed to filter");

		// 3. TEMPLATE STRINGS  (`${}`)
		trace("\n3. Template strings");

		r = interp.runDynamic("
			var name = \"NxScript\"
			`Hello ${name}!`
		");
		assert(r == "Hello NxScript!", "basic template string interpolation");

		r = interp.runDynamic("
			var a = 3
			var b = 4
			`${a} + ${b} = ${a + b}`
		");
		assert(r == "3 + 4 = 7", "template string with expressions");

		r = interp.runDynamic("
			var x = 10
			`value is ${x * x}`
		");
		assert(r == "value is 100", "template string with computed expr");

		r = interp.runDynamic('`no interpolation here`');
		assert(r == "no interpolation here", "template string without interpolation");

		// 4. ARRAY METHODS
		trace("\n4. Array methods");

		// map
		r = interp.runDynamic('
			var nums = [1, 2, 3]
			var doubled = nums.map(x => x * 2)
			doubled[2]
		');
		assert(r == 6, "array.map");

		// filter
		r = interp.runDynamic('
			var nums = [1, 2, 3, 4, 5, 6]
			var evens = nums.filter(x => x % 2 == 0)
			evens.length
		');
		assert(r == 3, "array.filter");

		// reduce
		r = interp.runDynamic('
			var nums = [1, 2, 3, 4, 5]
			nums.reduce((acc, x) => acc + x, 0)
		');
		assert(r == 15, "array.reduce sum");

		// forEach (side effect via closure)
		r = interp.runDynamic('
			var nums = [10, 20, 30]
			var sum = 0
			nums.forEach(x => { sum = sum + x })
			sum
		');
		assert(r == 60, "array.forEach");

		// find
		r = interp.runDynamic('
			var nums = [1, 3, 5, 8, 9]
			nums.find(x => x % 2 == 0)
		');
		assert(r == 8, "array.find");

		// findIndex
		r = interp.runDynamic('
			var nums = [10, 20, 30, 40]
			nums.findIndex(x => x > 25)
		');
		assert(r == 2, "array.findIndex");

		// every
		r = interp.runDynamic('
			var nums = [2, 4, 6, 8]
			nums.every(x => x % 2 == 0)
		');
		assert(r == true, "array.every (all even)");

		r = interp.runDynamic('
			var nums = [2, 4, 5, 8]
			nums.every(x => x % 2 == 0)
		');
		assert(r == false, "array.every (not all even)");

		// some
		r = interp.runDynamic('
			var nums = [1, 3, 4, 7]
			nums.some(x => x % 2 == 0)
		');
		assert(r == true, "array.some (has even)");

		// slice
		r = interp.runDynamic('
			var nums = [0, 1, 2, 3, 4]
			var s = nums.slice(1, 4)
			s.length
		');
		assert(r == 3, "array.slice length");

		r = interp.runDynamic('
			var nums = [0, 1, 2, 3, 4]
			var s = nums.slice(1, 4)
			s[0]
		');
		assert(r == 1, "array.slice first element");

		// concat
		r = interp.runDynamic('
			var a = [1, 2]
			var b = [3, 4]
			var c = a.concat(b)
			c.length
		');
		assert(r == 4, "array.concat length");

		// flat
		r = interp.runDynamic('
			var nested = [[1, 2], [3, 4], [5]]
			var flat = nested.flat()
			flat.length
		');
		assert(r == 5, "array.flat length");

		r = interp.runDynamic('
			var nested = [[1, 2], [3, 4]]
			nested.flat()[3]
		');
		assert(r == 4, "array.flat element");

		// copy
		r = interp.runDynamic('
			var a = [1, 2, 3]
			var b = a.copy()
			b.push(4)
			a.length
		');
		assert(r == 3, "array.copy is independent");

		// sort
		r = interp.runDynamic('
			var nums = [3, 1, 4, 1, 5, 9, 2, 6]
			var sorted = nums.sort((a, b) => a - b)
			sorted[0]
		');
		assert(r == 1, "array.sort ascending first");

		r = interp.runDynamic('
			var nums = [3, 1, 4, 1, 5, 9, 2, 6]
			var sorted = nums.sort((a, b) => a - b)
			sorted[7]
		');
		assert(r == 9, "array.sort ascending last");

		// sortBy
		r = interp.runDynamic('
			var words = ["banana", "apple", "cherry"]
			var sorted = words.sortBy(w => w.length)
			sorted[0]
		');
		assert(r == "apple", "array.sortBy string length");

		// 5. STRING METHODS
		trace("\n5. String methods");

		r = interp.runDynamic('"hello world".startsWith("hello")');
		assert(r == true, "startsWith true");

		r = interp.runDynamic('"hello world".startsWith("world")');
		assert(r == false, "startsWith false");

		r = interp.runDynamic('"hello world".endsWith("world")');
		assert(r == true, "endsWith true");

		r = interp.runDynamic('"hello world".endsWith("hello")');
		assert(r == false, "endsWith false");

		r = interp.runDynamic('"hello world".replace("world", "NxScript")');
		assert(r == "hello NxScript", "replace");

		r = interp.runDynamic('"ha".repeat(3)');
		assert(r == "hahaha", "repeat");

		r = interp.runDynamic('"5".padStart(4, "0")');
		assert(r == "0005", "padStart");

		r = interp.runDynamic('"hi".padEnd(5, "-")');
		assert(r == "hi---", "padEnd");

		// 6. DICT METHODS
		trace("\n6. Dict methods");

		r = interp.runDynamic('
			var d = {"a": 1, "b": 2, "c": 3}
			d.size()
		');
		assert(r == 3, "dict.size");

		r = interp.runDynamic('
			var d = {"a": 1, "b": 2}
			d.has("a")
		');
		assert(r == true, "dict.has existing key");

		r = interp.runDynamic('
			var d = {"a": 1, "b": 2}
			d.has("z")
		');
		assert(r == false, "dict.has missing key");

		r = interp.runDynamic('
			var d = {"a": 1, "b": 2}
			d.remove("a")
			d.has("a")
		');
		assert(r == false, "dict.remove");

		r = interp.runDynamic('
			var d = {"a": 1}
			d.set("b", 99)
			d["b"]
		');
		assert(r == 99, "dict.set");

		r = interp.runDynamic('
			var d = {"x": 10, "y": 20}
			var ks = d.keys()
			ks.length
		');
		assert(r == 2, "dict.keys length");

		r = interp.runDynamic('
			var d = {"x": 10, "y": 20}
			var vs = d.values()
			vs.reduce((acc, v) => acc + v, 0)
		');
		assert(r == 30, "dict.values sum");

		// 7. GLOBAL NATIVES
		trace("\n7. Global natives");

		// range
		r = interp.runDynamic('range(5).length');
		assert(r == 5, "range(5).length");

		r = interp.runDynamic('range(5)[0]');
		assert(r == 0, "range(5)[0]");

		r = interp.runDynamic('range(5)[4]');
		assert(r == 4, "range(5)[4]");

		r = interp.runDynamic('range(2, 6).length');
		assert(r == 4, "range(2,6).length");

		r = interp.runDynamic('range(2, 6)[0]');
		assert(r == 2, "range(2,6)[0]");

		// str / int / float
		r = interp.runDynamic('str(42)');
		assert(r == "42", "str(42)");

		r = interp.runDynamic('int(3.9)');
		assert(r == 3, "int(3.9)");

		r = interp.runDynamic('int("7")');
		assert(r == 7, "int(\"7\")");

		r = interp.runDynamic('float("3.14")');
		assertApprox(r, 3.14, "float(\"3.14\")");

		// math
		r = interp.runDynamic('abs(-5)');
		assert(r == 5, "abs(-5)");

		r = interp.runDynamic('floor(3.9)');
		assert(r == 3, "floor(3.9)");

		r = interp.runDynamic('ceil(3.1)');
		assert(r == 4, "ceil(3.1)");

		r = interp.runDynamic('round(3.5)');
		assert(r == 4, "round(3.5)");

		r = interp.runDynamic('sqrt(16)');
		assert(r == 4, "sqrt(16)");

		r = interp.runDynamic('pow(2, 10)');
		assert(r == 1024, "pow(2,10)");

		r = interp.runDynamic('min(3, 7)');
		assert(r == 3, "min(3,7)");

		r = interp.runDynamic('max(3, 7)');
		assert(r == 7, "max(3,7)");

		r = interp.runDynamic('PI > 3.14 && PI < 3.15');
		assert(r == true, "PI constant");

		// random() in range
		r = interp.runDynamic('var x = random()\nx >= 0 && x < 1');
		assert(r == true, "random() in [0,1)");

		// sin / cos
		r = interp.runDynamic('round(sin(0) * 1000) / 1000');
		assertApprox(r, 0.0, "sin(0) ≈ 0");

		r = interp.runDynamic('round(cos(0) * 1000) / 1000');
		assertApprox(r, 1.0, "cos(0) ≈ 1");

		// keys/values global
		r = interp.runDynamic('keys({"a": 1, "b": 2}).length');
		assert(r == 2, "global keys()");

		r = interp.runDynamic('values({"a": 10, "b": 20}).reduce((a, v) => a + v, 0)');
		assert(r == 30, "global values() + reduce");

		// 8. GC CONTROL
		trace("\n8. GC control");

		// AGGRESSIVE: caches wiped every execute()
		interp.gc_kind = AGGRESSIVE;
		r = interp.runDynamic('var arr = [1,2,3]\narr.map(x => x * 2).length');
		assert(r == 3, "AGGRESSIVE gc_kind still works");

		// SOFT: threshold-based flush
		interp.gc_kind = SOFT;
		interp.gc_softThreshold = 1; // force flush on next execute
		r = interp.runDynamic('"hello".startsWith("he")');
		assert(r == true, "SOFT gc_kind still works after forced threshold");

		// VERY_SOFT: never flushes proactively
		interp.gc_kind = VERY_SOFT;
		r = interp.runDynamic('range(3).reduce((a, x) => a + x, 0)');
		assert(r == 3, "VERY_SOFT gc_kind still works");

		// Manual gc() flush
		interp.gc_softThreshold = 512; // reset
		interp.gc_kind = SOFT;
		interp.gc();
		r = interp.runDynamic('str(99)');
		assert(r == "99", "manual gc() then execute still works");

		// DONE
		trace("\n========================================");
		trace("ALL TODO FEATURES TESTS PASSED! ✓");
		trace("========================================");
		Sys.exit(0);
	}
}
