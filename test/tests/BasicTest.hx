package;

import nz.script.Interpreter;

class BasicTest {
	static function main() {
		trace("========================================");
		trace("BASIC TESTS");
		trace("========================================\n");

		var interp = new Interpreter();

		// Test 1: Variables and arithmetic
		trace("Test 1: Variables and arithmetic");
		var result = interp.runDynamic('
			var x = 10
			var y = 20
			x + y
		');
		assert(result == 30, "Variables and addition");

		// Test 2: Functions
		trace("\nTest 2: Functions");
		result = interp.runDynamic('
			func add(a, b) {
				return a + b
			}
			add(15, 25)
		');
		assert(result == 40, "Function call");

		// Test 3: If/Else
		trace("\nTest 3: If/Else");
		result = interp.runDynamic('
			var x = 10
			var y = 20
			var max = 0
			if (x > y) {
				max = x
			} else {
				max = y
			}
			max
		');
		assert(result == 20, "If/else statement");

		// Test 4: While loop
		trace("\nTest 4: While loop");
		result = interp.runDynamic('
			var i = 0
			var sum = 0
			while (i < 10) {
				sum = sum + i
				i = i + 1
			}
			sum
		');
		assert(result == 45, "While loop");

		// Test 5: Arrays
		trace("\nTest 5: Arrays");
		result = interp.runDynamic('
			var arr = [1, 2, 3]
			arr.push(4)
			arr.length
		');
		assert(result == 4, "Array push and length");

		trace("\n========================================");
		trace("ALL BASIC TESTS PASSED!");
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
