import crowplexus.iris.Iris;
import haxe.Timer;
import hscript.Interp;
import hscript.Parser;
import nx.script.Interpreter;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

typedef Scenario = {
	var id:String;
	var name:String;
	var iterations:Int;
	var nxSource:String;
	var nxEntry:String;
	var irisSource:String;
	var irisEntry:String;
	var hsSource:String;
	var hsEntry:String;
}

typedef SanityCase = {
	var id:String;
	var name:String;
	var nxSource:String;
	var irisSource:String;
	var hsSource:String;
	var expected:Dynamic;
}

class ScriptTargetBench {
	static var SAMPLE_COUNT:Int = 10;
	static var ITERATION_SCALE:Float = 1.0;
	static var QUICK_MODE:Bool = false;
	static var CSV_ROWS:Array<String> = [];
	static var EMPTY_DYNAMIC_ARGS:Array<Dynamic> = [];

	static function main() {
		configureFromArgs(Sys.args());

		#if !sys
		trace("no tenemo sys");
		#else
		trace("tenemo sys");
		#end

		trace("========================================");
		trace('Script Target Benchmark (${targetName()})');
		trace("========================================");
		trace('Samples per scenario: $SAMPLE_COUNT');
		trace('Iteration scale: $ITERATION_SCALE');
		if (QUICK_MODE)
			trace('Quick mode: enabled');

		CSV_ROWS = [];
		CSV_ROWS.push("target,category,scenario_id,scenario_name,engine,sample,time_ms,ops_sec,pct_vs_nx,ok,message");

		runSanitySuite();

		var scenarios = buildScenarios();
		for (scenario in scenarios) {
			runScenario(scenario);
		}

		exportCsv();
	}

	static function runSanitySuite():Void {
		trace("\n========================================");
		trace("Sanity Suite (single file, isolated)");
		trace("========================================");

		var cases = buildSanityCases();
		var engines = ["NxScript", "Iris", "HScriptImproved"];
		var passed = 0;
		var failed = 0;

		for (c in cases) {
			trace('\nCase: ${c.name}');
			for (engine in engines) {
				var res = runSanityCaseForEngine(c, engine);
				if (res.ok)
					passed++;
				else
					failed++;

				var mark = res.ok ? "OK" : "FAIL";
				trace('  [$engine] $mark ${res.message}');
				addCsvRowGeneric("sanity", c.id, c.name, engine, "1", 0, 0, 0, res.ok, res.message);
			}
		}

		trace("\nSanity summary");
		trace('  Passed: $passed');
		trace('  Failed: $failed');
	}

	static function buildSanityCases():Array<SanityCase> {
		return [
			{
				id: "sanity_add",
				name: "Variables and addition",
				nxSource: '
					func main() {
						var x = 10
						var y = 20
						return x + y
					}
				',
				irisSource: 'function main(){ var x = 10; var y = 20; return x + y; }',
				hsSource: 'function main(){ var x = 10; var y = 20; return x + y; }',
				expected: 30
			},
			{
				id: "sanity_while",
				name: "While sum",
				nxSource: '
					func main() {
						var i = 0
						var sum = 0
						while (i < 10) {
							sum = sum + i
							i = i + 1
						}
						return sum
					}
				',
				irisSource: 'function main(){ var i = 0; var sum = 0; while (i < 10) { sum = sum + i; i = i + 1; } return sum; }',
				hsSource: 'function main(){ var i = 0; var sum = 0; while (i < 10) { sum = sum + i; i = i + 1; } return sum; }',
				expected: 45
			},
			{
				id: "sanity_array",
				name: "Array push length",
				nxSource: '
					func main() {
						var a = [1, 2, 3]
						a.push(4)
						return a.length
					}
				',
				irisSource: 'function main(){ var a = [1,2,3]; a.push(4); return a.length; }',
				hsSource: 'function main(){ var a = [1,2,3]; a.push(4); return a.length; }',
				expected: 4
			}
		];
	}

	static function runSanityCaseForEngine(c:SanityCase, engine:String):{ok:Bool, message:String} {
		try {
			var out:Dynamic = switch (engine) {
				case "NxScript":
					var interp = new Interpreter();
					interp.runDynamic(c.nxSource + "\nmain()\n");
				case "Iris":
					var iris = new Iris(c.irisSource);
					var irisOut:Dynamic = iris.call("main", EMPTY_DYNAMIC_ARGS);
					Reflect.field(irisOut, "returnValue");
				case "HScriptImproved":
					var parser = new Parser();
					var program = parser.parseString(c.hsSource);
					var interp = new Interp();
					interp.execute(program);
					var fn:Dynamic = interp.variables.get("main");
					Reflect.callMethod(null, fn, EMPTY_DYNAMIC_ARGS);
				default:
					null;
			};

			var ok = valuesEqualLoose(out, c.expected);
			return {
				ok: ok,
				message: ok ? 'expected=${c.expected} got=$out' : 'expected=${c.expected} got=$out'
			};
		} catch (e:Dynamic) {
			return {ok: false, message: 'exception: $e'};
		}
	}

