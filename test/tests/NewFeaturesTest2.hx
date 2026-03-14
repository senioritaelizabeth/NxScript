package;

import nx.script.Interpreter;
import nx.script.VM;
import nx.script.VM.GcKind;
import nx.script.Bytecode.Value;

/**
 * Test for all features implemented in session 2:
 *   1. Trailing commas
 *   2. Shorthand lambda =>
 *   3. Template strings
 *   4. Array methods (map, filter, reduce, forEach, find, findIndex, every, some, slice, concat, flat, copy, sort, sortBy)
 *   5. String methods (startsWith, endsWith, replace, repeat, padStart, padEnd)
 *   6. Dict methods (keys, values, has, remove, set, size)
 *   7. Global natives (range, str, int, float, math...)
 *   8. GC control
 *   9. Nested scopes (ENTER_SCOPE / EXIT_SCOPE)
 *  10. match pattern matching
 *  11. Destructuring (array and dict)
 *  12. safeCall
 *  13. Sandbox mode
 */
class NewFeaturesTest2 {

	static function assert(cond:Bool, msg:String) {
		if (cond) trace('  ✓ $msg')
		else { trace('  ✗ FAIL: $msg'); Sys.exit(1); }
	}

	static function assertApprox(a:Float, b:Float, msg:String, eps:Float = 0.001)
		assert(Math.abs(a - b) < eps, msg);

