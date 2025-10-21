package nz.script;

/**
 * Bytecode opcodes (hexadecimal)
 */
class Op {
	// Stack operations (0x00 - 0x0F)
	public static inline var LOAD_CONST = 0x00; // Load constant onto stack
	public static inline var LOAD_VAR = 0x01; // Load variable onto stack
	public static inline var STORE_VAR = 0x02; // Store top of stack to variable
	public static inline var STORE_LET = 0x03; // Store top of stack to let variable
	public static inline var STORE_CONST = 0x04; // Store top of stack to const variable
	public static inline var POP = 0x05; // Pop top of stack
	public static inline var DUP = 0x06; // Duplicate top of stack

	// Arithmetic operations (0x10 - 0x1F)
	public static inline var ADD = 0x10;
	public static inline var SUB = 0x11;
	public static inline var MUL = 0x12;
	public static inline var DIV = 0x13;
	public static inline var MOD = 0x14;
	public static inline var NEG = 0x15; // Negate

	// Bitwise operations (0x20 - 0x2F)
	public static inline var BIT_AND = 0x20;
	public static inline var BIT_OR = 0x21;
	public static inline var BIT_XOR = 0x22;
	public static inline var BIT_NOT = 0x23;
	public static inline var SHIFT_LEFT = 0x24;
	public static inline var SHIFT_RIGHT = 0x25;

	// Comparison operations (0x30 - 0x3F)
	public static inline var EQ = 0x30; // Equal
	public static inline var NEQ = 0x31; // Not equal
	public static inline var LT = 0x32; // Less than
	public static inline var GT = 0x33; // Greater than
	public static inline var LTE = 0x34; // Less than or equal
	public static inline var GTE = 0x35; // Greater than or equal

	// Logical operations (0x40 - 0x4F)
	public static inline var AND = 0x40;
	public static inline var OR = 0x41;
	public static inline var NOT = 0x42;

	// Control flow (0x50 - 0x5F)
	public static inline var JUMP = 0x50; // Unconditional jump
	public static inline var JUMP_IF_FALSE = 0x51; // Jump if top of stack is false
	public static inline var JUMP_IF_TRUE = 0x52; // Jump if top of stack is true

	// Functions (0x60 - 0x6F)
	public static inline var CALL = 0x60; // Call function with n arguments
	public static inline var RETURN = 0x61; // Return from function
	public static inline var MAKE_FUNC = 0x62; // Create function object
	public static inline var MAKE_LAMBDA = 0x63; // Create lambda function

	// Data structures (0x70 - 0x7F)
	public static inline var MAKE_ARRAY = 0x70; // Create array from top n stack items
	public static inline var MAKE_DICT = 0x71; // Create dict from top 2n stack items
	public static inline var GET_MEMBER = 0x72; // Get object member
	public static inline var SET_MEMBER = 0x73; // Set object member
	public static inline var GET_INDEX = 0x74; // Get indexed value
	public static inline var SET_INDEX = 0x75; // Set indexed value

	// Iterations (0x80 - 0x8F)
	public static inline var GET_ITER = 0x80; // Get iterator from iterable
	public static inline var FOR_ITER = 0x81; // Iterate or jump if done

	// Special (0x90 - 0x9F)
	public static inline var LOAD_NULL = 0x90;
	public static inline var LOAD_TRUE = 0x91;
	public static inline var LOAD_FALSE = 0x92;

	// End of file (0xFF)
	public static inline var EOF = 0xFF;

	/**
	 * Get opcode name for debugging
	 */
	public static function getName(opcode:Int):String {
		return switch (opcode) {
			case LOAD_CONST: "LOAD_CONST";
			case LOAD_VAR: "LOAD_VAR";
			case STORE_VAR: "STORE_VAR";
			case STORE_LET: "STORE_LET";
			case STORE_CONST: "STORE_CONST";
			case POP: "POP";
			case DUP: "DUP";
			case ADD: "ADD";
			case SUB: "SUB";
			case MUL: "MUL";
			case DIV: "DIV";
			case MOD: "MOD";
			case NEG: "NEG";
			case BIT_AND: "BIT_AND";
			case BIT_OR: "BIT_OR";
			case BIT_XOR: "BIT_XOR";
			case BIT_NOT: "BIT_NOT";
			case SHIFT_LEFT: "SHIFT_LEFT";
			case SHIFT_RIGHT: "SHIFT_RIGHT";
			case EQ: "EQ";
			case NEQ: "NEQ";
			case LT: "LT";
			case GT: "GT";
			case LTE: "LTE";
			case GTE: "GTE";
			case AND: "AND";
			case OR: "OR";
			case NOT: "NOT";
			case JUMP: "JUMP";
			case JUMP_IF_FALSE: "JUMP_IF_FALSE";
			case JUMP_IF_TRUE: "JUMP_IF_TRUE";
			case CALL: "CALL";
			case RETURN: "RETURN";
			case MAKE_FUNC: "MAKE_FUNC";
			case MAKE_LAMBDA: "MAKE_LAMBDA";
			case MAKE_ARRAY: "MAKE_ARRAY";
			case MAKE_DICT: "MAKE_DICT";
			case GET_MEMBER: "GET_MEMBER";
			case SET_MEMBER: "SET_MEMBER";
			case GET_INDEX: "GET_INDEX";
			case SET_INDEX: "SET_INDEX";
			case GET_ITER: "GET_ITER";
			case FOR_ITER: "FOR_ITER";
			case LOAD_NULL: "LOAD_NULL";
			case LOAD_TRUE: "LOAD_TRUE";
			case LOAD_FALSE: "LOAD_FALSE";
			case EOF: "EOF";
			default: "UNKNOWN(0x" + StringTools.hex(opcode, 2) + ")";
		}
	}
}

/**
 * Instruction with operands
 */
typedef Instruction = {
	op:Int, // Opcode
	?arg:Int, // Integer argument (for indices, offsets, etc.)
	?name:String, // String argument (for variable/field names)
	line:Int,
	col:Int
}

typedef Chunk = {
	instructions:Array<Instruction>,
	constants:Array<Value>,
	functions:Array<FunctionChunk>,
	strings:Array<String> // String pool for variable/field names
}

typedef FunctionChunk = {
	name:String,
	paramCount:Int,
	paramNames:Array<String>,
	chunk:Chunk,
	isLambda:Bool
}

enum Value {
	VNumber(v:Float);
	VString(v:String);
	VBool(v:Bool);
	VNull;
	VArray(elements:Array<Value>);
	VDict(map:Map<String, Value>);
	VFunction(func:FunctionChunk, closure:Map<String, Value>);
	VNativeFunction(name:String, arity:Int, fn:Array<Value>->Value);
}
