package nx.script;

import sys.FileSystem;
import haxe.Json;
import sys.io.Process;
import prismcli.CLI;
using StringTools;
/**
 * NxScript CLI — entry point for 'haxelib run nxscript'
 *
 * Usage:
 *   haxelib run nxscript run <file.nx>     — execute a script file
 *   haxelib run nxscript run <file.nx> -w  — watch mode (re-run on change)
 *   haxelib run nxscript repl              — interactive REPL
 *   haxelib run nxscript help              — show help
 *
 * Compile flags:
 *   -D NXDEBUG   — enable instruction tracing, AST/token/bytecode dumps
 */
class Main {
	static function lib_dir() {
		
		// run haxelib path nxscript to get the library directory, then add "src" to get to the sources
		var haxelibPath = '';
		try {
			var process = new Process("haxelib", ["path", "nxscript"]);
			haxelibPath = process.stdout.readAll().toString();
			process.close();
			if (haxelibPath == null || haxelibPath == "") {
				err("haxelib did not return a path for nxscript");
				Sys.exit(1);
			}
			haxelibPath = StringTools.trim(haxelibPath).split("\n")[0].trim(	);

			var isUsingBar = haxelibPath.contains("/");
			if (haxelibPath.endsWith("/") || haxelibPath.endsWith("\\")) 
				haxelibPath = haxelibPath.substring(0, haxelibPath.length- 1);
			if (haxelibPath.endsWith("/src") || haxelibPath.endsWith("\\src")) 
				haxelibPath = haxelibPath.substring(0, haxelibPath.length - 4);
			haxelibPath += isUsingBar ? "/" : "\\";
		} catch (e:Dynamic) {
			err("Failed to get haxelib path: " + Std.string(e));
			Sys.exit(1);
		}
		return StringTools.trim(haxelibPath).split("\n")[0];
	}
	static function args() {
		var args = Sys.args();
		var file = FileSystem.readDirectory("./");
		
		return args;
	}
	static function main() {
		
		
		var haxelib_json: HaxelibJson = Json.parse(sys.io.File.getContent(lib_dir() + "haxelib.json"));
		var args = args();

		var cwd = args.length > 0 ? args[args.length - 1] : null;
		if (cwd != null && sys.FileSystem.exists(cwd) && sys.FileSystem.isDirectory(cwd)) {
			args = args.slice(0, args.length - 1);
			Sys.setCwd(cwd);
		}
		
		if (args.length == 0) {
			startRepl();
		} else if (sys.FileSystem.exists(args[0]) && !sys.FileSystem.isDirectory(args[0]) && (args[0].endsWith(".nx") )) {
			runFile(args[0], false);
		} else {
			var cli = new CLI("NxScript", "NxScript CLI", haxelib_json.version);
			cli.addDefaults();
			var test = cli.addCommand("test", "Run tests all tests.", (cli, args, flags) -> {
				var path = lib_dir() + "test/tests/test_suite.hxml";
				Sys.setCwd(lib_dir() + "test/tests/");
				Sys.command("haxe " + path);
			});

			var runCmd = cli.addCommand("run", "Run a script file", (cli, args, flags) -> {
				var file = args["file"];
				var watch = flags.exists("w") || flags.exists("watch");
				runFile(file, watch);
			});
			runCmd.addArgument("file", "The script file to run", String);
			runCmd.addFlag("w", "Watch mode", ["-w", "--watch"]);

			cli.addCommand("repl", "Start interactive REPL", (cli, args, flags) -> {
				startRepl();
			});
			var h = cli.addCommand('help', 'Show this help message', (cli, args, flags) -> {
				printHelp();
			});
			cli.setDefaultCommand(h);
			cli.run();
		}
	}


	static function runFile(path:String, watch:Bool) {
		if (!sys.FileSystem.exists(path)) {
			err('File not found: $path');
			Sys.exit(1);
		}

		if (watch) {
			runWatch(path);
		} else {
			var code = sys.io.File.getContent(path);
			var interp = makeInterpreter(path);
			try {
				interp.runDynamic(code, path);
			} catch (e:Dynamic) {
				Sys.exit(1);
			}
		}
	}

	static function runWatch(path:String) {
		Sys.println('[NxScript] Watching $path  (Ctrl+C to stop)');
		var lastMod = sys.FileSystem.stat(path).mtime.getTime();

		// Run once immediately
		executeFile(path);

		while (true) {
			Sys.sleep(0.4);
			var mod = sys.FileSystem.stat(path).mtime.getTime();
			if (mod != lastMod) {
				lastMod = mod;
				Sys.println('\n[NxScript] Change detected — re-running $path\n');
				executeFile(path);
			}
		}
	}

