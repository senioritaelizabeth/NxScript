package tests;

import nz.tokenizer.Tokenizer;
import nz.parser.Parser;

class ParserTest {
	public static function run(script:String):Bool {
		trace("\n=== PARSER TEST ===");

		var tokenizer = new Tokenizer(script);
		var tokens = tokenizer.tokenize();
		var parser = new Parser(tokens);
		var blocks = parser.parse();

		trace('Total blocks: ${blocks.length}');

		if (blocks.length == 0) {
			trace("ERROR: No blocks generated");
			return false;
		}

		trace("Parser test passed");
		return true;
	}
}
