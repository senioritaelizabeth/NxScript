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

		// Test: for-from-to with continue (was infinite loop)
		trace("\nTest: for-from-to with continue");
		r = interp.runDynamic('
			var sum = 0
			for (i from 0 to 5) {
				if (i == 2) { continue }
				sum = sum + i
			}
			sum
		');
		assert(r == 8, "for-from-to with continue (0+1+3+4 = 8)");

		// Test: elseif keyword (was parse error)
		trace("\nTest: elseif keyword");
		r = interp.runDynamic('
			var x = 10
			if (x == 5) {
				return 1
			} elseif (x == 10) {
				return 2
			} else {
				return 3
			}
		');
		assert(r == 2, "elseif keyword works");

		// Test: postfix increment side effects (evaluated target twice)
		trace("\nTest: postfix increment side effects");
		var calls = 0;
		interp.register("getVal", 0, function(_) {
			calls++;
			return VNumber(10);
		});
		// Note: We can't easily test setting a value back to a native call result 
		// unless it returns an object/array.
		r = interp.runDynamic('
			var obj = { "x": 10 }
			func getObj() {
				getVal() // track call
				return obj
			}
			var old = getObj().x++
			[old, obj.x]
		');
		var res:Array<Dynamic> = cast r;
		assert(calls == 1, "getObj() called only once for postfix increment");
		assert(res[0] == 10, "Postfix returns old value 10");
		assert(res[1] == 11, "Target incremented to 11");

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
