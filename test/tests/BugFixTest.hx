package;

import nz.script.Interpreter;

class BugFixTest {
	static function main() {
		trace("========================================");
		trace("BUG FIX REGRESSION TESTS");
		trace("========================================\n");

		var interp = new Interpreter();

		// Test: array index assignment (was completely broken due to wrong stack order)
		trace("Test: arr[i] = value");
		var r = interp.runDynamic('
			var arr = [1, 2, 3]
			arr[1] = 99
			arr[1]
		');
		assert(r == 99, "Array index assignment arr[1] = 99");

		// Test: sequential member assignments in a method (DUP was leaking values)
		trace("\nTest: sequential this.x = ... in method");
		r = interp.runDynamic('
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
		');
		assert(r == 33, "Sequential member assignment: (1+10) + (2+20) == 33");

		// Test: instructionCount resets between runs (same interpreter, many runs)
		trace("\nTest: instructionCount resets (multiple runs on same interp)");
		var interp2 = new Interpreter();
		for (i in 0...10) {
			interp2.runDynamic('
				var i = 0
				while (i < 500) {
					i = i + 1
				}
				i
			');
		}
		// If instructionCount wasn't reset, 10 x 500-iteration loops might exceed limit
		var finalR = interp2.runDynamic('42');
		assert(finalR == 42, "instructionCount resets between runs");

		trace("\n========================================");
		trace("ALL BUG FIX TESTS PASSED!");
		trace("========================================");

		Sys.exit(0);
	}

	static function assert(condition:Bool, message:String) {
		if (!condition) {
			trace('FAIL: $message');
			Sys.exit(1);
		}
		trace('✓ $message');
	}
}