	static function buildScenarios():Array<Scenario> {
		return [
			{
				id: "update_100k",
				name: "Update Loop 100k",
				iterations: scaledIterations(100000),
				nxSource: '
					var x = 0
					var y = 0
					func checkHitbox() {}
					func step() {
						var delta = 16
						var velocity = 2
						x = x + velocity * delta
						y = y + velocity * delta
						var i = 0
						while (i < 5) {
							checkHitbox()
							i = i + 1
						}
					}
				',
				nxEntry: "step",
				irisSource: '
					var x = 0;
					var y = 0;
					function checkHitbox() {}
					function step() {
						var delta = 16;
						var velocity = 2;
						x = x + velocity * delta;
						y = y + velocity * delta;
						var i = 0;
						while (i < 5) {
							checkHitbox();
							i = i + 1;
						}
					}
				',
				irisEntry: "step",
				hsSource: '
					var x = 0;
					var y = 0;
					function checkHitbox() {}
					function step() {
						var delta = 16;
						var velocity = 2;
						x = x + velocity * delta;
						y = y + velocity * delta;
						var i = 0;
						while (i < 5) {
							checkHitbox();
							i = i + 1;
						}
					}
				',
				hsEntry: "step"
			},
			{
				id: "arith_60k",
				name: "Arithmetic Chain 60k",
				iterations: scaledIterations(60000),
				nxSource: '
					var acc = 0
					func step() {
						var i = 0
						while (i < 20) {
							acc = acc + i * 3 - 2
							i = i + 1
						}
					}
				',
				nxEntry: "step",
				irisSource: '
					var acc = 0;
					function step() {
						var i = 0;
						while (i < 20) {
							acc = acc + i * 3 - 2;
							i = i + 1;
						}
					}
				',
				irisEntry: "step",
				hsSource: '
					var acc = 0;
					function step() {
						var i = 0;
						while (i < 20) {
							acc = acc + i * 3 - 2;
							i = i + 1;
						}
					}
				',
				hsEntry: "step"
			},
			{
				id: "array_30k",
				name: "Array Push/Pop 30k",
				iterations: scaledIterations(30000),
				nxSource: '
					var arr = []
					func step() {
						var i = 0
						while (i < 20) {
							arr.push(i)
							i = i + 1
						}
						i = 0
						while (i < 10) {
							arr.pop()
							i = i + 1
						}
					}
				',
				nxEntry: "step",
				irisSource: '
					var arr = [];
					function step() {
						var i = 0;
						while (i < 20) {
							arr.push(i);
							i = i + 1;
						}
						i = 0;
						while (i < 10) {
							arr.pop();
							i = i + 1;
						}
					}
				',
				irisEntry: "step",
				hsSource: '
					var arr = [];
					function step() {
						var i = 0;
						while (i < 20) {
							arr.push(i);
							i = i + 1;
						}
						i = 0;
						while (i < 10) {
							arr.pop();
							i = i + 1;
						}
					}
				',
				hsEntry: "step"
			}
		];
	}

