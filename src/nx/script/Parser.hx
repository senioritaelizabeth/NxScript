package nx.script;

import nx.script.Token;
import nx.script.AST;

/**
 * Recursive descent parser. Reads tokens, produces an AST.
 * It's not fancy. It doesn't need to be.
 *
 * Error recovery strategy: throw immediately. You get one error at a time.
 * Parse errors will tell you the line and column. Fix the line. Re-run. You know the drill.
 */
class Parser {
	var tokens:Array<TokenPos>;
	var pos:Int = 0;
	var strictSemicolons:Bool;
	var syntheticCounter:Int = 0;
	var rules:SyntaxRules = null;

	public function new(tokens:Array<TokenPos>, strictSemicolons:Bool = false, ?rules:SyntaxRules) {
		this.tokens = tokens;
		this.strictSemicolons = strictSemicolons;
		this.rules = rules;
	}

	public function parse():Array<StmtWithPos> {
		var statements:Array<StmtWithPos> = [];

		while (!isEOF()) {
			skipSeparators();
			if (isEOF())
				break;
			var startToken = peek();
			var stmt = parseStatement();
			consumeStatementTerminator(stmt);
			statements.push({
				stmt: stmt,
				line: startToken.line,
				col: startToken.col
			});
		}

		return statements;
	}

	function parseStatement():Stmt {
		var token = peek();

		return switch (token.token) {
			case TKeyword(KLet): parseLet();
			case TKeyword(KVar): parseVar();
			case TKeyword(KConst): parseConst();
			case TKeyword(KFunc), TKeyword(KFn), TKeyword(KFun), TKeyword(KFunction): parseFunc();
			case TKeyword(KClass): parseClass();
			case TKeyword(KReturn): parseReturn();
			case TKeyword(KIf): parseIf();
			case TKeyword(KWhile): parseWhile();
			case TKeyword(KFor): parseFor();
			case TKeyword(KBreak): {advance(); SBreak;}
			case TKeyword(KContinue): {advance(); SContinue;}
			case TKeyword(KTry): parseTryCatch();
			case TKeyword(KThrow): parseThrow();
			case TKeyword(KMatch): parseMatch();
			case TKeyword(KSwitch): parseSwitch();
			case TKeyword(KUsing): parseUsing();
			case TKeyword(KEnum): parseEnum();
			case TKeyword(KAbstract): parseAbstract();
			case TKeyword(KStatic): parseStatic();
			case TLeftBrace: parseBlock();
			default: SExpr(parseExpression());
		}
	}

	function parseLet():Stmt {
		advance(); // consume 'let'
		// Destructure: let [a, b] = expr  or  let {x, y} = expr
		if (check(TLeftBracket)) return parseDestructureArray(false);
		if (check(TLeftBrace))   return parseDestructureDict(false);
		var name = expectIdentifier();
		var type = null;
		if (match(TColon)) type = parseTypeHint();
		var init = null;
		if (match(TOperator(OAssign))) init = parseExpression();
		return SLet(name, type, init);
	}

	function parseVar():Stmt {
		advance(); // consume 'var'
		// Destructure: var [a, b] = expr  or  var {x, y} = expr
		if (check(TLeftBracket)) return parseDestructureArray(true);
		if (check(TLeftBrace))   return parseDestructureDict(true);
		var name = expectIdentifier();
		var type = null;
		if (match(TColon)) type = parseTypeHint();
		var init = null;
		if (match(TOperator(OAssign))) init = parseExpression();
		return SVar(name, type, init);
	}

	function parseDestructureArray(isVar:Bool):Stmt {
		advance(); // consume [
		var names:Array<Null<String>> = [];
		skipNewlines();
		while (!check(TRightBracket) && !isEOF()) {
			skipNewlines();
			if (check(TRightBracket)) break;
			// _ means skip this element
			if (check(TIdentifier("_"))) { advance(); names.push(null); }
			else names.push(expectIdentifier());
			skipNewlines();
			if (!match(TComma)) break;
		}
		expect(TRightBracket, "Expected ']' in array destructure");
		expect(TOperator(OAssign), "Expected '=' in destructure declaration");
		var init = parseExpression();
		return SDestructureArray(names, init);
	}

	function parseDestructureDict(isVar:Bool):Stmt {
		advance(); // consume {
		var names:Array<String> = [];
		skipNewlines();
		while (!check(TRightBrace) && !isEOF()) {
			skipNewlines();
			if (check(TRightBrace)) break;
			names.push(expectIdentifier());
			skipNewlines();
			if (!match(TComma)) break;
		}
		expect(TRightBrace, "Expected '}' in dict destructure");
		expect(TOperator(OAssign), "Expected '=' in destructure declaration");
		var init = parseExpression();
		return SDestructureDict(names, init);
	}

