package nz.dialogue.parser;

/**
 * Represents executable blocks in the dialogue language AST
 */
enum Block {
	// Declaraciones
	BVar(name:String, value:Dynamic);
	BFunc(name:String, params:Array<String>, body:Array<Block>);
	BFuncCall(name:String, args:Array<String>);

	// Control de flujo
	BIf(condition:String, thenBlock:Array<Block>, elseIfs:Array<ElseIfBlock>, elseBlock:Array<Block>);
	BSwitch(value:String, cases:Array<CaseBlock>);
	BReturn(expr:String);

	// Comandos
	BAtCall(name:String, args:Array<String>);
	BDialog(text:String);

	// Comentarios
	BComment(text:String);
}

typedef ElseIfBlock = {
	condition:String,
	body:Array<Block>
}

typedef CaseBlock = {
	value:String,
	body:Array<Block>
}