	static function runScenario(s:Scenario):Void {
		trace("\n========================================");
		trace('Scenario: ${s.name} (${s.iterations} iterations)');
		trace("========================================");

		var nxInvoke = buildNxInvoker(s);
		var irisInvoke = buildIrisInvoker(s);
		var hsInvoke = buildHsInvoker(s);

		warmup(nxInvoke, s.iterations);
		warmup(irisInvoke, s.iterations);
		warmup(hsInvoke, s.iterations);

		var nxRates:Array<Float> = [];
		var irisRates:Array<Float> = [];
		var hsRates:Array<Float> = [];

		var sample = 1;
		while (sample <= SAMPLE_COUNT) {
			trace('\nSample $sample/$SAMPLE_COUNT');

			var nxRes = runBench("NxScript", s.iterations, nxInvoke);
			if (nxRes.ok)
				nxRates.push(nxRes.rate);
			addCsvRow(s, "NxScript", Std.string(sample), nxRes.timeMs, nxRes.rate, 100.0, nxRes.ok, nxRes.message);

			var irisRes = runBench("Iris", s.iterations, irisInvoke);
			if (irisRes.ok)
				irisRates.push(irisRes.rate);
			var irisPct = nxRes.rate > 0 ? (irisRes.rate / nxRes.rate) * 100 : 0;
			addCsvRow(s, "Iris", Std.string(sample), irisRes.timeMs, irisRes.rate, irisPct, irisRes.ok, irisRes.message);

			var hsRes = runBench("HScriptImproved", s.iterations, hsInvoke);
			if (hsRes.ok)
				hsRates.push(hsRes.rate);
			var hsPct = nxRes.rate > 0 ? (hsRes.rate / nxRes.rate) * 100 : 0;
			addCsvRow(s, "HScriptImproved", Std.string(sample), hsRes.timeMs, hsRes.rate, hsPct, hsRes.ok, hsRes.message);

			sample++;
		}

		var nxAvg = avg(nxRates);
		var irisAvg = avg(irisRates);
		var hsAvg = avg(hsRates);
		var irisAvgPct = nxAvg > 0 ? (irisAvg / nxAvg) * 100 : 0;
		var hsAvgPct = nxAvg > 0 ? (hsAvg / nxAvg) * 100 : 0;

		trace("\nSummary (average)");
		trace('NxScript: ${Math.round(nxAvg)} ops/sec (100%)');
		trace('Iris: ${Math.round(irisAvg)} ops/sec (${Math.round(irisAvgPct)}% of NxScript)');
		trace('HScriptImproved: ${Math.round(hsAvg)} ops/sec (${Math.round(hsAvgPct)}% of NxScript)');
		trace('NxScript stats: min=${Math.round(minV(nxRates))} max=${Math.round(maxV(nxRates))} stddev=${Math.round(stddev(nxRates))}');
		trace('Iris stats: min=${Math.round(minV(irisRates))} max=${Math.round(maxV(irisRates))} stddev=${Math.round(stddev(irisRates))}');
		trace('HScriptImproved stats: min=${Math.round(minV(hsRates))} max=${Math.round(maxV(hsRates))} stddev=${Math.round(stddev(hsRates))}');

		addCsvRow(s, "NxScript", "avg", 0, nxAvg, 100.0, true, "");
		addCsvRow(s, "Iris", "avg", 0, irisAvg, irisAvgPct, true, "");
		addCsvRow(s, "HScriptImproved", "avg", 0, hsAvg, hsAvgPct, true, "");

		addCsvRowGeneric("profile", s.id, s.name, "NxScript", "stats", 0, stddev(nxRates), 0, true,
			'min='
			+ Std.string(minV(nxRates))
			+ ';max='
			+ Std.string(maxV(nxRates))
			+ ';avg='
			+ Std.string(nxAvg));
		addCsvRowGeneric("profile", s.id, s.name, "Iris", "stats", 0, stddev(irisRates), 0, true,
			'min='
			+ Std.string(minV(irisRates))
			+ ';max='
			+ Std.string(maxV(irisRates))
			+ ';avg='
			+ Std.string(irisAvg));
		addCsvRowGeneric("profile", s.id, s.name, "HScriptImproved", "stats", 0, stddev(hsRates), 0, true,
			'min='
			+ Std.string(minV(hsRates))
			+ ';max='
			+ Std.string(maxV(hsRates))
			+ ';avg='
			+ Std.string(hsAvg));
	}

	static function buildNxInvoker(s:Scenario):Void->Void {
		var interp = new Interpreter();
		interp.run(s.nxSource);
		var callable = interp.resolveCallable(s.nxEntry);
		return function() {
			interp.callResolved0(callable);
		};
	}

	static function buildIrisInvoker(s:Scenario):Void->Void {
		var iris = new Iris(s.irisSource);
		return function() {
			iris.call(s.irisEntry, EMPTY_DYNAMIC_ARGS);
		};
	}

	static function buildHsInvoker(s:Scenario):Void->Void {
		var parser = new Parser();
		var program = parser.parseString(s.hsSource);

		var interp = new Interp();
		interp.execute(program);
		var fn:Dynamic = interp.variables.get(s.hsEntry);
		return function() {
			Reflect.callMethod(null, fn, EMPTY_DYNAMIC_ARGS);
		};
	}

	static function warmup(invoke:Void->Void, iterations:Int):Void {
		var warm = iterations < 1000 ? iterations : 1000;
		var i = 0;
		while (i < warm) {
			invoke();
			i++;
		}
	}

	static function runBench(engine:String, iterations:Int, invoke:Void->Void):{
		timeMs:Float,
		rate:Float,
		ok:Bool,
		message:String
	} {
		trace("Running: " + engine);
		try {
			var start = Timer.stamp();
			var i = 0;
			while (i < iterations) {
				invoke();
				i++;
			}
			var elapsed = Timer.stamp() - start;
			var ms = elapsed * 1000;
			trace('  Time: ${Math.round(ms * 100) / 100}ms');

			if (elapsed <= 0) {
				trace("  (Too fast to measure accurately)");
				return {
					timeMs: ms,
					rate: 0,
					ok: false,
					message: "elapsed<=0"
				};
			}

			var rate = iterations / elapsed;
			trace('  Rate: ${Math.round(rate)} ops/sec');
			return {
				timeMs: ms,
				rate: rate,
				ok: true,
				message: ""
			};
		} catch (e:Dynamic) {
			trace('  FAIL: $e');
			return {
				timeMs: 0,
				rate: 0,
				ok: false,
				message: Std.string(e)
			};
		}
	}

