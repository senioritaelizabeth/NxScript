import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

private typedef SummaryRow = {
	var target:String;
	var status:String;
	var reason:String;
	var logPath:String;
	var csvPath:String;
}

private typedef EngineStat = {
	var ops:Float;
	var pct:Float;
}

private typedef ScenarioData = {
	var id:String;
	var name:String;
	var engines:Map<String, EngineStat>;
}

class BenchReport {
	static function main() {
		var args = Sys.args();
		var runDir = args.length > 0 ? normalizePath(args[0]) : findLatestRunDir();
		if (runDir == null || runDir == "") {
			Sys.println("No run directory found. Pass one: haxe -cp . --run BenchReport test_results/auto_run_YYYY-MM-DD_HH-mm-ss");
			Sys.exit(1);
		}

		var summaryCsv = Path.join([runDir, "run_summary.csv"]);
		if (!FileSystem.exists(summaryCsv)) {
			Sys.println("Missing run_summary.csv: " + summaryCsv);
			Sys.exit(1);
		}

		var summaryRows = parseSummary(summaryCsv);
		var report = buildReport(runDir, summaryRows);
		var outPath = Path.join([runDir, "speed_comparison.md"]);
		File.saveContent(outPath, report);
		Sys.println("Speed report generated: " + outPath);
	}

	static function buildReport(runDir:String, summaryRows:Array<SummaryRow>):String {
		var scenariosByTarget:Map<String, Array<ScenarioData>> = new Map();
		var scenarioOrderByTarget:Map<String, Array<String>> = new Map();
		var scenarioNameByTarget:Map<String, Map<String, String>> = new Map();

		for (row in summaryRows) {
			if (row.status != "ok")
				continue;
			if (row.csvPath == null || row.csvPath == "")
				continue;
			if (!FileSystem.exists(row.csvPath))
				continue;

			var parsed = parseBenchmarkAvgRows(row.csvPath);
			scenariosByTarget.set(row.target, parsed.scenarios);
			scenarioOrderByTarget.set(row.target, parsed.order);
			scenarioNameByTarget.set(row.target, parsed.names);
		}

		var md = new StringBuf();
		md.add("# Speed Comparison Report\n\n");
		md.add("Run directory: `" + runDir + "`\n\n");

		md.add("## Target Status\n\n");
		md.add("| Target | Status | Reason | CSV |\n");
		md.add("|---|---|---|---|\n");
		for (row in summaryRows) {
			md.add("| " + row.target + " | " + row.status + " | " + safeCell(row.reason) + " | " + safeCell(row.csvPath) + " |\n");
		}
		md.add("\n");

		md.add("## Per-Target Comparisons\n\n");
		for (row in summaryRows) {
			if (!scenariosByTarget.exists(row.target))
				continue;
			md.add("### " + row.target + "\n\n");
			md.add("| Scenario | NxScript ops/s | Iris ops/s (%Nx) | HScriptImproved ops/s (%Nx) | Winner |\n");
			md.add("|---|---:|---:|---:|---|\n");

			var byId:Map<String, ScenarioData> = new Map();
			for (s in scenariosByTarget.get(row.target))
				byId.set(s.id, s);

			for (scenarioId in scenarioOrderByTarget.get(row.target)) {
				if (!byId.exists(scenarioId))
					continue;
				var s = byId.get(scenarioId);
				var nx = getEngineStat(s.engines, "NxScript");
				var iris = getEngineStat(s.engines, "Iris");
				var hs = getEngineStat(s.engines, "HScriptImproved");
				var winner = winnerName(s.engines);
				md.add("| "
					+ safeCell(s.name)
					+ " | "
					+ fmtOps(nx.ops)
					+ " | "
					+ fmtEngine(iris)
					+ " | "
					+ fmtEngine(hs)
					+ " | "
					+ winner
					+ " |\n");
			}
			md.add("\n");
		}

		md.add("## NxScript Cross-Target\n\n");
		md.add("| Scenario | Target | NxScript ops/s | Relative To Fastest |\n");
		md.add("|---|---|---:|---:|\n");

		var allScenarioIds = collectAllScenarioIds(scenarioOrderByTarget);
		for (scenarioId in allScenarioIds) {
			var entries:Array<{target:String, scenarioName:String, ops:Float}> = [];
			for (target in scenariosByTarget.keys()) {
				var byId:Map<String, ScenarioData> = new Map();
				for (s in scenariosByTarget.get(target))
					byId.set(s.id, s);
				if (!byId.exists(scenarioId))
					continue;
				var s = byId.get(scenarioId);
				var nx = getEngineStat(s.engines, "NxScript");
				if (nx.ops > 0)
					entries.push({target: target, scenarioName: s.name, ops: nx.ops});
			}

			var fastest = 0.0;
			for (e in entries)
				if (e.ops > fastest)
					fastest = e.ops;

			for (e in entries) {
				var rel = fastest > 0 ? (e.ops / fastest) * 100.0 : 0.0;
				md.add("| " + safeCell(e.scenarioName) + " | " + e.target + " | " + fmtOps(e.ops) + " | " + fmtPct(rel) + " |\n");
			}
		}

		return md.toString();
	}