	function parseConst():Stmt {
		advance(); // consume 'const'
		var name = expectIdentifier();
		var type = null;

		if (match(TColon)) {
			type = parseTypeHint();
		}

		expect(TOperator(OAssign), "Constants must be initialized");
		var init = parseExpression();

		return SConst(name, type, init);
	}

	function parseFunc():Stmt {
		advance(); // consume 'func'
		var name = expectIdentifier();

		expect(TLeftParen, "Expected '(' after function name");
		var params = parseParameters();
		expect(TRightParen, "Expected ')' after parameters");

		var returnType = null;
		if (match(TArrow) || match(TColon)) {
			returnType = parseTypeHint();
		}

		skipNewlines();
		expect(TLeftBrace, "Expected '{' before function body");
		var body = parseBlockBody();
		expect(TRightBrace, "Expected '}' after function body");

		return SFunc(name, params, returnType, body);
	}

	function parseClass():Stmt {
		advance(); // consume 'class'
		var name = expectIdentifier();

		var superClass:Null<String> = null;
		if (match(TKeyword(KExtends))) {
			superClass = expectIdentifier();
		}

		skipNewlines();
		expect(TLeftBrace, "Expected '{' before class body");

		var fields:Array<ClassField> = [];
		var methods:Array<ClassMethod> = [];

		skipSeparators();
		while (!check(TRightBrace) && !isEOF()) {
			var token = peek();

			switch (token.token) {
				case TKeyword(KVar):
					// Field declaration
					advance(); // consume 'var'
					var fieldName = expectIdentifier();
					var fieldType:Null<TypeHint> = null;
					var fieldInit:Null<Expr> = null;

					if (match(TColon)) {
						fieldType = parseTypeHint();
					}

					if (match(TOperator(OAssign))) {
						fieldInit = parseExpression();
					}

					fields.push({
						name: fieldName,
						type: fieldType,
						init: fieldInit
					});

				case TKeyword(KFunc), TKeyword(KFn), TKeyword(KFun), TKeyword(KFunction):
					// Method declaration
					advance(); // consume 'func'

					// Method name - 'new' is allowed as a special case for constructors
					var methodName:String;
					var token = peek();
					switch (token.token) {
						case TIdentifier(name):
							advance();
							methodName = name;
						case TKeyword(KNew):
							advance();
							methodName = "new";
						default:
							error("Expected method name");
							return null; // Unreachable
					}

					var isConstructor = (methodName == "new");

					expect(TLeftParen, "Expected '(' after method name");
					var params = parseParameters();
					expect(TRightParen, "Expected ')' after parameters");

					var returnType:Null<TypeHint> = null;
					if (match(TArrow) || match(TColon)) {
						returnType = parseTypeHint();
					}

					skipNewlines();
					expect(TLeftBrace, "Expected '{' before method body");
					var body = parseBlockBody();
					expect(TRightBrace, "Expected '}' after method body");

					methods.push({
						name: methodName,
						params: params,
						returnType: returnType,
						body: body,
						isConstructor: isConstructor
					});

				case TKeyword(KStatic):
					// static var / static func inside class
					advance(); // consume 'static'
					skipNewlines();
					if (match(TKeyword(KVar))) {
						var fieldName = expectIdentifier();
						if (match(TColon)) parseTypeHint();
						var fieldInit:Null<Expr> = null;
						if (match(TOperator(OAssign))) fieldInit = parseExpression();
						fields.push({ name: fieldName, type: null, init: fieldInit, isStatic: true });
					} else if (match(TKeyword(KFunc)) || match(TKeyword(KFunction)) || match(TKeyword(KFn)) || match(TKeyword(KFun))) {
						var methodName = expectMemberName();
						expect(TLeftParen, "Expected '(' after static method name");
						var params = parseParameters();
						expect(TRightParen, "Expected ')' after static method params");
						if (match(TArrow) || match(TColon)) parseTypeHint();
						skipNewlines();
						expect(TLeftBrace, "Expected '{' before static method body");
						var body = parseBlockBody();
						expect(TRightBrace, "Expected '}' after static method body");
						methods.push({ name: methodName, params: params, returnType: null, body: body, isConstructor: false, isStatic: true });
					} else {
						error("Expected 'var' or 'func' after 'static' in class body");
					}

				default:
					error("Expected 'var', 'func', or 'static' in class body");
			}

			skipSeparators();
		}

		expect(TRightBrace, "Expected '}' after class body");

		return SClass(name, superClass, methods, fields);
	}

	function parseParameters():Array<Param> {
		var params:Array<Param> = [];

		if (check(TRightParen))
			return params;

		do {
			skipNewlines();
			// Allow trailing comma: if next is ) after comma, stop
			if (check(TRightParen))
				break;
			var name = expectIdentifier();
			var type = null;

			if (match(TColon)) {
				type = parseTypeHint();
			}

			params.push({name: name, type: type});
			skipNewlines();
		} while (match(TComma));

		return params;
	}