	static function avg(values:Array<Float>):Float {
		if (values.length == 0)
			return 0;
		var sum = 0.0;
		for (v in values)
			sum += v;
		return sum / values.length;
	}

	static function minV(values:Array<Float>):Float {
		if (values.length == 0)
			return 0;
		var m = values[0];
		for (v in values)
			if (v < m)
				m = v;
		return m;
	}

	static function maxV(values:Array<Float>):Float {
		if (values.length == 0)
			return 0;
		var m = values[0];
		for (v in values)
			if (v > m)
				m = v;
		return m;
	}

	static function stddev(values:Array<Float>):Float {
		if (values.length == 0)
			return 0;
		var mean = avg(values);
		var sumSq = 0.0;
		for (v in values) {
			var d = v - mean;
			sumSq += d * d;
		}
		return Math.sqrt(sumSq / values.length);
	}

	static function addCsvRow(s:Scenario, engine:String, sample:String, timeMs:Float, opsSec:Float, pctVsNx:Float, ok:Bool, message:String):Void {
		addCsvRowGeneric("profile", s.id, s.name, engine, sample, timeMs, opsSec, pctVsNx, ok, message);
	}

	static function addCsvRowGeneric(category:String, scenarioId:String, scenarioName:String, engine:String, sample:String, timeMs:Float, opsSec:Float,
			pctVsNx:Float, ok:Bool, message:String):Void {
		var cols = [
			targetName(),
			category,
			scenarioId,
			escapeCsv(scenarioName),
			engine,
			sample,
			Std.string(timeMs),
			Std.string(opsSec),
			Std.string(pctVsNx),
			ok ? "true" : "false",
			escapeCsv(message)
		];
		CSV_ROWS.push(cols.join(","));
	}

	static function valuesEqualLoose(a:Dynamic, b:Dynamic):Bool {
		if (a == b)
			return true;
		var sa = Std.string(a);
		var sb = Std.string(b);
		if (sa == sb)
			return true;
		var fa = Std.parseFloat(sa);
		var fb = Std.parseFloat(sb);
		if (!Math.isNaN(fa) && !Math.isNaN(fb))
			return Math.abs(fa - fb) < 0.0001;
		return false;
	}

	static function escapeCsv(v:String):String {
		if (v.indexOf(",") >= 0 || v.indexOf('"') >= 0) {
			return '"' + v.split('"').join('""') + '"';
		}
		return v;
	}

	static function exportCsv():Void {
		#if sys
		var outDir = "test_results";
		if (!FileSystem.exists(outDir))
			FileSystem.createDirectory(outDir);
		var outPath = outDir + '/script_target_bench_' + targetName() + '.csv';
		File.saveContent(outPath, CSV_ROWS.join("\n") + "\n");
		trace('\nCSV exported: ' + outPath);
		#else
		trace('\nCSV export skipped: no tenemo sys');
		#end
	}

	static function configureFromArgs(args:Array<String>):Void {
		if (hasFlag(args, "--quick")) {
			QUICK_MODE = true;
			SAMPLE_COUNT = 2;
			ITERATION_SCALE = 0.1;
		}

		var sampleArg = getArgValue(args, "--samples=");
		if (sampleArg != null) {
			var parsed = Std.parseInt(sampleArg);
			if (parsed != null && parsed > 0)
				SAMPLE_COUNT = parsed;
		}

		var scaleArg = getArgValue(args, "--iter-scale=");
		if (scaleArg != null) {
			var parsedScale = Std.parseFloat(scaleArg);
			if (!Math.isNaN(parsedScale) && parsedScale > 0)
				ITERATION_SCALE = parsedScale;
		}
	}

	static function scaledIterations(base:Int):Int {
		var scaled = Std.int(Math.floor(base * ITERATION_SCALE));
		return scaled < 1 ? 1 : scaled;
	}

	static function hasFlag(args:Array<String>, flag:String):Bool {
		for (a in args)
			if (a == flag)
				return true;
		return false;
	}

	static function getArgValue(args:Array<String>, prefix:String):Null<String> {
		for (a in args)
			if (StringTools.startsWith(a, prefix))
				return a.substr(prefix.length);
		return null;
	}

	static function targetName():String {
		#if neko
		return "neko";
		#elseif hl
		return "hashlink";
		#elseif cpp
		return "cpp";
		#elseif js
		return "js";
		#elseif python
		return "python";
		#elseif eval
		return "eval";
		#else
		return "unknown";
		#end
	}
}