	static function parseSummary(path:String):Array<SummaryRow> {
		var lines = parseCsv(File.getContent(path));
		if (lines.length <= 1)
			return [];
		var out:Array<SummaryRow> = [];
		for (i in 1...lines.length) {
			var r = lines[i];
			if (r.length < 5)
				continue;
			out.push({
				target: r[0],
				status: r[1],
				reason: r[2],
				logPath: r[3],
				csvPath: r[4]
			});
		}
		return out;
	}

	static function parseBenchmarkAvgRows(path:String):{scenarios:Array<ScenarioData>, order:Array<String>, names:Map<String, String>} {
		var rows = parseCsv(File.getContent(path));
		var out:Array<ScenarioData> = [];
		var byScenario:Map<String, ScenarioData> = new Map();
		var order:Array<String> = [];
		var names:Map<String, String> = new Map();
		if (rows.length <= 1)
			return {scenarios: out, order: order, names: names};

		for (i in 1...rows.length) {
			var r = rows[i];
			if (r.length < 11)
				continue;
			var category = r[1];
			var scenarioId = r[2];
			var scenarioName = r[3];
			var engine = r[4];
			var sample = r[5];
			var opsSec = parseFloatSafe(r[7]);
			var pctVsNx = parseFloatSafe(r[8]);
			var ok = r[9] == "true";

			if (category != "profile" || sample != "avg" || !ok)
				continue;

			if (!byScenario.exists(scenarioId)) {
				var s:ScenarioData = {
					id: scenarioId,
					name: scenarioName,
					engines: new Map()
				};
				byScenario.set(scenarioId, s);
				out.push(s);
				order.push(scenarioId);
				names.set(scenarioId, scenarioName);
			}

			var scenario = byScenario.get(scenarioId);
			scenario.engines.set(engine, {ops: opsSec, pct: pctVsNx});
		}

		return {scenarios: out, order: order, names: names};
	}

	static function collectAllScenarioIds(orderByTarget:Map<String, Array<String>>):Array<String> {
		var ids:Array<String> = [];
		var seen:Map<String, Bool> = new Map();
		for (target in orderByTarget.keys()) {
			for (id in orderByTarget.get(target)) {
				if (seen.exists(id))
					continue;
				seen.set(id, true);
				ids.push(id);
			}
		}
		return ids;
	}

	static function getEngineStat(engines:Map<String, EngineStat>, name:String):EngineStat {
		if (engines.exists(name))
			return engines.get(name);
		return {ops: 0.0, pct: 0.0};
	}

	static function winnerName(engines:Map<String, EngineStat>):String {
		var winner = "-";
		var best = -1.0;
		for (name in engines.keys()) {
			var ops = engines.get(name).ops;
			if (ops > best) {
				best = ops;
				winner = name;
			}
		}
		return winner;
	}

	static function fmtEngine(s:EngineStat):String {
		if (s.ops <= 0)
			return "-";
		return fmtOps(s.ops) + " (" + fmtPct(s.pct) + ")";
	}

	static function fmtOps(v:Float):String {
		return Std.string(Math.round(v));
	}

	static function fmtPct(v:Float):String {
		return Std.string(Math.round(v)) + "%";
	}

	static function safeCell(v:String):String {
		if (v == null || v == "")
			return "-";
		return v.split("|").join("\\|");
	}

	static function parseFloatSafe(v:String):Float {
		var f = Std.parseFloat(v);
		if (Math.isNaN(f))
			return 0.0;
		return f;
	}

	static function findLatestRunDir():String {
		var root = "test_results";
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root))
			return "";
		var latest = "";
		for (name in FileSystem.readDirectory(root)) {
			if (!StringTools.startsWith(name, "auto_run_"))
				continue;
			var full = Path.join([root, name]);
			if (!FileSystem.isDirectory(full))
				continue;
			if (name > latest)
				latest = name;
		}
		if (latest == "")
			return "";
		return Path.join([root, latest]);
	}

	static function normalizePath(path:String):String {
		if (path == null)
			return "";
		return path.split("\\").join("/");
	}

	static function parseCsv(content:String):Array<Array<String>> {
		var rows:Array<Array<String>> = [];
		var lines = content.split("\n");
		for (line in lines) {
			var clean = StringTools.trim(line);
			if (clean == "")
				continue;
			rows.push(parseCsvLine(clean));
		}
		return rows;
	}

	static function parseCsvLine(line:String):Array<String> {
		var out:Array<String> = [];
		var cell = new StringBuf();
		var inQuotes = false;
		var i = 0;
		while (i < line.length) {
			var ch = line.charAt(i);
			if (ch == '"') {
				if (inQuotes && i + 1 < line.length && line.charAt(i + 1) == '"') {
					cell.add('"');
					i += 2;
					continue;
				}
				inQuotes = !inQuotes;
				i++;
				continue;
			}
			if (!inQuotes && ch == ",") {
				out.push(cell.toString());
				cell = new StringBuf();
				i++;
				continue;
			}
			cell.add(ch);
			i++;
		}
		out.push(cell.toString());
		return out;
	}
}
