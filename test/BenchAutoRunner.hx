import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

private typedef TargetSpec = {
	var name:String;
	var compileCmd:Null<Array<String>>;
	var runCmd:Array<String>;
	var requiredCommands:Array<String>;
	var slow:Bool;
	var csvName:String;
}

private typedef CmdResult = {
	var ok:Bool;
	var exitCode:Int;
	var stdout:String;
	var stderr:String;
}

private typedef TargetResult = {
	var target:String;
	var status:String;
	var reason:String;
	var logPath:String;
	var csvPath:String;
}

class BenchAutoRunner {
	static inline var TRACE_PREFIX = "[BenchAutoRunner]";

	static function main() {
		var args = Sys.args();
		var skipSlow = hasFlag(args, "--skip-slow");
		var quick = hasFlag(args, "--quick");
		var onlyTargets = parseOnlyTargets(args);
		traceLog('Starting with args: ' + args.join(" "));
		traceLog('Flags -> skipSlow=' + skipSlow + ', quick=' + quick + ', only=' + onlyTargets.join(","));

		var testDir = Sys.getCwd();
		var resultsRoot = Path.join([testDir, "test_results"]);
		traceLog('Working directory: ' + testDir);
		traceLog('Results root: ' + resultsRoot);
		ensureDir(resultsRoot);

		var runDir = Path.join([resultsRoot, 'auto_run_${timestamp()}']);
		var logsDir = Path.join([runDir, "logs"]);
		var csvDir = Path.join([runDir, "csv"]);
		traceLog('Run dir: ' + runDir);
		traceLog('Logs dir: ' + logsDir);
		traceLog('CSV dir: ' + csvDir);
		ensureDir(runDir);
		ensureDir(logsDir);
		ensureDir(csvDir);

		var targets = buildTargets(quick);
		traceLog('Initial targets: ' + [for (t in targets) t.name].join(","));
		if (onlyTargets.length > 0) {
			targets = [for (t in targets) if (onlyTargets.indexOf(t.name) >= 0) t];
			traceLog('Targets after --only filter: ' + [for (t in targets) t.name].join(","));
		}
		if (skipSlow) {
			targets = [for (t in targets) if (!t.slow) t];
			traceLog('Targets after --skip-slow filter: ' + [for (t in targets) t.name].join(","));
		}

		if (targets.length == 0) {
			traceLog('No targets selected after filters, exiting with error.');
			Sys.println("No targets selected. Use --only=<target1,target2>.");
			Sys.exit(1);
		}
		traceLog('Selected target count: ' + targets.length);

		var summary:Array<TargetResult> = [];

		for (target in targets) {
			traceLog('--- Target start: ' + target.name + ' ---');
			traceLog('Required commands: ' + target.requiredCommands.join(","));
			traceLog('Compile cmd: ' + (target.compileCmd == null ? "<none>" : formatCommand(target.compileCmd)));
			traceLog('Run cmd: ' + formatCommand(target.runCmd));
			var missing = missingCommands(target.requiredCommands);
			if (missing.length > 0) {
				traceLog('Skipping target ' + target.name + ' due to missing commands: ' + missing.join(","));
				summary.push({
					target: target.name,
					status: "skipped",
					reason: 'missing: ${missing.join(";")}',
					logPath: "",
					csvPath: ""
				});
				continue;
			}

			if (target.csvName != "") {
				var stale = Path.join([resultsRoot, target.csvName]);
				traceLog('Checking stale CSV for target ' + target.name + ': ' + stale);
				if (FileSystem.exists(stale)) {
					traceLog('Deleting stale CSV: ' + stale);
					FileSystem.deleteFile(stale);
				}
			}

			var logParts:Array<String> = [];
			var ok = true;

			if (target.compileCmd != null) {
				traceLog('Compiling target: ' + target.name);
				logParts.push('=== COMPILE (${target.name}) ===');
				logParts.push(formatCommand(target.compileCmd));
				var compileRes = runCommand(target.compileCmd, testDir);
				traceLog('Compile result for ' + target.name + ' -> ok=' + compileRes.ok + ', exit=' + compileRes.exitCode + ', outLen='
					+ compileRes.stdout.length + ', errLen=' + compileRes.stderr.length);
				logParts.push(compileRes.stdout);
				if (compileRes.stderr != "")
					logParts.push("[stderr]\n" + compileRes.stderr);
				if (!compileRes.ok)
					ok = false;
			}

			if (ok) {
				traceLog('Running target: ' + target.name);
				logParts.push('=== RUN (${target.name}) ===');
				logParts.push(formatCommand(target.runCmd));
				var runRes = runCommand(target.runCmd, testDir);
				traceLog('Run result for ' + target.name + ' -> ok=' + runRes.ok + ', exit=' + runRes.exitCode + ', outLen=' + runRes.stdout.length
					+ ', errLen=' + runRes.stderr.length);
				logParts.push(runRes.stdout);
				if (runRes.stderr != "")
					logParts.push("[stderr]\n" + runRes.stderr);
				if (!runRes.ok)
					ok = false;
			}

			var logPath = Path.join([logsDir, 'bench_${target.name}.log']);
			traceLog('Writing log file for ' + target.name + ': ' + logPath);
			File.saveContent(logPath, logParts.join("\n") + "\n");

			var copiedCsv = "";
			if (target.csvName != "") {
				var srcCsv = Path.join([resultsRoot, target.csvName]);
				traceLog('Checking CSV output for ' + target.name + ': ' + srcCsv);
				if (FileSystem.exists(srcCsv)) {
					copiedCsv = Path.join([csvDir, target.csvName]);
					traceLog('Copying CSV to run folder: ' + copiedCsv);
					File.copy(srcCsv, copiedCsv);
				} else {
					traceLog('CSV not found for ' + target.name + ' (expected: ' + target.csvName + ')');
				}
			}

			traceLog('Target complete: ' + target.name + ' -> status=' + (ok ? "ok" : "failed"));
			summary.push({
				target: target.name,
				status: ok ? "ok" : "failed",
				reason: "",
				logPath: logPath,
				csvPath: copiedCsv
			});
		}

		traceLog('Writing global summary with ' + summary.length + ' rows.');
		writeSummary(runDir, summary);
		traceLog('Auto runner completed.');
		Sys.println('Done. Summary: ${Path.join([runDir, "run_summary.md"])}');
	}

