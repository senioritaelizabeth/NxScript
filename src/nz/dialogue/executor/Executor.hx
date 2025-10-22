package nz.dialogue.executor;

import nz.dialogue.parser.Block;

/**
 * Executes dialogue code block by block
 * Manages variables, functions, and control flow
 */
class Executor {
	var blocks:Array<Block>;
	var pos:Int = 0;
	var variables:Map<String, Dynamic> = new Map();
	var functions:Map<String, FunctionDef> = new Map();
	var callbackHandler:CallbackHandler;

	var currentBlockStack:Array<Array<Block>> = [];
	var currentPosStack:Array<Int> = [];

	public function new(blocks:Array<Block>, ?callbackHandler:CallbackHandler) {
		this.blocks = blocks;
		this.callbackHandler = callbackHandler != null ? callbackHandler : new DefaultCallbackHandler();
	}

	public function hasNext():Bool {
		if (currentBlockStack.length > 0) {
			var currentBlocks = currentBlockStack[currentBlockStack.length - 1];
			var currentPos = currentPosStack[currentPosStack.length - 1];
			return currentPos < currentBlocks.length;
		}
		return pos < blocks.length;
	}

	public function nextExecute():ExecuteResult {
		if (!hasNext()) {
			return EREnd;
		}

		var block:Block;

		// Si estamos en un bloque anidado, ejecutar desde ahí
		if (currentBlockStack.length > 0) {
			var currentBlocks = currentBlockStack[currentBlockStack.length - 1];
			var currentPos = currentPosStack[currentPosStack.length - 1];
			block = currentBlocks[currentPos];
			currentPosStack[currentPosStack.length - 1]++;

			// Si terminamos el bloque actual, salir del stack
			if (currentPosStack[currentPosStack.length - 1] >= currentBlocks.length) {
				currentBlockStack.pop();
				currentPosStack.pop();
			}
		} else {
			block = blocks[pos];
			pos++;
		}

		return executeBlock(block);
	}

	private function executeBlock(block:Block):ExecuteResult {
		return switch (block) {
			case BComment(text):
				ERComment(text);

			case BVar(name, value):
				// Evaluate the expression before storing
				var evaluatedValue = (value != null) ? evaluateExpression(Std.string(value)) : null;
				variables.set(name, evaluatedValue);
				ERVar(name, evaluatedValue);

			case BFunc(name, params, body):
				functions.set(name, {name: name, params: params, body: body});
				ERFunc(name);

			case BIf(condition, thenBlock, elseIfs, elseBlock):
				var result = evaluateCondition(condition);
				if (result) {
					enterBlock(thenBlock);
					ERIf(condition, true);
				} else {
					var matched = false;
					for (elseIf in elseIfs) {
						if (evaluateCondition(elseIf.condition)) {
							enterBlock(elseIf.body);
							matched = true;
							break;
						}
					}
					if (!matched && elseBlock.length > 0) {
						enterBlock(elseBlock);
					}
					ERIf(condition, false);
				}

			case BSwitch(value, cases):
				var switchValue = evaluateExpression(value);
				for (caseBlock in cases) {
					var caseValue = evaluateExpression(caseBlock.value);
					if (switchValue == caseValue) {
						enterBlock(caseBlock.body);
						break;
					}
				}
				ERSwitch(value, switchValue);

			case BReturn(expr):
				var value = evaluateExpression(expr);
				ERReturn(value);

			case BFuncCall(name, args):
				// Intentar ejecutar la función
				if (functions.exists(name)) {
					var func = functions.get(name);
					enterBlock(func.body);
					ERFuncCall(name);
				} else {
					// Si no existe como función, tratarlo como comando
					callbackHandler.handleAtCall(name, args);
					ERAtCall(name, args);
				}

			case BAtCall(name, args):
				// Primero verificar si es una función definida
				if (functions.exists(name)) {
					var func = functions.get(name);
					enterBlock(func.body);
					ERFuncCall(name);
				} else {
					// Si no, ejecutar como comando normal
					callbackHandler.handleAtCall(name, args);
					ERAtCall(name, args);
				}

			case BDialog(text):
				ERDialog(text);
		}
	}

	private function enterBlock(blocks:Array<Block>):Void {
		if (blocks.length > 0) {
			currentBlockStack.push(blocks);
			currentPosStack.push(0);
		}
	}

	private function evaluateCondition(condition:String):Bool {
		// Simple condition evaluation
		var result = evaluateExpression(condition);
		if (result == true || result == false) {
			return result == true;
		}
		if (Std.isOfType(result, Int) || Std.isOfType(result, Float)) {
			var numValue:Float = Std.parseFloat(Std.string(result));
			return !Math.isNaN(numValue) && numValue > 0;
		}
		return result != null;
	}

