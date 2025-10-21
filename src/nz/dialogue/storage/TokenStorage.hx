package nz.dialogue.storage;

import nz.dialogue.tokenizer.Token;
import sys.io.File;

using StringTools;

/**
 * Handles saving and reconstructing dialogue code from tokens
 */
class TokenStorage {
	public function new() {}

	public function save(tokens:Array<TokenPos>, filePath:String):Void {
		var output = reconstructCode(tokens);
		File.saveContent(filePath, output);
	}

	private function reconstructCode(tokens:Array<TokenPos>):String {
		var lines:Array<String> = [];
		var currentLine = "";
		var indentLevel = 0;
		var prevWasBlockStart = false;
		var inSwitch = false;
		var i = 0;

		while (i < tokens.length) {
			var token = tokens[i].token;

			switch (token) {
				case TComment(text):
					currentLine += '# ${text}';
					i++;

				case TKeyword(keyword):
					switch (keyword) {
						case KVar:
							i++;
							// Read: var IDENT = EXPR
							currentLine += 'var ';

							// Read identifier
							if (i < tokens.length) {
								switch (tokens[i].token) {
									case TIdentifier(id):
										currentLine += id;
										i++;
									default:
										i++;
								}
							}

							// Check for assignment
							if (i < tokens.length) {
								switch (tokens[i].token) {
									case TAssign:
										currentLine += ' = ';
										i++;
										// Read expression until newline
										currentLine += readExpressionString(tokens, i);
										i = skipToNewLine(tokens, i);
									default:
								}
							}

						case KFunc:
							i++;
							// Read: func IDENT(params)
							currentLine += 'func ';

							// Read function name
							if (i < tokens.length) {
								switch (tokens[i].token) {
									case TIdentifier(id):
										currentLine += id;
										i++;
									default:
										i++;
								}
							}

							// Read parameters
							if (i < tokens.length && Type.enumEq(tokens[i].token, TLParen)) {
								currentLine += '(';
								i++;

								var firstParam = true;
								while (i < tokens.length && !Type.enumEq(tokens[i].token, TRParen)) {
									switch (tokens[i].token) {
										case TIdentifier(id):
											if (!firstParam)
												currentLine += ', ';
											currentLine += id;
											firstParam = false;
											i++;
										case TComma:
											i++;
										default:
											i++;
									}
								}

								if (i < tokens.length && Type.enumEq(tokens[i].token, TRParen)) {
									currentLine += ')';
									i++;
								}
							}
							prevWasBlockStart = true;

						case KIf:
							i++;
							currentLine += 'if ';

							// Optional opening paren
							if (i < tokens.length && Type.enumEq(tokens[i].token, TLParen)) {
								currentLine += '(';
								i++;
								currentLine += readExpressionString(tokens, i);
								i = skipToToken(tokens, i, TRParen);
								if (i < tokens.length && Type.enumEq(tokens[i].token, TRParen)) {
									currentLine += ')';
									i++;
								}
							} else {
								currentLine += '(';
								currentLine += readExpressionString(tokens, i);
								currentLine += ')';
								i = skipToNewLine(tokens, i);
							}
							prevWasBlockStart = true;

						case KElseIf:
							i++;
							if (indentLevel > 0)
								indentLevel--;
							currentLine += 'elseif ';

							// Optional opening paren
							if (i < tokens.length && Type.enumEq(tokens[i].token, TLParen)) {
								currentLine += '(';
								i++;
								currentLine += readExpressionString(tokens, i);
								i = skipToToken(tokens, i, TRParen);
								if (i < tokens.length && Type.enumEq(tokens[i].token, TRParen)) {
									currentLine += ')';
									i++;
								}
							} else {
								currentLine += '(';
								currentLine += readExpressionString(tokens, i);
								currentLine += ')';
								i = skipToNewLine(tokens, i);
							}
							prevWasBlockStart = true;

						case KElse:
							i++;
							if (indentLevel > 0)
								indentLevel--;
							currentLine += 'else';
							prevWasBlockStart = true;

						case KSwitch:
							i++;
							currentLine += 'switch ';

							// Optional opening paren
							if (i < tokens.length && Type.enumEq(tokens[i].token, TLParen)) {
								currentLine += '(';
								i++;
								currentLine += readExpressionString(tokens, i);
								i = skipToToken(tokens, i, TRParen);
								if (i < tokens.length && Type.enumEq(tokens[i].token, TRParen)) {
									currentLine += ')';
									i++;
								}
							} else {
								currentLine += '(';
								currentLine += readExpressionString(tokens, i);
								currentLine += ')';
								i = skipToNewLine(tokens, i);
							}
							prevWasBlockStart = true;
							inSwitch = true;

						case KCase:
							i++;
							if (inSwitch && indentLevel > 0)
								indentLevel--;
							currentLine += 'case ';
							currentLine += readExpressionString(tokens, i);
							i = skipToNewLine(tokens, i);
							prevWasBlockStart = true;

						case KEnd:
							i++;
							if (indentLevel > 0)
								indentLevel--;
							currentLine += 'end';
							prevWasBlockStart = false;
							inSwitch = false;

						case KReturn:
							i++;
							currentLine += 'return ';
							currentLine += readExpressionString(tokens, i);
							i = skipToNewLine(tokens, i);
					}

				case TAtCommand(name):
					i++;
					currentLine += '@${name}';

					// Read arguments until newline
					while (i < tokens.length && !Type.enumEq(tokens[i].token, TNewLine) && !Type.enumEq(tokens[i].token, TEndOfFile)) {
						switch (tokens[i].token) {
							case TString(str):
								if (str.indexOf(" ") != -1) {
									currentLine += ' "${str}"';
								} else {
									currentLine += ' ${str}';
								}
								i++;
							case TIdentifier(id):
								currentLine += ' ${id}';
								i++;
							case TNumber(n):
								currentLine += ' ${n}';
								i++;
							case TBool(b):
								currentLine += ' ${b}';
								i++;
							default:
								i++;
						}
					}

				case TDialog(text):
					currentLine += '${text}';
					i++;

				case TNewLine:
					if (currentLine.trim().length > 0) {
						// Apply current indentation
						var indent = "";
						for (j in 0...indentLevel) {
							indent += "\t";
						}
						lines.push(indent + currentLine);

						// Increase indent after block start
						if (prevWasBlockStart) {
							indentLevel++;
							prevWasBlockStart = false;
						}
					} else {
						lines.push("");
					}
					currentLine = "";
					i++;

				case TEndOfFile:
					if (currentLine.trim().length > 0) {
						var indent = "";
						for (j in 0...indentLevel) {
							indent += "\t";
						}
						lines.push(indent + currentLine);
					}
					i++;

				default:
					// Skip other tokens (they're part of expressions)
					i++;
			}
		}

		return lines.join("\n");
	}

