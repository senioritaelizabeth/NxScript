package nz.tokenizer;

/**
 * Represents a token in the dialogue language
 */
enum Token {
	// Comments
	TComment(text:String);

	// Declarations
	TVar(name:String, value:Dynamic);
	TFunc(name:String, params:Array<String>);

	// Control flow
	TIf(condition:String);
	TElseIf(condition:String);
	TElse;
	TSwitch(value:String);
	TCase(value:String);
	TEnd;
	TReturn(expr:String);

	// Commands
	TAtCall(name:String, args:Array<String>);

	// Literals
	TIdentifier(name:String);
	TNumber(value:Float);
	TString(value:String);
	TBool(value:Bool);

	// Operators and symbols
	TOp(op:String);
	TLParen;
	TRParen;
	TComma;
	TAssign;

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
