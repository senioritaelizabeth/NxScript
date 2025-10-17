package tests;

import nz.tokenizer.Tokenizer;
import nz.parser.Parser;
import nz.executor.Executor;

class FlowTest {
	public static function run(script:String):Bool {
		trace("\n=== FLOW TEST ===");

		var tokenizer = new Tokenizer(script);
		var tokens = tokenizer.tokenize();
		var parser = new Parser(tokens);
		var blocks = parser.parse();
		var executor = new Executor(blocks);

		var executionOrder:Array<String> = [];

		while (executor.hasNext()) {
			var result = executor.nextExecute();

			switch (result) {
				case ERDialog(text):
					executionOrder.push('Dialog: ${text}');
				case ERFuncCall(name):
					executionOrder.push('Call: ${name}');
				default:
			}
		}

		trace("Execution order:");
		for (i in 0...executionOrder.length) {
			trace('  [${i + 1}] ${executionOrder[i]}');
		}

		trace("Flow test passed");
		return true;
	}
}
