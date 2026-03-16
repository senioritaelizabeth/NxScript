package nx.script;

using StringTools;

/**
 * NxScript preprocessor — handles #if / #elseif / #else / #end directives.
 *
 * Runs on raw source text before tokenization.
 * Inactive blocks are replaced with blank lines (preserving line numbers for error messages).
 *
 * Usage:
 *   var defines = ["debug" => true, "cpp" => true, "windows" => false];
 *   var processed = Preprocessor.run(source, defines);
 *
 * Supported syntax:
 *   #if debug
 *     trace("debug build")
 *   #end
 *
 *   #if release
 *     trace("release")
 *   #elseif debug
 *     trace("debug")
 *   #else
 *     trace("other")
 *   #end
 *
 * Built-in defines (set automatically by Interpreter based on compile target):
 *   debug / release
 *   cpp / hl / neko / js / java / cs / python / lua / eval / interp
 *   windows / linux / mac / android / ios
 *
 * The host can add custom defines:
 *   interp.defines.set("myFeature", true);
 */
class Preprocessor {

	/**
	 * Process source, stripping inactive #if blocks.
	 * Inactive lines are replaced with empty lines to preserve line numbers.
	 */
	public static function run(source:String, defines:Map<String, Bool>):String {
		var lines  = source.split("\n");
		var result = [];

		var i = 0;
		while (i < lines.length) {
			var line = lines[i].trim();

			if (line.startsWith("#if ") || line == "#if") {
				// Parse the whole #if / #elseif / #else / #end block
				var consumed = processBlock(lines, i, defines, result);
				i += consumed;
			} else {
				result.push(lines[i]);
				i++;
			}
		}

		return result.join("\n");
	}

	/**
	 * Process a #if block starting at `startLine`.
	 * Appends processed lines to `result`.
	 * Returns the number of lines consumed (including #end).
	 */
	static function processBlock(
		lines:Array<String>,
		startLine:Int,
		defines:Map<String, Bool>,
		result:Array<String>
	):Int {
		// Parse condition from the #if line
		var ifLine   = lines[startLine].trim();
		var cond     = ifLine.substr(4).trim(); // everything after "#if "
		var active   = eval(cond, defines);
		var emitted  = false; // did we already emit a block?

		// Replace the #if line with blank
		result.push("");
		var i = startLine + 1;
		var depth = 1;

		// Collect lines for each branch
		var branchLines:Array<String> = [];

		while (i < lines.length) {
			var raw = lines[i];
			var trimmed = raw.trim();

			if (trimmed.startsWith("#if ") || trimmed == "#if") {
				// Nested #if — just collect and recurse later
				depth++;
				branchLines.push(raw);
				i++;
			} else if (depth == 1 && (trimmed.startsWith("#elseif ") || trimmed.startsWith("#elif "))) {
				// Flush current branch
				if (active && !emitted) {
					// Emit this branch, recursively processing nested #if
					var sub = Preprocessor.run(branchLines.join("\n"), defines);
					for (l in sub.split("\n")) result.push(l);
					emitted = true;
				} else {
					for (_ in branchLines) result.push("");
				}
				branchLines = [];
				// Parse new condition
				var prefix = trimmed.startsWith("#elseif") ? "#elseif " : "#elif ";
				var newCond = trimmed.substr(prefix.length).trim();
				active = !emitted && eval(newCond, defines);
				result.push(""); // replace #elseif line with blank
				i++;
			} else if (depth == 1 && trimmed == "#else") {
				// Flush current branch
				if (active && !emitted) {
					var sub = Preprocessor.run(branchLines.join("\n"), defines);
					for (l in sub.split("\n")) result.push(l);
					emitted = true;
				} else {
					for (_ in branchLines) result.push("");
				}
				branchLines = [];
				active = !emitted;
				result.push(""); // replace #else with blank
				i++;
			} else if (trimmed == "#end") {
				depth--;
				if (depth == 0) {
					// Flush final branch
					if (active && !emitted) {
						var sub = Preprocessor.run(branchLines.join("\n"), defines);
						for (l in sub.split("\n")) result.push(l);
					} else {
						for (_ in branchLines) result.push("");
					}
					result.push(""); // replace #end with blank
					return (i - startLine) + 1; // lines consumed
				} else {
					branchLines.push(raw);
					i++;
				}
			} else {
				branchLines.push(raw);
				i++;
			}
		}

		// Unterminated #if — emit what we have
		if (active && !emitted) {
			var sub = Preprocessor.run(branchLines.join("\n"), defines);
			for (l in sub.split("\n")) result.push(l);
		} else {
			for (_ in branchLines) result.push("");
		}

		return i - startLine;
	}

	/**
	 * Evaluate a preprocessor condition expression.
	 * Supports: identifier, !identifier, a && b, a || b, (expr)
	 */
	static function eval(expr:String, defines:Map<String, Bool>):Bool {
		expr = expr.trim();

		// Parentheses
		if (expr.startsWith("(") && expr.endsWith(")"))
			return eval(expr.substr(1, expr.length - 2), defines);

		// OR  (lowest precedence)
		var orIdx = findOuterOp(expr, "||");
		if (orIdx >= 0)
			return eval(expr.substr(0, orIdx), defines) || eval(expr.substr(orIdx + 2), defines);

		// AND
		var andIdx = findOuterOp(expr, "&&");
		if (andIdx >= 0)
			return eval(expr.substr(0, andIdx), defines) && eval(expr.substr(andIdx + 2), defines);

		// NOT
		if (expr.startsWith("!"))
			return !eval(expr.substr(1), defines);

		// Simple identifier
		var name = expr.trim();
		return defines.exists(name) && defines.get(name);
	}

	/** Find the index of `op` at depth 0 in `expr`. Returns -1 if not found. */
	static function findOuterOp(expr:String, op:String):Int {
		var depth = 0;
		var i = 0;
		while (i < expr.length - op.length + 1) {
			var c = expr.charAt(i);
			if (c == "(") { depth++; i++; continue; }
			if (c == ")") { depth--; i++; continue; }
			if (depth == 0 && expr.substr(i, op.length) == op)
				return i;
			i++;
		}
		return -1;
	}

	/**
	 * Build the default defines map for the current compile target.
	 * Called by Interpreter constructor.
	 */
	public static function defaultDefines():Map<String, Bool> {
		var d:Map<String, Bool> = new Map();

		// Debug / release
		#if debug
		d.set("debug",   true);
		d.set("release", false);
		#else
		d.set("debug",   false);
		d.set("release", true);
		#end

		// Haxe compile target
		#if cpp     d.set("cpp",    true); #end
		#if hl      d.set("hl",     true); #end
		#if neko    d.set("neko",   true); #end
		#if js      d.set("js",     true); #end
		#if java    d.set("java",   true); #end
		#if cs      d.set("cs",     true); #end
		#if python  d.set("python", true); #end
		#if lua     d.set("lua",    true); #end
		#if eval    d.set("eval",   true); #end
		#if interp  d.set("interp", true); #end

		// Platform
		#if windows d.set("windows", true); #end
		#if linux   d.set("linux",   true); #end
		#if mac     d.set("mac",     true); #end
		#if android d.set("android", true); #end
		#if ios     d.set("ios",     true); #end

		return d;
	}
}
