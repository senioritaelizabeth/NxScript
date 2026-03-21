package nx.script;

// Token.hx — Lexical token definitions for NxScript
//
// Produced by 'Tokenizer', consumed by 'Parser'.
// Every token carries its source position (line, col) via 'TokenPos'.
//
// Layout:
//   Keyword    → reserved words (let, func, if, class, …)
//   Operator   → arithmetic, comparison, logical, assignment, bitwise
//   Token      → the union of all token kinds (literals, keywords, operators,
//                delimiters, and structural tokens like TNewLine / TEOF)
//   TokenPos   → a Token plus its (line, col) in the source file

/** Reserved keywords. The tokenizer maps source identifiers to these. */
/**
 * Lexical token definitions for NxScript.
 *
 * Produced by 'Tokenizer', consumed by 'Parser'.
 * Every token carries its source position via 'TokenPos'.
 *
 * - 'Keyword'  — reserved words ('let', 'func', 'if', 'class', …)
 * - 'Operator' — all operators (arithmetic, logical, bitwise, assignment)
 * - 'Token'    — the full token union (literals, keywords, operators, delimiters)
 * - 'TokenPos' — a 'Token' tagged with '(line, col)' from the source file
 */
enum Keyword {
	KLet;       // let  — block-scoped variable
	KVar;       // var  — mutable variable
	KConst;     // const — immutable binding
	KFunc;      // func  — function declaration
	KFn;        // fn    — short alias for func
	KFun;       // fun   — short alias for func
	KFunction;  // function — long alias for func

	KClass;     // class
	KExtends;   // extends
	KNew;       // new
	KThis;      // this

	KReturn;    // return
	KIf;        // if
	KElse;      // else
	KElseIf;    // elseif  (also: elif, elsif via SyntaxRules aliases)
	KWhile;     // while
	KFor;       // for
	KBreak;     // break
	KContinue;  // continue
	KIn;        // in  — for-in loop
	KOf;        // of  — for-of loop
	KFrom;      // from — for-range loop  (for x from 0 to 10)
	KTo;        // to   — for-range loop

	KTrue;      // true
	KFalse;     // false
	KNull;      // null

	KTry;       // try
	KCatch;     // catch
	KThrow;     // throw

	KMatch;     // match — pattern matching (also accepted: switch via alias)
	KCase;      // case  — match arm
	KDefault;   // default — fallback match arm

	KUsing;     // using — extension method import
	KEnum;      // enum
	KAbstract;  // abstract
	KStatic;    // static
	KIs;        // is — type check:  expr is TypeName
}

/** All operators, grouped by category. */
enum Operator {
	// Arithmetic
	OAdd;   // +
	OSub;   // -
	OMul;   // *
	ODiv;   // /
	OMod;   // %

	// Comparison
	OEqual;     // ==
	ONotEqual;  // !=
	OLess;      // <
	OGreater;   // >
	OLessEq;    // <=
	OGreaterEq; // >=

	// Logical
	OAnd;      // &&
	OOr;       // ||
	ONot;      // !
	ONullCoal; // ??  null-coalescing
	OOptChain; // ?.  optional chaining

	// Assignment
	OAssign;    // =
	OAddAssign; // +=
	OSubAssign; // -=
	OMulAssign; // *=
	ODivAssign; // /=
	OModAssign; // %=
	OIncrement; // ++
	ODecrement; // --

	// Bitwise
	OBitAnd;    // &
	OBitOr;     // |
	OBitXor;    // ^
	OBitNot;    // ~
	OShiftLeft; // <<
	OShiftRight;// >>
}

/**
 * The full set of tokens the tokenizer can produce.
 *
 * Notes:
 *   - 'TBool' is emitted directly for 'true'/'false' (not as 'TKeyword(KTrue)').
 *   - 'TNull' is emitted directly for 'null'.
 *   - 'TNewLine' is significant: the parser uses it as an implicit statement
 *     terminator in non-strict mode.
 *   - 'TEOF' marks the end of the token stream; the parser stops there.
 */
enum Token {
	// Literals
	TNumber(value:Float);
	TString(value:String);
	TBool(value:Bool);
	TNull;

	// Identifiers and keywords
	TIdentifier(name:String);
	TKeyword(keyword:Keyword);

	// Operators
	TOperator(op:Operator);

	// Delimiters
	TLeftParen;    // (
	TRightParen;   // )
	TLeftBrace;    // {
	TRightBrace;   // }
	TLeftBracket;  // [
	TRightBracket; // ]
	TComma;        // ,
	TSemicolon;    // ;
	TColon;        // :
	TDot;          // .
	TRange;        // ...
	TQuestion;     // ?  (standalone — ternary  cond ? a : b)
	TArrow;        // ->  (lambda arrow)
	TFatArrow;     // =>  (fat-arrow lambda)

	// Structural
	TNewLine; // implicit statement separator
	TEOF;     // end of token stream
}

/** A token paired with its source location. */
typedef TokenPos = {
	token: Token,
	line:  Int,
	col:   Int
}
