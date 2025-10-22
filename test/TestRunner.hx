package;

import sys.io.File;
import sys.FileSystem;

using StringTools;

/**
 * Simple Test Runner
 * Executes all test .hxml files and saves results to test_results/
 */
class TestRunner {
	static function main() {
		trace("╔════════════════════════════════════════════════════════╗");
		trace("║       Nz-Dialogue Test Runner                         ║");
		trace("╚════════════════════════════════════════════════════════╝\n");

		// Create results directory
		if (!FileSystem.exists("test_results")) {
			FileSystem.createDirectory("test_results");
		}

		// Find all .hxml files in tests directory
		var testFiles = [];
		if (!FileSystem.exists("tests")) {
			trace("Error: tests/ directory not found!");
			trace("Create tests/ directory with .hxml files");
			Sys.exit(1);
		}

		for (file in FileSystem.readDirectory("tests")) {
			if (file.endsWith(".hxml")) {
				testFiles.push(file);
			}
		}

		if (testFiles.length == 0) {
			trace("No test .hxml files found in tests/ directory");
			trace("Create test files like: tests/mytest.hxml");
			return;
		}

		trace('Found ${testFiles.length} test file(s):\n');
		for (file in testFiles) {
			trace('  - $file');
		}
		trace("");

		var passed = 0;
		var failed = 0;
		var current_cwd = Sys.getCwd();

		// Run each test
		for (testFile in testFiles) {
			var testName = testFile.substring(0, testFile.length - 5); // Remove .hxml
			trace('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
			trace('Running: $testName');
			trace('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
			Sys.setCwd(current_cwd + "/tests");

			// Run haxe from the tests directory
			var exitCode = Sys.command('haxe $testFile > ../test_results/${testName}_output.txt 2>&1');

			if (exitCode == 0) {
				trace('✓ $testName PASSED\n');
				passed++;
			} else {
				trace('✗ $testName FAILED (exit code: $exitCode)\n');
				failed++;
			}
			Sys.setCwd(current_cwd);

			// Save result summary
			var resultFile = 'test_results/${testName}_result.txt';
			var status = (exitCode == 0) ? "PASSED" : "FAILED";
			File.saveContent(resultFile, '$status (exit code: $exitCode)');
		} // Summary
		trace('═══════════════════════════════════════════════════════════');
		trace('TEST SUMMARY');
		trace('═══════════════════════════════════════════════════════════');
		trace('Passed: $passed');
		trace('Failed: $failed');
		trace('Total:  ${passed + failed}');
		trace('═══════════════════════════════════════════════════════════\n');

		if (failed == 0) {
			trace('✓ ALL TESTS PASSED!');
		} else {
			trace('✗ SOME TESTS FAILED!');
			trace('\nCheck test_results/ directory for detailed output.');
		}

		Sys.exit(failed > 0 ? 1 : 0);
	}
}
