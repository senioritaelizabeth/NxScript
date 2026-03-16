package nx.script;

/**
 * Keywords in the script language
 */
enum Keyword {
	KLet; // let - temporal variable
	KVar; // var - external variable
	KConst; // const - constant
	KFunc; // func - function
	KFn; // fn - function alias
	KFun; // fun - function alias
	KFunction; // function - function alias
	KClass; // class - class declaration
	KExtends; // extends - class inheritance
	KNew; // new - instantiation
	KThis; // this - self reference
	KReturn; // return
	KIf; // if
	KElse; // else
	KElseIf; // elseif
	KWhile; // while
	KFor; // for
	KBreak; // break
	KContinue; // continue
	KIn; // in (for loops)
	KOf; // of (for-of loops)
	KFrom; // from (for-range loops)
	KTo; // to (for-range loops)
	KTrue; // true
	KFalse; // false
	KNull; // null
	KTry; // try
	KCatch; // catch
	KThrow; // throw
	KMatch; // match
	KSwitch; // switch (alias for match)
	KCase; // case (in match)
	KDefault; // default (in match)
	KUsing; // using — extension methods
	KEnum; // enum
	KAbstract;
	KStatic; // abstract type
	KIs; // type check: x is SomeType
}

/**
 * Operators in the script language
 */
enum Operator {
	// Arithmetic
	OAdd; // +
	OSub; // -
	OMul; // *
	ODiv; // /
	OMod; // %

	// Comparison
	OEqual; // ==
	ONotEqual; // !=
	OLess; // <
	OGreater; // >
	OLessEq; // <=
	OGreaterEq; // >=

	// Logical
	OAnd; // &&
	OOr; // ||
	ONullCoal; // ?? null-coalescing
	OOptChain; // ?. optional chain
	ONot; // !

	// Assignment
	OAssign; // =
	OAddAssign; // +=
	OSubAssign; // -=
	OMulAssign; // *=
	ODivAssign; // /=
	OModAssign; // %=
	OIncrement; // ++
	ODecrement; // --

	// Bitwise
	OBitAnd; // &
	OBitOr; // |
	OBitXor; // ^
	OBitNot; // ~
	OShiftLeft; // <<
	OShiftRight; // >>
}

/**
 * Represents a token in the script language
 */
enum Token {
	// Literals
	TNumber(value:Float);
	TString(value:String);
	TBool(value:Bool);
	TNull;

	// Identifiers
	TIdentifier(name:String);

	// Keywords
	TKeyword(keyword:Keyword);

	// Operators
	TOperator(op:Operator);

	// Delimiters
	TLeftParen; // (
	TRightParen; // )
	TLeftBrace; // {
	TRightBrace; // }
	TLeftBracket; // [
	TRightBracket; // ]
	TComma; // ,
	TSemicolon; // ;
	TColon; // :
	TDot; // .
	TRange; // ...
	TQuestion; // ? (standalone, for future ternary)
	TArrow; // ->
	TFatArrow; // =>

	// Special
	TNewLine;
	TEOF;
	TComment(text:String);
}

typedef TokenPos = {
	token:Token,
	line:Int,
	col:Int
}
