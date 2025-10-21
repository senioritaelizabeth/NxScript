package nz.script;

/**
 * Keywords in the script language
 */
enum Keyword {
	KLet; // let - temporal variable
	KVar; // var - external variable
	KConst; // const - constant
	KFunc; // func - function
	KReturn; // return
	KIf; // if
	KElse; // else
	KElseIf; // elseif
	KWhile; // while
	KFor; // for
	KBreak; // break
	KContinue; // continue
	KIn; // in (for loops)
	KTrue; // true
	KFalse; // false
	KNull; // null
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
	ONot; // !

	// Assignment
	OAssign; // =

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
	TArrow; // ->

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
