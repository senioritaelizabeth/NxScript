package nz.parser;

import nz.tokenizer.Token;
import nz.parser.Block;

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

			case TVar(name, value):
				advance();
				BVar(name, value);

			case TFunc(name, params):
				advance();
				skipNewLines();
				var body = parseUntilEnd();
				BFunc(name, params, body);

			case TIf(condition):
				parseIfBlock();

			case TSwitch(value):
				parseSwitchBlock();

			case TReturn(expr):
				advance();
				BReturn(expr);

			case TAtCall(name, args):
				advance();
				BAtCall(name, args);

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

	private function parseIfBlock():Block {
		var ifToken = current();
		var condition = switch (ifToken.token) {
			case TIf(cond): cond;
			default: "";
		}
		advance();
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
			var elseIfToken = current();
			var elseIfCondition = switch (elseIfToken.token) {
				case TElseIf(cond): cond;
				default: "";
			}
			advance();
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
		var switchToken = current();
		var value = switch (switchToken.token) {
			case TSwitch(val): val;
			default: "";
		}
		advance();
		skipNewLines();

		var cases:Array<CaseBlock> = [];

		while (!isEOF() && !isEnd()) {
			skipNewLines();
			if (isEOF() || isEnd())
				break;

			if (isCase()) {
				var caseToken = current();
				var caseValue = switch (caseToken.token) {
					case TCase(val): val;
					default: "";
				}
				advance();
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
		return !isEOF() && Type.enumEq(current().token, TEnd);
	}

	private function isElse():Bool {
		return !isEOF() && Type.enumEq(current().token, TElse);
	}

	private function isElseIf():Bool {
		return !isEOF() && switch (current().token) {
			case TElseIf(_): true;
			default: false;
		}}

	private function isCase():Bool {
		return !isEOF() && switch (current().token) {
			case TCase(_): true;
			default: false;
		}}
}
