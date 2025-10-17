package nz.storage;

import nz.tokenizer.Token;
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

		for (i in 0...tokens.length) {
			var token = tokens[i].token;

			switch (token) {
				case TComment(text):
					currentLine += '# ${text}';

				case TVar(name, value):
					currentLine += 'var ${name}';
					if (value != null) {
						currentLine += ' = ${value}';
					}

				case TFunc(name, params):
					currentLine += 'func ${name}';
					if (params.length > 0) {
						currentLine += '(${params.join(", ")})';
					}
					prevWasBlockStart = true;

				case TIf(condition):
					currentLine += 'if (${condition})';
					prevWasBlockStart = true;

				case TElseIf(condition):
					// Decrease indent for elseif itself
					if (indentLevel > 0)
						indentLevel--;
					currentLine += 'elseif (${condition})';
					prevWasBlockStart = true;

				case TElse:
					// Decrease indent for else itself
					if (indentLevel > 0)
						indentLevel--;
					currentLine += 'else';
					prevWasBlockStart = true;

				case TSwitch(value):
					currentLine += 'switch (${value})';
					prevWasBlockStart = true;
					inSwitch = true;

				case TCase(value):
					// Case is at same level as switch
					if (inSwitch && indentLevel > 0)
						indentLevel--;
					currentLine += '\tcase ${value}';
					prevWasBlockStart = true;

				case TEnd:
					if (indentLevel > 0)
						indentLevel--;
					currentLine += 'end';
					prevWasBlockStart = false;
					inSwitch = false;

				case TReturn(expr):
					currentLine += 'return ${expr}';

				case TAtCall(name, args):
					var formattedArgs = args.map(arg -> {
						if (arg.indexOf(" ") != -1) {
							return '"${arg}"';
						}
						return arg;
					}).join(" ");
					currentLine += '@${name} ${formattedArgs}';

				case TDialog(text):
					currentLine += '${text}';

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

				case TEndOfFile:
					if (currentLine.trim().length > 0) {
						var indent = "";
						for (j in 0...indentLevel) {
							indent += "\t";
						}
						lines.push(indent + currentLine);
					}

				default:
					// Ignore other tokens like operators, parens, etc.
			}
		}

		return lines.join("\n");
	}

	private function isBlockEnd(token:Token):Bool {
		return token != null && switch (token) {
			case TEnd: true;
			case TElse: true;
			case TElseIf(_): true;
			case TCase(_): true;
			default: false;
		}}
}