	static function buildTargets(quick:Bool):Array<TargetSpec> {
		var baseCommon = ["-cp", ".", "-cp", "../src/", "-lib", "hscript-improved", "-lib", "hscript-iris"];
		var base = ["haxe"].concat(baseCommon).concat(["-main", "ScriptTargetBench"]);
		var quickArg = quick ? ["--quick"] : [];

		return [
			{
				name: "eval",
				compileCmd: null,
				runCmd: ["haxe"].concat(baseCommon).concat(["--run", "ScriptTargetBench"]).concat(quickArg),
				requiredCommands: ["haxe"],
				slow: false,
				csvName: "script_target_bench_eval.csv"
			},
			{
				name: "js",
				compileCmd: base.concat(["-js", "bin/ScriptTargetBench.js"]),
				runCmd: ["node", "./bin/ScriptTargetBench.js"].concat(quickArg),
				requiredCommands: ["haxe", "node"],
				slow: false,
				csvName: ""
			},
			{
				name: "hl",
				compileCmd: base.concat(["-hl", "bin/ScriptTargetBench.hl"]),
				runCmd: ["hl", "./bin/ScriptTargetBench.hl"].concat(quickArg),
				requiredCommands: ["haxe", "hl"],
				slow: false,
				csvName: "script_target_bench_hashlink.csv"
			},
			{
				name: "cpp",
				compileCmd: base.concat(["-cpp", "bin/cpp_scriptbench"]),
				runCmd: ["./bin/cpp_scriptbench/ScriptTargetBench"].concat(quickArg),
				requiredCommands: ["haxe"],
				slow: false,
				csvName: "script_target_bench_cpp.csv"
			},
			{
				name: "neko",
				compileCmd: base.concat(["-neko", "bin/ScriptTargetBench.n"]),
				runCmd: ["neko", "./bin/ScriptTargetBench.n"].concat(quickArg),
				requiredCommands: ["haxe", "neko"],
				slow: true,
				csvName: "script_target_bench_neko.csv"
			},
			{
				name: "python",
				compileCmd: base.concat(["-python", "bin/ScriptTargetBench.py"]),
				runCmd: ["python", "./bin/ScriptTargetBench.py"].concat(quickArg),
				requiredCommands: ["haxe", "python"],
				slow: true,
				csvName: "script_target_bench_python.csv"
			}
		];
	}

	static function runCommand(cmd:Array<String>, cwd:String):CmdResult {
		var previous = Sys.getCwd();
		traceLog('runCommand -> cwd=' + cwd + ' cmd=' + formatCommand(cmd));
		try {
			Sys.setCwd(cwd);
			// Use Sys.command so child output is streamed live and we avoid stdout/stderr pipe deadlocks.
			var code = Sys.command(cmd[0], cmd.slice(1));
			Sys.setCwd(previous);
			traceLog('runCommand <- exit=' + code);
			return {
				ok: code == 0,
				exitCode: code,
				stdout: "",
				stderr: ""
			};
		} catch (e:Dynamic) {
			Sys.setCwd(previous);
			traceLog('runCommand !! exception=' + Std.string(e));
			return {
				ok: false,
				exitCode: -1,
				stdout: "",
				stderr: Std.string(e)
			};
		}
	}

