package;

import haxe.io.Bytes;
import sys.io.File;
import nz.dialogue.tokenizer.Tokenizer;
import nz.dialogue.parser.Parser;
import nz.dialogue.executor.Executor;

using StringTools;

/**
 * Interactive Test Menu System for Nz-Dialogue
 * Navigate with W/S keys, select with Enter
 */
class TestMain {
	static var currentMenu:MenuType = MainMenu;
	static var selectedIndex:Int = 0;

	public static function main() {
		clearScreen();
		showMenu();

		while (true) {
			Sys.print("> ");
			var input = Sys.stdin().readLine().trim().toLowerCase();

			if (input == "q" || input == "exit" || input == "esc") {
				if (currentMenu == MainMenu) {
					clearScreen();
					trace("\n\nGoodbye! 👋\n");
					Sys.exit(0);
				} else {
					// Go back to main menu
					currentMenu = MainMenu;
					selectedIndex = 0;
					clearScreen();
					showMenu();
				}
			} else if (input == "w" || input == "up") {
				selectedIndex--;
				if (selectedIndex < 0)
					selectedIndex = getMenuLength() - 1;
				clearScreen();
				showMenu();
			} else if (input == "s" || input == "down") {
				selectedIndex++;
				if (selectedIndex >= getMenuLength())
					selectedIndex = 0;
				clearScreen();
				showMenu();
			} else if (input == "" || input == "enter") {
				handleSelection();
			} else {
				// Try to parse as number
				var num = Std.parseInt(input);
				if (num != null && num >= 0 && num < getMenuLength()) {
					selectedIndex = num;
					handleSelection();
				} else {
					trace('Invalid input. Use W/S to navigate, Enter to select, or type a number (0-${getMenuLength() - 1})');
				}
			}
		}
	}

	static function clearScreen() {
		#if windows
		Sys.command("cls");
		#else
		Sys.command("clear");
		#end
	}

	static function getMenuLength():Int {
		return switch (currentMenu) {
			case MainMenu: 4;
			case DialogueTests: 11; // 0. All + 10 individual tests
			case CinematicTests: 1;
			case ScriptingTests: 1;
		}
	}

	static function showMenu() {
		trace("╔══════════════════════════════════════════════════════════╗");
		trace("║           Nz-Dialogue Interactive Test Suite            ║");
		trace("╚══════════════════════════════════════════════════════════╝\n");

		switch (currentMenu) {
			case MainMenu:
				trace("What test do you want to do?\n");
				printMenuItem(0, "Test Dialogues");
				printMenuItem(1, "Test Cinematic (Requires Flixel installed)", true);
				printMenuItem(2, "Test Scripting Bytecode", true);
				printMenuItem(3, "Exit");

			case DialogueTests:
				trace("Test Dialogues\n");
				printMenuItem(0, "All Tests");
				printMenuItem(1, "Variables");
				printMenuItem(2, "Functions");
				printMenuItem(3, "Function Calls");
				printMenuItem(4, "Dialogs");
				printMenuItem(5, "@Commands");
				printMenuItem(6, "Comparison Operators");
				printMenuItem(7, "Logical Operators");
				printMenuItem(8, "Boolean Variables");
				printMenuItem(9, "Complex Conditions");
				printMenuItem(10, "Control Flow");

			case CinematicTests:
				trace("Test Cinematic\n");
				printMenuItem(0, "Coming soon...", true);

			case ScriptingTests:
				trace("Test Scripting Bytecode\n");
				printMenuItem(0, "Coming soon...", true);
		}

		trace("\n╔══════════════════════════════════════════════════════════╗");
		trace("║  W/S=navigate | Enter=select | 0-9=direct | Q/ESC=back  ║");
		trace("╚══════════════════════════════════════════════════════════╝");
	}

	static function printMenuItem(index:Int, label:String, disabled:Bool = false) {
		var isSelected = (index == selectedIndex);
		var prefix = isSelected ? "  > " : "    ";
		var suffix = ' [$index]';
		var color = disabled ? "\x1b[90m" : (isSelected ? "\x1b[97;1m" : "\x1b[37m");
		var reset = "\x1b[0m";
		trace('$prefix$color$label$suffix$reset');
	}