	static function executeFile(path:String) {
		var code   = sys.io.File.getContent(path);
		var interp = makeInterpreter(path);
		try {
			interp.runDynamic(code, path);
		} catch (_:Dynamic) {}
	}


	static function startRepl() {
		Sys.println("NxScript REPL  (type 'exit' or Ctrl+C to quit, 'help' for commands)");
		Sys.println("─────────────────────────────────────────────────────────────────");

		var interp = makeInterpreter("<repl>");
		var lineNum = 1;
		var buf = new StringBuf();  // accumulates multi-line input

		while (true) {
			var prompt = buf.toString().length == 0 ? 'nx:$lineNum> ' : '     ... > ';
			Sys.print(prompt);

			var line:String;
			try {
				line = Sys.stdin().readLine();
			} catch (_:Dynamic) {
				// EOF (Ctrl+D)
				Sys.println("\nBye!");
				break;
			}

			// REPL commands
			switch (StringTools.trim(line)) {
				case "exit" | "quit" | ":q":
					Sys.println("Bye!");
					break;

				case "help" | ":h" | ":help":
					replHelp();
					continue;

				case "clear" | ":clear":
					buf = new StringBuf();
					Sys.println("(buffer cleared)");
					continue;

				case ":reset":
					interp = makeInterpreter("<repl>");
					buf = new StringBuf();
					Sys.println("(interpreter reset)");
					continue;

				case ":globals":
					var g = interp.vm.globals;
					if (Lambda.count(g) == 0) {
						Sys.println("(no globals)");
					} else {
						for (k in g.keys())
							Sys.println('  $k = ${interp.vm.valueToString(g.get(k))}');
					}
					continue;

				default:
			}

			buf.add(line);
			buf.add("\n");
			lineNum++;

			// Try to evaluate — if it looks incomplete (open braces), keep buffering
			var src = buf.toString();
			if (isIncomplete(src)) {
				continue;
			}

			buf = new StringBuf();

			if (StringTools.trim(src) == "")
				continue;

			try {
				var result = interp.runDynamic(src, "<repl>");
				// Print non-null results
				if (result != null) {
					var str = interp.vm.valueToString(interp.vm.haxeToValue(result));
					if (str != "null")
						Sys.println('=> $str');
				}
			} catch (e:Dynamic) {
				// Error already printed by interpreter — just keep going
			}
		}
	}

	/**
	 * Rough heuristic: if there are more open braces/parens than closed,
	 * the input is probably incomplete and we should keep buffering.
	 */
	static function isIncomplete(src:String):Bool {
		var braces = 0;
		var parens = 0;
		var inStr  = false;
		var strCh  = '"';

		var i = 0;
		while (i < src.length) {
			var c = src.charAt(i);
			if (inStr) {
				if (c == "\\") { i += 2; continue; }
				if (c == strCh) inStr = false;
			} else {
				if (c == '"' || c == "'") { inStr = true; strCh = c; }
				else if (c == '{') braces++;
				else if (c == '}') braces--;
				else if (c == '(') parens++;
				else if (c == ')') parens--;
			}
			i++;
		}
		return braces > 0 || parens > 0;
	}

	static function makeInterpreter(name:String):Interpreter {
		var interp = new Interpreter();
		// Register print that goes to stdout cleanly (no file:line prefix)
		interp.vm.natives.set("print", nx.script.Bytecode.Value.VNativeFunction("print", -1, (args) -> {
			Sys.println([for (a in args) interp.vm.valueToString(a)].join(" "));
			return nx.script.Bytecode.Value.VNull;
		}));
		interp.vm.natives.set("println", interp.vm.natives.get("print"));
		return interp;
	}

	static inline function err(msg:String)
		Sys.stderr().writeString('Error: $msg\n');

	static function printHelp() {
		Sys.println("
NxScript CLI

  haxelib run nxscript run <file.nx>       Run a script file
  haxelib run nxscript run <file.nx> -w    Watch mode — re-run on file change
  haxelib run nxscript repl                Interactive REPL
  haxelib run nxscript help                Show this help

  haxelib run nxscript <file.nx>           Shorthand for 'run'

Compile flags:
  -D NXDEBUG    Enable debug output (tokens, AST, bytecode, instruction trace)
");
	}

	static function replHelp() {
		Sys.println("
REPL commands:
  exit / quit / :q    Quit
  clear / :clear      Clear input buffer
  :reset              Reset interpreter (clears all globals)
  :globals            Show all global variables
  help / :help        Show this message

Multi-line input:
  Open a { or ( and press Enter — the REPL buffers until balanced.
");
	}
}
typedef  HaxelibJson = {
	name: String,
	version: String,
	url: String,
	license: String,
	tags: Array<String>,
	description: String,
	releasenote: String,
	contributors: Array<String>,
	dependencies: Map<String, String>,
	main: String
};