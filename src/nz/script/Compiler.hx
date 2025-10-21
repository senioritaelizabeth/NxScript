package nz.script;

import nz.script.AST;
import nz.script.Bytecode;
import nz.script.Token;

/**
 * Compiler that converts AST to bytecode
 */
class Compiler {
	var chunk:Chunk;
	var constants:Array<Value>;
	var functions:Array<FunctionChunk>;
	var strings:Array<String>;
	var stringMap:Map<String, Int>;
	var currentLine:Int = 0;
	var currentCol:Int = 0;

	// For break/continue
	var loopStack:Array<LoopContext> = [];

	public function new() {
		constants = [];
		functions = [];
		strings = [];
		stringMap = new Map();
		chunk = {
			instructions: [],
			constants: constants,
			functions: functions,
			strings: strings
		};
	}

	public function compile(statements:Array<StmtWithPos>):Chunk {
		for (i in 0...statements.length) {
			var isLast = (i == statements.length - 1);
			var stmtWithPos = statements[i];
			// Update current line/col from statement position
			currentLine = stmtWithPos.line;
			currentCol = stmtWithPos.col;
			compileStatement(stmtWithPos.stmt, isLast);
		}
		// Ensure there's always a value on the stack
		if (statements.length == 0) {
			emit(Op.LOAD_NULL);
		}
		return chunk;
	}

	function compileStatement(stmt:Stmt, isLast:Bool = false) {
		switch (stmt) {
			case SLet(name, type, init):
				if (init != null) {
					compileExpression(init);
				} else {
					emit(Op.LOAD_NULL);
				}
				emitWithString(Op.STORE_LET, name);
				if (!isLast)
					emit(Op.POP);

			case SVar(name, type, init):
				if (init != null) {
					compileExpression(init);
				} else {
					emit(Op.LOAD_NULL);
				}
				emitWithString(Op.STORE_VAR, name);
				if (!isLast)
					emit(Op.POP);

			case SConst(name, type, init):
				compileExpression(init);
				emitWithString(Op.STORE_CONST, name);
				if (!isLast)
					emit(Op.POP);

			case SFunc(name, params, returnType, body):
				var funcChunk = compileFunction(name, params, body, false);
				var funcIndex = functions.length;
				functions.push(funcChunk);
				emitWithArg(Op.MAKE_FUNC, funcIndex);
				emitWithString(Op.STORE_VAR, name);
				if (!isLast)
					emit(Op.POP);

			case SReturn(expr):
				if (expr != null) {
					compileExpression(expr);
				} else {
					emit(Op.LOAD_NULL);
				}
				emit(Op.RETURN);

			case SIf(condition, thenBody, elseBody):
				compileExpression(condition);
				var jumpToElse = emitJump(Op.JUMP_IF_FALSE);

				// Compile then branch - pass isLast to the last statement in the branch
				for (i in 0...thenBody.length) {
					var stmtIsLast = isLast && (i == thenBody.length - 1);
					compileStatement(thenBody[i], stmtIsLast);
				}

				if (elseBody != null) {
					var jumpToEnd = emitJump(Op.JUMP);
					patchJump(jumpToElse);

					// Compile else branch - pass isLast to the last statement
					for (i in 0...elseBody.length) {
						var stmtIsLast = isLast && (i == elseBody.length - 1);
						compileStatement(elseBody[i], stmtIsLast);
					}
					patchJump(jumpToEnd);
				} else {
					patchJump(jumpToElse);
				}

			case SWhile(condition, body):
				var loopStart = chunk.instructions.length;
				var loop = {
					start: loopStart,
					breaks: [],
					continues: []
				};
				loopStack.push(loop);

				compileExpression(condition);
				var exitJump = emitJump(Op.JUMP_IF_FALSE);

				// Inside a loop, no statement is "last" - they all need to pop their values
				for (s in body) {
					compileStatement(s, false);
				}

				emitLoop(loopStart);
				patchJump(exitJump);

				var endLoop = chunk.instructions.length;
				for (breakPos in loop.breaks) {
					patchJumpAt(breakPos, endLoop);
				}
				for (continuePos in loop.continues) {
					patchJumpAt(continuePos, loopStart);
				}

				loopStack.pop();

			case SFor(variable, iterable, body):
				compileExpression(iterable);
				emit(Op.GET_ITER);

				var loopStart = chunk.instructions.length;
				var loop = {
					start: loopStart,
					breaks: [],
					continues: []
				};
				loopStack.push(loop);

				var exitJump = emitJump(Op.FOR_ITER);
				emitWithString(Op.STORE_LET, variable);
				emit(Op.POP);

				// Inside a loop, no statement is "last" - they all need to pop their values
				for (s in body) {
					compileStatement(s, false);
				}

				emitLoop(loopStart);
				patchJump(exitJump);
				// No need to POP here - FOR_ITER already pops the iterator when done

				var endLoop = chunk.instructions.length;
				for (breakPos in loop.breaks) {
					patchJumpAt(breakPos, endLoop);
				}
				for (continuePos in loop.continues) {
					patchJumpAt(continuePos, loopStart);
				}

				loopStack.pop();

			case SBreak:
				if (loopStack.length == 0) {
					throw "Break outside of loop";
				}
				var breakJump = emitJump(Op.JUMP);
				loopStack[loopStack.length - 1].breaks.push(breakJump);

			case SContinue:
				if (loopStack.length == 0) {
					throw "Continue outside of loop";
				}
				var continueJump = emitJump(Op.JUMP);
				loopStack[loopStack.length - 1].continues.push(continueJump);

			case SExpr(expr):
				compileExpression(expr);
				if (!isLast) {
					emit(Op.POP);
				}

			case SBlock(stmts):
				for (i in 0...stmts.length) {
					var stmtIsLast = isLast && (i == stmts.length - 1);
					compileStatement(stmts[i], stmtIsLast);
				}
		}
	}