	static function handleSelection() {
		switch (currentMenu) {
			case MainMenu:
				if (selectedIndex == 0) {
					currentMenu = DialogueTests;
					selectedIndex = 0;
					clearScreen();
					showMenu();
				} else if (selectedIndex == 1) {
					// Cinematic tests (disabled) - do nothing
					clearScreen();
					showMenu();
				} else if (selectedIndex == 2) {
					// Scripting tests (disabled) - do nothing
					clearScreen();
					showMenu();
				} else if (selectedIndex == 3) {
					clearScreen();
					trace("\n\nGoodbye! 👋\n");
					Sys.exit(0);
				}

			case DialogueTests:
				clearScreen();
				if (selectedIndex == 0) {
					runAllDialogueTests();
				} else {
					runSpecificDialogueTest(selectedIndex);
				}
				trace("\n\n════════════════════════════════════════════════════════");
				trace("Press Enter to return to menu...");
				Sys.stdin().readLine();
				currentMenu = MainMenu;
				selectedIndex = 0;
				clearScreen();
				showMenu();

			case CinematicTests:
				trace("\nCinematic tests not yet implemented.\n");

			case ScriptingTests:
				trace("\nScripting tests not yet implemented.\n");
		}
	}

	static function runAllDialogueTests() {
		trace("╔════════════════════════════════════════════════════════╗");
		trace("║       Running All Dialogue Tests                      ║");
		trace("╚════════════════════════════════════════════════════════╝\n");

		var passed = 0;
		var failed = 0;

		// Load the test file
		var code = File.getContent("test/all_tests.dia");

		// Parse
		trace("→ Tokenizing...");
		var tokenizer = new Tokenizer(code);
		var tokens = tokenizer.tokenize();
		trace('  ✓ Generated ${tokens.length} tokens\n');

		trace("→ Parsing...");
		var parser = new Parser(tokens);
		var blocks = parser.parse();
		trace('  ✓ Generated ${blocks.length} blocks\n');

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
				case ERIf(condition, taken):
					conditions.push({expr: condition, result: taken});
				case ERFuncCall(name):
					functionCalls.push(name);
				default:
			}
		}

		// Define helper functions first
		function assert(condition:Bool, message:String) {
			if (condition) {
				passed++;
			} else {
				failed++;
				trace('  ✗ FAILED: $message');
			}
		}

		function testSection(name:String, test:Void->Void) {
			trace('\n[$name]');
			test();
		}

		function getVarValue(vars:Array<{name:String, value:Dynamic}>, name:String):Dynamic {
			for (v in vars) {
				if (v.name == name)
					return v.value;
			}
			return null;
		}

		// Debug: show what we collected
		trace('\nDEBUG: Collected ${conditions.length} conditions');
		for (c in conditions) {
			trace('  - "${c.expr}" = ${c.result}');
		}

		// Run all test sections
		testSection("VARIABLES", function() {
			assert(variables.length >= 14, 'Expected at least 14 variables, got ${variables.length}');
			var x = getVarValue(variables, "x");
			assert(x == 10, 'x should be 10, got $x');
			var sum = getVarValue(variables, "sum");
			assert(sum == 15, 'sum should be 15, got $sum');
		});

		testSection("FUNCTIONS", function() {
			assert(functions.length >= 4, 'Expected at least 4 functions, got ${functions.length}');
			trace('  Functions found: ${functions.join(", ")}');
			assert(functions.indexOf("greet") >= 0, "Should have greet function");
			assert(functions.indexOf("farewell") >= 0, "Should have farewell function");
		});
		testSection("FUNCTION CALLS", function() {
			assert(functionCalls.length >= 2, 'Expected at least 2 function calls, got ${functionCalls.length}');
		});

		testSection("DIALOGS", function() {
			assert(dialogs.length >= 10, 'Expected at least 10 dialogs, got ${dialogs.length}');
		});

		testSection("@COMMANDS", function() {
			assert(atCalls.length >= 2, 'Expected at least 2 @commands, got ${atCalls.length}');
		});

		testSection("COMPARISON OPERATORS", function() {
			var greaterResults = conditions.filter(c -> c.expr.indexOf("a > b") >= 0);
			assert(greaterResults.length > 0, "Should have 'a > b' condition");
			if (greaterResults.length > 0) {
				assert(greaterResults[0].result == true, "a > b should be true");
			}
		});

		testSection("LOGICAL OPERATORS", function() {
			var andSymbol = conditions.filter(c -> c.expr.indexOf("x > 5 && y < 20") >= 0);
			assert(andSymbol.length > 0, "Should have 'x > 5 && y < 20' condition");

			var andWord = conditions.filter(c -> c.expr.indexOf("x > 5 and y < 20") >= 0);
			assert(andWord.length > 0, "Should have 'x > 5 and y < 20' condition");
		});

		testSection("BOOLEAN VARIABLES", function() {
			var isActive = getVarValue(variables, "isActive");
			assert(isActive == true, 'isActive should be true, got $isActive');

			var isReady = getVarValue(variables, "isReady");
			assert(isReady == false, 'isReady should be false, got $isReady');
		});

		testSection("COMPLEX CONDITIONS", function() {
			var complex = conditions.filter(c -> c.expr.indexOf("(") >= 0);
			assert(complex.length > 0, "Should have conditions with parentheses");
		});

		testSection("CONTROL FLOW", function() {
			assert(conditions.length >= 15, 'Expected at least 15 conditions, got ${conditions.length}');
		});

		// Summary
		trace("\n════════════════════════════════════════════════════════");
		trace('Passed: $passed');
		trace('Failed: $failed');
		trace('Total: ${passed + failed}');
		trace("════════════════════════════════════════════════════════");

		if (failed == 0) {
			trace("\n✓ ALL TESTS PASSED!");
		} else {
			trace('\n✗ $failed TEST(S) FAILED!');
		}
	}

	static function runSpecificDialogueTest(testIndex:Int) {
		var testNames = [
			"All Tests",
			"Variables",
			"Functions",
			"Function Calls",
			"Dialogs",
			"@Commands",
			"Comparison Operators",
			"Logical Operators",
			"Boolean Variables",
			"Complex Conditions",
			"Control Flow"
		];

		var testName = testNames[testIndex];

		trace("╔════════════════════════════════════════════════════════╗");
		trace('║       Running Test: $testName');
		trace("╚════════════════════════════════════════════════════════╝\n");

		var passed = 0;
		var failed = 0;

		// Load the test file
		var code = File.getContent("test/all_tests.dia");

		// Parse
		trace("→ Tokenizing...");
		var tokenizer = new Tokenizer(code);
		var tokens = tokenizer.tokenize();
		trace('  ✓ Generated ${tokens.length} tokens\n');

		trace("→ Parsing...");
		var parser = new Parser(tokens);
		var blocks = parser.parse();
		trace('  ✓ Generated ${blocks.length} blocks\n');

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
				case ERIf(condition, taken):
					conditions.push({expr: condition, result: taken});
				case ERFuncCall(name):
					functionCalls.push(name);
				default:
			}
		}

		// Define helper functions first
		function assert(condition:Bool, message:String) {
			if (condition) {
				passed++;
			} else {
				failed++;
				trace('  ✗ FAILED: $message');
			}
		}

		function testSection(name:String, test:Void->Void) {
			trace('\n[$name]');
			test();
		}

		function getVarValue(vars:Array<{name:String, value:Dynamic}>, name:String):Dynamic {
			for (v in vars) {
				if (v.name == name)
					return v.value;
			}
			return null;
		}

		// Run specific test
		switch (testIndex) {
			case 1: // Variables
				testSection("VARIABLES", function() {
					assert(variables.length >= 14, 'Expected at least 14 variables, got ${variables.length}');
					var x = getVarValue(variables, "x");
					assert(x == 10, 'x should be 10, got $x');
					var y = getVarValue(variables, "y");
					assert(y == 5, 'y should be 5, got $y');
					var a = getVarValue(variables, "a");
					assert(a == 10, 'a should be 10, got $a');
					var b = getVarValue(variables, "b");
					assert(b == 5, 'b should be 5, got $b');
					var sum = getVarValue(variables, "sum");
					assert(sum == 15, 'sum should be 15, got $sum');
					var diff = getVarValue(variables, "diff");
					assert(diff == 5, 'diff should be 5, got $diff');
					var mult = getVarValue(variables, "mult");
					assert(mult == 50, 'mult should be 50, got $mult');
					var div = getVarValue(variables, "div");
					assert(div == 2, 'div should be 2, got $div');
				});

			case 2: // Functions
				testSection("FUNCTIONS", function() {
					assert(functions.length >= 4, 'Expected at least 4 functions, got ${functions.length}');
					assert(functions.indexOf("greet") >= 0, "Should have greet function");
					assert(functions.indexOf("farewell") >= 0, "Should have farewell function");
					assert(functions.indexOf("nested") >= 0, "Should have nested function");
					assert(functions.indexOf("inner") >= 0, "Should have inner function");
				});

			case 3: // Function Calls
				testSection("FUNCTION CALLS", function() {
					assert(functionCalls.length >= 2, 'Expected at least 2 function calls, got ${functionCalls.length}');
					assert(functionCalls.indexOf("greet") >= 0, "Should call greet function");
					assert(functionCalls.indexOf("farewell") >= 0, "Should call farewell function");
				});

			case 4: // Dialogs
				testSection("DIALOGS", function() {
					assert(dialogs.length >= 10, 'Expected at least 10 dialogs, got ${dialogs.length}');
					trace('  Found ${dialogs.length} dialog lines');
				});

			case 5: // @Commands
				testSection("@COMMANDS", function() {
					assert(atCalls.length >= 2, 'Expected at least 2 @commands, got ${atCalls.length}');
					assert(atCalls.indexOf("sayHello") >= 0, "Should have @sayHello command");
					assert(atCalls.indexOf("wait") >= 0, "Should have @wait command");
				});

			case 6: // Comparison Operators
				testSection("COMPARISON OPERATORS", function() {
					var greaterResults = conditions.filter(c -> c.expr.indexOf("a > b") >= 0);
					assert(greaterResults.length > 0, "Should have 'a > b' condition");
					assert(greaterResults[0].result == true, "a > b should be true (10 > 5)");

					var lessResults = conditions.filter(c -> c.expr.indexOf("a < b") >= 0);
					assert(lessResults.length > 0, "Should have 'a < b' condition");
					assert(lessResults[0].result == false, "a < b should be false");

					var equalResults = conditions.filter(c -> c.expr.indexOf("sum == 15") >= 0);
					assert(equalResults.length > 0, "Should have 'sum == 15' condition");
					assert(equalResults[0].result == true, "sum == 15 should be true");
				});

			case 7: // Logical Operators
				testSection("LOGICAL OPERATORS", function() {
					var andSymbol = conditions.filter(c -> c.expr.indexOf("x > 5 && y < 20") >= 0);
					assert(andSymbol.length > 0, "Should have 'x > 5 && y < 20' condition");

					var andWord = conditions.filter(c -> c.expr.indexOf("x > 5 and y < 20") >= 0);
					assert(andWord.length > 0, "Should have 'x > 5 and y < 20' condition");

					var orSymbol = conditions.filter(c -> c.expr.indexOf("a == 0 || b == 0") >= 0);
					assert(orSymbol.length > 0, "Should have 'a == 0 || b == 0' condition");

					var orWord = conditions.filter(c -> c.expr.indexOf("a == 0 or b == 0") >= 0);
					assert(orWord.length > 0, "Should have 'a == 0 or b == 0' condition");

					var notSymbol = conditions.filter(c -> c.expr.indexOf("!(a == 0)") >= 0);
					assert(notSymbol.length > 0, "Should have '!(a == 0)' condition");

					var notWord = conditions.filter(c -> c.expr.indexOf("not a == 0") >= 0);
					assert(notWord.length > 0, "Should have 'not a == 0' condition");
				});

			case 8: // Boolean Variables
				testSection("BOOLEAN VARIABLES", function() {
					var isActive = getVarValue(variables, "isActive");
					assert(isActive == true, 'isActive should be true, got $isActive');

					var isReady = getVarValue(variables, "isReady");
					assert(isReady == false, 'isReady should be false, got $isReady');

					var boolCond = conditions.filter(c -> c.expr.indexOf("isActive") >= 0);
					assert(boolCond.length > 0, "Should have condition with isActive");
				});

			case 9: // Complex Conditions
				testSection("COMPLEX CONDITIONS", function() {
					var complex = conditions.filter(c -> c.expr.indexOf("(") >= 0);
					assert(complex.length > 0, "Should have conditions with parentheses");
					trace('  Found ${complex.length} complex conditions');
				});

			case 10: // Control Flow
				testSection("CONTROL FLOW", function() {
					assert(conditions.length >= 15, 'Expected at least 15 conditions, got ${conditions.length}');
					trace('  Total conditions evaluated: ${conditions.length}');
				});
		}

		// Summary
		trace("\n════════════════════════════════════════════════════════");
		trace('Passed: $passed');
		trace('Failed: $failed');
		trace('Total: ${passed + failed}');
		trace("════════════════════════════════════════════════════════");

		if (failed == 0) {
			trace("\n✓ ALL TESTS PASSED!");
		} else {
			trace('\n✗ $failed TEST(S) FAILED!');
		}
	}
}

enum MenuType {
	MainMenu;
	DialogueTests;
	CinematicTests;
	ScriptingTests;
}
