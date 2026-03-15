package nx.script;

import nx.script.AST;
import nx.script.Bytecode;
import nx.script.Token;

/**
 * Walks the AST and emits bytecode. One pass, no regrets.
 *
 * Local variables inside functions get integer slot indices instead of string map lookups.
 * This means LOAD_LOCAL/STORE_LOCAL are O(1) array accesses instead of O(1) hash lookups
 * with extra overhead. Yes, there is a difference. The benchmarks said so.
 *
 * Module-level code (outside any func) has no slot system — globals only.
 * Try to use module-level `var` inside a function and you'll get a STORE_VAR. Intentional.
 */
class Compiler {
	// The instruction stream we're building. One Chunk per compilation.
	var chunk:Chunk;
	var constants:Array<Value>;
	var functions:Array<FunctionChunk>;
	var strings:Array<String>;
	var stringMap:Map<String, Int>; // dedup string constants so we don't store "x" 500 times
	var currentLine:Int = 0;
	var currentCol:Int = 0;

	// Jump target stacks for break/continue. Push on loop enter, pop on loop exit.
	// If this is empty inside a break statement, the parser already messed up.
	var loopStack:Array<LoopContext> = [];

	// How deep we are in try blocks. Used to emit the right number of POP_TRY on return.
	var tryDepth:Int = 0;

	// Counter for synthetic variable names
	var syntheticCounter:Int = 0;

	// Slot allocator for function-local variables. null means we're at module level.
	// Slots are integer indices into stack[stackBase..stackBase+localCount-1].
	var localSlots:Map<String, Int> = null;
	var nextLocalSlot:Int = 0;
	var globalSlots:Map<String, Int>;
	var globalNames:Array<String>;
	var globalConstMask:Array<Bool>;
	var upvalueSlots:Map<String, Int> = null;
	var upvalueNames:Array<String> = null;
	var enclosingLocalSlots:Map<String, Int> = null;
	var enclosingUpvalueSlots:Map<String, Int> = null;

	// When compiling a class method body, this holds all method names so
	// bare calls like foo() can resolve to this.foo() if no local shadows it.
	var currentClassMethodNames:Map<String, Bool> = null;

	// Get or create a slot for a local variable. Slots are never reused (simple but fine for scripts).
	inline function allocSlot(name:String):Int {
		if (localSlots.exists(name))
			return localSlots.get(name);
		var slot = nextLocalSlot++;
		localSlots.set(name, slot);
		return slot;
	}

	inline function allocGlobalSlot(name:String):Int {
		if (globalSlots.exists(name))
			return globalSlots.get(name);
		var slot = globalNames.length;
		globalSlots.set(name, slot);
		globalNames.push(name);
		globalConstMask.push(false);
		return slot;
	}

	inline function markGlobalConst(name:String):Int {
		var slot = allocGlobalSlot(name);
		globalConstMask[slot] = true;
		return slot;
	}

	inline function resolveUpvalueSlot(name:String):Int {
		if (upvalueSlots == null)
			return -1;
		if (upvalueSlots.exists(name))
			return upvalueSlots.get(name);

		var foundInEnclosing = false;
		if (enclosingLocalSlots != null && enclosingLocalSlots.exists(name)) {
			foundInEnclosing = true;
		} else if (enclosingUpvalueSlots != null && enclosingUpvalueSlots.exists(name)) {
			foundInEnclosing = true;
		}

		if (!foundInEnclosing)
			return -1;

		var slot = upvalueNames.length;
		upvalueSlots.set(name, slot);
		upvalueNames.push(name);
		return slot;
	}