	function parseTypeHint():TypeHint {
		var token = peek();

		return switch (token.token) {
			case TIdentifier("Number"): {advance(); TNumber;}
			case TIdentifier("String"): {advance(); TString;}
			case TIdentifier("Bool"): {advance(); TBool;}
			case TIdentifier("Any"): {advance(); TAny;}
			case TLeftBracket:
				advance();
				var elementType = parseTypeHint();
				expect(TRightBracket, "Expected ']' after array type");
				TArray(elementType);
			case TIdentifier(name):
				advance();
				// Haxe generics: Array<T>, Map<K,V>, etc — consume and discard type params
				if (check(TOperator(OLess))) {
					advance(); // consume <
					var depth = 1;
					while (!isEOF() && depth > 0) {
						if (check(TOperator(OLess)))       { depth++; advance(); }
						else if (check(TOperator(OGreater))){ depth--; advance(); }
						else if (check(TNewLine) || check(TRightBrace)) break;
						else advance();
					}
				}
				TCustom(name);
			default:
				throw 'Expected type hint at line ${token.line}, col ${token.col}';
		}
	}

	function parseReturn():Stmt {
		advance(); // consume 'return'

		if (check(TNewLine) || check(TSemicolon) || check(TRightBrace) || isEOF()) {
			return SReturn(null);
		}

		return SReturn(parseExpression());
	}

	/**
	 * Parses either a braced block { ... } or a single statement.
	 * Allows braceless if/while/for bodies:
	 *   if (x) return 1
	 *   while (x > 0) x--
	 */
	function parseBody():Array<Stmt> {
		if (check(TLeftBrace)) {
			advance();
			var body = parseBlockBody();
			expect(TRightBrace, "Expected '}' after body");
			return body;
		} else {
			// Single statement (no braces) — newlines allowed before it
			skipNewlines();
			var stmt = parseStatement();
			consumeSingleStmtTerminator(stmt);
			return [stmt];
		}
	}

	/** Consume terminator for a single-stmt braceless body — softer than consumeStatementTerminator */
	function consumeSingleStmtTerminator(stmt:Stmt):Void {
		if (statementNeedsTerminator(stmt))
			skipSeparators();
	}

	function parseIf():Stmt {
		advance(); // consume 'if'
		return parseIfRest();
	}

	function parseIfRest():Stmt {
		expect(TLeftParen, "Expected '(' after 'if'");
		var condition = parseExpression();
		expect(TRightParen, "Expected ')' after condition");

		var thenBody = parseBody();

		var elseBody = null;
		skipSeparators();

		if (match(TKeyword(KElse))) {
			skipSeparators();
			if (check(TKeyword(KIf))) {
				elseBody = [parseIf()];
			} else {
				elseBody = parseBody();
			}
		} else if (check(TKeyword(KElseIf))) {
			advance();
			elseBody = [parseIfRest()];
		}

		return SIf(condition, thenBody, elseBody);
	}

	function parseWhile():Stmt {
		advance(); // consume 'while'

		expect(TLeftParen, "Expected '(' after 'while'");
		var condition = parseExpression();
		expect(TRightParen, "Expected ')' after condition");

		var body = parseBody();

		return SWhile(condition, body);
	}

	function parseFor():Stmt {
		advance(); // consume 'for'

		expect(TLeftParen, "Expected '(' after 'for'");
		var variable = expectIdentifier();

		var forKind = peek().token;
		var loopStmt:Stmt;
		switch (forKind) {
			case TKeyword(KIn), TKeyword(KOf):
				advance();
				var iterable = parseExpression();
				expect(TRightParen, "Expected ')' after for header");
				loopStmt = SFor(variable, iterable, parseBody());

			case TKeyword(KFrom):
				advance();
				var fromExpr = parseExpression();
				expect(TKeyword(KTo), "Expected 'to' in for-from-to loop");
				var toExpr = parseExpression();
				expect(TRightParen, "Expected ')' after for header");
				loopStmt = SForRange(variable, fromExpr, toExpr, parseBody());

			default:
				error("Expected 'in', 'of', or 'from' in for loop");
				return null;
		}

		return loopStmt;
	}

	function parseBlock():Stmt {
		expect(TLeftBrace, "Expected '{'");
		var stmts = parseBlockBody();
		expect(TRightBrace, "Expected '}'");
		return SBlock(stmts);
	}

	function parseTryCatch():Stmt {
		advance(); // consume 'try'
		expect(TLeftBrace, "Expected '{' after 'try'");
		var body = parseBlockBody();
		expect(TRightBrace, "Expected '}' after try body");

		skipNewlines();
		expect(TKeyword(KCatch), "Expected 'catch' after try body");
		expect(TLeftParen, "Expected '(' after 'catch'");
		var catchVar = expectIdentifier();
		expect(TRightParen, "Expected ')' after catch variable");
		expect(TLeftBrace, "Expected '{' after catch clause");
		var catchBody = parseBlockBody();
		expect(TRightBrace, "Expected '}' after catch body");

		return STryCatch(body, catchVar, catchBody);
	}