	private function evaluateExpression(expr:String):Dynamic {
		if (expr == null || expr.length == 0) {
			return null;
		}

		expr = StringTools.trim(expr);

		// Boolean literals
		if (expr == "true")
			return true;
		if (expr == "false")
			return false;

		// String literals
		if (StringTools.startsWith(expr, '"') && StringTools.endsWith(expr, '"')) {
			return expr.substring(1, expr.length - 1);
		}
		if (StringTools.startsWith(expr, "'") && StringTools.endsWith(expr, "'")) {
			return expr.substring(1, expr.length - 1);
		}

		// Number literals
		var num = Std.parseFloat(expr);
		if (!Math.isNaN(num)) {
			return num;
		}

		// Variable lookup
		if (variables.exists(expr)) {
			return variables.get(expr);
		}

		// Handle logical operators (&&, ||)
		// Process OR first (lower precedence)
		var orParts = splitByOperator(expr, "||");
		if (orParts.length > 1) {
			for (part in orParts) {
				var result = evaluateExpression(part);
				if (result == true) {
					return true;
				}
			}
			return false;
		}

		// Process AND
		var andParts = splitByOperator(expr, "&&");
		if (andParts.length > 1) {
			for (part in andParts) {
				var result = evaluateExpression(part);
				if (result != true) {
					return false;
				}
			}
			return true;
		}

		// Handle NOT operator
		if (StringTools.startsWith(expr, "!")) {
			var innerExpr = StringTools.trim(expr.substring(1));
			var result = evaluateExpression(innerExpr);
			return result != true;
		}

		// Handle parentheses
		if (StringTools.startsWith(expr, "(") && StringTools.endsWith(expr, ")")) {
			var inner = expr.substring(1, expr.length - 1);
			return evaluateExpression(inner);
		}

		// Comparison operators (check compound operators first)
		if (expr.indexOf(">=") != -1) {
			var parts = splitByOperator(expr, ">=");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				return leftNum >= rightNum;
			}
		}

		if (expr.indexOf("<=") != -1) {
			var parts = splitByOperator(expr, "<=");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				return leftNum <= rightNum;
			}
		}

		if (expr.indexOf("==") != -1) {
			var parts = splitByOperator(expr, "==");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				return left == right;
			}
		}

		if (expr.indexOf("!=") != -1) {
			var parts = splitByOperator(expr, "!=");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				return left != right;
			}
		}

		// Simple comparison operators (must be after compound ones)
		if (expr.indexOf(">") != -1) {
			var parts = splitByOperator(expr, ">");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				return leftNum > rightNum;
			}
		}

		if (expr.indexOf("<") != -1) {
			var parts = splitByOperator(expr, "<");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				return leftNum < rightNum;
			}
		}

		// Arithmetic operators
		if (expr.indexOf("+") != -1) {
			var parts = splitByOperator(expr, "+");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				if (!Math.isNaN(leftNum) && !Math.isNaN(rightNum)) {
					return leftNum + rightNum;
				}
			}
		}

		if (expr.indexOf("-") != -1) {
			var parts = splitByOperator(expr, "-");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				if (!Math.isNaN(leftNum) && !Math.isNaN(rightNum)) {
					return leftNum - rightNum;
				}
			}
		}

		if (expr.indexOf("*") != -1) {
			var parts = splitByOperator(expr, "*");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				if (!Math.isNaN(leftNum) && !Math.isNaN(rightNum)) {
					return leftNum * rightNum;
				}
			}
		}

		if (expr.indexOf("/") != -1) {
			var parts = splitByOperator(expr, "/");
			if (parts.length == 2) {
				var left = evaluateExpression(parts[0]);
				var right = evaluateExpression(parts[1]);
				var leftNum = Std.parseFloat(Std.string(left));
				var rightNum = Std.parseFloat(Std.string(right));
				if (!Math.isNaN(leftNum) && !Math.isNaN(rightNum) && rightNum != 0) {
					return leftNum / rightNum;
				}
			}
		}

		// Default: return the expression as-is
		return expr;
	}

	// Helper function to split by operator while respecting parentheses
	private function splitByOperator(expr:String, op:String):Array<String> {
		var parts:Array<String> = [];
		var currentPart = "";
		var parenDepth = 0;
		var i = 0;

		while (i < expr.length) {
			var char = expr.charAt(i);

			if (char == "(") {
				parenDepth++;
				currentPart += char;
				i++;
			} else if (char == ")") {
				parenDepth--;
				currentPart += char;
				i++;
			} else if (parenDepth == 0 && expr.substr(i, op.length) == op) {
				parts.push(StringTools.trim(currentPart));
				currentPart = "";
				i += op.length;
			} else {
				currentPart += char;
				i++;
			}
		}

		if (currentPart.length > 0) {
			parts.push(StringTools.trim(currentPart));
		}

		return parts;
	}

	public function getVariable(name:String):Dynamic {
		return variables.get(name);
	}

	public function setVariable(name:String, value:Dynamic):Void {
		variables.set(name, value);
	}

	public function reset():Void {
		pos = 0;
		currentBlockStack = [];
		currentPosStack = [];
	}

	public function callFunction(name:String, ?args:Array<Dynamic>):Bool {
		if (!functions.exists(name)) {
			return false;
		}

		var func = functions.get(name);

		// TODO: Bind parameters with args if needed
		// For now, just execute the function body
		enterBlock(func.body);
		return true;
	}

	public function hasFunction(name:String):Bool {
		return functions.exists(name);
	}

	public function getFunctionNames():Array<String> {
		var names:Array<String> = [];
		for (name in functions.keys()) {
			names.push(name);
		}
		return names;
	}
}

typedef FunctionDef = {
	name:String,
	params:Array<String>,
	body:Array<Block>
}

enum ExecuteResult {
	ERDialog(text:String);
	ERComment(text:String);
	ERVar(name:String, value:Dynamic);
	ERFunc(name:String);
	ERFuncCall(name:String);
	ERIf(condition:String, taken:Bool);
	ERSwitch(value:String, result:Dynamic);
	ERReturn(value:Dynamic);
	ERAtCall(name:String, args:Array<String>);
	EREnd;
}

interface CallbackHandler {
	function handleAtCall(name:String, args:Array<String>):Void;
}

class DefaultCallbackHandler implements CallbackHandler {
	public function new() {}

	public function handleAtCall(name:String, args:Array<String>):Void {
		trace('@${name}(${args.join(", ")})');
	}
}
