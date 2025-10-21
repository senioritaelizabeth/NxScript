package;

import nz.script.Interpreter;
import nz.script.Bytecode;

/**
 * Simple test suite for Nz-Script
 * Tests all major features
 */
class TestAll {
	static var passed:Int = 0;
	static var failed:Int = 0;

	public static function main() {
		trace("╔════════════════════════════════════════════════════════╗");
		trace("║       NzLang Suite - Test Runner                      ║");
		trace("╚════════════════════════════════════════════════════════╝\n");

		// Run all tests
		testArithmetic();
		testVariables();
		testFunctions();
		testArrays();
		testDictionaries();
		testStringMethods();
		testNumberMethods();
		testIfElse();
		testWhileLoop();
		testForLoop();

		// Summary
		trace("\n═══════════════════════════════════════════════════════════");
		trace("TEST SUMMARY");
		trace("═══════════════════════════════════════════════════════════");
		trace('Passed: $passed');
		trace('Failed: $failed');
		trace('Total:  ${passed + failed}');
		trace("═══════════════════════════════════════════════════════════");

		if (failed > 0) {
			trace("\n✗ SOME TESTS FAILED!");
			Sys.exit(1);
		} else {
			trace("\n✓ ALL TESTS PASSED!");
			Sys.exit(0);
		}
	}

	static function test(name:String, script:String, expected:Dynamic) {
		try {
			var interp = new Interpreter(false);
			var result = interp.run(script, "test");

			var resultValue:Dynamic = switch (result) {
				case VNumber(v): v;
				case VString(v): v;
				case VBool(v): v;
				case VNull: null;
				case VArray(arr): arr.length;
				default: null;
			}

			if (resultValue == expected) {
				trace('  ✓ $name');
				passed++;
			} else {
				trace('  ✗ $name - Expected: $expected, Got: $resultValue');
				failed++;
			}
		} catch (e:Dynamic) {
			trace('  ✗ $name - Error: $e');
			failed++;
		}
	}

	static function testArithmetic() {
		trace("\n[1/10] Testing Arithmetic Operations...");
		test("Addition", "10 + 5", 15);
		test("Subtraction", "20 - 8", 12);
		test("Multiplication", "6 * 7", 42);
		test("Division", "100 / 4", 25);
		test("Modulo", "17 % 5", 2);
	}

	static function testVariables() {
		trace("\n[2/10] Testing Variables...");
		test("Let variable", "let x = 42\nx", 42);
		test("Var variable", "var y = 100\ny", 100);
		test("Const variable", "const PI = 3.14\nPI", 3.14);
		test("Variable arithmetic", "let a = 10\nlet b = 20\na + b", 30);
	}

	static function testFunctions() {
		trace("\n[3/10] Testing Functions...");
		test("Simple function", 'func add(a, b) { return a + b }\nadd(5, 3)', 8);
		test("Function with multiple params", 'func multiply(x, y) { return x * y }\nmultiply(4, 7)', 28);
		test("Recursive factorial", 'func fact(n) { if (n <= 1) { return 1 } return n * fact(n - 1) }\nfact(5)', 120);
	}

	static function testArrays() {
		trace("\n[4/10] Testing Arrays...");
		test("Array creation", "let arr = [1, 2, 3]\nlen(arr)", 3);
		test("Array push", "let arr = [1, 2]\narr.push(3)\nlen(arr)", 3);
		test("Array access", "let arr = [10, 20, 30]\narr[1]", 20);
	}

	static function testDictionaries() {
		trace("\n[5/10] Testing Dictionaries...");
		test("Dict creation", 'let d = {"name": "John", "age": 25}\nd["age"]', 25);
		test("Dict access", 'let person = {"x": 10}\nperson["x"]', 10);
	}

	static function testStringMethods() {
		trace("\n[6/10] Testing String Methods...");
		test("String upper", '"hello".upper()', "HELLO");
		test("String lower", '"WORLD".lower()', "world");
		test("String length", 'len("test")', 4);
	}

	static function testNumberMethods() {
		trace("\n[7/10] Testing Number Methods...");
		test("Number floor", "(10.7).floor()", 10);
		test("Number round", "(10.5).round()", 11);
		test("Number abs", "(-5).abs()", 5);
	}

	static function testIfElse() {
		trace("\n[8/10] Testing If/Else...");
		test("If true", "let x = 10\nif (x > 5) { x = 20 }\nx", 20);
		test("If false", "let x = 10\nif (x > 50) { x = 20 }\nx", 10);
		test("If/else", "let x = 3\nif (x > 5) { x = 10 } else { x = 20 }\nx", 20);
	}

	static function testWhileLoop() {
		trace("\n[9/10] Testing While Loop...");
		test("While sum", "let i = 0\nlet sum = 0\nwhile (i < 5) { sum = sum + i\ni = i + 1 }\nsum", 10);
		test("While counter", "let count = 0\nwhile (count < 3) { count = count + 1 }\ncount", 3);
	}

	static function testForLoop() {
		trace("\n[10/10] Testing For Loop...");
		test("For with array", "let arr = [1, 2, 3]\nlet sum = 0\nfor (x in arr) { sum = sum + x }\nsum", 6);
		test("For iteration", "let nums = [10, 20, 30]\nlet count = 0\nfor (n in nums) { count = count + 1 }\ncount", 3);
	}
}
