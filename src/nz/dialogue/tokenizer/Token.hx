package nz.dialogue.tokenizer;

/**
 * Keywords in the dialogue language
 */
enum Keyword {
	KVar;
	KFunc;
	KIf;
	KElseIf;
	KElse;
	KSwitch;
	KCase;
	KEnd;
	KReturn;
}

/**
 * Operators in the dialogue language
 */
enum Operator {
	// Arithmetic
	OAdd; // +
	OSub; // -
	OMul; // *
	ODiv; // /

	// Comparison
	OEqual; // ==
	ONotEqual; // !=
	OLess; // <
	OGreater; // >
	OLessEq; // <=
	OGreaterEq; // >=

	// Logical
	OAnd; // &&, and
	OOr; // ||, or
	ONot; // !, not
}

/**
 * Represents a token in the dialogue language
 */
enum Token {
	// Comments
	TComment(text:String);

	// Keywords
	TKeyword(keyword:Keyword);

	// Commands
	TAtCommand(name:String);

	// Literals
	TIdentifier(name:String);
	TNumber(value:Float);
	TString(value:String);
	TBool(value:Bool);

	// Operators and symbols
	TOp(op:Operator);
	TLParen;
	TRParen;
	TComma;
	TAssign; // =
	TColon;

	// Dialogue
	TDialog(text:String);

	// Special
	TNewLine;
	TEndOfFile;
}

/**
 * Token with position information
 */
typedef TokenPos = {
	token:Token,
	line:Int,
	col:Int
}
