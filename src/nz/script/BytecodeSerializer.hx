package nz.script;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.BytesInput;
import nz.script.Bytecode;

/**
 * Serializes compiled Chunks to binary (.nxb) and deserializes them back.
 * Useful for shipping precompiled scripts so users can't easily read your source.
 * (They still can if they're determined. This isn't encryption.)
 *
 * Magic bytes: 0x4E580001 ("NX" + version 1).
 * Throws on format mismatch — don't load .json files with this.
 */
class BytecodeSerializer {
	// Magic number para verificar formato de archivo (NX + version)
	static inline var MAGIC = 0x4E580001; // "NX" + version 1

	/**
	 * Serializes a Chunk to raw bytes. Feed the result to deserialize() to get it back.
	 */
	public static function serialize(chunk:Chunk):Bytes {
		var output = new BytesOutput();

		// Escribir magic number
		output.writeInt32(MAGIC);

		// Serializar chunk principal
		writeChunk(output, chunk);

		return output.getBytes();
	}

	/**
	 * Deserializes raw bytes back into a Chunk ready to execute.
	 * Throws if the magic number doesn't match — don't pass arbitrary bytes here.
	 */
	public static function deserialize(bytes:Bytes):Chunk {
		var input = new BytesInput(bytes);

		// Verificar magic number
		var magic = input.readInt32();
		if (magic != MAGIC) {
			throw 'Invalid bytecode file format (expected 0x${StringTools.hex(MAGIC, 8)}, got 0x${StringTools.hex(magic, 8)})';
		}

		// Deserializar chunk principal
		return readChunk(input);
	}

	/**
	 * Convenience wrapper: serialize and write to a file path.
	 * Requires sys target (-neko, -cpp, etc.). Won't do anything on JS.
	 */
	public static function saveToFile(chunk:Chunk, path:String):Void {
		var bytes = serialize(chunk);
		#if sys sys.io.File.saveBytes(path, bytes); #end
	}

	/**
	 * Reads a .nxb file and returns a ready-to-execute Chunk.
	 */
	public static function loadFromFile(path:String):Chunk {
		#if sys
		var bytes = sys.io.File.getBytes(path);
		return deserialize(bytes);
		#else
		throw "BytecodeSerializer.loadFromFile is only available on sys targets";
		#end
	}

	// === SERIALIZACIÓN ===

	static function writeChunk(output:BytesOutput, chunk:Chunk):Void {
		// String pool
		output.writeInt32(chunk.strings.length);
		for (str in chunk.strings) {
			writeString(output, str);
		}

		// Constants
		output.writeInt32(chunk.constants.length);
		for (constant in chunk.constants) {
			writeValue(output, constant);
		}

		// Instructions
		output.writeInt32(chunk.instructions.length);
		for (inst in chunk.instructions) {
			writeInstruction(output, inst);
		}

		// Functions
		output.writeInt32(chunk.functions.length);
		for (func in chunk.functions) {
			writeFunctionChunk(output, func);
		}
	}

	static function writeInstruction(output:BytesOutput, inst:Instruction):Void {
		output.writeByte(inst.op);
		output.writeInt32(inst.arg != null ? inst.arg : 0);
		output.writeInt32(inst.line);
		output.writeInt32(inst.col);
	}

	static function writeValue(output:BytesOutput, value:Value):Void {
		switch (value) {
			case VNumber(n):
				output.writeByte(0x01);
				output.writeDouble(n);

			case VString(s):
				output.writeByte(0x02);
				writeString(output, s);

			case VBool(b):
				output.writeByte(0x03);
				output.writeByte(b ? 1 : 0);

			case VNull:
				output.writeByte(0x04);

			case VArray(arr):
				output.writeByte(0x05);
				output.writeInt32(arr.length);
				for (item in arr) {
					writeValue(output, item);
				}

			case VDict(map):
				output.writeByte(0x06);
				var keys = [for (k in map.keys()) k];
				output.writeInt32(keys.length);
				for (key in keys) {
					writeString(output, key);
					writeValue(output, map.get(key));
				}

			default:
				throw 'Cannot serialize value type: ${Type.enumConstructor(value)}';
		}
	}

	static function writeFunctionChunk(output:BytesOutput, func:FunctionChunk):Void {
		writeString(output, func.name);
		output.writeInt32(func.paramCount);

		// Parameter names
		output.writeInt32(func.paramNames.length);
		for (param in func.paramNames) {
			writeString(output, param);
		}

		output.writeByte(func.isLambda ? 1 : 0);

		// Function body chunk
		writeChunk(output, func.chunk);
	}

	static function writeString(output:BytesOutput, str:String):Void {
		var bytes = Bytes.ofString(str);
		output.writeInt32(bytes.length);
		output.write(bytes);
	}

	// === DESERIALIZACIÓN ===

	static function readChunk(input:BytesInput):Chunk {
		// String pool
		var stringCount = input.readInt32();
		var strings = [];
		for (i in 0...stringCount) {
			strings.push(readString(input));
		}

		// Constants
		var constantCount = input.readInt32();
		var constants = [];
		for (i in 0...constantCount) {
			constants.push(readValue(input));
		}

		// Instructions
		var instructionCount = input.readInt32();
		var instructions = [];
		for (i in 0...instructionCount) {
			instructions.push(readInstruction(input));
		}

		// Functions
		var functionCount = input.readInt32();
		var functions = [];
		for (i in 0...functionCount) {
			functions.push(readFunctionChunk(input));
		}

		return {
			strings: strings,
			constants: constants,
			instructions: instructions,
			functions: functions
		};
	}

	static function readInstruction(input:BytesInput):Instruction {
		var op = input.readByte();
		var arg = input.readInt32();
		var line = input.readInt32();
		var col = input.readInt32();

		return {
			op: op,
			arg: arg,
			line: line,
			col: col
		};
	}

	static function readValue(input:BytesInput):Value {
		var type = input.readByte();

		return switch (type) {
			case 0x01: // Number
				VNumber(input.readDouble());

			case 0x02: // String
				VString(readString(input));

			case 0x03: // Bool
				VBool(input.readByte() == 1);

			case 0x04: // Null
				VNull;

			case 0x05: // Array
				var length = input.readInt32();
				var arr = [];
				for (i in 0...length) {
					arr.push(readValue(input));
				}
				VArray(arr);

			case 0x06: // Dict
				var length = input.readInt32();
				var map = new Map<String, Value>();
				for (i in 0...length) {
					var key = readString(input);
					var value = readValue(input);
					map.set(key, value);
				}
				VDict(map);

			default:
				throw 'Unknown value type: 0x${StringTools.hex(type, 2)}';
		}
	}

	static function readFunctionChunk(input:BytesInput):FunctionChunk {
		var name = readString(input);
		var paramCount = input.readInt32();

		// Parameter names
		var paramNameCount = input.readInt32();
		var paramNames = [];
		for (i in 0...paramNameCount) {
			paramNames.push(readString(input));
		}

		var isLambda = input.readByte() == 1;

		// Function body chunk
		var chunk = readChunk(input);

		return {
			name: name,
			paramCount: paramCount,
			paramNames: paramNames,
			isLambda: isLambda,
			chunk: chunk
		};
	}

	static function readString(input:BytesInput):String {
		var length = input.readInt32();
		var bytes = Bytes.alloc(length);
		input.readBytes(bytes, 0, length);
		return bytes.toString();
	}
}