	function compileExpression(expr:Expr) {
		switch (expr) {
			case ENumber(v):
				emitConstant(VNumber(v));

			case EString(v):
				emitConstant(VString(v));

			case EBool(v):
				emit(v ? Op.LOAD_TRUE : Op.LOAD_FALSE);

			case ENull:
				emit(Op.LOAD_NULL);

			case EIdentifier(name):
				emitWithString(Op.LOAD_VAR, name);

			case EBinary(op, left, right):
				compileExpression(left);
				compileExpression(right);
				compileBinaryOp(op);

			case EUnary(op, e):
				compileExpression(e);
				compileUnaryOp(op);

			case EMember(object, field):
				compileExpression(object);
				emitWithString(Op.GET_MEMBER, field);

			case EIndex(object, index):
				compileExpression(object);
				compileExpression(index);
				emit(Op.GET_INDEX);

			case ECall(callee, args):
				compileExpression(callee);
				for (arg in args) {
					compileExpression(arg);
				}
				emitWithArg(Op.CALL, args.length);

			case EArray(elements):
				for (elem in elements) {
					compileExpression(elem);
				}
				emitWithArg(Op.MAKE_ARRAY, elements.length);

			case EDict(pairs):
				for (pair in pairs) {
					compileExpression(pair.key);
					compileExpression(pair.value);
				}
				emitWithArg(Op.MAKE_DICT, pairs.length);

			case ELambda(params, body):
				var funcName = "<lambda>";
				var funcBody = switch (body) {
					case Left(e): [SReturn(e)];
					case Right(stmts): stmts;
				}
				var funcChunk = compileFunction(funcName, params, funcBody, true);
				var funcIndex = functions.length;
				functions.push(funcChunk);
				emitWithArg(Op.MAKE_LAMBDA, funcIndex);

			case EAssign(target, value):
				compileExpression(value);

				switch (target) {
					case EIdentifier(name):
						emitWithString(Op.STORE_VAR, name);

					case EMember(object, field):
						emit(Op.DUP);
						compileExpression(object);
						emitWithString(Op.SET_MEMBER, field);

					case EIndex(object, index):
						emit(Op.DUP);
						compileExpression(object);
						compileExpression(index);
						emit(Op.SET_INDEX);

					default:
						throw "Invalid assignment target";
				}
		}
	}

