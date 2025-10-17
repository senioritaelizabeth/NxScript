import sys.io.File;
import nz.DiaTokenizer;

class Main {
	static function main() {
		var script = File.getContent("test/example.dia");

		var tokenizer = new DiaTokenizer(script);
		var tokens = tokenizer.tokenize();

		trace("=== TOKENS ===");
		for (t in tokens) {
			trace('Line ${t.line}, Col ${t.col}: ${t.token}');
		}
	}
}