	private function readExpressionString(tokens:Array<TokenPos>, startIndex:Int):String {
		var expr = "";
		var i = startIndex;

		while (i < tokens.length) {
			var token = tokens[i].token;

			switch (token) {
				case TNewLine | TEndOfFile:
					break;

				case TIdentifier(id):
					expr += id;
					i++;

				case TNumber(n):
					expr += Std.string(n);
					i++;

				case TString(str):
					expr += '"${str}"';
					i++;

				case TBool(b):
					expr += Std.string(b);
					i++;

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
					i++;

				case TAssign:
					expr += "=";
					i++;

				case TLParen:
					expr += "(";
					i++;

				case TRParen:
					// Stop at closing paren (let caller handle it)
					break;

				case TComma:
					break;

				case TKeyword(_):
					break;

				default:
					i++;
			}
		}

		return expr.trim();
	}

	private function skipToNewLine(tokens:Array<TokenPos>, startIndex:Int):Int {
		var i = startIndex;
		while (i < tokens.length && !Type.enumEq(tokens[i].token, TNewLine) && !Type.enumEq(tokens[i].token, TEndOfFile)) {
			i++;
		}
		return i;
	}

	private function skipToToken(tokens:Array<TokenPos>, startIndex:Int, targetToken:Token):Int {
		var i = startIndex;
		while (i < tokens.length && !Type.enumEq(tokens[i].token, targetToken)) {
			i++;
		}
		return i;
	}

	private function isBlockEnd(token:Token):Bool {
		return token != null && switch (token) {
			case TKeyword(keyword):
				switch (keyword) {
					case KEnd | KElse | KElseIf | KCase: true;
					default: false;
				}
			default: false;
		};
	}
}