	function compileBinaryOp(op:Operator) {
		switch (op) {
			case OAdd:
				emit(Op.ADD);
			case OSub:
				emit(Op.SUB);
			case OMul:
				emit(Op.MUL);
			case ODiv:
				emit(Op.DIV);
			case OMod:
				emit(Op.MOD);
			case OEqual:
				emit(Op.EQ);
			case ONotEqual:
				emit(Op.NEQ);
			case OLess:
				emit(Op.LT);
			case OGreater:
				emit(Op.GT);
			case OLessEq:
				emit(Op.LTE);
			case OGreaterEq:
				emit(Op.GTE);
			case OAnd:
				emit(Op.AND);
			case OOr:
				emit(Op.OR);
			case OBitAnd:
				emit(Op.BIT_AND);
			case OBitOr:
				emit(Op.BIT_OR);
			case OBitXor:
				emit(Op.BIT_XOR);
			case OShiftLeft:
				emit(Op.SHIFT_LEFT);
			case OShiftRight:
				emit(Op.SHIFT_RIGHT);
			default:
				throw 'Unexpected binary operator: $op';
		}
	}

	function compileUnaryOp(op:Operator) {
		switch (op) {
			case ONot:
				emit(Op.NOT);
			case OSub:
				emit(Op.NEG);
			case OBitNot:
				emit(Op.BIT_NOT);
			default:
				throw 'Unexpected unary operator: $op';
		}
	}

	function compileFunction(name:String, params:Array<Param>, body:Array<Stmt>, isLambda:Bool):FunctionChunk {
		var savedChunk = chunk;
		var savedConstants = constants;
		var savedFunctions = functions;
		var savedStrings = strings;
		var savedStringMap = stringMap;

		constants = [];
		functions = [];
		strings = [];
		stringMap = new Map();
		chunk = {
			instructions: [],
			constants: constants,
			functions: functions,
			strings: strings
		};

		for (stmt in body) {
			compileStatement(stmt);
		}

		emit(Op.LOAD_NULL);
		emit(Op.RETURN);

		var funcChunk:FunctionChunk = {
			name: name,
			paramCount: params.length,
			paramNames: [for (p in params) p.name],
			chunk: chunk,
			isLambda: isLambda
		};

		chunk = savedChunk;
		constants = savedConstants;
		functions = savedFunctions;
		strings = savedStrings;
		stringMap = savedStringMap;

		return funcChunk;
	}

	// String pool management
	function addString(str:String):Int {
		if (stringMap.exists(str)) {
			return stringMap.get(str);
		}
		var index = strings.length;
		strings.push(str);
		stringMap.set(str, index);
		return index;
	}

	// Emit functions
	function emit(op:Int) {
		chunk.instructions.push({
			op: op,
			line: currentLine,
			col: currentCol
		});
	}

	function emitWithArg(op:Int, arg:Int) {
		chunk.instructions.push({
			op: op,
			arg: arg,
			line: currentLine,
			col: currentCol
		});
	}

	function emitWithString(op:Int, name:String) {
		var index = addString(name);
		chunk.instructions.push({
			op: op,
			arg: index,
			line: currentLine,
			col: currentCol
		});
	}

	function emitConstant(value:Value) {
		var index = constants.length;
		constants.push(value);
		emitWithArg(Op.LOAD_CONST, index);
	}

	function emitJump(op:Int):Int {
		emitWithArg(op, 0xFFFF); // Placeholder
		return chunk.instructions.length - 1;
	}

	function emitLoop(loopStart:Int) {
		// Calculate how many instructions to jump back
		// Current position will be AFTER the JUMP instruction is added
		var offset = -(chunk.instructions.length - loopStart + 1);
		emitWithArg(Op.JUMP, offset);
	}

	function patchJump(jumpPos:Int) {
		var jump = chunk.instructions.length - jumpPos - 1;
		chunk.instructions[jumpPos].arg = jump;
	}

	function patchJumpAt(jumpPos:Int, target:Int) {
		var jump = target - jumpPos - 1;
		chunk.instructions[jumpPos].arg = jump;
	}
}

typedef LoopContext = {
	start:Int,
	breaks:Array<Int>,
	continues:Array<Int>
}
