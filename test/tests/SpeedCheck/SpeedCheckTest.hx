package ;

import sys.io.File;
import haxe.io.Bytes;
import nx.script.Tokenizer;
import nx.script.Parser;
import nx.script.Compiler;
import nx.script.BytecodeSerializer;
import nx.script.Interpreter;
import nx.script.VM;

class SpeedCheckTest {
    static function assert(cond:Bool, msg:String) {
        if (!cond) throw 'Assert failed: ' + msg;
    }

    static function timeit<T>(label:String, fn:Void->T):T {
        var t0 = Sys.time();
        var result = fn();
        var t1 = Sys.time();
        Sys.println(label + ': ' + ((t1 - t0) * 1000) + ' ms');
        return result;
    }

    static function parseSources(source:String) {
        var tokenizer = new Tokenizer(source);
        var tokens = tokenizer.tokenize();
        var parser = new Parser(tokens);
        var ast = parser.parse();
        return ast;
    }

    static function compileProject(source:String) {
        var ast = parseSources(source);
        var compiler = new Compiler();
        var chunk = compiler.compile(ast);
        return chunk;
    }

    static function encodeBytecode(chunk:Dynamic):Bytes {
        return BytecodeSerializer.serialize(chunk);
    }

    static function decodeBytecode(bytes:Bytes):Dynamic {
        return BytecodeSerializer.deserialize(bytes);
    }

    static function loadSourceRuntime(source:String):Dynamic {
        var interp = new Interpreter();
        return interp.run(source);
    }

    static function loadBytecodeRuntime(chunk:Dynamic):Dynamic {
        var interp = new Interpreter();
        return interp.runChunk(chunk);
    }

    static function astCall(source:String, func:String, f:Array<Dynamic>):Dynamic {
        var interp = new Interpreter();
        interp.run(source);
        var args = f.map(function(x) return interp.vm.haxeToValue(x));  


        return interp.call(func, args);
        // return interp.call(func, args);
    }

    static function astExecutionRun(source:String):Dynamic {
        var interp = new Interpreter();
        return interp.run(source);
    }

    static function vmCall(source:String, func:String, args:Array<Dynamic>):Dynamic {
        var interp = new Interpreter();
        interp.run(source);
        var vmArgs = args.map(function(x) return interp.vm.haxeToValue(x));

        return interp.call(func, vmArgs);
    }

    static function vmExecutionRun(source:String):Dynamic {
        var interp = new Interpreter();
        return interp.run(source);
    }

    public static function main() {
        var src = "func add(a, b) { return a + b }\nadd(2, 3)";
        // parseSources
        var ast = timeit('parseSources', function() return parseSources(src));
        assert(ast != null, "parseSources failed");
        // compileProject
        var chunk = timeit('compileProject', function() return compileProject(src));
        assert(chunk != null, "compileProject failed");
        // encodeBytecode
        var bytes = timeit('encodeBytecode', function() return encodeBytecode(chunk));
        assert(bytes != null && bytes.length > 0, "encodeBytecode failed");
        // decodeBytecode
        var chunk2 = timeit('decodeBytecode', function() return decodeBytecode(bytes));
        assert(chunk2 != null, "decodeBytecode failed");
        // loadSourceRuntime
        var result1 = timeit('loadSourceRuntime', function() return loadSourceRuntime(src));
        assert(result1 != null, "loadSourceRuntime failed");
        // loadBytecodeRuntime
        var result2 = timeit('loadBytecodeRuntime', function() return loadBytecodeRuntime(chunk2));
        assert(result2 != null, "loadBytecodeRuntime failed");
        // astCall
        var callResult = timeit('astCall', function() return astCall("func mul(a, b) { return a * b }", "mul", [2, 4]));
        assert(callResult != null, "astCall failed");
        // astExecutionRun
        var execResult = timeit('astExecutionRun', function() return astExecutionRun("1 + 2 * 3"));
        assert(execResult != null, "astExecutionRun failed");
        // vmCall
        var vmCallResult = timeit('vmCall', function() return vmCall("func sub(a, b) { return a - b }", "sub", [5, 2]));
        assert(vmCallResult != null, "vmCall failed");
        // vmExecutionRun
        var vmExecResult = timeit('vmExecutionRun', function() return vmExecutionRun("10 / 2"));
        assert(vmExecResult != null, "vmExecutionRun failed");
        Sys.println("All SpeedCheck tests passed.");
    }
}
