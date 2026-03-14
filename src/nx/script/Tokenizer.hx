package nx.script;

import nx.script.Token;

using StringTools;

/**
 * Turns a string of source code into a flat list of tokens.
 * Handles `#` line comments, string literals (with escape sequences),
 * numbers (int and float), operators, and keywords.
 *
 * Normalizes all line endings to `\n` up front because Windows exists
 * and `\r\n` in error messages is deeply unpleasant.
 */
class Tokenizer {
	var input:String;
	var pos:Int = 0;
	var line:Int = 1;
	var col:Int = 1;
	// Queue for multi-token emissions (template string interpolation)
	var pendingTokens:Array<TokenPos> = [];

	static var keywords = [
		"let" => KLet,
		"var" => KVar,
		"moewvar" => KVar,
		"const" => KConst,
		"func" => KFunc,
		"fn" => KFn,
		"fun" => KFun,
		"function" => KFunction,
		"class" => KClass,
		"extends" => KExtends,
		"new" => KNew,
		"this" => KThis,
		"return" => KReturn,
		"if" => KIf,
		"else" => KElse,
		"elseif" => KElseIf,
		"while" => KWhile,
		"for" => KFor,
		"break" => KBreak,
		"continue" => KContinue,
		"in" => KIn,
		"of" => KOf,
		"from" => KFrom,
		"to" => KTo,
		"true" => KTrue,
		"false" => KFalse,
		"null" => KNull,
		"try" => KTry,
		"catch" => KCatch,
		"throw" => KThrow
	];

	public function new(input:String) {
		this.input = input.replace('\r\n', '\n').replace('\r', '\n');
	}

	public function tokenize():Array<TokenPos> {
		var tokens:Array<TokenPos> = [];

		while (!isEOF() || pendingTokens.length > 0) {
			// Drain any tokens queued by template string expansion
			if (pendingTokens.length > 0) {
				for (t in pendingTokens) tokens.push(t);
				pendingTokens = [];
				continue;
			}

			skipWhitespaceExceptNewline();

			if (isEOF())
				break;

			var startLine = line;
			var startCol = col;
			var token = nextToken();

			if (pendingTokens.length > 0) {
				// Template string emitted multiple tokens — first was already pushed via pending
				var allPending = pendingTokens.copy();
				pendingTokens = [];
				for (t in allPending) tokens.push(t);
			} else if (token != null) {
				tokens.push({token: token, line: startLine, col: startCol});
			}
		}

		tokens.push({token: TEOF, line: line, col: col});
		return tokens;
	}

	function nextToken():Token {
		if (isEOF())
			return null;

		var c = peek();

		// Comments (skip them)
		if (c == '#') {
			skipLineComment();
			return null;
		}
		if (c == '/' && peekNext() == '/') {
			skipLineComment();
			return null;
		}
		if (c == '/' && peekNext() == '*') {
			skipBlockComment();
			return null;
		}

		// Newlines
		if (c == '\n') {
			advance();
			line++;
			col = 1;
			return TNewLine;
		}

		// Strings
		if (c == '"' || c == "'") {
			return readString();
		}
		if (c == '`') {
			readTemplateString();
			return null;
		}

		// Numbers
		if (isDigit(c) || (c == '.' && isDigit(peekNext()))) {
			return readNumber();
		}

		// Identifiers and keywords
		if (isAlpha(c) || c == '_') {
			return readIdentifier();
		}

		// Operators and delimiters
		return readOperatorOrDelimiter();
	}

	function skipLineComment():Void {
		var c = advance(); // # or /
		if (c == '/')
			advance(); // the second /

		while (!isEOF() && peek() != '\n') {
			advance();
		}
	}

	function skipBlockComment():Void {
		advance(); // /
		advance(); // *
		while (!isEOF()) {
			if (peek() == '*' && peekNext() == '/') {
				advance(); // *
				advance(); // /
				return;
			}
			if (peek() == '\n') {
				line++;
				col = 0;
			}
			advance();
		}
		throw 'Unterminated block comment at line $line, col $col';
	}

