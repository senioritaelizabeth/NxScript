package tests;

import nz.tokenizer.Tokenizer;
import nz.parser.Parser;
import nz.executor.Executor;

class ExecutorTest {
	public static function run(script:String):Bool {
		trace("\n=== EXECUTOR TEST ===");

		var tokenizer = new Tokenizer(script);
		var tokens = tokenizer.tokenize();
		var parser = new Parser(tokens);
		var blocks = parser.parse();
		var executor = new Executor(blocks);

		var stepCount = 0;
		var dialogCount = 0;
		var funcCount = 0;

		while (executor.hasNext()) {
			stepCount++;
			var result = executor.nextExecute();

			switch (result) {
				case ERDialog(_):
					dialogCount++;
				case ERFunc(_):
					funcCount++;
				default:
			}
		}

		trace('Executed ${stepCount} steps');
		trace('Found ${dialogCount} dialogs');
		trace('Found ${funcCount} functions');

		if (stepCount == 0) {
			trace("ERROR: No steps executed");
			return false;
		}

		trace("Executor test passed");
		return true;
	}
}
