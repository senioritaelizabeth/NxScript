package nx.script;

// SyntaxRules.hx — Configurable syntax dialect for NxScript
//
// `SyntaxRules` lets you tune which language features are available and how
// identifiers map to keywords or operators. Pass an instance to `Interpreter`,
// `Tokenizer`, or `Parser` to override the defaults.
//
// ## Quick start
//
//   // Built-in presets:
//   var interp = new Interpreter(false, false, SyntaxRules.nxScript());
//   var interp = new Interpreter(false, false, SyntaxRules.pythonish());
//
//   // Or build a custom ruleset:
//   var rules = new SyntaxRules();
//   rules.addKeywordAlias("fn", "func");
//   rules.addOperatorAlias("not", "!");
//   rules.addOperatorAlias("and", "&&");
//   var interp = new Interpreter(false, false, rules);
//
// ## Feature flags
//
// The boolean flags below describe the *intended* feature set. Most are
// enforced at the **tokenizer level** (operatorAliases / keywordAliases),
// but enforcement in the parser is still a work-in-progress — flags that
// are not yet checked are marked `// TODO: enforce`.
//
// ## Keyword aliases
//
// Map an alternative spelling to the canonical keyword string used in the
// `Tokenizer.keywords` table. Applied during identifier resolution.
//
//   Example:  rules.addKeywordAlias("elif", "elseif")
//             rules.addKeywordAlias("def",  "func")
//
// ## Operator aliases
//
// Map an identifier to an operator string. Applied before keyword lookup.
//
//   Example:  rules.addOperatorAlias("not", "!")
//             rules.addOperatorAlias("and", "&&")
//             rules.addOperatorAlias("or",  "||")
//
// Recognized operator strings: `!`  `&&`  `||`  `==`  `!=`  `??`

/**
 * Configures the syntax dialect for a NxScript interpreter instance.
 *
 * Pass to `Interpreter`, `Tokenizer`, or `Parser` to control which language
 * features are active and how identifiers map to keywords or operators.
 *
 * ### Quick start
 *
 *     var interp = new Interpreter(false, false, SyntaxRules.nxScript());
 *     var interp = new Interpreter(false, false, SyntaxRules.pythonish());
 *
 *     var rules = new SyntaxRules();
 *     rules.addKeywordAlias("fn", "func");
 *     rules.addOperatorAlias("not", "!");
 *
 * ### Feature flags
 *
 * The boolean fields describe the intended feature set. Flags that are not yet
 * enforced by the tokenizer/parser are documented as such inline.
 *
 * ### Keyword aliases
 *
 * Maps an alternative spelling to the canonical keyword string used in
 * `Tokenizer.keywords`. Example: `addKeywordAlias("elif", "elseif")`.
 *
 * ### Operator aliases
 *
 * Maps an identifier to an operator string. Supported targets:
 * `"!"` `"&&"` `"||"` `"=="` `"!="` `"??"`
 * Example: `addOperatorAlias("not", "!")`.
 */
class SyntaxRules {


	/** Allow truthy coercion in conditions: `if (x)` instead of `if (x != null)` */
	public var truthyCoercion:Bool = true;

	/** Allow null coalescing operator: `x ?? y` */
	public var nullCoalescing:Bool = true;

	/** Allow optional chaining: `obj?.field` */
	public var optionalChain:Bool = true;

	/** Allow backtick template strings: `` `hello ${name}` `` */
	public var templateStrings:Bool = true;

	/** Allow shorthand arrow lambdas: `x => x * 2`  and  `(a, b) -> a + b` */
	public var arrowFunctions:Bool = true;

	/** Allow trailing commas in arrays, dicts, and function parameters */
	public var trailingCommas:Bool = true;

	/** Allow braceless control-flow bodies: `if (x) return 1` */
	public var bracelessBodies:Bool = true;

	/** Require explicit semicolons to terminate statements */
	public var strictSemicolons:Bool = false;


	/**
	 * Keyword aliases — maps an alternative spelling to the canonical keyword.
	 *
	 * The canonical keyword must be a key in `Tokenizer.keywords`
	 * (e.g. `"elseif"`, `"func"`, `"match"`).
	 */
	public var keywordAliases:Map<String, String> = new Map();