	function readString():Token {
		var quote = advance();
		var value = '';

		while (!isEOF() && peek() != quote) {
			if (peek() == '\\') {
				advance();
				if (isEOF())
					throw 'Unterminated string at line $line, col $col';
				var escaped = advance();
				switch (escaped) {
					case 'n':
						value += '\n';
					case 't':
						value += '\t';
					case 'r':
						value += '\r';
					case '\\':
						value += '\\';
					case '"':
						value += '"';
					case "'":
						value += "'";
					default:
						value += escaped;
				}
			} else {
				if (peek() == '\n') {
					line++;
					col = 0;
				}
				value += advance();
			}
		}

		if (isEOF())
			throw 'Unterminated string at line $line, col $col';

		advance(); // closing quote
		return TString(value);
	}

	/**
	 * Template strings: `Hello ${name}, you are ${age} years old!`
	 * Expands into a sequence of tokens representing string concatenation.
	 * e.g.:  TString("Hello ") TOperator(OAdd) TIdentifier("name") TOperator(OAdd) TString(", you are ") ...
	 */
	function readTemplateString():Void {
		advance(); // consume opening `
		var startLine = line;
		var startCol  = col;

		var parts:Array<TokenPos> = [];
		var hasContent = false;

		inline function pushStr(s:String, l:Int, c:Int) {
			if (s.length > 0) {
				if (hasContent) parts.push({token: TOperator(OAdd), line: l, col: c});
				parts.push({token: TString(s), line: l, col: c});
				hasContent = true;
			}
		}

		var literal = new StringBuf();
		var litLine = line; var litCol = col;

		while (!isEOF() && peek() != '`') {
			if (peek() == '$' && peekNext() == '{') {
				// Flush accumulated literal
				pushStr(literal.toString(), litLine, litCol);
				literal = new StringBuf();
				advance(); // $
				advance(); // {
				// Tokenize until matching }
				var depth = 1;
				var exprStart = pos;
				var exprTokens:Array<TokenPos> = [];
				var innerizer = new Tokenizer(input.substring(exprStart));
				// We need the raw sub-tokenizer — but since we share pos/line/col
				// we instead walk manually and collect chars
				var exprBuf = new StringBuf();
				while (!isEOF() && depth > 0) {
					var c = peek();
					if (c == '{') depth++;
					else if (c == '}') { depth--; if (depth == 0) { advance(); break; } }
					if (c == '\n') { line++; col = 0; }
					exprBuf.add(advance());
				}
				// Re-tokenize the expression fragment
				var exprStr = exprBuf.toString();
				var subTok = new Tokenizer(exprStr);
				var subTokens = subTok.tokenize();
				// subTokens ends with EOF — strip it
				if (subTokens.length > 1) {
					var exprToks = subTokens.slice(0, subTokens.length - 1);
					// Wrap in parens: TLeftParen, ...expr..., TRightParen
					if (hasContent) parts.push({token: TOperator(OAdd), line: line, col: col});
					parts.push({token: TLeftParen, line: line, col: col});
					for (t in exprToks) parts.push(t);
					parts.push({token: TRightParen, line: line, col: col});
					hasContent = true;
				}
				litLine = line; litCol = col;
			} else if (peek() == '\\') {
				advance();
				if (!isEOF()) {
					switch (advance()) {
						case 'n': literal.add('\n');
						case 't': literal.add('\t');
						case 'r': literal.add('\r');
						case '\\': literal.add('\\');
						case '`': literal.add('`');
						case c: literal.add(c);
					}
				}
			} else {
				if (peek() == '\n') { line++; col = 0; }
				literal.add(advance());
			}
		}

		if (!isEOF()) advance(); // consume closing `

		// Flush remaining literal
		pushStr(literal.toString(), litLine, litCol);

		// If empty template string
		if (parts.length == 0) {
			pendingTokens.push({token: TString(""), line: startLine, col: startCol});
		} else {
			for (p in parts) pendingTokens.push(p);
		}
	}

	function readNumber():Token {
		var start = pos;
		var hasDot = false;

		while (!isEOF() && (isDigit(peek()) || peek() == '.')) {
			if (peek() == '.') {
				// Range operator support: stop number token before `...`
				if (peekNext() == '.')
					break;
				if (hasDot)
					break;
				hasDot = true;
			}
			advance();
		}

		var numStr = input.substring(start, pos);
		return TNumber(Std.parseFloat(numStr));
	}