	function parseThrow():Stmt {
		advance(); // consume 'throw'
		return SThrow(parseExpression());
	}

	function parseBlockBody():Array<Stmt> {
		var stmts:Array<Stmt> = [];
		skipSeparators();

		while (!check(TRightBrace) && !isEOF()) {
			var stmt = parseStatement();
			consumeStatementTerminator(stmt);
			stmts.push(stmt);
		}

		return stmts;
	}

	// Expression parsing with operator precedence
	function parseExpression():Expr {
		var expr = parseAssignment();
		// `is` type check: expr is TypeName
		if (check(TKeyword(KIs))) {
			advance();
			var typeName = expectIdentifier();
			return EIs(expr, typeName);
		}
		return expr;
	}

	function parseRange():Expr {
		var left = parseNullCoal();
		while (match(TRange)) {
			var right = parseNullCoal();
			left = ECall(EIdentifier("range"), [left, right]);
		}
		return left;
	}

	// ?? has lower precedence than || but higher than assignment
	function parseNullCoal():Expr {
		var left = parseLogicalOr();
		while (match(TOperator(ONullCoal))) {
			var right = parseLogicalOr();
			left = ENullCoal(left, right);
		}
		return left;
	}

	function parseAssignment():Expr {
		var expr = parseRange();

		if (match(TOperator(OAssign))) {
			var value = parseAssignment();
			return EAssign(expr, value);
		}

		// Compound assignment operators (+=, -=, etc.)
		var compoundOp = switch (peek().token) {
			case TOperator(OAddAssign):
				advance();
				OAdd;
			case TOperator(OSubAssign):
				advance();
				OSub;
			case TOperator(OMulAssign):
				advance();
				OMul;
			case TOperator(ODivAssign):
				advance();
				ODiv;
			case TOperator(OModAssign):
				advance();
				OMod;
			default: null;
		}

		if (compoundOp != null) {
			var value = parseAssignment();
			// Transform: x += y  =>  x = x + y
			return EAssign(expr, EBinary(compoundOp, expr, value));
		}

		return expr;
	}

