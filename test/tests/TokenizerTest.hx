package tests;

import nz.tokenizer.Tokenizer;

class TokenizerTest {
	public static function run(script:String):Bool {
		trace("=== TOKENIZER TEST ===");

		var tokenizer = new Tokenizer(script);
		var tokens = tokenizer.tokenize();

		trace('Total tokens: ${tokens.length}');

		if (tokens.length == 0) {
			trace("ERROR: No tokens generated");
			return false;
		}

		trace("Tokenizer test passed");
		return true;
	}
}
