package;

import nz.script.Interpreter;

class NewFeaturesTest {
	static function assert(cond:Bool, msg:String) {
		if (cond)
			trace('  ? ' + msg)
		else {
			trace('  ? FAIL: ' + msg);
			Sys.exit(1);
		}
	}

	static function main() {
		trace("========================================");
		trace("NEW FEATURES TESTS");
		trace("========================================\n");
		var interp = new Interpreter();

		// ++ prefix
		trace("Test 1: ++ and --");
		var r:Dynamic;
		r = interp.runDynamic('var x = 5\n++x\nx');
		assert(r == 6, "prefix ++");

		r = interp.runDynamic('var x = 5\n--x\nx');
		assert(r == 4, "prefix --");

		r = interp.runDynamic('var x = 5\nx++\nx');
		assert(r == 6, "postfix ++");

		r = interp.runDynamic('var x = 5\nx--\nx');
		assert(r == 4, "postfix --");

		// try/catch/throw
		trace("\nTest 2: try/catch/throw");
		r = interp.runDynamic('
            var result = "none"
            try {
                throw "oops"
                result = "bad"
            } catch (e) {
                result = e
            }
            result
        ');
		assert(r == "oops", "try/catch catches thrown value");

		r = interp.runDynamic('
            var result = 0
            try {
                result = 1
                result = 2
            } catch (e) {
                result = -1
            }
            result
        ');
		assert(r == 2, "try body runs normally when no throw");

		r = interp.runDynamic('
            func risky(n) {
                if (n < 0) { throw "negative" }
                return n * 2
            }
            var out = "none"
            try {
                out = risky(-1)
            } catch (e) {
                out = e
            }
            out
        ');
		assert(r == "negative", "catch exception from function call");

		trace("\n========================================");
		trace("ALL NEW FEATURES TESTS PASSED!");
		trace("========================================");
	}
}