	function readIdentifier():Token {
		var start = pos;

		while (!isEOF() && (isAlphaNumeric(peek()) || peek() == '_')) {
			advance();
		}

		var id = input.substring(start, pos);

		// Check if it's a keyword
		if (keywords.exists(id)) {
			var keyword = keywords.get(id);
			// Handle boolean literals
			if (keyword == KTrue)
				return TBool(true);
			if (keyword == KFalse)
				return TBool(false);
			if (keyword == KNull)
				return TNull;
			return TKeyword(keyword);
		}

		return TIdentifier(id);
	}

	function readOperatorOrDelimiter():Token {
		var c = advance();

		switch (c) {
			case '(':
				return TLeftParen;
			case ')':
				return TRightParen;
			case '{':
				return TLeftBrace;
			case '}':
				return TRightBrace;
			case '[':
				return TLeftBracket;
			case ']':
				return TRightBracket;
			case ',':
				return TComma;
			case ';':
				return TSemicolon;
			case ':':
				return TColon;
			case '.':
				if (peek() == '.' && peekNext() == '.') {
					advance();
					advance();
					return TRange;
				}
				return TDot;

			case '+':
				if (peek() == '+') {
					advance();
					return TOperator(OIncrement);
				}
				if (peek() == '=') {
					advance();
					return TOperator(OAddAssign);
				}
				return TOperator(OAdd);
			case '*':
				if (peek() == '=') {
					advance();
					return TOperator(OMulAssign);
				}
				return TOperator(OMul);
			case '%':
				if (peek() == '=') {
					advance();
					return TOperator(OModAssign);
				}
				return TOperator(OMod);
			case '~':
				return TOperator(OBitNot);
			case '^':
				return TOperator(OBitXor);

			case '-':
				if (peek() == '-') {
					advance();
					return TOperator(ODecrement);
				}
				if (peek() == '>') {
					advance();
					return TArrow;
				}
				if (peek() == '=') {
					advance();
					return TOperator(OSubAssign);
				}
				return TOperator(OSub);

			case '/':
				if (peek() == '=') {
					advance();
					return TOperator(ODivAssign);
				}
				return TOperator(ODiv);

			case '=':
				if (peek() == '=') {
					advance();
					return TOperator(OEqual);
				}
				if (peek() == '>') {
					advance();
					return TFatArrow;
				}
				return TOperator(OAssign);

			case '!':
				if (peek() == '=') {
					advance();
					return TOperator(ONotEqual);
				}
				return TOperator(ONot);

			case '<':
				if (peek() == '=') {
					advance();
					return TOperator(OLessEq);
				}
				if (peek() == '<') {
					advance();
					return TOperator(OShiftLeft);
				}
				return TOperator(OLess);

			case '>':
				if (peek() == '=') {
					advance();
					return TOperator(OGreaterEq);
				}
				if (peek() == '>') {
					advance();
					return TOperator(OShiftRight);
				}
				return TOperator(OGreater);

			case '&':
				if (peek() == '&') {
					advance();
					return TOperator(OAnd);
				}
				return TOperator(OBitAnd);

			case '|':
				if (peek() == '|') {
					advance();
					return TOperator(OOr);
				}
				return TOperator(OBitOr);

			default:
				throw 'Unexpected character "$c" at line $line, col $col';
		}
	}

	inline function peek():String {
		return isEOF() ? '' : input.charAt(pos);
	}

	inline function peekNext():String {
		return (pos + 1 >= input.length) ? '' : input.charAt(pos + 1);
	}

	inline function advance():String {
		if (isEOF())
			return '';
		var c = input.charAt(pos);
		pos++;
		col++;
		return c;
	}

	inline function isEOF():Bool {
		return pos >= input.length;
	}

	function skipWhitespaceExceptNewline() {
		while (!isEOF()) {
			var c = peek();
			if (c == ' ' || c == '\t' || c == '\r') {
				advance();
			} else {
				break;
			}
		}
	}

	inline function isDigit(c:String):Bool {
		return c >= '0' && c <= '9';
	}

	inline function isAlpha(c:String):Bool {
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
	}

	inline function isAlphaNumeric(c:String):Bool {
		return isAlpha(c) || isDigit(c);
	}
}
