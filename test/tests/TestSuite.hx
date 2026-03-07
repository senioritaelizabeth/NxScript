package;

import nz.script.Interpreter;

class TestSuite {
	static var passed:Int = 0;
	static var failed:Int = 0;

	static function main() {
		trace("========================================");
		trace("NxScript Test Suite");
		trace("========================================\n");

		basicTests();
		classesTests();
		methodsTests();
		bugFixTests();

		trace("\n========================================");
		trace('Results: $passed passed, $failed failed');
		trace("========================================");

		if (failed > 0)
			Sys.exit(1);
		else
			Sys.exit(0);
	}

	// ========================================
	// Basic Tests
	// ========================================

	static function basicTests() {
		trace("--- Basic Tests ---");
		var interp = new Interpreter();

		check(interp.runDynamic('
			var x = 10
			var y = 20
			x + y
		') == 30, "variables and addition");

		check(interp.runDynamic('
			func add(a, b) {
				return a + b
			}
			add(15, 25)
		') == 40, "function call");

		check(interp.runDynamic('
			var x = 10
			var y = 20
			var max = 0
			if (x > y) { max = x } else { max = y }
			max
		') == 20, "if/else statement");

		check(interp.runDynamic('
			var i = 0
			var sum = 0
			while (i < 10) {
				sum = sum + i
				i = i + 1
			}
			sum
		') == 45, "while loop");

		check(interp.runDynamic('
			var arr = [1, 2, 3]
			arr.push(4)
			arr.length
		') == 4, "array push and length");
	}

	// ========================================
	// Classes Tests
	// ========================================

	static function classesTests() {
		trace("\n--- Classes Tests ---");
		var interp = new Interpreter();

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
		check(true, "class definition compiles");

		var instance:Dynamic = interp.createInstance("Point", [3.0, 4.0]);
		check(instance.x == 3.0, "class instantiation - field x");
		check(instance.y == 4.0, "class instantiation - field y");
		check(instance.sum() == 7.0, "method call sum()");

		instance.x = 10.0;
		check(instance.sum() == 14.0, "field modification + auto-sync");
	}

	// ========================================
	// Methods Tests
	// ========================================

	static function methodsTests() {
		trace("\n--- Methods Tests ---");
		var interp = new Interpreter();

		// Number methods
		check(interp.runDynamic('
			var x = 3.7
			x.floor()
		') == 3, "Number.floor()");
		check(interp.runDynamic('
			var x = -5
			x.abs()
		') == 5, "Number.abs()");
		check(interp.runDynamic('
			var x = 2
			x.pow(3)
		') == 8, "Number.pow()");

		// String methods
		check(interp.runDynamic('
			var s = "hello"
			s.upper()
		') == "HELLO", "String.upper()");
		check(interp.runDynamic('
			var s = "WORLD"
			s.lower()
		') == "world", "String.lower()");
		check(interp.runDynamic('
			var s = "  trim me  "
			s.trim()
		') == "trim me", "String.trim()");

		// Array methods
		check(interp.runDynamic('
			var arr = [1, 2, 3]
			arr.push(4)
			arr.length
		') == 4, "Array.push() and length");
		check(interp.runDynamic('
			var arr = [1, 2, 3]
			arr.first()
		') == 1, "Array.first()");
		check(interp.runDynamic('
			var arr = [1, 2, 3, 4]
			arr.last()
		') == 4, "Array.last()");

		// Method chaining
		check(interp.runDynamic('
			var x = -2000 / 2
			x.abs().floor()
		') == 1000, "Number method chaining");
		check(interp.runDynamic('
			var s = "  HELLO  "
			s.trim().lower()
		') == "hello", "String method chaining");
	}

	// ========================================
	// Bug Fix Regression Tests
	// ========================================

	static function bugFixTests() {
		trace("\n--- Bug Fix Regression Tests ---");
		var interp = new Interpreter();

		check(interp.runDynamic('
			var arr = [1, 2, 3]
			arr[1] = 99
			arr[1]
		') == 99, "Array index assignment arr[1] = 99");

		check(interp.runDynamic('
			class Vec {
				var x
				var y
				func new(px, py) {
					this.x = px
					this.y = py
				}
				func move(dx, dy) {
					this.x = this.x + dx
					this.y = this.y + dy
					return this.x + this.y
				}
			}
			var v = new Vec(1, 2)
			v.move(10, 20)
		') == 33, "Sequential member assignment in method");

		// Run same interpreter many times — instructionCount must reset
		var interp2 = new Interpreter();
		for (_ in 0...10)
			interp2.runDynamic('
				var i = 0
				while (i < 500) {
					i = i + 1
				}
				i
			');
		check(interp2.runDynamic('42') == 42, "instructionCount resets between executions");
	}

	// ========================================
	// Helpers
	// ========================================

	static function check(condition:Bool, label:String) {
		if (condition) {
			passed++;
			trace('  ✓ $label');
		} else {
			failed++;
			trace('  ✗ FAIL: $label');
		}
	}
}
