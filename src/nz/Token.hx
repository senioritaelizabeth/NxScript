package nz;

enum Token {
	TComment(text:String);
	TVar(name:String, value:Dynamic);
	TFunc(name:String, params:Array<String>);
	TIf(condition:String);
	TElseIf(condition:String);
	TElse;
	TSwitch(value:String);
	TCase(value:String);
	TEnd;
	TReturn(expr:String);

	TAtCall(name:String, args:Array<String>);

	TIdentifier(name:String);
	TNumber(value:Float);
	TString(value:String);
	TBool(value:Bool);

	TOp(op:String);
	TLParen;
	TRParen;
	TComma;
	TAssign;

	TDialog(text:String);
	TNewLine;
	TEndOfFile;
}

typedef TokenPos = {
	token:Token,
	line:Int,
	col:Int
}
