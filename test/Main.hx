import sys.io.File;
import tests.TokenizerTest;
import tests.ParserTest;
import tests.ExecutorTest;
import tests.FunctionCallTest;
import tests.TokenStorageTest;
import tests.FlowTest;

class Main {
	static function main() {
		trace("==================================================");
		trace("           Nz-Dialogue Test Suite");
		trace("==================================================\n");

		var exampleScript = File.getContent("test/examples/example.dia");
		var functionScript = File.getContent("test/examples/function_test.dia");

		var passedTests = 0;
		var totalTests = 6;

		if (TokenizerTest.run(exampleScript))
			passedTests++;
		if (ParserTest.run(exampleScript))
			passedTests++;
		if (ExecutorTest.run(exampleScript))
			passedTests++;
		if (FunctionCallTest.run(functionScript))
			passedTests++;
		if (TokenStorageTest.run(exampleScript))
			passedTests++;
		if (FlowTest.run(functionScript))
			passedTests++;

		trace("==================================================");
		trace("                  SUMMARY");
		trace("==================================================");
		trace('Tests passed: ${passedTests}/${totalTests}');

		if (passedTests == totalTests) {
			trace("Status: ALL TESTS PASSED");
		} else {
			trace("Status: SOME TESTS FAILED");
		}

		trace("finished~");
	}
}
