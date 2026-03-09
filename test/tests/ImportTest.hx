package;

import nz.script.Interpreter;

class ImportTest {
	static function main() {
		trace("========================================");
		trace("IMPORT TESTS");
		trace("========================================\n");

		var interp = new Interpreter();

		trace("Test 1: i \"package.name\"");
		var result = interp.runDynamic('i "haxe.ds.StringMap"\nvar m = new StringMap()\nm.set("k", 10)\nm.get("k")', "tests/import_i.nx");
		assert(result == 10, "i import resolves Haxe class");

		trace("\nTest 2: import \"package.name\"");
		result = interp.runDynamic('import "haxe.ds.StringMap"\nvar m = new StringMap()\nm.set("k", 21)\nm.get("k")', "tests/import_string.nx");
		assert(result == 21, "quoted import resolves Haxe class");

		trace("\nTest 3: import package.name");
		result = interp.runDynamic('import haxe.ds.StringMap\nvar m = new StringMap()\nm.set("k", 42)\nm.get("k")', "tests/import_plain.nx");
		assert(result == 42, "plain import resolves Haxe class");

		trace("\nTest 4: Haxe-style return type");
		result = interp.runDynamic('function add(a:Int, b:Int):Int { return a + b; } add(8, 9);', "tests/hx_return_type.nx");
		assert(result == 17, "Haxe-style :ReturnType parses and runs");

		trace("\n========================================");
		trace("ALL IMPORT TESTS PASSED!");
		trace("========================================");
		Sys.exit(0);
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition)
			throw 'Assertion failed: ' + message;
		trace('✓ ' + message);
	}
}