	static function commandAvailable(name:String):Bool {
		traceLog('Checking command availability: ' + name);
		// Avoid interactive probes like `python` or `node` with no args, which can block forever.
		var lookupCmd = isWindows() ? ["where", name] : ["which", name];
		var lookup = runCommand(lookupCmd, Sys.getCwd());
		if (lookup.exitCode == -1) {
			traceLog('Lookup tool unavailable while checking ' + name + ': ' + formatCommand(lookupCmd));
			return false;
		}
		traceLog('Lookup result for ' + name + ' -> ok=' + lookup.ok + ', exit=' + lookup.exitCode);
		if (!lookup.ok)
			return false;

		// Secondary signal for diagnostics only; non-zero still means command likely exists.
		var version = runCommand([name, "--version"], Sys.getCwd());
		traceLog('Version probe for ' + name + ' -> ok=' + version.ok + ', exit=' + version.exitCode);
		return version.exitCode != -1;
	}

	static function missingCommands(required:Array<String>):Array<String> {
		var missing:Array<String> = [];
		for (cmd in required) {
			if (!commandAvailable(cmd))
				missing.push(cmd);
		}
		if (missing.length == 0)
			traceLog('All required commands available: ' + required.join(","));
		else
			traceLog('Missing commands: ' + missing.join(","));
		return missing;
	}

	static function writeSummary(runDir:String, rows:Array<TargetResult>):Void {
		traceLog('writeSummary -> ' + runDir);
		var csvLines = ["target,status,reason,log,csv"];
		for (r in rows) {
			csvLines.push([
				r.target,
				r.status,
				escapeCsv(r.reason),
				escapeCsv(r.logPath),
				escapeCsv(r.csvPath)
			].join(","));
		}

		var md = new StringBuf();
		md.add("# Benchmark Auto Run\n\n");
		md.add('| Target | Status | Reason | Log | CSV |\n');
		md.add('|---|---|---|---|---|\n');
		for (r in rows) {
			md.add('| ${r.target} | ${r.status} | ${r.reason} | ${r.logPath} | ${r.csvPath} |\n');
		}

		File.saveContent(Path.join([runDir, "run_summary.csv"]), csvLines.join("\n") + "\n");
		File.saveContent(Path.join([runDir, "run_summary.md"]), md.toString());
		traceLog('Summary files written: ' + Path.join([runDir, "run_summary.csv"]) + ' and ' + Path.join([runDir, "run_summary.md"]));
	}

	static function ensureDir(path:String):Void {
		if (!FileSystem.exists(path)) {
			traceLog('Creating directory: ' + path);
			FileSystem.createDirectory(path);
		} else {
			traceLog('Directory already exists: ' + path);
		}
	}

	static function formatCommand(cmd:Array<String>):String {
		return cmd.join(" ");
	}

	static function escapeCsv(v:String):String {
		if (v == null)
			return "";
		if (v.indexOf(",") >= 0 || v.indexOf('"') >= 0)
			return '"' + v.split('"').join('""') + '"';
		return v;
	}

	static function hasFlag(args:Array<String>, flag:String):Bool {
		for (a in args)
			if (a == flag)
				return true;
		return false;
	}

	static function parseOnlyTargets(args:Array<String>):Array<String> {
		for (i in 0...args.length) {
			var a = args[i];
			if (StringTools.startsWith(a, "--only=")) {
				var raw = a.substr("--only=".length);
				traceLog('Parsed --only inline value: ' + raw);
				return [for (v in raw.split(",")) if (v != "") StringTools.trim(v.toLowerCase())];
			}
			if (a == "--only" && i + 1 < args.length) {
				var raw2 = args[i + 1];
				traceLog('Parsed --only next-arg value: ' + raw2);
				return [for (v in raw2.split(",")) if (v != "") StringTools.trim(v.toLowerCase())];
			}
		}
		traceLog('No --only filter provided.');
		return [];
	}

	static function isWindows():Bool {
		return Sys.systemName().toLowerCase().indexOf("windows") >= 0;
	}

	static function traceLog(msg:String):Void {
		Sys.println(TRACE_PREFIX + " " + msg);
	}

	static function timestamp():String {
		var d = Date.now();
		return '${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}_${pad2(d.getHours())}-${pad2(d.getMinutes())}-${pad2(d.getSeconds())}';
	}

	static function pad2(v:Int):String {
		return v < 10 ? "0" + v : Std.string(v);
	}
}
