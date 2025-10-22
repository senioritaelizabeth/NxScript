package;

import nz.script.Interpreter;

class ClassesTest {
	static function main() {
		trace("========================================");
		trace("CLASSES TESTS");
		trace("========================================\n");

		var interp = new Interpreter();

		// Test 1: Class definition
		trace("Test 1: Class definition");
		interp.runDynamic('
			class Point {
				var x
				var y
				
				func new(px, py) {
					this.x = px
					this.y = py
				}
				
				func sum() {
					return this.x + this.y
				}
			}
		');
		trace('✓ Class definition successful');

		// Test 2: Class instantiation
		trace("\nTest 2: Class instantiation");
		var instance:Dynamic = interp.createInstance("Point", [3.0, 4.0]);
		assert(instance.x == 3.0, "Class instantiation - field x");
		assert(instance.y == 4.0, "Class instantiation - field y");

		// Test 3: Method calls
		trace("\nTest 3: Method calls");
		var result = instance.sum();
		assert(result == 7.0, "Method call sum()");

		// Test 4: Field modification
		trace("\nTest 4: Field modification");
		instance.x = 10.0;
		result = instance.sum();
		assert(result == 14.0, "Field modification (auto-sync)");

		trace("\n========================================");
		trace("ALL CLASSES TESTS PASSED!");
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