	public function new() {
		constants = [];
		functions = [];
		strings = [];
		stringMap = new Map();
		globalSlots = new Map();
		globalNames = [];
		globalConstMask = [];
		chunk = {
			instructions: [],
			constants: constants,
			functions: functions,
			strings: strings,
			globalNames: globalNames,
			globalConstMask: globalConstMask
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
		emit(Op.RETURN);
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
				if (localSlots != null) {
					emitWithArg(Op.STORE_LOCAL, allocSlot(name));
				} else {
					emitWithString(Op.STORE_LET, name);
				}
				if (!isLast)
					emit(Op.POP);

			case SVar(name, type, init):
				if (init != null) {
					compileExpression(init);
				} else {
					emit(Op.LOAD_NULL);
				}
				if (localSlots != null) {
					// Inside a function, treat var as function-local slot (avoids global Map overhead)
					emitWithArg(Op.STORE_LOCAL, allocSlot(name));
				} else {
					emitWithArg(Op.STORE_GLOBAL, allocGlobalSlot(name));
				}
				if (!isLast)
					emit(Op.POP);

			case SConst(name, type, init):
				compileExpression(init);
				if (localSlots != null) {
					emitWithString(Op.STORE_CONST, name);
				} else {
					emitWithArg(Op.STORE_GLOBAL, markGlobalConst(name));
				}
				if (!isLast)
					emit(Op.POP);

			case SFunc(name, params, returnType, body):
				var funcChunk = compileFunction(name, params, body, false, null);
				var funcIndex = functions.length;
				functions.push(funcChunk);
				emitWithArg(Op.MAKE_FUNC, funcIndex);
				emitWithArg(Op.STORE_GLOBAL, allocGlobalSlot(name));
				if (!isLast)
					emit(Op.POP);

			case SClass(className, superClass, methods, fields):
				var classMethodNames = new Map<String, Bool>();
				for (m in methods)
					classMethodNames.set(m.name, true);

				// Push class name
				emitConstant(VString(className));
				// Push super class (or null)
				if (superClass != null) {
					emitWithString(Op.LOAD_VAR, superClass);
				} else {
					emit(Op.LOAD_NULL);
				}
				// Compile and push methods
				for (method in methods) {
					// Push method name
					emitConstant(VString(method.name));
					// Push method function
					var funcChunk = compileFunction(method.name, method.params, method.body, false, classMethodNames);
					var funcIndex = functions.length;
					functions.push(funcChunk);
					emitWithArg(Op.MAKE_FUNC, funcIndex);
					// Push isConstructor flag
					emit(method.isConstructor ? Op.LOAD_TRUE : Op.LOAD_FALSE);
				}
				// Compile and push fields
				for (field in fields) {
					// Push field name
					emitConstant(VString(field.name));
					// Push field init value
					if (field.init != null) {
						compileExpression(field.init);
					} else {
						emit(Op.LOAD_NULL);
					}
				}
				// Create class: MAKE_CLASS with encoded counts (methods << 16 | fields)
				var counts = (methods.length << 16) | fields.length;
				emitWithArg(Op.MAKE_CLASS, counts);
				// Store class
				emitWithArg(Op.STORE_GLOBAL, allocGlobalSlot(className));
				if (!isLast)
					emit(Op.POP);

			case SReturn(expr):
				if (expr != null) {
					compileExpression(expr);
				} else {
					emit(Op.LOAD_NULL);
				}
				for (_ in 0...tryDepth)
					emit(Op.POP_TRY);
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
					continues: [],
					tryDepth: tryDepth
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
					continues: [],
					tryDepth: tryDepth
				};
				loopStack.push(loop);

				var exitJump = emitJump(Op.FOR_ITER);
				if (localSlots != null) {
					emitWithArg(Op.STORE_LOCAL, allocSlot(variable));
				} else {
					emitWithString(Op.STORE_LET, variable);
				}
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

			case SForRange(variable, from, to, body):
				if (localSlots != null) {
					// Fast path inside functions: both loop var and end are stack slots.
					// Emits FOR_RANGE_SETUP (metadata) + FOR_RANGE (check+jump) which together
					// replace STORE_CONST + LOAD_VAR + LT + JUMP_IF_FALSE — no Map touch at all.
					var varSlot = allocSlot(variable);
					var endSlot = allocSlot('__for_end_${syntheticCounter++}');

					compileExpression(from);
					emitWithArg(Op.STORE_LOCAL, varSlot);
					emit(Op.POP);

					compileExpression(to);
					emitWithArg(Op.STORE_LOCAL, endSlot);
					emit(Op.POP);

					var loopStart = chunk.instructions.length;
					var loop = {
						start: loopStart,
						breaks: [],
						continues: [],
						tryDepth: tryDepth
					};
					loopStack.push(loop);

					// Emit SETUP (carries slot info) then FOR_RANGE (carries jump offset)
					emitWithArg(Op.FOR_RANGE_SETUP, varSlot | (endSlot << 16));
					var exitJump = emitJump(Op.FOR_RANGE);

					for (s in body)
						compileStatement(s, false);

					// Increment varSlot and loop back
					var stepStart = chunk.instructions.length;
					emitWithArg(Op.INC_LOCAL, varSlot);
					emit(Op.POP); // discard old value returned by INC_LOCAL

					emitLoop(loopStart);
					patchJump(exitJump);

					var endLoop = chunk.instructions.length;
					for (breakPos in loop.breaks)
						patchJumpAt(breakPos, endLoop);
					for (continuePos in loop.continues)
						patchJumpAt(continuePos, stepStart);

					loopStack.pop();
				} else {
					// Module-level fallback: old behaviour with STORE_CONST + LOAD_VAR
					var endName = '__for_end_${syntheticCounter++}';
					compileExpression(from);
					emitWithString(Op.STORE_LET, variable);
					emit(Op.POP);

					compileExpression(to);
					emitWithString(Op.STORE_CONST, endName);
					emit(Op.POP);

					var loopStart = chunk.instructions.length;
					var loop = {
						start: loopStart,
						breaks: [],
						continues: [],
						tryDepth: tryDepth
					};
					loopStack.push(loop);

					emitWithString(Op.LOAD_VAR, variable);
					emitWithString(Op.LOAD_VAR, endName);
					emit(Op.LT);
					var exitJump = emitJump(Op.JUMP_IF_FALSE);

					for (s in body)
						compileStatement(s, false);

					var stepStart = chunk.instructions.length;
					emitWithString(Op.LOAD_VAR, variable);
					emitConstant(VNumber(1));
					emit(Op.ADD);
					emitWithString(Op.STORE_VAR, variable);
					emit(Op.POP);

					emitLoop(loopStart);
					patchJump(exitJump);

					var endLoop = chunk.instructions.length;
					for (breakPos in loop.breaks)
						patchJumpAt(breakPos, endLoop);
					for (continuePos in loop.continues)
						patchJumpAt(continuePos, stepStart);

					loopStack.pop();
				}

			case SBreak:
				if (loopStack.length == 0) {
					throw "Break outside of loop";
				}
				var loopTryDepth = tryDepth - loopStack[loopStack.length - 1].tryDepth;
				for (_ in 0...loopTryDepth)
					emit(Op.POP_TRY);
				var breakJump = emitJump(Op.JUMP);
				loopStack[loopStack.length - 1].breaks.push(breakJump);

			case SContinue:
				if (loopStack.length == 0) {
					throw "Continue outside of loop";
				}
				var loopTryDepth = tryDepth - loopStack[loopStack.length - 1].tryDepth;
				for (_ in 0...loopTryDepth)
					emit(Op.POP_TRY);
				var continueJump = emitJump(Op.JUMP);
				loopStack[loopStack.length - 1].continues.push(continueJump);

			case SExpr(expr):
				compileExpression(expr);
				if (!isLast) {
					emit(Op.POP);
				}

			case SDestructureArray(names, init):
				// var [a, b, c] = expr
				// Evaluate init once, then index into it for each name
				var tmpName = '__da_${syntheticCounter++}';
				compileExpression(init);
				if (localSlots != null) emitWithArg(Op.STORE_LOCAL, allocSlot(tmpName))
				else emitWithString(Op.STORE_LET, tmpName);
				emit(Op.POP);
				for (i in 0...names.length) {
					var name = names[i];
					if (name == null) continue; // _ = skip
					if (localSlots != null) emitWithArg(Op.LOAD_LOCAL, localSlots.get(tmpName))
					else emitWithString(Op.LOAD_VAR, tmpName);
					emitConstant(VNumber(i));
					emit(Op.GET_INDEX);
					if (localSlots != null) emitWithArg(Op.STORE_LOCAL, allocSlot(name))
					else emitWithString(Op.STORE_LET, name);
					if (!isLast) emit(Op.POP);
				}
				if (!isLast) emit(Op.LOAD_NULL);

			case SDestructureDict(names, init):
				// var {x, y} = expr
				var tmpName = '__dd_${syntheticCounter++}';
				compileExpression(init);
				if (localSlots != null) emitWithArg(Op.STORE_LOCAL, allocSlot(tmpName))
				else emitWithString(Op.STORE_LET, tmpName);
				emit(Op.POP);
				for (name in names) {
					if (localSlots != null) emitWithArg(Op.LOAD_LOCAL, localSlots.get(tmpName))
					else emitWithString(Op.LOAD_VAR, tmpName);
					emitWithString(Op.GET_MEMBER, name);
					if (localSlots != null) emitWithArg(Op.STORE_LOCAL, allocSlot(name))
					else emitWithString(Op.STORE_LET, name);
					if (!isLast) emit(Op.POP);
				}
				if (!isLast) emit(Op.LOAD_NULL);

			case SEnum(name, variants):
				// Build an enum object via __make_enum__(enumName, [variantName, fieldCount, ...])
				// Results in a VDict: { "Red": VEnumValue, "Ok": VNativeFunction(...) }
				emitWithString(Op.LOAD_VAR, "__make_enum__");
				emitConstant(VString(name));
				for (v in variants) {
					emitConstant(VString(v.name));
					emitConstant(VNumber(v.fields.length));
				}
				emitWithArg(Op.MAKE_ARRAY, variants.length * 2);
				emitWithArg(Op.CALL, 2); // __make_enum__(enumName, variantsArray)
				if (localSlots != null)
					emitWithArg(Op.STORE_LOCAL, allocSlot(name))
				else
					emitWithArg(Op.STORE_GLOBAL, allocGlobalSlot(name));
				if (!isLast) emit(Op.POP);

			case SAbstract(name, baseType, methods):
				// Abstract compiles as a class with a special marker.
				// The constructor wraps the base value.
				// We compile it exactly like SClass but register it as abstract.
				compileStatement(SClass(name, null, methods, []), isLast);

			case SUsing(className):
				// `using` is parsed but currently a no-op at runtime.
				// Extension methods via VProxy were removed for performance.
				if (!isLast) emit(Op.LOAD_NULL);

			case SMatch(subject, cases, defaultBody):
				compileMatch(subject, cases, defaultBody, isLast);

			case SBlock(stmts):
				// Only emit ENTER/EXIT_SCOPE when at module level AND the block
				// actually declares let/const — avoids a Map alloc on every if/while/for body.
				var needsScope = (localSlots == null) && blockHasLetDecl(stmts);
				if (needsScope) emit(Op.ENTER_SCOPE);
				for (i in 0...stmts.length) {
					var stmtIsLast = isLast && (i == stmts.length - 1);
					compileStatement(stmts[i], stmtIsLast);
				}
				if (needsScope) emit(Op.EXIT_SCOPE);

			case STryCatch(body, catchVar, catchBody):
				// Emit SETUP_TRY pointing to the catch block
				var setupTryPos = emitJump(Op.SETUP_TRY);
				tryDepth++;
				for (s in body)
					compileStatement(s, false);
				tryDepth--;
				// Normal exit: remove catch handler then jump over catch block
				emit(Op.POP_TRY);
				var jumpOverCatch = emitJump(Op.JUMP);
				// Patch SETUP_TRY to point here (start of catch block)
				patchJump(setupTryPos);
				// Catch block: caught value is on top of stack
				if (localSlots != null) {
					emitWithArg(Op.STORE_LOCAL, allocSlot(catchVar));
				} else {
					emitWithString(Op.STORE_LET, catchVar);
				}
				emit(Op.POP);
				for (s in catchBody)
					compileStatement(s, false);
				// Patch jump to after catch block
				patchJump(jumpOverCatch);
				if (isLast)
					emit(Op.LOAD_NULL);

			case SThrow(expr):
				compileExpression(expr);
				emit(Op.THROW);
		}
	}

	function compileExpression(expr:Expr) {
		var folded = tryFoldConstant(expr);
		if (folded != null) {
			emitFoldedConstant(folded);
			return;
		}

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
				if (localSlots != null && localSlots.exists(name)) {
					emitWithArg(Op.LOAD_LOCAL, localSlots.get(name));
				} else {
					var upSlot = resolveUpvalueSlot(name);
					if (upSlot >= 0)
						emitWithArg(Op.LOAD_UPVALUE, upSlot);
					else if (globalSlots.exists(name))
						emitWithArg(Op.LOAD_GLOBAL, globalSlots.get(name));
					else
						emitWithString(Op.LOAD_VAR, name);
				}

			case EThis:
				emit(Op.GET_THIS);

			case ENew(className, args):
				// Load the class
				if (globalSlots.exists(className))
					emitWithArg(Op.LOAD_GLOBAL, globalSlots.get(className));
				else
					emitWithString(Op.LOAD_VAR, className);
				// Push arguments
				for (arg in args) {
					compileExpression(arg);
				}
				// Instantiate
				emitWithArg(Op.INSTANTIATE, args.length);

			case EBinary(op, left, right):
				switch (op) {
					case OAnd:
						// Short-circuit &&: if left is falsy, skip right entirely
						// Stack trace: left → DUP → [left,left] → JUMP_IF_FALSE(pops top, jumps) → [left(false)]
						//              or: [left(true)] → POP → [] → right → [right]
						compileExpression(left);
						emit(Op.DUP);
						var skip = emitJump(Op.JUMP_IF_FALSE);
						emit(Op.POP);
						compileExpression(right);
						patchJump(skip);
					case OOr:
						// Short-circuit ||: if left is truthy, skip right entirely
						compileExpression(left);
						emit(Op.DUP);
						var skip = emitJump(Op.JUMP_IF_TRUE);
						emit(Op.POP);
						compileExpression(right);
						patchJump(skip);
					default:
						compileExpression(left);
						compileExpression(right);
						compileBinaryOp(op);
				}

			case EUnary(op, e):
				compileExpression(e);
				compileUnaryOp(op);

			case EPostfix(op, e):
				var isInc = (op == OAdd);
				switch (e) {
					case EIdentifier(name):
						if (localSlots != null && localSlots.exists(name)) {
							emitWithArg(isInc ? Op.INC_LOCAL : Op.DEC_LOCAL, localSlots.get(name));
						} else if (globalSlots.exists(name)) {
							emitWithArg(isInc ? Op.INC_GLOBAL : Op.DEC_GLOBAL, globalSlots.get(name));
						} else {
							// Fallback for LOAD_VAR style if not in slots (less efficient)
							compileExpression(e);
							emit(Op.DUP);
							emitConstant(VNumber(1));
							compileBinaryOp(op);
							emitWithString(Op.STORE_VAR, name);
							emit(Op.POP);
						}
					case EMember(obj, field):
						compileExpression(obj);
						emitWithArg(isInc ? Op.INC_MEMBER : Op.DEC_MEMBER, addString(field));
					case EIndex(obj, idx):
						compileExpression(obj);
						compileExpression(idx);
						emit(isInc ? Op.INC_INDEX : Op.DEC_INDEX);
					default:
						throw "Invalid postfix operand";
				}

			case EMember(object, field):
				compileExpression(object);
				emitWithString(Op.GET_MEMBER, field);

			case EIndex(object, index):
				compileExpression(object);
				compileExpression(index);
				emit(Op.GET_INDEX);

			case ECall(callee, args):
				switch (callee) {
					case EMember(object, field):
						compileExpression(object);
						for (arg in args)
							compileExpression(arg);
						emitCallMember(field, args.length);
					case EIdentifier(name)
						if (currentClassMethodNames != null
							&& currentClassMethodNames.exists(name)
							&& (localSlots == null || !localSlots.exists(name))):
						// Inside class methods, allow bare method calls: foo() => this.foo()
						emit(Op.GET_THIS);
						emitWithString(Op.GET_MEMBER, name);
						for (arg in args)
							compileExpression(arg);
						emitWithArg(Op.CALL, args.length);
					default:
						compileExpression(callee);
						for (arg in args)
							compileExpression(arg);
						emitWithArg(Op.CALL, args.length);
				}

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
				var funcChunk = compileFunction(funcName, params, funcBody, true, null);
				var funcIndex = functions.length;
				functions.push(funcChunk);
				emitWithArg(Op.MAKE_LAMBDA, funcIndex);

			case EIs(expr, typeName):
				emitWithString(Op.LOAD_VAR, "__is__");
				compileExpression(expr);
				emitConstant(VString(typeName));
				emitWithArg(Op.CALL, 2);

			case EAssign(target, value):
				switch (target) {
					case EIdentifier(name):
						compileExpression(value);
						if (localSlots != null && localSlots.exists(name)) {
							emitWithArg(Op.STORE_LOCAL, localSlots.get(name));
						} else {
							var upSlot = resolveUpvalueSlot(name);
							if (upSlot >= 0)
								emitWithArg(Op.STORE_UPVALUE, upSlot);
							else if (globalSlots.exists(name))
								emitWithArg(Op.STORE_GLOBAL, globalSlots.get(name));
							else
								emitWithString(Op.STORE_VAR, name);
						}

					case EMember(object, field):
						// Stack: [value, object] → SET_MEMBER pops object then value, pushes value
						compileExpression(value);
						compileExpression(object);
						emitWithString(Op.SET_MEMBER, field);

					case EIndex(object, index):
						// SET_INDEX pops: value (top), index, object (bottom) → stack [object, index, value]
						compileExpression(object);
						compileExpression(index);
						compileExpression(value);
						emit(Op.SET_INDEX);

					default:
						throw "Invalid assignment target";
				}
		}
	}

	function emitFoldedConstant(value:Value):Void {
		switch (value) {
			case VNull:
				emit(Op.LOAD_NULL);
			case VBool(v):
				emit(v ? Op.LOAD_TRUE : Op.LOAD_FALSE);
			case VNumber(_) | VString(_):
				emitConstant(value);
			default:
				// Mutable/complex values should never be constant-folded in this compiler pass.
				emitConstant(value);
		}
	}

	function tryFoldConstant(expr:Expr):Null<Value> {
		return switch (expr) {
			case ENumber(v): VNumber(v);
			case EString(v): VString(v);
			case EBool(v): VBool(v);
			case ENull: VNull;

			case EUnary(op, e):
				var v = tryFoldConstant(e);
				if (v == null) {
					null;
				} else {
					switch (op) {
						case OSub:
							switch (v) {
								case VNumber(n): VNumber(-n);
								default: null;
							}
						case ONot:
							VBool(!constTruthy(v));
						case OBitNot:
							switch (v) {
								case VNumber(n): VNumber(~Std.int(n));
								default: null;
							}
						default:
							null;
					}
				}

			case EBinary(op, left, right):
				var lv = tryFoldConstant(left);
				var rv = tryFoldConstant(right);
				if (lv == null || rv == null) {
					null;
				} else {
					switch (op) {
						case OAdd:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(a + b);
								case [VString(a), VString(b)]: VString(a + b);
								case [VString(a), _]: VString(a + constToString(rv));
								case [_, VString(b)]: VString(constToString(lv) + b);
								default: null;
							}
						case OSub:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(a - b);
								default: null;
							}
						case OMul:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(a * b);
								default: null;
							}
						case ODiv:
							switch ([lv, rv]) {
								case [VNumber(_), VNumber(0)]: null;
								case [VNumber(a), VNumber(b)]: VNumber(a / b);
								default: null;
							}
						case OMod:
							switch ([lv, rv]) {
								case [VNumber(_), VNumber(0)]: null;
								case [VNumber(a), VNumber(b)]: VNumber(a % b);
								default: null;
							}
						case OBitAnd:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(Std.int(a) & Std.int(b));
								default: null;
							}
						case OBitOr:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(Std.int(a) | Std.int(b));
								default: null;
							}
						case OBitXor:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(Std.int(a) ^ Std.int(b));
								default: null;
							}
						case OShiftLeft:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(Std.int(a) << Std.int(b));
								default: null;
							}
						case OShiftRight:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VNumber(Std.int(a) >> Std.int(b));
								default: null;
							}
						case OEqual:
							VBool(constEquals(lv, rv));
						case ONotEqual:
							VBool(!constEquals(lv, rv));
						case OLess:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VBool(a < b);
								case [VString(a), VString(b)]: VBool(a < b);
								default: null;
							}
						case OGreater:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VBool(a > b);
								case [VString(a), VString(b)]: VBool(a > b);
								default: null;
							}
						case OLessEq:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VBool(a <= b);
								case [VString(a), VString(b)]: VBool(a <= b);
								default: null;
							}
						case OGreaterEq:
							switch ([lv, rv]) {
								case [VNumber(a), VNumber(b)]: VBool(a >= b);
								case [VString(a), VString(b)]: VBool(a >= b);
								default: null;
							}
						default:
							null;
					}
				}

			case EIs(_, _):
				null; // runtime check, cannot fold
			default:
				null;
		};
	}

	inline function constTruthy(v:Value):Bool {
		return switch (v) {
			case VNull: false;
			case VBool(b): b;
			case VNumber(n): n != 0;
			case VString(s): s.length > 0;
			default: true;
		}
	}

	inline function constEquals(a:Value, b:Value):Bool {
		return switch ([a, b]) {
			case [VNumber(x), VNumber(y)]: x == y;
			case [VString(x), VString(y)]: x == y;
			case [VBool(x), VBool(y)]: x == y;
			case [VNull, VNull]: true;
			default: false;
		};
	}

	inline function constToString(v:Value):String {
		return switch (v) {
			case VNumber(n): Std.string(n);
			case VString(s): s;
			case VBool(b): b ? "true" : "false";
			case VNull: "null";
			default: "null";
		};
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

	function compileMatch(subject:Expr, cases:Array<MatchCase>, defaultBody:Null<Array<Stmt>>, isLast:Bool) {
		// Evaluate subject and leave it on stack for each comparison
		// Strategy: compile as a chain of if/else if using the subject value
		// We store the subject in a synthetic local/scope var to avoid re-evaluating it
		var subjectName = '__match_${syntheticCounter++}';

		// Compile subject and store it
		compileExpression(subject);
		if (localSlots != null) {
			emitWithArg(Op.STORE_LOCAL, allocSlot(subjectName));
		} else {
			emitWithString(Op.STORE_LET, subjectName);
		}
		emit(Op.POP);

		var jumpToEnds:Array<Int> = [];

		for (matchCase in cases) {
			// Load subject for comparison
			if (localSlots != null) {
				emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName));
			} else {
				emitWithString(Op.LOAD_VAR, subjectName);
			}

			// Compile pattern test — leaves Bool on stack
			var jumpOverBody:Int;
			switch (matchCase.pattern) {
				case MPValue(expr):
					compileExpression(expr);
					emit(Op.EQ);
					jumpOverBody = emitJump(Op.JUMP_IF_FALSE);

				case MPRange(from, to):
					// Cleanest: __range_match__(subject, from, to) -> Bool
					// Avoids all stack-juggling from short-circuit AND.
					// subject is on stack from loop-top load — pop it, reload via stored name.
					emit(Op.POP); // drop subject from loop-top load
					emitWithString(Op.LOAD_VAR, "__range_match__");
					if (localSlots != null)
						emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName))
					else
						emitWithString(Op.LOAD_VAR, subjectName);
					compileExpression(from);
					compileExpression(to);
					emitWithArg(Op.CALL, 3); // __range_match__(subject, from, to)
					jumpOverBody = emitJump(Op.JUMP_IF_FALSE);

				case MPType(typeName):
					// Compare type() result against type name string
					// Reuse the native "type" function
					emitWithString(Op.LOAD_VAR, "type");
					// swap: we need type(subject) but subject is TOS
					// Easier: load subject fresh
					emit(Op.POP); // pop the duplicate subject
					if (localSlots != null)
						emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName))
					else
						emitWithString(Op.LOAD_VAR, subjectName);
					emitWithArg(Op.CALL, 1); // type(subject)
					emitConstant(VString(typeName));
					emit(Op.EQ);
					jumpOverBody = emitJump(Op.JUMP_IF_FALSE);

				case MPBind(name):
					// Always matches — bind subject to name in body scope
					emit(Op.POP); // pop the loaded subject (binding handled below)
					emit(Op.LOAD_TRUE);
					jumpOverBody = emitJump(Op.JUMP_IF_FALSE); // never jumps
					// Bind: store subject as name before body
					if (localSlots != null) {
						emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName));
						emitWithArg(Op.STORE_LOCAL, allocSlot(name));
						emit(Op.POP);
					} else {
						emitWithString(Op.LOAD_VAR, subjectName);
						emitWithString(Op.STORE_LET, name);
						emit(Op.POP);
					}

				case MPEnum(variantName, binds):
					// Runtime check: __enum_variant_match__(subject, "variantName")
					// Returns true only if subject is VEnumValue with matching variant.
					// Falls through to false (skip body) if subject is not an enum at all.
					emitWithString(Op.LOAD_VAR, "__enum_variant_match__");
					// subject is on stack — swap: we need [fn, subject, variantStr] for CALL 2
					// reload subject from stored name (it was already popped by the load above)
					// Actually subject is still on stack — LOAD_VAR doesn't pop it
					// Stack: [subject, __enum_variant_match__fn]
					// We need: [__enum_variant_match__fn, subject, variantStr]
					// So: pop subject, load fn first, reload subject, push variant
					// Cleanest: emit POP first (drop the subject from loop-top load),
					// then LOAD_VAR fn, LOAD_VAR subjectName, CONST variantName, CALL 2
					emit(Op.POP); // drop the subject loaded at loop top
					emitWithString(Op.LOAD_VAR, "__enum_variant_match__");
					if (localSlots != null)
						emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName))
					else
						emitWithString(Op.LOAD_VAR, subjectName);
					emitConstant(VString(variantName));
					emitWithArg(Op.CALL, 2);
					jumpOverBody = emitJump(Op.JUMP_IF_FALSE);
					// Bind payload fields if any
					for (i in 0...binds.length) {
						var bname = binds[i];
						if (bname == null) continue;
						// Load subject.values[i]
						if (localSlots != null)
							emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName))
						else
							emitWithString(Op.LOAD_VAR, subjectName);
						emitWithString(Op.GET_MEMBER, "values");
						emitConstant(VNumber(i));
						emit(Op.GET_INDEX);
						if (localSlots != null)
							emitWithArg(Op.STORE_LOCAL, allocSlot(bname))
						else
							emitWithString(Op.STORE_LET, bname);
						emit(Op.POP);
					}

				case MPArray(elements):
					// Match if subject is array of right length, bind elements
					// type(subject) == "Array" && subject.length == elements.length
					emit(Op.POP); // pop loaded subject
					if (localSlots != null)
						emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName))
					else
						emitWithString(Op.LOAD_VAR, subjectName);
					emitWithString(Op.GET_MEMBER, "length");
					emitConstant(VNumber(elements.length));
					emit(Op.EQ);
					jumpOverBody = emitJump(Op.JUMP_IF_FALSE);
					// Bind each element to its name (if it's an identifier)
					for (i in 0...elements.length) {
						switch (elements[i]) {
							case EIdentifier(name) if (name != "_"):
								if (localSlots != null)
									emitWithArg(Op.LOAD_LOCAL, localSlots.get(subjectName))
								else
									emitWithString(Op.LOAD_VAR, subjectName);
								emitConstant(VNumber(i));
								emit(Op.GET_INDEX);
								if (localSlots != null)
									emitWithArg(Op.STORE_LOCAL, allocSlot(name))
								else
									emitWithString(Op.STORE_LET, name);
								emit(Op.POP);
							default:
						}
					}
			}

			// Compile body — last statement leaves its value on the stack (match as expression)
			for (i in 0...matchCase.body.length) {
				var bodyIsLast = (i == matchCase.body.length - 1);
				compileStatement(matchCase.body[i], bodyIsLast);
			}
			// Jump to end of match (skipping other cases)
			jumpToEnds.push(emitJump(Op.JUMP));
			// Patch the "pattern didn't match" jump to here (next case)
			patchJump(jumpOverBody);
		}

		// Default body
		if (defaultBody != null) {
			for (i in 0...defaultBody.length) {
				var bodyIsLast = (i == defaultBody.length - 1);
				compileStatement(defaultBody[i], bodyIsLast);
			}
		} else {
			// No default — push null as the match result when nothing matched
			emit(Op.LOAD_NULL);
		}

		// Patch all "jump to end" targets — everyone lands here with a value on stack
		for (j in jumpToEnds)
			patchJump(j);
	}

	function compileFunction(name:String, params:Array<Param>, body:Array<Stmt>, isLambda:Bool, classMethodNames:Map<String, Bool>):FunctionChunk {
		var savedChunk = chunk;
		var savedConstants = constants;
		var savedFunctions = functions;
		var savedStrings = strings;
		var savedStringMap = stringMap;
		var savedTryDepth = tryDepth;
		var savedLocalSlots = localSlots;
		var savedNextLocalSlot = nextLocalSlot;
		var savedUpvalueSlots = upvalueSlots;
		var savedUpvalueNames = upvalueNames;
		var savedEnclosingLocalSlots = enclosingLocalSlots;
		var savedEnclosingUpvalueSlots = enclosingUpvalueSlots;
		var savedClassMethodNames = currentClassMethodNames;
		tryDepth = 0;
		currentClassMethodNames = classMethodNames;
		enclosingLocalSlots = savedLocalSlots;
		enclosingUpvalueSlots = savedUpvalueSlots;

		// Set up fresh slot tracking for this function
		localSlots = new Map();
		nextLocalSlot = 0;
		upvalueSlots = new Map();
		upvalueNames = [];
		// Pre-register params as slots 0..N-1
		for (p in params) {
			localSlots.set(p.name, nextLocalSlot++);
		}

		constants = [];
		functions = [];
		strings = [];
		stringMap = new Map();
		chunk = {
			instructions: [],
			constants: constants,
			functions: functions,
			strings: strings,
			globalNames: globalNames,
			globalConstMask: globalConstMask
		};

		for (stmt in body) {
			compileStatement(stmt);
		}

		emit(Op.LOAD_NULL);
		emit(Op.RETURN);

		// Build localNames array indexed by slot number
		var slotCount = nextLocalSlot;
		var localNames:Array<String> = [for (_ in 0...slotCount) ""];
		for (varName in localSlots.keys())
			localNames[localSlots.get(varName)] = varName;

		var funcChunk:FunctionChunk = {
			name: name,
			paramCount: params.length,
			paramNames: [for (p in params) p.name],
			chunk: chunk,
			isLambda: isLambda,
			localCount: slotCount,
			localNames: localNames,
			localSlots: localSlots, // preserve Map<String,Int> for O(1) slot lookup in call()
			upvalueNames: upvalueNames
		};
		// Also store localNames on the Chunk so run() can access it for closure building
		chunk.localNames = localNames;

		chunk = savedChunk;
		constants = savedConstants;
		functions = savedFunctions;
		strings = savedStrings;
		stringMap = savedStringMap;
		tryDepth = savedTryDepth;
		localSlots = savedLocalSlots;
		nextLocalSlot = savedNextLocalSlot;
		upvalueSlots = savedUpvalueSlots;
		upvalueNames = savedUpvalueNames;
		enclosingLocalSlots = savedEnclosingLocalSlots;
		enclosingUpvalueSlots = savedEnclosingUpvalueSlots;
		currentClassMethodNames = savedClassMethodNames;

		return funcChunk;
	}

	// Returns true if any direct child statement is SLet or SConst (shallow check).
	// Used to avoid emitting ENTER/EXIT_SCOPE on blocks that don't need it.
	static function blockHasLetDecl(stmts:Array<Stmt>):Bool {
		for (s in stmts) switch (s) {
			case SLet(_, _, _) | SConst(_, _, _): return true;
			default:
		}
		return false;
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

	function emitCallMember(field:String, argc:Int) {
		if (argc < 0 || argc > 0xFFFF)
			throw 'Too many call arguments for CALL_MEMBER: $argc';
		var fieldIdx = addString(field);
		if (fieldIdx < 0 || fieldIdx > 0xFFFF)
			throw 'String pool index out of CALL_MEMBER range: $fieldIdx';
		emitWithArg(Op.CALL_MEMBER, (fieldIdx << 16) | argc);
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
	continues:Array<Int>,
	tryDepth:Int
}
