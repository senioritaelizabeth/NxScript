import nz.script.Interpreter;

class TestExpr {
	static function main() {
		var interp = new Interpreter();

		trace("Testing expression: n = 16*(10*7*8/(8-9*(16+23)))");

		var result:Float = interp.runDynamic('
			var n = 16*(10*7*8/(8-9*(16+23)))
			n
		');

		trace('Result: $result');
		trace('Type: ${Type.typeof(result)}');

		// Verificar en Haxe puro
		var expected = 16 * (10 * 7 * 8 / (8 - 9 * (16 + 23)));
		trace('Expected (Haxe): $expected');

		if (result == expected) {
			trace('✓ Match!');
		} else {
			trace('✗ Mismatch! Got $result but expected $expected');
		}
	}
}
