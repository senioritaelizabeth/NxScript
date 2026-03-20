package nx.script;

import nx.script.Token;

// AST.hx — Abstract Syntax Tree node types for NxScript
//
// Produced by `Parser`, consumed by `Compiler`.
//
// ## Structure
//
//   `Expr`        — expressions that produce a value
//   `Stmt`        — statements that produce side-effects
//   `TypeHint`    — optional type annotations (parsed but not enforced at runtime)
//   `StmtWithPos` — a `Stmt` tagged with its source (line, col)
//   `Param`       — a named function parameter with an optional type hint
//   `ClassMethod` — a method declaration inside a `class` body
//   `ClassField`  — a field declaration inside a `class` body
//   `MatchCase`   — one arm of a `match` expression
//   `MatchPattern`— the pattern part of a match arm
//   `EnumVariant` — one variant in an `enum` declaration
//   `Either<L,R>` — generic sum type used for lambda bodies
//
// ## Notes on TypeHint
//
//   Type hints are parsed and stored in the AST for future use, but the
//   `Compiler` currently ignores them — NxScript is fully dynamically typed
//   at runtime.  `TDict` and `TFunc` in particular have no runtime effect yet.

enum Expr {
	// Literals
	ENumber(value:Float);
	EString(value:String);
	EBool(value:Bool);
	ENull;

	// Variables and references
	EIdentifier(name:String);
	EThis; // `this` — current instance

	// Binary operations
	EBinary(op:Operator, left:Expr, right:Expr);
	ENullCoal(left:Expr, right:Expr);
	ETernary(cond:Expr, then:Expr, els:Expr); // cond ? then : els
	EOptChain(object:Expr, field:String); // obj?.field

	// Unary operations
	EUnary(op:Operator, expr:Expr);

	// Postfix operations: x++, x--
	EPostfix(op:Operator, expr:Expr);

	// Member access: obj.field
	EMember(object:Expr, field:String);

	// Index access: obj[index]
	EIndex(object:Expr, index:Expr);

	// Function call
	ECall(callee:Expr, args:Array<Expr>);

	// Instantiation: new ClassName(args)
	ENew(className:String, args:Array<Expr>);

	// Array literal
	EArray(elements:Array<Expr>);

	// Dictionary literal
	EDict(pairs:Array<{key:Expr, value:Expr}>);

	// Lambda function: (args) -> expr or (args) -> { stmts }
	ELambda(params:Array<Param>, body:Either<Expr, Array<Stmt>>);

	// Assignment
	EAssign(target:Expr, value:Expr);

	// Type check: expr is TypeName  — returns Bool
	EIs(expr:Expr, typeName:String);
}

enum Stmt {
	// Variable declarations
	SLet(name:String, type:Null<TypeHint>, init:Null<Expr>);
	SVar(name:String, type:Null<TypeHint>, init:Null<Expr>);
	SConst(name:String, type:Null<TypeHint>, init:Expr);

	// Function declaration
	SFunc(name:String, params:Array<Param>, returnType:Null<TypeHint>, body:Array<Stmt>);

	// Class declaration
	SClass(name:String, superClass:Null<String>, methods:Array<ClassMethod>, fields:Array<ClassField>);

	// Control flow
	SReturn(expr:Null<Expr>);
	SIf(condition:Expr, thenBody:Array<Stmt>, elseBody:Null<Array<Stmt>>);
	SWhile(condition:Expr, body:Array<Stmt>);
	SFor(variable:String, iterable:Expr, body:Array<Stmt>);
	SForRange(variable:String, from:Expr, to:Expr, body:Array<Stmt>);
	SBreak;
	SContinue;

	// Exception handling
	STryCatch(body:Array<Stmt>, catchVar:String, catchBody:Array<Stmt>);
	SThrow(expr:Expr);

	// Destructuring declarations
	// var [a, b, _] = expr   — array destructure; null names skip that position
	SDestructureArray(names:Array<Null<String>>, init:Expr);
	// var {x, y} = expr      — dict/object destructure
	SDestructureDict(names:Array<String>, init:Expr);

	// Expression statement
	SExpr(expr:Expr);

	// Block
	SBlock(stmts:Array<Stmt>);

	// Pattern matching
	// match expr { case pattern => body ... default => body }
	SMatch(subject:Expr, cases:Array<MatchCase>, defaultBody:Null<Array<Stmt>>);

	// Using declaration — imports a class as extension methods
	// using MyClass  => methods of MyClass become callable on the first arg type
	SUsing(className:String);
	/** static var x = val  — module-level or class-level static field */
	SStaticVar(name:String, init:Null<Expr>);
	/** static func f(...) {...} — module-level or class-level static method.
	    Note: returnType is stored as a raw String here (unlike ClassMethod which uses TypeHint). */
	SStaticFunc(name:String, params:Array<Param>, returnType:Null<String>, body:Array<Stmt>);

	// Enum declaration
	// enum Color { Red, Green, Blue }
	// enum Status { Ok(msg:String), Error(code:Int) }
	SEnum(name:String, variants:Array<EnumVariant>);

	// Abstract type declaration
	// abstract Meters(Float) { ... }
	SAbstract(name:String, baseType:Null<TypeHint>, methods:Array<ClassMethod>);
}

typedef EnumVariant = {
	name: String,
	fields: Array<Param>   // empty for plain variants like Red, non-empty for Ok(msg)
}

typedef MatchCase = {
	pattern: MatchPattern,
	body: Array<Stmt>
}

enum MatchPattern {
	MPValue(expr:Expr);              // case 42, case "hello", case true
	MPRange(from:Expr, to:Expr);     // case 1...5
	MPType(typeName:String);         // case String, case Number, case Bool, case Null
	MPArray(elements:Array<Expr>);   // case [x, y]  (destructure)
	MPBind(name:String);             // case x  (bind to variable)
	MPEnum(variantName:String, binds:Array<Null<String>>); // case Ok(msg) or case Red
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

typedef ClassMethod = {
	name:String,
	params:Array<Param>,
	returnType:Null<TypeHint>,
	body:Array<Stmt>,
	isConstructor:Bool,
	?isStatic:Bool
}

typedef ClassField = {
	?isStatic:Bool,
	name:String,
	type:Null<TypeHint>,
	init:Null<Expr>
}

enum TypeHint {
	TNumber;
	TString;
	TBool;
	TAny;
	TArray(elementType:TypeHint);
	TDict(keyType:TypeHint, valueType:TypeHint);
	TFunc(params:Array<TypeHint>, returnType:TypeHint);
	TCustom(className:String); // Para clases externas como FlxSound
}

// Helper type for Either
enum Either<L, R> {
	Left(v:L);
	Right(v:R);
}
