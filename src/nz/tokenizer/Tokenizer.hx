package nz.tokenizer;

import nz.tokenizer.Token;
import nz.storage.TokenStorage;

using StringTools;

/**
 * Tokenizer for the dialogue language
 * Converts source code into a stream of tokens
 */
class Tokenizer {
	var input:String;
	var pos:Int = 0;
	var line:Int = 1;
	var col:Int = 1;
	var storage:TokenStorage;

	static var keywords = ["var", "func", "if", "elseif", "else", "switch", "case", "end", "return"];
	static var operators = ["+", "-", "*", "/", "==", "!=", "<=", ">=", "<", ">", "and", "or"];

	public function new(input:String) {
		this.input = input.replace('\r\n', '\n').replace('\r', '\n');
		this.storage = new TokenStorage();
	}

	public function tokenize():Array<TokenPos> {
		var tokens:Array<TokenPos> = [];
		var lastWasNewLine = false;

		while (!isEOF()) {
			skipWhitespace();

			if (isEOF())
				break;

			var token = nextToken();
			if (token != null) {
				// Skip consecutive newlines
				if (Type.enumEq(token, TNewLine)) {
					if (!lastWasNewLine) {
						tokens.push({token: token, line: line, col: col});
						lastWasNewLine = true;
					}
				} else {
					tokens.push({token: token, line: line, col: col});
					lastWasNewLine = false;
				}
			}
		}

		tokens.push({token: TEndOfFile, line: line, col: col});
		return tokens;
	}

	private function nextToken():Token {
		if (peek() == '#')
			return readComment();

		if (peek() == '\n') {
			advance();
			return TNewLine;
		}

		// @call directive
		if (peek() == '@') {
			return readAtCall();
		}

		// Numbers (only if not part of a dialog line)
		if (isDigit(peek()) && isStartOfStatement()) {
			return readNumber();
		}

		if (peek() == '"' || peek() == "'") {
			return readString();
		}

		if (isAlpha(peek()) && isStartOfStatement()) {
			var word = peekWord();
			if (keywords.contains(word)) {
				return readKeywordOrIdentifier();
			}
		}

		// Special symbols that indicate code rather than dialog
		var ch = peek();
		switch (ch) {
			case '(':
				advance();
				return TLParen;
			case ')':
				advance();
				return TRParen;
			case ',':
				advance();
				return TComma;
			case '=':
				// Check for == operator
				if (peek(1) == '=') {
					advance(2);
					return TOp('==');
				}
				advance();
				return TAssign;
			default:
				// Two-character operators
				if (pos + 1 < input.length) {
					var twoChar = input.substr(pos, 2);
					if (operators.contains(twoChar)) {
						advance(2);
						return TOp(twoChar);
					}
				}

				// Single-character operators (only in expressions)
				if (operators.contains(ch)) {
					advance();
					return TOp(ch);
				}

				// Otherwise, it's a dialog line
				return readDialog();
		}
	}

	private function isStartOfStatement():Bool {
		// Check if we're at the beginning of a line (after whitespace)
		if (pos == 0)
			return true;

		var i = pos - 1;
		while (i >= 0) {
			var ch = input.charAt(i);
			if (ch == '\n')
				return true;
			if (ch != ' ' && ch != '\t' && ch != '\r')
				return false;
			i--;
		}
		return true;
	}

	private function peekWord():String {
		var word = "";
		var i = 0;
		while (pos + i < input.length) {
			var ch = input.charAt(pos + i);
			if (!isAlphaNum(ch) && ch != '_')
				break;
			word += ch;
			i++;
		}
		return word;
	}

	private function readComment():Token {
		advance(); // skip #
		var text = "";
		while (!isEOF() && peek() != '\n') {
			text += advance();
		}
		return TComment(text.trim());
	}

	private function readAtCall():Token {
		advance(); // skip @

		// Read the function name
		var name = "";
		while (!isEOF() && (isAlphaNum(peek()) || peek() == '_')) {
			name += advance();
		}

		skipWhitespace();

		// Read arguments
		var args:Array<String> = [];
		while (!isEOF() && peek() != '\n') {
			skipWhitespace();

			if (peek() == '"') {
				// String argument with quotes
				advance(); // skip opening "
				var arg = "";
				while (!isEOF() && peek() != '"') {
					arg += advance();
				}
				if (!isEOF())
					advance(); // skip closing "
				args.push(arg);
			} else {
				// Simple argument without quotes
				var arg = "";
				while (!isEOF() && peek() != ' ' && peek() != '\t' && peek() != '\n') {
					arg += advance();
				}
				if (arg.length > 0) {
					args.push(arg);
				}
			}

			skipWhitespace();
		}

		return TAtCall(name, args);
	}

	private function readNumber():Token {
		var numStr = "";
		while (!isEOF() && (isDigit(peek()) || peek() == '.')) {
			numStr += advance();
		}
		return TNumber(Std.parseFloat(numStr));
	}

	private function readString():Token {
		var quote = advance(); // opening quote
		var str = "";
		while (!isEOF() && peek() != quote) {
			str += advance();
		}
		if (!isEOF())
			advance(); // closing quote
		return TString(str);
	}

