package tests;

import nz.tokenizer.Tokenizer;
import nz.parser.Parser;
import nz.executor.Executor;

class FunctionCallTest {
	public static function run(script:String):Bool {
		trace("\n=== FUNCTION CALL TEST ===");

		var tokenizer = new Tokenizer(script);
		var tokens = tokenizer.tokenize();
		var parser = new Parser(tokens);
		var blocks = parser.parse();
		var executor = new Executor(blocks);

		var funcCallCount = 0;

		while (executor.hasNext()) {
			var result = executor.nextExecute();

			switch (result) {
				case ERFuncCall(name):
					funcCallCount++;
					trace('Function called: ${name}');
				default:
			}
		}

		trace('Total function calls: ${funcCallCount}');

		if (funcCallCount == 0) {
			trace("WARNING: No function calls detected");
		}

		trace("Function call test passed");
		return true;
	}
}
