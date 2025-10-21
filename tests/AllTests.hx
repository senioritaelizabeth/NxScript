package;

import nz.dialogue.tokenizer.Tokenizer;
import nz.dialogue.parser.Parser;
import nz.dialogue.executor.Executor;

/**
 * Complete Test Suite for Nz-Dialogue
 * All tests in one file, one .dia file
 */
class AllTests {
	static var passed = 0;
	static var failed = 0;

	public static function main() {
		trace("╔════════════════════════════════════════════════════════╗");
		trace("║       Nz-Dialogue Complete Test Suite                 ║");
		trace("╚════════════════════════════════════════════════════════╝\n");

		// Load the single test file
		var code = sys.io.File.getContent("all_tests.dia");

		// Parse
		trace("→ Tokenizing...");
		var tokenizer = new Tokenizer(code);
		var tokens = tokenizer.tokenize();
		trace("  ✓ Generated ${tokens.length} tokens\n");

		trace("→ Parsing...");
		var parser = new Parser(tokens);
		var blocks = parser.parse();
		trace("  ✓ Generated ${blocks.length} blocks\n");

		// Execute
		trace("→ Executing...\n");
		var executor = new Executor(blocks);

		var dialogs:Array<String> = [];
		var variables:Array<{name:String, value:Dynamic}> = [];
		var functions:Array<String> = [];
		var atCalls:Array<String> = [];
		var conditions:Array<{expr:String, result:Bool}> = [];
		var functionCalls:Array<String> = [];

		var steps = 0;
		var maxSteps = 500;

		while (executor.hasNext() && steps < maxSteps) {
			var result = executor.nextExecute();
			steps++;

			switch (result) {
				case ERDialog(text):
					dialogs.push(text);

				case ERVar(name, value):
					variables.push({name: name, value: value});

				case ERFunc(name):
					functions.push(name);

				case ERAtCall(name, args):
					atCalls.push(name);

				case ERIf(condition, result):
					conditions.push({expr: condition, result: result});

				case ERFuncCall(name):
					functionCalls.push(name);

				default:
			}
		}

		trace("╔════════════════════════════════════════════════════════╗");
		trace("║ EXECUTION RESULTS                                      ║");
		trace("╚════════════════════════════════════════════════════════╝\n");

		trace("Execution Steps: " + steps);
		trace("Variables: " + variables.length);
		trace("Functions: " + functions.length);
		trace("Dialogs: " + dialogs.length);
		trace("@Commands: " + atCalls.length);
		trace("If Statements: " + conditions.length);
		trace("Function Calls: " + functionCalls.length);
		trace("");

		// Run tests
		trace("╔════════════════════════════════════════════════════════╗");
		trace("║ RUNNING TESTS                                          ║");
		trace("╚════════════════════════════════════════════════════════╝\n");

		// Test 1: Variables
		testSection("VARIABLES", function() {
			assert(variables.length >= 10, "Should have at least 10 variables");

			// Check specific variables
			var playerName = findVar(variables, "playerName");
			assert(playerName != null, "Should have playerName variable");

			var health = findVar(variables, "health");
			assert(health != null && health == 100, "health should be 100");

			var sum = findVar(variables, "sum");
			assert(sum != null && sum == 15, "sum should be 15 (10+5)");

			var diff = findVar(variables, "diff");
			assert(diff != null && diff == 5, "diff should be 5 (10-5)");

			var mult = findVar(variables, "mult");
			assert(mult != null && mult == 50, "mult should be 50 (10*5)");

			var div = findVar(variables, "div");
			assert(div != null && div == 2, "div should be 2 (10/5)");
		});

		// Test 2: Functions
		testSection("FUNCTIONS", function() {
			assert(functions.length >= 2, "Should have at least 2 functions defined");
			assert(functions.contains("greet"), "Should have 'greet' function");
			assert(functions.contains("sayHello"), "Should have 'sayHello' function");
			assert(functions.contains("showInfo"), "Should have 'showInfo' function");
		});

		// Test 3: Function Calls
		testSection("FUNCTION CALLS", function() {
			assert(functionCalls.length >= 2, "Should have at least 2 function calls");
			assert(functionCalls.contains("sayHello"), "Should call 'sayHello'");
			assert(functionCalls.contains("showInfo"), "Should call 'showInfo'");
		});

		// Test 4: Dialogs
		testSection("DIALOGS", function() {
			assert(dialogs.length >= 20, "Should have at least 20 dialogs");

			// Check for specific dialogs
			assert(dialogs.contains("Hello there, player!"), "Should have greeting dialog");
			assert(dialogs.contains("A is greater than B"), "Should show comparison result");
			assert(dialogs.contains("Both conditions are true (AND)"), "Should handle AND operator");
			assert(dialogs.contains("At least one condition is true (OR)"), "Should handle OR operator");
			assert(dialogs.contains("System is not ready (using !)"), "Should handle ! operator");
			assert(dialogs.contains("System is not ready (using not)"), "Should handle 'not' operator");
			assert(dialogs.contains("All tests completed!"), "Should reach the end");
		});

		// Test 5: @Commands
		testSection("@COMMANDS", function() {
			assert(atCalls.length >= 2, "Should have at least 2 @commands");
			assert(atCalls.contains("playSound"), "Should have playSound command");
			assert(atCalls.contains("show_message"), "Should have show_message command");
		});

		// Test 6: Comparison Operators
		testSection("COMPARISON OPERATORS", function() {
			var greaterFound = false;
			var greaterEqFound = false;
			var lessFound = false;
			var lessEqFound = false;
			var equalFound = false;
			var notEqualFound = false;

			for (c in conditions) {
				if (c.expr.indexOf(">") != -1 && c.expr.indexOf("=") == -1 && c.expr.indexOf("<") == -1)
					greaterFound = true;
				if (c.expr.indexOf(">=") != -1)
					greaterEqFound = true;
				if (c.expr.indexOf("<") != -1 && c.expr.indexOf("=") == -1)
					lessFound = true;
				if (c.expr.indexOf("<=") != -1)
					lessEqFound = true;
				if (c.expr.indexOf("==") != -1)
					equalFound = true;
				if (c.expr.indexOf("!=") != -1)
					notEqualFound = true;
			}

			assert(greaterFound, "Should test > operator");
			assert(greaterEqFound, "Should test >= operator");
			assert(lessFound, "Should test < operator");
			assert(lessEqFound, "Should test <= operator");
			assert(equalFound, "Should test == operator");
			assert(notEqualFound, "Should test != operator");
		});

		// Test 7: Logical Operators
		testSection("LOGICAL OPERATORS", function() {
			var andFound = false;
			var orFound = false;
			var notFound = false;

			for (c in conditions) {
				if (c.expr.indexOf("&&") != -1)
					andFound = true;
				if (c.expr.indexOf("||") != -1)
					orFound = true;
				if (c.expr.indexOf("!") != -1)
					notFound = true;
			}

			assert(andFound, "Should test && operator");
			assert(orFound, "Should test || operator");
			assert(notFound, "Should test ! operator");
		});

		// Test 8: Boolean Variables
		testSection("BOOLEAN VARIABLES", function() {
			var isActive = findVar(variables, "isActive");
			var isReady = findVar(variables, "isReady");

			assert(isActive != null && isActive == true, "isActive should be true");
			assert(isReady != null && isReady == false, "isReady should be false");
		});

		// Test 9: Complex Conditions
		testSection("COMPLEX CONDITIONS", function() {
			var parenthesesFound = false;
			var multipleOpsFound = false;

			for (c in conditions) {
				if (c.expr.indexOf("(") != -1 && c.expr.indexOf(")") != -1)
					parenthesesFound = true;
				if ((c.expr.indexOf("&&") != -1 || c.expr.indexOf("||") != -1)
					&& (c.expr.indexOf(">") != -1 || c.expr.indexOf("<") != -1 || c.expr.indexOf("==") != -1)) {
					multipleOpsFound = true;
				}
			}

			assert(parenthesesFound, "Should handle parentheses in conditions");
			assert(multipleOpsFound, "Should handle multiple operators");
		});

		// Test 10: Control Flow
		testSection("CONTROL FLOW", function() {
			assert(dialogs.contains("A is small or equal to 10"), "Should execute else branch");
			assert(!dialogs.contains("This should not appear (AND false)"), "Should skip false AND");
			assert(!dialogs.contains("This should not appear (OR false)"), "Should skip false OR");
			assert(!dialogs.contains("This should not appear (both false)"), "Should skip false condition");
		});

		// Summary
		trace("\n╔════════════════════════════════════════════════════════╗");
		trace("║ TEST SUMMARY                                           ║");
		trace("╚════════════════════════════════════════════════════════╝\n");

		trace("Passed: " + passed);
		trace("Failed: " + failed);
		trace("Total:  " + (passed + failed));
		trace("");

		if (failed == 0) {
			trace("✓ ALL TESTS PASSED!");
		} else {
			trace("✗ SOME TESTS FAILED");
		}

		trace("\n══════════════════════════════════════════════════════════\n");
	}

	static function testSection(name:String, test:Void->Void) {
		trace("── " + name + " " + repeat("─", 54 - name.length));
		try {
			test();
			trace("");
		} catch (e:Dynamic) {
			trace("  ✗ SECTION FAILED: " + e);
			trace("");
		}
	}

	static function assert(condition:Bool, message:String) {
		if (condition) {
			trace("  ✓ " + message);
			passed++;
		} else {
			trace("  ✗ " + message);
			failed++;
		}
	}

	static function findVar(variables:Array<{name:String, value:Dynamic}>, name:String):Dynamic {
		for (v in variables) {
			if (v.name == name)
				return v.value;
		}
		return null;
	}

	static function repeat(str:String, count:Int):String {
		var result = "";
		for (i in 0...count)
			result += str;
		return result;
	}
}
