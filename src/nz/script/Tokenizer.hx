package nz.script;

import nz.script.Token;

using StringTools;

/**
 * Tokenizer for the script language
 * Converts source code into a stream of tokens
 */
class Tokenizer {
	var input:String;
	var pos:Int = 0;
	var line:Int = 1;
	var col:Int = 1;

	static var keywords = [
		"let" => KLet,
		"var" => KVar,
		"const" => KConst,
		"func" => KFunc,
		"return" => KReturn,
		"if" => KIf,
		"else" => KElse,
		"elseif" => KElseIf,
		"while" => KWhile,
		"for" => KFor,
		"break" => KBreak,
		"continue" => KContinue,
		"in" => KIn,
		"true" => KTrue,
		"false" => KFalse,
		"null" => KNull
	];

	public function new(input:String) {
		this.input = input.replace('\r\n', '\n').replace('\r', '\n');
	}

	public function tokenize():Array<TokenPos> {
		var tokens:Array<TokenPos> = [];

		while (!isEOF()) {
			skipWhitespaceExceptNewline();

			if (isEOF())
				break;

			var startLine = line;
			var startCol = col;
			var token = nextToken();

			if (token != null) {
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
		advance(); // #
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

	function readNumber():Token {
		var start = pos;
		var hasDot = false;

		while (!isEOF() && (isDigit(peek()) || peek() == '.')) {
			if (peek() == '.') {
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
				return TDot;

			case '+':
				return TOperator(OAdd);
			case '*':
				return TOperator(OMul);
			case '%':
				return TOperator(OMod);
			case '~':
				return TOperator(OBitNot);
			case '^':
				return TOperator(OBitXor);

			case '-':
				if (peek() == '>') {
					advance();
					return TArrow;
				}
				return TOperator(OSub);

			case '/':
				return TOperator(ODiv);

			case '=':
				if (peek() == '=') {
					advance();
					return TOperator(OEqual);
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
