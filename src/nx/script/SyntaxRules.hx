package nx.script;

/**
 * SyntaxRules — configures how the Tokenizer and Parser interpret source text.
 *
 * Pass to Interpreter constructor or set on Tokenizer/Parser directly.
 *
 *   // Use built-in presets:
 *   var interp = new Interpreter(SyntaxRules.nxScript());
 *   var interp = new Interpreter(SyntaxRules.haxeStyle());
 *
 *   // Or build a custom ruleset:
 *   var rules = new SyntaxRules();
 *   rules.addKeywordAlias("fn", "func");
 *   rules.addKeywordAlias("let", "var");
 *   rules.addOperatorAlias("not", "!");
 *   rules.addOperatorAlias("and", "&&");
 *   rules.addOperatorAlias("or", "||");
 *   var interp = new Interpreter(rules);
 */
class SyntaxRules {
	// -- Feature toggles --

	/** Allow truthy coercion in if/while/for: if (x) instead of if (x != null) */
	public var truthyCoercion:Bool = true;

	/** Allow null coalescing: x ?? y */
	public var nullCoalescing:Bool = true;

	/** Allow optional chaining: obj?.field */
	public var optionalChain:Bool = true;

	/** Allow template strings: `hello ${name}` */
	public var templateStrings:Bool = true;

	/** Allow shorthand lambdas: x => x * 2 */
	public var arrowFunctions:Bool = true;

	/** Allow trailing commas in arrays, dicts, function params */
	public var trailingCommas:Bool = true;

	/** Allow braceless control flow: if (x) stmt */
	public var bracelessBodies:Bool = true;

	/** Require semicolons (strict mode) */
	public var strictSemicolons:Bool = false;

	// -- Aliases ---

	/**
	 * Keyword aliases: maps an alternative spelling to the canonical keyword.
	 * e.g. "fn" → "func", "function" → "func", "let" → "var"
	 * Applied in the Tokenizer when an identifier matches an alias key.
	 */
	public var keywordAliases:Map<String, String> = new Map();

	/**
	 * Operator aliases: maps an identifier string to an operator string.
	 * e.g. "not" → "!", "and" → "&&", "or" → "||"
	 * Applied in the Tokenizer when an identifier matches an alias key.
	 * Value must be a recognized operator string.
	 */
	public var operatorAliases:Map<String, String> = new Map();

	// --- construction ---

	public function new() {}

	public function addKeywordAlias(alias:String, canonical:String):SyntaxRules {
		keywordAliases.set(alias, canonical);
		return this;
	}

	public function addOperatorAlias(alias:String, op:String):SyntaxRules {
		operatorAliases.set(alias, op);
		return this;
	}

	// --- presets ---

	/**
	 * Default NxScript ruleset — all features on, NxScript keywords.
	 */
	public static function nxScript():SyntaxRules {
		var r = new SyntaxRules();
		r.keywordAliases.set("function", "func");  // accept both
		r.keywordAliases.set("elsif", "elseif");
		r.keywordAliases.set("elif", "elseif");
		return r;
	}

	/**
	 * Haxe-style ruleset — keywords match Haxe conventions.
	 */
	public static function haxeStyle():SyntaxRules {
		var r = new SyntaxRules();
		r.strictSemicolons    = true;
		r.keywordAliases.set("func", "function");   // func → function (reverse)
		r.keywordAliases.set("function", "func");   // keep function working too
		return r;
	}

	/**
	 * Minimal ruleset — close to plain NxScript with no extras.
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
	 * Python-ish flavour — keyword operators.
	 */
	public static function pythonish():SyntaxRules {
		var r = new SyntaxRules();
		r.addOperatorAlias("not", "!");
		r.addOperatorAlias("and", "&&");
		r.addOperatorAlias("or",  "||");
		r.addKeywordAlias("def",  "func");
		r.addKeywordAlias("elif", "elseif");
		r.addKeywordAlias("None", "null");
		r.addKeywordAlias("True", "true");
		r.addKeywordAlias("False","false");
		r.addKeywordAlias("pass", "null"); // no-op expression
		return r;
	}
}
