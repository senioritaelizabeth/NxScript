package nz.dialogue.parser;

import nz.dialogue.tokenizer.Token;
import nz.dialogue.parser.Block;

using StringTools;

/**
 * Parser for the dialogue language
 * Converts tokens into an Abstract Syntax Tree (AST)
 */
class Parser {
	var tokens:Array<TokenPos>;
	var pos:Int = 0;

	public function new(tokens:Array<TokenPos>) {
		this.tokens = tokens;
	}

	public function parse():Array<Block> {
		var blocks:Array<Block> = [];

		while (!isEOF()) {
			skipNewLines();
			if (isEOF())
				break;

			var block = parseBlock();
			if (block != null) {
				blocks.push(block);
			}
		}

		return blocks;
	}

	private function parseBlock():Block {
		var token = current();

		return switch (token.token) {
			case TComment(text):
				advance();
				BComment(text);

			case TKeyword(keyword):
				switch (keyword) {
					case KVar:
						parseVar();

					case KFunc:
						parseFunc();

					case KIf:
						parseIfBlock();

					case KSwitch:
						parseSwitchBlock();

					case KReturn:
						parseReturn();

					default:
						trace('Unexpected keyword: ${keyword}');
						advance();
						null;
				}

			case TAtCommand(name):
				parseAtCommand(name);

			case TDialog(text):
				advance();
				BDialog(text);

			case TNewLine:
				advance();
				null;

			default:
				trace('Unexpected token: ${token.token}');
				advance();
				null;
		}
	}

	private function parseVar():Block {
		advance(); // skip 'var'
		skipWhitespace();

		// Read identifier
		var name = switch (current().token) {
			case TIdentifier(id): id;
			default: "";
		}
		advance();

		skipWhitespace();

		// Check for assignment
		var value:Dynamic = null;
		if (!isEOF() && Type.enumEq(current().token, TAssign)) {
			advance(); // skip '='
			skipWhitespace();
			value = readExpression();
		}

		return BVar(name, value);
	}

	private function parseFunc():Block {
		advance(); // skip 'func'
		skipWhitespace();

		// Read function name
		var name = switch (current().token) {
			case TIdentifier(id): id;
			default: "";
		}
		advance();

		skipWhitespace();

		// Read parameters
		var params:Array<String> = [];
		if (!isEOF() && Type.enumEq(current().token, TLParen)) {
			advance(); // skip '('
			skipWhitespace();

			while (!isEOF() && !Type.enumEq(current().token, TRParen)) {
				switch (current().token) {
					case TIdentifier(id):
						params.push(id);
						advance();
					default:
						advance();
				}

				skipWhitespace();

				if (!isEOF() && Type.enumEq(current().token, TComma)) {
					advance();
					skipWhitespace();
				}
			}

			if (!isEOF() && Type.enumEq(current().token, TRParen)) {
				advance(); // skip ')'
			}
		}

		skipNewLines();
		var body = parseUntilEnd();
		return BFunc(name, params, body);
	}

	private function parseReturn():Block {
		advance(); // skip 'return'
		skipWhitespace();
		var expr = readExpression();
		return BReturn(expr);
	}

	private function parseAtCommand(name:String):Block {
		advance(); // skip @command token
		skipWhitespace();

		// Read all arguments until newline
		var args:Array<String> = [];
		while (!isEOF() && !Type.enumEq(current().token, TNewLine) && !Type.enumEq(current().token, TEndOfFile)) {
			switch (current().token) {
				case TString(str):
					args.push(str);
					advance();
				case TIdentifier(id):
					args.push(id);
					advance();
				case TNumber(n):
					args.push(Std.string(n));
					advance();
				case TBool(b):
					args.push(Std.string(b));
					advance();
				default:
					advance();
			}
			skipWhitespace();
		}

		return BAtCall(name, args);
	}

	private function readExpression():String {
		var expr = "";

		while (!isEOF()) {
			var token = current().token;

			switch (token) {
				case TNewLine | TEndOfFile:
					break;

				case TIdentifier(id):
					expr += id;
					advance();

				case TNumber(n):
					expr += Std.string(n);
					advance();

				case TString(str):
					expr += '"${str}"';
					advance();

				case TBool(b):
					expr += Std.string(b);
					advance();

				case TOp(op):
					var opStr = switch (op) {
						case OAdd: "+";
						case OSub: "-";
						case OMul: "*";
						case ODiv: "/";
						case OEqual: "==";
						case ONotEqual: "!=";
						case OLess: "<";
						case OGreater: ">";
						case OLessEq: "<=";
						case OGreaterEq: ">=";
						case OAnd: "&&";
						case OOr: "||";
						case ONot: "!";
					};
					expr += opStr;
					advance();

				case TAssign:
					expr += "=";
					advance();

				case TLParen:
					expr += "(";
					advance();

				case TRParen:
					// Check if this closes our expression context
					if (expr.length > 0) {
						var depth = 0;
						for (i in 0...expr.length) {
							if (expr.charAt(i) == '(')
								depth++;
							if (expr.charAt(i) == ')')
								depth--;
						}
						if (depth <= 0) {
							break;
						}
					}
					expr += ")";
					advance();

				case TComma:
					break;

				case TKeyword(_):
					break;

				default:
					advance();
			}
		}

		return expr.trim();
	}

