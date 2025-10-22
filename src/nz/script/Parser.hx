package nz.script;

import nz.script.Token;
import nz.script.AST;

/**
 * Parser for the script language
 * Converts tokens into an Abstract Syntax Tree
 */
class Parser {
	var tokens:Array<TokenPos>;
	var pos:Int = 0;

	public function new(tokens:Array<TokenPos>) {
		this.tokens = tokens;
	}

	public function parse():Array<StmtWithPos> {
		var statements:Array<StmtWithPos> = [];

		while (!isEOF()) {
			skipNewlines();
			if (isEOF())
				break;
			var startToken = peek();
			var stmt = parseStatement();
			statements.push({
				stmt: stmt,
				line: startToken.line,
				col: startToken.col
			});
			skipNewlines();
		}

		return statements;
	}

	function parseStatement():Stmt {
		var token = peek();

		return switch (token.token) {
			case TKeyword(KLet): parseLet();
			case TKeyword(KVar): parseVar();
			case TKeyword(KConst): parseConst();
			case TKeyword(KFunc): parseFunc();
			case TKeyword(KClass): parseClass();
			case TKeyword(KReturn): parseReturn();
			case TKeyword(KIf): parseIf();
			case TKeyword(KWhile): parseWhile();
			case TKeyword(KFor): parseFor();
			case TKeyword(KBreak): {advance(); SBreak;}
			case TKeyword(KContinue): {advance(); SContinue;}
			case TLeftBrace: parseBlock();
			default: SExpr(parseExpression());
		}
	}

	function parseLet():Stmt {
		advance(); // consume 'let'
		var name = expectIdentifier();
		var type = null;

		if (match(TColon)) {
			type = parseTypeHint();
		}

		var init = null;
		if (match(TOperator(OAssign))) {
			init = parseExpression();
		}

		return SLet(name, type, init);
	}

	function parseVar():Stmt {
		advance(); // consume 'var'
		var name = expectIdentifier();
		var type = null;

		if (match(TColon)) {
			type = parseTypeHint();
		}

		var init = null;
		if (match(TOperator(OAssign))) {
			init = parseExpression();
		}

		return SVar(name, type, init);
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
		if (match(TArrow)) {
			returnType = parseTypeHint();
		}

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

		expect(TLeftBrace, "Expected '{' before class body");

		var fields:Array<ClassField> = [];
		var methods:Array<ClassMethod> = [];

		skipNewlines();
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

				case TKeyword(KFunc):
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
					if (match(TArrow)) {
						returnType = parseTypeHint();
					}

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

				default:
					error("Expected 'var' or 'func' in class body");
			}

			skipNewlines();
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
			default:
				throw 'Expected type hint at line ${token.line}, col ${token.col}';
		}
	}

	function parseReturn():Stmt {
		advance(); // consume 'return'

		if (check(TNewLine) || check(TRightBrace) || isEOF()) {
			return SReturn(null);
		}

		return SReturn(parseExpression());
	}

	function parseIf():Stmt {
		advance(); // consume 'if'

		expect(TLeftParen, "Expected '(' after 'if'");
		var condition = parseExpression();
		expect(TRightParen, "Expected ')' after condition");

		expect(TLeftBrace, "Expected '{' after if condition");
		var thenBody = parseBlockBody();
		expect(TRightBrace, "Expected '}' after if body");

		var elseBody = null;
		skipNewlines();

		if (match(TKeyword(KElse))) {
			skipNewlines();
			if (check(TKeyword(KIf))) {
				// elseif
				elseBody = [parseIf()];
			} else {
				expect(TLeftBrace, "Expected '{' after 'else'");
				elseBody = parseBlockBody();
				expect(TRightBrace, "Expected '}' after else body");
			}
		}

		return SIf(condition, thenBody, elseBody);
	}

	function parseWhile():Stmt {
		advance(); // consume 'while'

		expect(TLeftParen, "Expected '(' after 'while'");
		var condition = parseExpression();
		expect(TRightParen, "Expected ')' after condition");

		expect(TLeftBrace, "Expected '{' after while condition");
		var body = parseBlockBody();
		expect(TRightBrace, "Expected '}' after while body");

		return SWhile(condition, body);
	}

	function parseFor():Stmt {
		advance(); // consume 'for'

		expect(TLeftParen, "Expected '(' after 'for'");
		var variable = expectIdentifier();
		expect(TKeyword(KIn), "Expected 'in' in for loop");
		var iterable = parseExpression();
		expect(TRightParen, "Expected ')' after for header");

		expect(TLeftBrace, "Expected '{' after for header");
		var body = parseBlockBody();
		expect(TRightBrace, "Expected '}' after for body");

		return SFor(variable, iterable, body);
	}

	function parseBlock():Stmt {
		expect(TLeftBrace, "Expected '{'");
		var stmts = parseBlockBody();
		expect(TRightBrace, "Expected '}'");
		return SBlock(stmts);
	}

	function parseBlockBody():Array<Stmt> {
		var stmts:Array<Stmt> = [];
		skipNewlines();

		while (!check(TRightBrace) && !isEOF()) {
			stmts.push(parseStatement());
			skipNewlines();
		}

		return stmts;
	}

	// Expression parsing with operator precedence
	function parseExpression():Expr {
		return parseAssignment();
	}

	function parseAssignment():Expr {
		var expr = parseLogicalOr();

		if (match(TOperator(OAssign))) {
			var value = parseAssignment();
			return EAssign(expr, value);
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
			default:
				parsePostfix();
		}
	}

	function parsePostfix():Expr {
		var expr = parsePrimary();

		while (true) {
			var token = peek().token;

			expr = switch (token) {
				case TDot:
					advance();
					var field = expectIdentifier();
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

				default:
					break;
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
				EIdentifier(name);

			case TLeftParen:
				advance();
				// Could be grouped expression or lambda
				// Look ahead to detect lambda: () -> or (id) -> or (id, id) ->
				var savedPos = pos;
				var isLambda = false;

				if (check(TRightParen)) {
					// Could be () -> ...
					advance(); // skip )
					if (check(TArrow)) {
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
						if (check(TArrow)) {
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
		expect(TArrow, "Expected '->' for lambda");

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

	function isEOF():Bool {
		return pos >= tokens.length || Type.enumEq(peek().token, TEOF);
	}
}