	/**
	 * Operator aliases — maps an identifier to an operator string.
	 *
	 * Supported targets: `"!"` `"&&"` `"||"` `"=="` `"!="` `"??"`
	 */
	public var operatorAliases:Map<String, String> = new Map();


	/** Creates a new empty `SyntaxRules` instance with all features enabled and no aliases. */
	public function new() {}

	/** Fluent alias registration. Returns `this` for chaining. */
	/**
	 * Registers a keyword alias. Returns `this` for fluent chaining.
	 * @param alias      The alternative spelling to recognise in source.
	 * @param canonical  The canonical keyword string (must exist in `Tokenizer.keywords`).
	 */
	public function addKeywordAlias(alias:String, canonical:String):SyntaxRules {
		keywordAliases.set(alias, canonical);
		return this;
	}

	/** Fluent operator-alias registration. Returns `this` for chaining. */
	/**
	 * Registers an operator alias. Returns `this` for fluent chaining.
	 * @param alias  Identifier to treat as an operator.
	 * @param op     Target operator string: `"!"`, `"&&"`, `"||"`, `"=="`, `"!="`, `"??"`.
	 */
	public function addOperatorAlias(alias:String, op:String):SyntaxRules {
		operatorAliases.set(alias, op);
		return this;
	}


	/**
	 * **NxScript** — the default dialect.
	 *
	 * All features enabled. Accepts both `func` and `function`, plus the
	 * common `elif`/`elsif` spellings for `elseif`.
	 */
	/** Default NxScript dialect — all features on. Accepts `func`/`function`, `elif`/`elsif`/`elseif`, and `switch` as an alias for `match`. */
	public static function nxScript():SyntaxRules {
		var r = new SyntaxRules();
		r.addKeywordAlias("function", "func");
		r.addKeywordAlias("elif",     "elseif");
		r.addKeywordAlias("elsif",    "elseif");
		r.addKeywordAlias("switch",   "match"); // switch → match
		return r;
	}

	/**
	 * **Haxe-style** — leans toward Haxe conventions.
	 *
	 * Uses `function` as the primary keyword; `func` is still accepted.
	 */
	/** Haxe-style dialect. Uses `function` as the primary keyword; `func` is still accepted. */
	public static function haxeStyle():SyntaxRules {
		var r = new SyntaxRules();
		r.addKeywordAlias("func", "function");
		return r;
	}

	/**
	 * **Minimal** — a stripped-down dialect close to plain NxScript.
	 *
	 * Template strings, arrow functions, trailing commas, braceless bodies,
	 * null-coalescing, and optional chaining are all disabled.
	 *
	 * > **Note:** feature-flag enforcement is still in progress.
	 * > Some disabled features may still be accepted by the tokenizer/parser.
	 */
	/**
	 * Minimal dialect with most syntactic sugar disabled.
	 * Feature-flag enforcement is still in progress; some disabled features
	 * may still be accepted by the tokenizer/parser.
	 */
	public static function minimal():SyntaxRules {
		var r = new SyntaxRules();
		r.templateStrings  = false;
		r.arrowFunctions   = false;
		r.trailingCommas   = false;
		r.bracelessBodies  = false;
		r.nullCoalescing   = false;
		r.optionalChain    = false;
		r.truthyCoercion   = true;
		return r;
	}

	/**
	 * **Python-ish** — keyword operators and Python-flavoured spellings.
	 *
	 * - `not` → `!`  |  `and` → `&&`  |  `or` → `||`
	 * - `def` → `func`  |  `elif` → `elseif`
	 * - `None`, `True`, `False` map to `null`, `true`, `false`
	 * - `pass` is accepted as a no-op (maps to `null`)
	 */
	/**
	 * Python-flavoured dialect.
	 * `not`/`and`/`or` as operators; `def`/`elif`/`None`/`True`/`False`/`pass` as keywords.
	 */
	public static function pythonish():SyntaxRules {
		var r = new SyntaxRules();
		r.addOperatorAlias("not", "!");
		r.addOperatorAlias("and", "&&");
		r.addOperatorAlias("or",  "||");
		r.addKeywordAlias("def",   "func");
		r.addKeywordAlias("elif",  "elseif");
		r.addKeywordAlias("None",  "null");
		r.addKeywordAlias("True",  "true");
		r.addKeywordAlias("False", "false");
		r.addKeywordAlias("pass",  "null");
		return r;
	}
}
