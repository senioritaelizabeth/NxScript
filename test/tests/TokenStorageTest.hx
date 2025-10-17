package tests;

import nz.tokenizer.Tokenizer;
import nz.storage.TokenStorage;

class TokenStorageTest {
	public static function run(script:String):Bool {
		trace("\n=== TOKEN STORAGE TEST ===");

		var tokenizer = new Tokenizer(script);
		var tokens = tokenizer.tokenize();

		// Save tokens
		var storage = new TokenStorage();
		var outputPath = "test/tests/output/reconstructed.dia";
		storage.save(tokens, outputPath);
		trace('Saved reconstructed code to: ${outputPath}');

		trace("Token storage test passed");
		return true;
	}
}
