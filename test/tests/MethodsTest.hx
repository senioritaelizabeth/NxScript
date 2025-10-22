package;

import nz.script.Interpreter;

class MethodsTest {
	static function main() {
		trace("========================================");
		trace("METHODS TESTS");
		trace("========================================\n");

		var interp = new Interpreter();

		// Test 1: Number methods
		trace("Test 1: Number methods");
		var result = interp.runDynamic('
			var x = 3.7
			x.floor()
		');
		assert(result == 3, "Number.floor()");

		result = interp.runDynamic('
			var x = -5
			x.abs()
		');
		assert(result == 5, "Number.abs()");

		result = interp.runDynamic('
			var x = 2
			x.pow(3)
		');
		assert(result == 8, "Number.pow()");

		// Test 2: String methods
		trace("\nTest 2: String methods");
		var strResult:String = interp.runDynamic('
			var s = "hello"
			s.upper()
		');
		assert(strResult == "HELLO", "String.upper()");

		strResult = interp.runDynamic('
			var s = "WORLD"
			s.lower()
		');
		assert(strResult == "world", "String.lower()");

		strResult = interp.runDynamic('
			var s = "  trim me  "
			s.trim()
		');
		assert(strResult == "trim me", "String.trim()");

		// Test 3: Array methods
		trace("\nTest 3: Array methods");
		result = interp.runDynamic('
			var arr = [1, 2, 3]
			arr.push(4)
			arr.length
		');
		assert(result == 4, "Array.push() and length");

		result = interp.runDynamic('
			var arr = [1, 2, 3]
			arr.first()
		');
		assert(result == 1, "Array.first()");

		result = interp.runDynamic('
			var arr = [1, 2, 3, 4]
			arr.last()
		');
		assert(result == 4, "Array.last()");

		// Test 4: Method chaining
		trace("\nTest 4: Method chaining");
		result = interp.runDynamic('
			var x = -2000 / 2
			x.abs().floor()
		');
		assert(result == 1000, "Number method chaining");

		strResult = interp.runDynamic('
			var s = "  HELLO  "
			s.trim().lower()
		');
		assert(strResult == "hello", "String method chaining");

		trace("\n========================================");
		trace("ALL METHODS TESTS PASSED!");
		trace("========================================");

		Sys.exit(0);
	}

	static function assert(condition:Bool, message:String) {
		if (!condition) {
			throw 'Assertion failed: $message';
		}
		trace('✓ $message');
	}
}