	private function skipWhitespace():Void {
		// Whitespace is not tokenized, so this is a no-op in the new design
		// But we keep it for compatibility
	}

	private function parseIfBlock():Block {
		advance(); // skip 'if'
		skipWhitespace();

		// Read condition - might have optional parentheses
		if (!isEOF() && Type.enumEq(current().token, TLParen)) {
			advance(); // skip '('
		}

		var condition = readExpression();

		skipWhitespace();
		if (!isEOF() && Type.enumEq(current().token, TRParen)) {
			advance(); // skip ')'
		}

		skipNewLines();

		// Parse then block
		var thenBlock:Array<Block> = [];
		while (!isEOF() && !isElseIf() && !isElse() && !isEnd()) {
			skipNewLines();
			if (isEOF() || isElseIf() || isElse() || isEnd())
				break;

			var block = parseBlock();
			if (block != null) {
				thenBlock.push(block);
			}
		}

		// Parse elseif blocks
		var elseIfs:Array<ElseIfBlock> = [];
		while (isElseIf()) {
			advance(); // skip 'elseif'
			skipWhitespace();

			// Read condition
			if (!isEOF() && Type.enumEq(current().token, TLParen)) {
				advance(); // skip '('
			}

			var elseIfCondition = readExpression();

			skipWhitespace();
			if (!isEOF() && Type.enumEq(current().token, TRParen)) {
				advance(); // skip ')'
			}

			skipNewLines();

			var elseIfBody:Array<Block> = [];
			while (!isEOF() && !isElseIf() && !isElse() && !isEnd()) {
				skipNewLines();
				if (isEOF() || isElseIf() || isElse() || isEnd())
					break;

				var block = parseBlock();
				if (block != null) {
					elseIfBody.push(block);
				}
			}

			elseIfs.push({condition: elseIfCondition, body: elseIfBody});
		}

		// Parse else block
		var elseBlock:Array<Block> = [];
		if (isElse()) {
			advance();
			skipNewLines();

			while (!isEOF() && !isEnd()) {
				skipNewLines();
				if (isEOF() || isEnd())
					break;

				var block = parseBlock();
				if (block != null) {
					elseBlock.push(block);
				}
			}
		}

		// Consume 'end'
		if (isEnd()) {
			advance();
		}

		return BIf(condition, thenBlock, elseIfs, elseBlock);
	}

	private function parseSwitchBlock():Block {
		advance(); // skip 'switch'
		skipWhitespace();

		// Read value - might have optional parentheses
		if (!isEOF() && Type.enumEq(current().token, TLParen)) {
			advance(); // skip '('
		}

		var value = readExpression();

		skipWhitespace();
		if (!isEOF() && Type.enumEq(current().token, TRParen)) {
			advance(); // skip ')'
		}

		skipNewLines();

		var cases:Array<CaseBlock> = [];

		while (!isEOF() && !isEnd()) {
			skipNewLines();
			if (isEOF() || isEnd())
				break;

			if (isCase()) {
				advance(); // skip 'case'
				skipWhitespace();

				var caseValue = readExpression();

				skipNewLines();

				var caseBody:Array<Block> = [];
				while (!isEOF() && !isCase() && !isEnd()) {
					skipNewLines();
					if (isEOF() || isCase() || isEnd())
						break;

					var block = parseBlock();
					if (block != null) {
						caseBody.push(block);
					}
				}

				cases.push({value: caseValue, body: caseBody});
			} else {
				advance();
			}
		}

		// Consume 'end'
		if (isEnd()) {
			advance();
		}

		return BSwitch(value, cases);
	}

	private function parseUntilEnd():Array<Block> {
		var blocks:Array<Block> = [];

		while (!isEOF() && !isEnd()) {
			skipNewLines();
			if (isEOF() || isEnd())
				break;

			var block = parseBlock();
			if (block != null) {
				blocks.push(block);
			}
		}

		// Consume 'end'
		if (isEnd()) {
			advance();
		}

		return blocks;
	}

	// Helper functions
	private function current():TokenPos {
		return tokens[pos];
	}

	private function peek(offset:Int = 1):TokenPos {
		var p = pos + offset;
		return (p < tokens.length) ? tokens[p] : tokens[tokens.length - 1];
	}

	private function advance():Void {
		if (pos < tokens.length) {
			pos++;
		}
	}

	private function isEOF():Bool {
		return pos >= tokens.length || Type.enumEq(current().token, TEndOfFile);
	}

	private function skipNewLines():Void {
		while (!isEOF() && Type.enumEq(current().token, TNewLine)) {
			advance();
		}
	}

	private function isEnd():Bool {
		return !isEOF() && switch (current().token) {
			case TKeyword(KEnd): true;
			default: false;
		};
	}

	private function isElse():Bool {
		return !isEOF() && switch (current().token) {
			case TKeyword(KElse): true;
			default: false;
		};
	}

	private function isElseIf():Bool {
		return !isEOF() && switch (current().token) {
			case TKeyword(KElseIf): true;
			default: false;
		};
	}

	private function isCase():Bool {
		return !isEOF() && switch (current().token) {
			case TKeyword(KCase): true;
			default: false;
		};
	}
}
