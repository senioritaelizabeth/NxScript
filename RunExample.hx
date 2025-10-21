package;

import sys.io.File;
import nz.script.Interpreter;

class RunExample {
	static function main() {
		trace("===========================================");
		trace("  Nz-Script - Bytecode System");
		trace("  Running: example.nzs");
		trace("===========================================");

		try {
			// Read the file
			var filename = "example.nzs";
			var script = File.getContent(filename);

			// Create interpreter without debug mode
			var interp = new Interpreter(false);

			// Execute the script with the filename
			var result = interp.run(script, filename);

			trace("===========================================");
			if (result != null) {
				trace("Final returned value: " + interp.vm.valueToString(result));
			} else {
				trace("Script executed successfully (no return value)");
			}
			trace("===========================================");
		} catch (e:Dynamic) {
			trace("===========================================");
			trace("ERROR: " + e);
			trace("===========================================");
		}
	}
}