	function parseLogicalOr():Expr {
		var left = parseLogicalAnd();

		while (match(TOperator(OOr))) {
			var op = OOr;
			var right = parseLogicalAnd();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseLogicalAnd():Expr {
		var left = parseBitwiseOr();

		while (match(TOperator(OAnd))) {
			var op = OAnd;
			var right = parseBitwiseOr();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseBitwiseOr():Expr {
		var left = parseBitwiseXor();

		while (match(TOperator(OBitOr))) {
			var op = OBitOr;
			var right = parseBitwiseXor();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseBitwiseXor():Expr {
		var left = parseBitwiseAnd();

		while (match(TOperator(OBitXor))) {
			var op = OBitXor;
			var right = parseBitwiseAnd();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseBitwiseAnd():Expr {
		var left = parseEquality();

		while (match(TOperator(OBitAnd))) {
			var op = OBitAnd;
			var right = parseEquality();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseEquality():Expr {
		var left = parseComparison();

		while (true) {
			var token = peek().token;
			var op = switch (token) {
				case TOperator(OEqual): {advance(); OEqual;}
				case TOperator(ONotEqual): {advance(); ONotEqual;}
				default: break;
			}

			var right = parseComparison();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseComparison():Expr {
		var left = parseShift();

		while (true) {
			var token = peek().token;
			var op = switch (token) {
				case TOperator(OLess): {advance(); OLess;}
				case TOperator(OGreater): {advance(); OGreater;}
				case TOperator(OLessEq): {advance(); OLessEq;}
				case TOperator(OGreaterEq): {advance(); OGreaterEq;}
				default: break;
			}

			var right = parseShift();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseShift():Expr {
		var left = parseTerm();

		while (true) {
			var token = peek().token;
			var op = switch (token) {
				case TOperator(OShiftLeft): {advance(); OShiftLeft;}
				case TOperator(OShiftRight): {advance(); OShiftRight;}
				default: break;
			}

			var right = parseTerm();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseTerm():Expr {
		var left = parseFactor();

		while (true) {
			var token = peek().token;
			var op = switch (token) {
				case TOperator(OAdd): {advance(); OAdd;}
				case TOperator(OSub): {advance(); OSub;}
				default: break;
			}

			var right = parseFactor();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseFactor():Expr {
		var left = parseUnary();

		while (true) {
			var token = peek().token;
			var op = switch (token) {
				case TOperator(OMul): {advance(); OMul;}
				case TOperator(ODiv): {advance(); ODiv;}
				case TOperator(OMod): {advance(); OMod;}
				default: break;
			}

			var right = parseUnary();
			left = EBinary(op, left, right);
		}

		return left;
	}

	function parseUnary():Expr {
		var token = peek().token;

		return switch (token) {
			case TOperator(ONot), TOperator(OSub), TOperator(OBitNot):
				var op = switch (token) {
					case TOperator(ONot): ONot;
					case TOperator(OSub): OSub;
					case TOperator(OBitNot): OBitNot;
					default: throw "Unexpected";
				}
				advance();
				EUnary(op, parseUnary());
			case TOperator(OIncrement):
				advance();
				var target = parsePostfix();
				EAssign(target, EBinary(OAdd, target, ENumber(1)));
			case TOperator(ODecrement):
				advance();
				var target = parsePostfix();
				EAssign(target, EBinary(OSub, target, ENumber(1)));
			default:
				parsePostfix();
		}
	}

	function parsePostfix():Expr {
		var expr = parsePrimary();
		var running = true;

		while (running) {
			var token = peek().token;
			expr = switch (token) {
				case TOperator(OOptChain): // ?.
					advance();
					var field = expectMemberName();
					EOptChain(expr, field);

				case TDot:
					advance();
					var field = expectMemberName(); // allows keywords as field names (d.enum, x.new)
					EMember(expr, field);

				case TLeftBracket:
					advance();
					var index = parseExpression();
					expect(TRightBracket, "Expected ']' after index");
					EIndex(expr, index);

				case TLeftParen:
					advance();
					var args = parseArguments();
					expect(TRightParen, "Expected ')' after arguments");
					ECall(expr, args);

				case TOperator(OIncrement):
					advance();
					expr = EPostfix(OAdd, expr);

				case TOperator(ODecrement):
					advance();
					expr = EPostfix(OSub, expr);

				default:
					running = false;
					expr;
			}
		}

		return expr;
	}

	function parseArguments():Array<Expr> {
		var args:Array<Expr> = [];

		if (check(TRightParen))
			return args;

		do {
			skipNewlines();
			// Allow trailing comma before )
			if (check(TRightParen))
				break;
			args.push(parseExpression());
			skipNewlines();
		} while (match(TComma));

		return args;
	}

	function parsePrimary():Expr {
		var token = peek();

		return switch (token.token) {
			case TNumber(v):
				advance();
				ENumber(v);

			case TString(v):
				advance();
				EString(v);

			case TBool(v):
				advance();
				EBool(v);

			case TNull:
				advance();
				ENull;

			case TKeyword(KThis):
				advance();
				EThis;

			case TKeyword(KNew):
				advance();
				var className = expectIdentifier();
				expect(TLeftParen, "Expected '(' after class name in 'new' expression");
				var args = parseArguments();
				expect(TRightParen, "Expected ')' after arguments");
				ENew(className, args);

			case TIdentifier(name):
				advance();
				// Shorthand lambda: x => expr  or  x => { stmts }
				if (check(TFatArrow)) {
					advance(); // consume =>
					if (check(TLeftBrace)) {
						advance();
						var body = parseBlockBody();
						expect(TRightBrace, "Expected '}' after lambda body");
						return ELambda([{name: name, type: null}], Right(body));
					} else {
						var expr = parseExpression();
						return ELambda([{name: name, type: null}], Left(expr));
					}
				}
				EIdentifier(name);

			case TLeftParen:
				advance();
				// Could be grouped expression or lambda
				// Look ahead to detect lambda: () -> or (id) -> or (id, id) ->  (also =>)
				var savedPos = pos;
				var isLambda = false;

				if (check(TRightParen)) {
					// Could be () -> ...
					advance(); // skip )
					if (check(TArrow) || check(TFatArrow)) {
						isLambda = true;
					}
				} else if (isIdentifier()) {
					// Could be (x) -> or (x, y) ->
					while (isIdentifier()) {
						advance();
						if (check(TComma)) {
							advance();
						} else {
							break;
						}
					}
					if (check(TRightParen)) {
						advance();
						if (check(TArrow) || check(TFatArrow)) {
							isLambda = true;
						}
					}
				}

				pos = savedPos; // restore position

				if (isLambda) {
					pos--; // back to the (
					return parseLambda();
				}

				var expr = parseExpression();
				expect(TRightParen, "Expected ')' after expression");
				expr;

			case TKeyword(KFunc) | TKeyword(KFn) | TKeyword(KFun) | TKeyword(KFunction):
				// Anonymous function as expression: function(a:T, b:T) { ... }
				advance(); // consume func/function
				expect(TLeftParen, "Expected '(' after function");
				var params = parseParameters();
				expect(TRightParen, "Expected ')' after parameters");
				if (match(TColon) || match(TArrow)) parseTypeHint(); // optional return type
				skipNewlines();
				expect(TLeftBrace, "Expected '{' before function body");
				var body = parseBlockBody();
				expect(TRightBrace, "Expected '}' after function body");
				ELambda(params, Right(body));

			case TLeftBracket:
				parseArrayLiteral();

			case TLeftBrace:
				parseDictLiteral();

			default:
				throw 'Unexpected token ${token.token} at line ${token.line}, col ${token.col}';
		}
	}

	function parseLambda():Expr {
		expect(TLeftParen, "Expected '(' for lambda");
		var params = parseParameters();
		expect(TRightParen, "Expected ')' after lambda parameters");
		// Support both -> and => as lambda arrow
		if (!match(TArrow) && !match(TFatArrow))
			throw 'Expected "->" or "=>" for lambda at line ${peek().line}, col ${peek().col}';

		if (check(TLeftBrace)) {
			advance();
			var body = parseBlockBody();
			expect(TRightBrace, "Expected '}' after lambda body");
			return ELambda(params, Right(body));
		} else {
			var expr = parseExpression();
			return ELambda(params, Left(expr));
		}
	}

	function parseArrayLiteral():Expr {
		advance(); // consume '['
		var elements:Array<Expr> = [];

		skipNewlines();
		if (!check(TRightBracket)) {
			do {
				skipNewlines();
				// Allow trailing comma before ]
				if (check(TRightBracket))
					break;
				elements.push(parseExpression());
				skipNewlines();
			} while (match(TComma));
		}

		expect(TRightBracket, "Expected ']' after array elements");
		return EArray(elements);
	}

	function parseDictLiteral():Expr {
		advance(); // consume '{'
		var pairs:Array<{key:Expr, value:Expr}> = [];

		skipNewlines();
		if (!check(TRightBrace)) {
			do {
				skipNewlines();
				// Allow trailing comma before }
				if (check(TRightBrace))
					break;
				var key = parseExpression();
				expect(TColon, "Expected ':' after dictionary key");
				var value = parseExpression();
				pairs.push({key: key, value: value});
				skipNewlines();
			} while (match(TComma));
		}

		expect(TRightBrace, "Expected '}' after dictionary pairs");
		return EDict(pairs);
	}

	function parseSwitch():Stmt {
		advance(); // consume 'switch'
		expect(TLeftParen, "Expected '(' after switch");
		var subject = parseExpression();
		expect(TRightParen, "Expected ')' after switch expression");
		skipNewlines();
		expect(TLeftBrace, "Expected '{' after switch(...)");
		skipSeparators();

		var cases:Array<MatchCase> = [];
		var defaultBody:Null<Array<Stmt>> = null;

		while (!check(TRightBrace) && !isEOF()) {
			skipSeparators();
			if (check(TRightBrace)) break;

			if (match(TKeyword(KDefault))) {
				expect(TColon, "Expected ':' after default");
				defaultBody = parseSwitchBody();
			} else {
				expect(TKeyword(KCase), "Expected 'case' in switch block");
				var pattern = parseMatchPattern();
				expect(TColon, "Expected ':' after case value");
				var body = parseSwitchBody();
				cases.push({ pattern: pattern, body: body });
			}
			skipSeparators();
		}

		expect(TRightBrace, "Expected '}' after switch block");
		return SMatch(subject, cases, defaultBody);
	}

	function parseSwitchBody():Array<Stmt> {
		var stmts:Array<Stmt> = [];
		skipSeparators();
		// Collect statements until next case/default/}
		while (!isEOF() && !check(TRightBrace)
			&& !check(TKeyword(KCase)) && !check(TKeyword(KDefault))) {
			var s = parseStatement();
			stmts.push(s);
			// Handle break keyword — stop collecting (don't emit anything, match doesn't fall through)
			if (check(TKeyword(KBreak))) { advance(); skipSeparators(); break; }
			skipSeparators();
		}
		return stmts;
	}

	function parseMatch():Stmt {
		advance(); // consume 'match'
		var subject = parseExpression();
		expect(TLeftBrace, "Expected '{' after match expression");
		skipSeparators();

		var cases:Array<MatchCase> = [];
		var defaultBody:Null<Array<Stmt>> = null;

		while (!check(TRightBrace) && !isEOF()) {
			skipSeparators();
			if (check(TRightBrace)) break;

			if (match(TKeyword(KDefault))) {
				// default => body
				if (!match(TArrow) && !match(TFatArrow))
					throw 'Expected "=>" after "default" at line ${peek().line}';
				defaultBody = parseMatchBody();
			} else {
				expect(TKeyword(KCase), "Expected 'case' in match block");
				var pattern = parseMatchPattern();
				if (!match(TArrow) && !match(TFatArrow))
					throw 'Expected "=>" after case pattern at line ${peek().line}';
				var body = parseMatchBody();
				cases.push({ pattern: pattern, body: body });
			}
			skipSeparators();
		}

		expect(TRightBrace, "Expected '}' after match block");
		return SMatch(subject, cases, defaultBody);
	}

	function parseMatchPattern():MatchPattern {
		var tok = peek();
		return switch (tok.token) {
			// Range: 1...5
			case TNumber(_):
				var expr = parsePrimary();
				if (check(TRange)) {
					advance(); // consume ...
					var toExpr = parsePrimary();
					MPRange(expr, toExpr);
				} else {
					MPValue(expr);
				}
			// String/Bool/Null literals
			case TString(_) | TBool(_) | TNull:
				MPValue(parsePrimary());
			// Negative number: -5
			case TOperator(OSub):
				MPValue(parseUnary());
			// Type name, enum variant, or bind variable
			case TIdentifier(name):
				advance();
				// Enum variant with payload binds: case Ok(msg) or case Error(code, _)
				if (check(TLeftParen)) {
					advance();
					var binds:Array<Null<String>> = [];
					if (!check(TRightParen)) {
						do {
							skipNewlines();
							if (check(TRightParen)) break;
							if (check(TIdentifier("_"))) { advance(); binds.push(null); }
							else binds.push(expectIdentifier());
							skipNewlines();
						} while (match(TComma));
					}
					expect(TRightParen, "Expected ')' after enum pattern");
					MPEnum(name, binds);
				} else {
					switch (name) {
						case "String" | "Number" | "Bool" | "Null" | "Array" | "Dict" | "Function" | "Int" | "Float":
							MPType(name);
						default:
							// Convention: UpperCase = enum variant, lowerCase = bind variable
							var firstChar = name.charAt(0);
							if (firstChar >= "A" && firstChar <= "Z")
								MPEnum(name, []); // e.g. Red, Green, Ok
							else
								MPBind(name);    // e.g. n, x, value
					}
				}
			// Array destructure: [x, y]
			case TLeftBracket:
				advance();
				var elements:Array<Expr> = [];
				if (!check(TRightBracket)) {
					do {
						skipNewlines();
						if (check(TRightBracket)) break;
						elements.push(parseExpression());
						skipNewlines();
					} while (match(TComma));
				}
				expect(TRightBracket, "Expected ']' after array pattern");
				MPArray(elements);
			default:
				throw 'Unexpected pattern token ${tok.token} at line ${tok.line}';
		}
	}

	function parseMatchBody():Array<Stmt> {
		// Body is either a single-line expression or a { block }
		if (check(TLeftBrace)) {
			advance();
			var stmts = parseBlockBody();
			expect(TRightBrace, "Expected '}' after match case body");
			return stmts;
		} else {
			var expr = parseExpression();
			return [SExpr(expr)];
		}
	}

	function parseStatic():Stmt {
		advance(); // consume 'static'
		skipNewlines();
		// static var name = value
		if (match(TKeyword(KVar))) {
			var name = expectIdentifier();
			// optional type hint
			if (match(TColon)) parseTypeHint();
			var init:Null<Expr> = null;
			if (match(TOperator(OAssign)))
				init = parseExpression();
			return SStaticVar(name, init);
		}
		// static func name(...) { }
		if (match(TKeyword(KFunc)) || match(TKeyword(KFunction))) {
			var name = expectIdentifier();
			expect(TLeftParen, "Expected '(' after static function name");
			var params = parseParameters();
			expect(TRightParen, "Expected ')' after static function params");
			if (match(TArrow) || match(TColon)) parseTypeHint();
			skipNewlines();
			expect(TLeftBrace, "Expected '{' before static function body");
			var body = parseBlockBody();
			expect(TRightBrace, "Expected '}' after static function body");
			return SStaticFunc(name, params, null, body);
		}
		error("Expected 'var' or 'func' after 'static'");
		return SExpr(ENull);
	}

	function parseEnum():Stmt {
		advance(); // consume 'enum'
		var name = expectIdentifier();
		expect(TLeftBrace, "Expected '{' after enum name");
		skipSeparators();

		var variants:Array<EnumVariant> = [];
		while (!check(TRightBrace) && !isEOF()) {
			skipSeparators();
			if (check(TRightBrace)) break;
			var vname = expectIdentifier();
			var fields:Array<Param> = [];
			if (match(TLeftParen)) {
				// Variant with fields: Ok(msg:String, code:Int)
				fields = parseParameters();
				expect(TRightParen, "Expected ')' after enum variant fields");
			}
			variants.push({ name: vname, fields: fields });
			skipSeparators();
			match(TComma); // optional comma between variants
			skipSeparators();
		}
		expect(TRightBrace, "Expected '}' after enum body");
		return SEnum(name, variants);
	}

	function parseAbstract():Stmt {
		advance(); // consume 'abstract'
		var name = expectIdentifier();

		// Optional base type: abstract Meters(Float) { ... }
		var baseType:Null<TypeHint> = null;
		if (match(TLeftParen)) {
			baseType = parseTypeHint();
			expect(TRightParen, "Expected ')' after abstract base type");
		}

		skipNewlines();
		expect(TLeftBrace, "Expected '{' before abstract body");
		skipSeparators();

		var methods:Array<ClassMethod> = [];
		while (!check(TRightBrace) && !isEOF()) {
			skipSeparators();
			if (check(TRightBrace)) break;
			// Parse method like class methods
			var tok = peek();
			if (!check(TKeyword(KFunc)) && !check(TKeyword(KFn)) && !check(TKeyword(KFun)) && !check(TKeyword(KFunction)))
				throw 'Expected method in abstract body at line ${tok.line}';
			advance(); // consume func
			var mname = expectMemberName(); // allows keywords like 'new'
			expect(TLeftParen, "Expected '(' after method name");
			var params = parseParameters();
			expect(TRightParen, "Expected ')' after method params");
			var retType = null;
			if (match(TArrow) || match(TColon)) retType = parseTypeHint();
			expect(TLeftBrace, "Expected '{' before method body");
			var body = parseBlockBody();
			expect(TRightBrace, "Expected '}' after method body");
			methods.push({ name: mname, params: params, returnType: retType, body: body, isConstructor: mname == "new" });
			skipSeparators();
		}
		expect(TRightBrace, "Expected '}' after abstract body");
		return SAbstract(name, baseType, methods);
	}

	function parseUsing():Stmt {
		advance(); // consume 'using'
		// Accept dotted class name: using MyClass or using my.package.MyClass
		var name = expectIdentifier();
		while (check(TDot)) {
			advance(); // consume .
			name += "." + expectIdentifier();
		}
		return SUsing(name);
	}

	// Helper functions
	function peek():TokenPos {
		return tokens[pos];
	}

	function advance():TokenPos {
		if (!isEOF())
			pos++;
		return tokens[pos - 1];
	}

	function check(expected:Token):Bool {
		if (isEOF())
			return false;
		return Type.enumEq(peek().token, expected);
	}

	function isIdentifier():Bool {
		if (isEOF())
			return false;
		return switch (peek().token) {
			case TIdentifier(_): true;
			default: false;
		}
	}

	function match(expected:Token):Bool {
		if (check(expected)) {
			advance();
			return true;
		}
		return false;
	}

	function expect(expected:Token, message:String):TokenPos {
		if (check(expected))
			return advance();

		var token = peek();
		throw '$message at line ${token.line}, col ${token.col}. Got ${token.token}';
	}

	/**
	 * Like expectIdentifier but also accepts keywords as field names.
	 * Needed for member access like `d.enum`, `obj.new`, `x.type`, etc.
	 * In JavaScript/Haxe, any word can be a field name even if it's reserved.
	 */
	function expectMemberName():String {
		var token = peek();
		switch (token.token) {
			case TIdentifier(name):
				advance();
				return name;
			case TKeyword(kw):
				advance();
				// Strip leading 'K' from constructor name and lowercase — e.g. KEnum -> "enum"
				var raw = Type.enumConstructor(kw); // "KEnum", "KVar", etc.
				return raw.length > 1 ? raw.substr(1).toLowerCase() : raw.toLowerCase();
			default:
				throw 'Expected identifier at line ${token.line}, col ${token.col}';
		}
	}

	function expectIdentifier():String {
		var token = peek();
		return switch (token.token) {
			case TIdentifier(name):
				advance();
				name;
			default:
				throw 'Expected identifier at line ${token.line}, col ${token.col}';
		}
	}

	function error(message:String):Void {
		var token = peek();
		throw '$message at line ${token.line}, col ${token.col}';
	}

	function skipNewlines() {
		while (match(TNewLine)) {}
	}

	function skipSeparators() {
		while (match(TNewLine) || match(TSemicolon)) {}
	}

	function statementNeedsTerminator(stmt:Stmt):Bool {
		return switch (stmt) {
			case SIf(_, _, _), SWhile(_, _), SFor(_, _, _), SBlock(_), STryCatch(_, _, _), SFunc(_, _, _, _), SClass(_, _, _, _), SMatch(_, _, _): false;
			default: true;
		}
	}

	function consumeStatementTerminator(stmt:Stmt):Void {
		if (!statementNeedsTerminator(stmt)) {
			skipSeparators();
			return;
		}

		if (strictSemicolons) {
			if (check(TRightBrace) || isEOF())
				return;
			expect(TSemicolon, "Expected ';' in strict mode");
			skipSeparators();
		} else {
			skipSeparators();
		}
	}

	function isEOF():Bool {
		return pos >= tokens.length || Type.enumEq(peek().token, TEOF);
	}
}