	private function readKeywordOrIdentifier():Token {
		var word = "";
		while (!isEOF() && (isAlphaNum(peek()) || peek() == '_')) {
			word += advance();
		}

		// Check if it's a keyword
		if (keywords.contains(word)) {
			return handleKeyword(word);
		}

		// Check for boolean
		if (word == "true")
			return TBool(true);
		if (word == "false")
			return TBool(false);

		return TIdentifier(word);
	}

	private function handleKeyword(keyword:String):Token {
		skipWhitespace();

		switch (keyword) {
			case "var":
				return parseVar();
			case "func":
				return parseFunc();
			case "if":
				return parseIf();
			case "elseif":
				return parseElseIf();
			case "else":
				return TElse;
			case "switch":
				return parseSwitch();
			case "case":
				return parseCase();
			case "end":
				return TEnd;
			case "return":
				return parseReturn();
			default:
				return TIdentifier(keyword);
		}
	}

	private function parseVar():Token {
		skipWhitespace();
		var name = "";
		while (!isEOF() && (isAlphaNum(peek()) || peek() == '_')) {
			name += advance();
		}

		skipWhitespace();

		// Check for assignment
		var value:Dynamic = null;
		if (peek() == '=') {
			advance(); // skip =
			skipWhitespace();
			value = readExpression();
		}

		return TVar(name, value);
	}

	private function parseFunc():Token {
		skipWhitespace();
		var name = "";
		while (!isEOF() && (isAlphaNum(peek()) || peek() == '_')) {
			name += advance();
		}

		skipWhitespace();

		var params:Array<String> = [];
		if (peek() == '(') {
			advance(); // skip (
			skipWhitespace();

			while (!isEOF() && peek() != ')') {
				var param = "";
				while (!isEOF() && peek() != ',' && peek() != ')' && peek() != ' ') {
					param += advance();
				}
				if (param.length > 0) {
					params.push(param);
				}
				skipWhitespace();
				if (peek() == ',') {
					advance();
					skipWhitespace();
				}
			}

			if (peek() == ')')
				advance(); // skip )
		}

		return TFunc(name, params);
	}

	private function parseIf():Token {
		skipWhitespace();
		if (peek() == '(')
			advance(); // skip optional (
		skipWhitespace();

		var condition = readExpression();

		skipWhitespace();
		if (peek() == ')')
			advance(); // skip optional )

		return TIf(condition);
	}

	private function parseElseIf():Token {
		skipWhitespace();
		if (peek() == '(')
			advance(); // skip optional (
		skipWhitespace();

		var condition = readExpression();

		skipWhitespace();
		if (peek() == ')')
			advance(); // skip optional )

		return TElseIf(condition);
	}

	private function parseSwitch():Token {
		skipWhitespace();
		if (peek() == '(')
			advance(); // skip optional (
		skipWhitespace();

		var value = readExpression();

		skipWhitespace();
		if (peek() == ')')
			advance(); // skip optional )

		return TSwitch(value);
	}

	private function parseCase():Token {
		skipWhitespace();
		var value = readExpression();
		return TCase(value);
	}

	private function parseReturn():Token {
		skipWhitespace();
		var expr = readExpression();
		return TReturn(expr);
	}

	private function readExpression():String {
		var expr = "";
		var depth = 0;

		while (!isEOF()) {
			var ch = peek();

			if (ch == '(')
				depth++;
			if (ch == ')') {
				if (depth == 0)
					break;
				depth--;
			}

			if (depth == 0 && (ch == '\n' || ch == '{'))
				break;

			expr += advance();
		}

		return expr.trim();
	}

	private function readDialog():Token {
		var text = "";

		while (!isEOF()) {
			var ch = peek();

			// Stop at newline or certain keywords at start of line
			if (ch == '\n')
				break;

			text += advance();
		}

		text = text.trim();
		if (text.length == 0)
			return null;

		return TDialog(text);
	}

	// Helper functions
	private function peek(offset:Int = 0):String {
		var p = pos + offset;
		return (p < input.length) ? input.charAt(p) : "";
	}

	private function advance(n:Int = 1):String {
		var result = "";
		for (i in 0...n) {
			if (pos < input.length) {
				var ch = input.charAt(pos);
				result += ch;
				pos++;

				if (ch == '\n') {
					line++;
					col = 1;
				} else {
					col++;
				}
			}
		}
		return result;
	}

	private function skipWhitespace():Void {
		while (!isEOF() && (peek() == ' ' || peek() == '\t' || peek() == '\r')) {
			advance();
		}
	}

	private function isEOF():Bool {
		return pos >= input.length;
	}

	private function isDigit(ch:String):Bool {
		return ch >= '0' && ch <= '9';
	}

	private function isAlpha(ch:String):Bool {
		return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
	}

	private function isAlphaNum(ch:String):Bool {
		return isAlpha(ch) || isDigit(ch);
	}

	// Save tokens to file
	public function saveTokens(tokens:Array<TokenPos>, filePath:String):Void {
		storage.save(tokens, filePath);
	}
}
