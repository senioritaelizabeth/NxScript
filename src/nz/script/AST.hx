package nz.script;

import nz.script.Token;

/**
 * Abstract Syntax Tree nodes
 */
enum Expr {
	// Literals
	ENumber(value:Float);
	EString(value:String);
	EBool(value:Bool);
	ENull;

	// Variables
	EIdentifier(name:String);

	// Binary operations
	EBinary(op:Operator, left:Expr, right:Expr);

	// Unary operations
	EUnary(op:Operator, expr:Expr);

	// Member access: obj.field
	EMember(object:Expr, field:String);

	// Index access: obj[index]
	EIndex(object:Expr, index:Expr);

	// Function call
	ECall(callee:Expr, args:Array<Expr>);

	// Array literal
	EArray(elements:Array<Expr>);

	// Dictionary literal
	EDict(pairs:Array<{key:Expr, value:Expr}>);

	// Lambda function: (args) -> expr or (args) -> { stmts }
	ELambda(params:Array<Param>, body:Either<Expr, Array<Stmt>>);

	// Assignment
	EAssign(target:Expr, value:Expr);
}

enum Stmt {
	// Variable declarations
	SLet(name:String, type:Null<TypeHint>, init:Null<Expr>);
	SVar(name:String, type:Null<TypeHint>, init:Null<Expr>);
	SConst(name:String, type:Null<TypeHint>, init:Expr);

	// Function declaration
	SFunc(name:String, params:Array<Param>, returnType:Null<TypeHint>, body:Array<Stmt>);

	// Control flow
	SReturn(expr:Null<Expr>);
	SIf(condition:Expr, thenBody:Array<Stmt>, elseBody:Null<Array<Stmt>>);
	SWhile(condition:Expr, body:Array<Stmt>);
	SFor(variable:String, iterable:Expr, body:Array<Stmt>);
	SBreak;
	SContinue;

	// Expression statement
	SExpr(expr:Expr);

	// Block
	SBlock(stmts:Array<Stmt>);
}

typedef StmtWithPos = {
	stmt:Stmt,
	line:Int,
	col:Int
}

typedef Param = {
	name:String,
	type:Null<TypeHint>
}

enum TypeHint {
	TNumber;
	TString;
	TBool;
	TAny;
	TArray(elementType:TypeHint);
	TDict(keyType:TypeHint, valueType:TypeHint);
	TFunc(params:Array<TypeHint>, returnType:TypeHint);
}

// Helper type for Either
enum Either<L, R> {
	Left(v:L);
	Right(v:R);
}