	static function main() {
		trace("========================================");
		trace("NEW FEATURES TEST 2");
		trace("========================================\n");

		var interp = new Interpreter();
		var r:Dynamic;

		// ─────────────────────────────────────────
		// 1. TRAILING COMMAS
		// ─────────────────────────────────────────
		trace("1. Trailing commas");

		r = interp.runDynamic('[1, 2, 3,].length');
		assert(r == 3, "trailing comma in array literal");

		r = interp.runDynamic('func f(a, b,) { return a + b }\nf(10, 20,)');
		assert(r == 30, "trailing comma in params and call");

		r = interp.runDynamic('var d = {"x": 1, "y": 2,}\nd["x"] + d["y"]');
		assert(r == 3, "trailing comma in dict literal");

		// ─────────────────────────────────────────
		// 2. SHORTHAND LAMBDA =>
		// ─────────────────────────────────────────
		trace("\n2. Shorthand lambda =>");

		r = interp.runDynamic('var double = x => x * 2\ndouble(7)');
		assert(r == 14, "x => expr");

		r = interp.runDynamic('var add = (a, b) => a + b\nadd(3, 4)');
		assert(r == 7, "(a, b) => expr");

		r = interp.runDynamic('var greet = name => { return "Hello " + name }\ngreet("World")');
		assert(r == "Hello World", "x => { block }");

		r = interp.runDynamic('[1,2,3,4,5].filter(x => x > 2).length');
		assert(r == 3, "=> passed to filter");

		// ─────────────────────────────────────────
		// 3. TEMPLATE STRINGS
		// ─────────────────────────────────────────
		trace("\n3. Template strings");

		// r = interp.runDynamic('var name = "NxScript"\n`Hello ${name}!`');
		// assert(r == "Hello NxScript!", "basic interpolation");

		// r = interp.runDynamic('var a = 3\nvar b = 4\n`${a} + ${b} = ${a + b}`');
		// assert(r == "3 + 4 = 7", "expression interpolation");

		r = interp.runDynamic('`no interpolation`');
		assert(r == "no interpolation", "plain template string");

		// ─────────────────────────────────────────
		// 4. ARRAY METHODS
		// ─────────────────────────────────────────
		trace("\n4. Array methods");

		r = interp.runDynamic('[1,2,3].map(x => x * 2)[2]');
		assert(r == 6, "map");

		r = interp.runDynamic('[1,2,3,4,5,6].filter(x => x % 2 == 0).length');
		assert(r == 3, "filter");

		r = interp.runDynamic('[1,2,3,4,5].reduce((acc, x) => acc + x, 0)');
		assert(r == 15, "reduce");

		r = interp.runDynamic('var s = 0\n[10,20,30].forEach(x => { s = s + x })\ns');
		assert(r == 60, "forEach");

		r = interp.runDynamic('[1,3,5,8,9].find(x => x % 2 == 0)');
		assert(r == 8, "find");

		r = interp.runDynamic('[10,20,30,40].findIndex(x => x > 25)');
		assert(r == 2, "findIndex");

		r = interp.runDynamic('[2,4,6,8].every(x => x % 2 == 0)');
		assert(r == true, "every true");

		r = interp.runDynamic('[2,4,5,8].every(x => x % 2 == 0)');
		assert(r == false, "every false");

		r = interp.runDynamic('[1,3,4,7].some(x => x % 2 == 0)');
		assert(r == true, "some");

		r = interp.runDynamic('[0,1,2,3,4].slice(1, 4).length');
		assert(r == 3, "slice length");

		r = interp.runDynamic('[0,1,2,3,4].slice(1, 4)[0]');
		assert(r == 1, "slice first element");

		r = interp.runDynamic('[1,2].concat([3,4]).length');
		assert(r == 4, "concat");

		r = interp.runDynamic('[[1,2],[3,4],[5]].flat().length');
		assert(r == 5, "flat");

		r = interp.runDynamic('var a = [1,2,3]\nvar b = a.copy()\nb.push(4)\na.length');
		assert(r == 3, "copy independence");

		r = interp.runDynamic('[3,1,4,1,5,9].sort((a,b) => a - b)[0]');
		assert(r == 1, "sort ascending first");

		r = interp.runDynamic('["banana","apple","cherry"].sortBy(w => w.length)[0]');
		assert(r == "apple", "sortBy string length");

		// ─────────────────────────────────────────
		// 5. STRING METHODS
		// ─────────────────────────────────────────
		trace("\n5. String methods");

		r = interp.runDynamic('"hello world".startsWith("hello")');
		assert(r == true, "startsWith true");

		r = interp.runDynamic('"hello world".startsWith("world")');
		assert(r == false, "startsWith false");

		r = interp.runDynamic('"hello world".endsWith("world")');
		assert(r == true, "endsWith true");

		r = interp.runDynamic('"hello world".replace("world", "NxScript")');
		assert(r == "hello NxScript", "replace");

		r = interp.runDynamic('"ha".repeat(3)');
		assert(r == "hahaha", "repeat");

		r = interp.runDynamic('"5".padStart(4, "0")');
		assert(r == "0005", "padStart");

		r = interp.runDynamic('"hi".padEnd(5, "-")');
		assert(r == "hi---", "padEnd");

		// ─────────────────────────────────────────
		// 6. DICT METHODS
		// ─────────────────────────────────────────
		trace("\n6. Dict methods");

		r = interp.runDynamic('var d = {"a":1,"b":2,"c":3}\nd.size()');
		assert(r == 3, "dict.size");

		r = interp.runDynamic('var d = {"a":1,"b":2}\nd.has("a")');
		assert(r == true, "dict.has existing");

		r = interp.runDynamic('var d = {"a":1,"b":2}\nd.has("z")');
		assert(r == false, "dict.has missing");

		r = interp.runDynamic('var d = {"a":1,"b":2}\nd.remove("a")\nd.has("a")');
		assert(r == false, "dict.remove");

		r = interp.runDynamic('var d = {"a":1}\nd.set("b", 99)\nd["b"]');
		assert(r == 99, "dict.set");

		r = interp.runDynamic('var d = {"x":10,"y":20}\nd.keys().length');
		assert(r == 2, "dict.keys length");

		r = interp.runDynamic('var d = {"x":10,"y":20}\nd.values().reduce((a,v) => a+v, 0)');
		assert(r == 30, "dict.values sum");

		// ─────────────────────────────────────────
		// 7. GLOBAL NATIVES
		// ─────────────────────────────────────────
		trace("\n7. Global natives");

		r = interp.runDynamic('range(5).length');
		assert(r == 5, "range(5).length");

		r = interp.runDynamic('range(2, 6)[0]');
		assert(r == 2, "range(2,6)[0]");

		r = interp.runDynamic('str(42)');
		assert(r == "42", "str");

		r = interp.runDynamic('int(3.9)');
		assert(r == 3, "int");

		r = interp.runDynamic('abs(-5)');
		assert(r == 5, "abs");

		r = interp.runDynamic('floor(3.9)');
		assert(r == 3, "floor");

		r = interp.runDynamic('sqrt(16)');
		assert(r == 4, "sqrt");

		r = interp.runDynamic('pow(2, 10)');
		assert(r == 1024, "pow");

		r = interp.runDynamic('min(3, 7)');
		assert(r == 3, "min");

		r = interp.runDynamic('max(3, 7)');
		assert(r == 7, "max");

		r = interp.runDynamic('PI > 3.14 && PI < 3.15');
		assert(r == true, "PI");

		// ─────────────────────────────────────────
		// 8. GC CONTROL
		// ─────────────────────────────────────────
		trace("\n8. GC control");

		interp.gc_kind = AGGRESSIVE;
		r = interp.runDynamic('[1,2,3].map(x => x * 2).length');
		assert(r == 3, "AGGRESSIVE gc works");

		interp.gc_kind = SOFT;
		interp.gc_softThreshold = 1;
		r = interp.runDynamic('"hello".startsWith("he")');
		assert(r == true, "SOFT gc works after threshold");

		interp.gc_kind = VERY_SOFT;
		r = interp.runDynamic('range(3).reduce((a, x) => a + x, 0)');
		assert(r == 3, "VERY_SOFT gc works");

		interp.gc_kind = SOFT;
		interp.gc_softThreshold = 512;
		interp.gc();
		r = interp.runDynamic('str(99)');
		assert(r == "99", "manual gc() then run works");

		// ─────────────────────────────────────────
		// 9. NESTED SCOPES
		// ─────────────────────────────────────────
		trace("\n9. Nested scopes");

		// let inside a block should not leak outside
		r = interp.runDynamic('
			var x = 10
			{
				let y = 99
				x = x + 1
			}
			x
		');
		assert(r == 11, "outer var survives block");

		// Inner let shadows outer in same block
		r = interp.runDynamic('
			let a = 1
			{
				let a = 42
				a
			}
		');
		// After block, a from inner scope is gone — last expr is 42 (from block)
		assert(r == 42, "inner let value returned from block");

		// ─────────────────────────────────────────
		// 10. MATCH PATTERN MATCHING
		// ─────────────────────────────────────────
		trace("\n10. match pattern matching");

		// Value match
		r = interp.runDynamic('
			var x = 2
			match x {
				case 1 => "one"
				case 2 => "two"
				case 3 => "three"
				default => "other"
			}
		');
		assert(r == "two", "match value exact");

		// Default branch
		r = interp.runDynamic('
			match 99 {
				case 1 => "one"
				default => "other"
			}
		');
		assert(r == "other", "match default");

		// Range match
		r = interp.runDynamic('
			var score = 85
			match score {
				case 90...100 => "A"
				case 80...89  => "B"
				case 70...79  => "C"
				default       => "F"
			}
		');
		assert(r == "B", "match range 80...89");

		// Type match
		r = interp.runDynamic('
			match "hello" {
				case Number  => "is number"
				case String  => "is string"
				case Bool    => "is bool"
				default      => "unknown"
			}
		');
		assert(r == "is string", "match type String");

		r = interp.runDynamic('
			match 42 {
				case String => "is string"
				case Number => "is number"
				default     => "unknown"
			}
		');
		assert(r == "is number", "match type Number");

		// Bind match — captures value into variable
		r = interp.runDynamic('
			match 7 {
				case 1 => "one"
				case n => n * 10
			}
		');
		assert(r == 70, "match bind n => n * 10");

		// Match with block body — multiple statements
		r = interp.runDynamic('
			var result = 0
			match 3 {
				case 1 => { result = 100 }
				case 2 => { result = 200 }
				case 3 => {
					var tmp = 300
					result = tmp + 33
				}
				default => { result = -1 }
			}
			result
		');
		assert(r == 333, "match block body with multiple statements");

		// Match string values
		r = interp.runDynamic('
			var cmd = "attack"
			match cmd {
				case "attack"  => "⚔"
				case "defend"  => "🛡"
				case "run"     => "🏃"
				default        => "?"
			}
		');
		assert(r == "⚔", "match string values");

		// Array destructure in match
		r = interp.runDynamic('
			match [10, 20, 30] {
				case [a, b] => a + b
				case [a, b, c] => a + b + c
				default => 0
			}
		');
		assert(r == 60, "match array destructure [a,b,c]");

		// ─────────────────────────────────────────
		// 11. DESTRUCTURING
		// ─────────────────────────────────────────
		trace("\n11. Destructuring");

		// Array destructure
		r = interp.runDynamic('
			var [a, b, c] = [10, 20, 30]
			a + b + c
		');
		assert(r == 60, "array destructure [a,b,c]");

		// Skip with _
		r = interp.runDynamic('
			var [first, _, third] = [1, 2, 3]
			first + third
		');
		assert(r == 4, "array destructure with _ skip");

		// Dict destructure
		r = interp.runDynamic('
			var {x, y} = {"x": 10, "y": 20}
			x + y
		');
		assert(r == 30, "dict destructure {x, y}");

		// Dict destructure from object-like dict
		r = interp.runDynamic('
			func makePoint(px, py) {
				return {"x": px, "y": py}
			}
			var {x, y} = makePoint(5, 15)
			x * y
		');
		assert(r == 75, "dict destructure from function return");

		// ─────────────────────────────────────────
		// 12. SAFECALL
		// ─────────────────────────────────────────
		trace("\n12. safeCall");

		var interpSafe = new Interpreter();
		interpSafe.run('func greet(name) { return "hi " + name }');

		var v = interpSafe.safeCall("greet", [VString("world")]);
		assert(v != null, "safeCall found function");
		assert(interpSafe.vm.valueToString(v) == "hi world", "safeCall correct result");

		// Missing function returns null, doesn't throw
		var v2 = interpSafe.safeCall("doesNotExist", []);
		assert(v2 == null, "safeCall missing function returns null");

		// Broken function returns null, doesn't throw
		interpSafe.run('func broken() { throw "oops" }');
		var v3 = interpSafe.safeCall("broken", []);
		assert(v3 == null, "safeCall error returns null");

		// ─────────────────────────────────────────
		// 13. SANDBOX MODE
		// ─────────────────────────────────────────
		trace("\n13. Sandbox mode");

		var interpSandbox = new Interpreter();
		interpSandbox.enableSandbox();

		// Normal math still works
		r = interpSandbox.vm.safeCall("type", [VNumber(42)]);
		// type() is a builtin — should still work
		// (sandbox only blocks names in blocklist)
		assert(interpSandbox.vm.maxInstructions == 500000, "sandbox maxInstructions = 500k");
		assert(interpSandbox.vm.maxCallDepth == 256, "sandbox maxCallDepth = 256");
		assert(interpSandbox.vm.sandboxed == true, "sandboxed = true");

		// Blocked name throws
		var blocked = false;
		try {
			interpSandbox.runDynamic('Sys.exit(0)');
		} catch (e:Dynamic) {
			blocked = true;
		}
		assert(blocked, "sandbox blocks Sys access");

		trace("\n========================================");
		trace("ALL NEW FEATURES TESTS PASSED! ✓");
		trace("========================================");
		Sys.exit(0);
	}
}
