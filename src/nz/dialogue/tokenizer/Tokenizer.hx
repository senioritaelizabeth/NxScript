package nz.dialogue.tokenizer;

import nz.dialogue.tokenizer.Token;
import nz.dialogue.storage.TokenStorage;

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
	var inCodeMode:Bool = false; // Track if we're parsing code tokens

	static var keywords = ["var", "func", "if", "elseif", "else", "switch", "case", "end", "return"];

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
			inCodeMode = false; // Reset at end of line
			return TNewLine;
		}

		// @call directive
		if (peek() == '@') {
			inCodeMode = true;
			return readAtCall();
		}

		// Numbers (only if not part of a dialog line)
		if (isDigit(peek()) && (isStartOfStatement() || inCodeMode)) {
			return readNumber();
		}

		if (peek() == '"' || peek() == "'") {
			return readString();
		}

		if (isAlpha(peek()) && isStartOfStatement()) {
			var word = peekWord();
			if (keywords.contains(word)) {
				inCodeMode = true; // We're starting code parsing
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
					return TOp(OEqual);
				}
				advance();
				return TAssign;
			case '!':
				// Check for != operator
				if (peek(1) == '=') {
					advance(2);
					return TOp(ONotEqual);
				}
				advance();
				return TOp(ONot);
			case '<':
				// Check for <= operator
				if (peek(1) == '=') {
					advance(2);
					return TOp(OLessEq);
				}
				advance();
				return TOp(OLess);
			case '>':
				// Check for >= operator
				if (peek(1) == '=') {
					advance(2);
					return TOp(OGreaterEq);
				}
				advance();
				return TOp(OGreater);
			case '&':
				// Check for && operator
				if (peek(1) == '&') {
					advance(2);
					return TOp(OAnd);
				}
				advance();
				return TDialog(readDialogText());
			case '|':
				// Check for || operator
				if (peek(1) == '|') {
					advance(2);
					return TOp(OOr);
				}
				advance();
				return TDialog(readDialogText());
			case '+':
				advance();
				return TOp(OAdd);
			case '-':
				advance();
				return TOp(OSub);
			case '*':
				advance();
				return TOp(OMul);
			case '/':
				advance();
				return TOp(ODiv);
			default:
				// If we're in code mode (after keywords, operators, etc.), read identifiers
				if (isAlpha(ch) && inCodeMode) {
					return readKeywordOrIdentifier();
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

		return TAtCommand(name);
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

		// Check for logical operators (word form)
		switch (word) {
			case "and":
				return TOp(OAnd);
			case "or":
				return TOp(OOr);
			case "not":
				return TOp(ONot);
		}

		// Check for boolean
		if (word == "true")
			return TBool(true);
		if (word == "false")
			return TBool(false);

		return TIdentifier(word);
	}

	private function handleKeyword(keyword:String):Token {
		// Simply return the keyword token, let parser handle the rest
		switch (keyword) {
			case "var":
				return TKeyword(KVar);
			case "func":
				return TKeyword(KFunc);
			case "if":
				return TKeyword(KIf);
			case "elseif":
				return TKeyword(KElseIf);
			case "else":
				return TKeyword(KElse);
			case "switch":
				return TKeyword(KSwitch);
			case "case":
				return TKeyword(KCase);
			case "end":
				return TKeyword(KEnd);
			case "return":
				return TKeyword(KReturn);
			default:
				return TIdentifier(keyword);
		}
	}

	private function readDialog():Token {
		var text = readDialogText();
		text = text.trim();
		if (text.length == 0)
			return null;
		return TDialog(text);
	}

	private function readDialogText():String {
		var text = "";

		while (!isEOF()) {
			var ch = peek();

			// Stop at newline or certain keywords at start of line
			if (ch == '\n')
				break;

			text += advance();
		}

		return text;
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
