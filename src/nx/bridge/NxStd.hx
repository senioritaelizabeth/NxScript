package nx.bridge;

import nx.script.VM;
import nx.script.Bytecode.Value;

/**
 * Registers Haxe extern classes that can't be resolved via Type.resolveClass()
 * (because they're @:coreApi externs, not real runtime classes).
 *
 * Call NxStd.registerAll(vm) after creating the VM to make these available
 * as globals in NxScript:
 *
 *   import Math;   Math.sin(1.0)
 *   import Std;    Std.parseInt("42")
 *   import Sys;    Sys.command("echo hi")
 *   import Json;   Json.stringify({})
 */
class NxStd {
	public static function registerAll(vm:VM):Void {
		registerMath(vm);
		registerStd(vm);
		registerJson(vm);
		#if sys
		registerSys(vm);
		registerFile(vm);
		#end
	}


	static function registerMath(vm:VM):Void {
		var v = VNativeObject(Math);
		vm.globals.set("Math", v);
		vm.globals.set("math", v); // lowercase alias
	}


	static function registerStd(vm:VM):Void {
		// Expose Std functions as individual globals too, for convenience
		vm.globals.set("Std", VNativeObject(Std));

		// parseInt / parseFloat as script globals
		vm.natives.set("parseInt", VNativeFunction("parseInt", 1, (args) -> {
			var s = switch (args[0]) { case VString(s): s; default: vm.valueToString(args[0]); };
			var n = Std.parseInt(s);
			return n == null ? VNull : VNumber(n);
		}));
		vm.natives.set("parseFloat", VNativeFunction("parseFloat", 1, (args) -> {
			var s = switch (args[0]) { case VString(s): s; default: vm.valueToString(args[0]); };
			var n = Std.parseFloat(s);
			return Math.isNaN(n) ? VNull : VNumber(n);
		}));

		// isNaN, isFinite
		vm.natives.set("isNaN", VNativeFunction("isNaN", 1, (args) ->
			VBool(switch (args[0]) { case VNumber(n): Math.isNaN(n); default: true; })
		));
		vm.natives.set("isFinite", VNativeFunction("isFinite", 1, (args) ->
			VBool(switch (args[0]) { case VNumber(n): Math.isFinite(n); default: false; })
		));
	}


	static function registerJson(vm:VM):Void {
		vm.globals.set("Json", VNativeObject(haxe.Json));

		vm.natives.set("jsonParse", VNativeFunction("jsonParse", 1, (args) -> {
			var s = switch (args[0]) { case VString(s): s; default: throw "jsonParse expects string"; };
			return vm.haxeToValue(haxe.Json.parse(s));
		}));
		vm.natives.set("jsonStringify", VNativeFunction("jsonStringify", 1, (args) -> {
			return VString(haxe.Json.stringify(vm.valueToHaxe(args[0])));
		}));
	}


	#if sys
	static function registerSys(vm:VM):Void {
		vm.globals.set("Sys", VNativeObject(Sys));

		// Convenience natives
		vm.natives.set("command", VNativeFunction("command", -1, (args) -> {
			if (args.length == 0) throw "command() requires at least 1 argument";
			var cmd = switch (args[0]) { case VString(s): s; default: throw "command() expects string"; };
			var cmdArgs = [for (i in 1...args.length) switch (args[i]) {
				case VString(s): s;
				default: vm.valueToString(args[i]);
			}];
			return VNumber(Sys.command(cmd, cmdArgs));
		}));

		vm.natives.set("exit", VNativeFunction("exit", 1, (args) -> {
			var code = switch (args[0]) { case VNumber(n): Std.int(n); default: 0; };
			Sys.exit(code);
			return VNull;
		}));

		vm.natives.set("getEnv", VNativeFunction("getEnv", 1, (args) -> {
			var key = switch (args[0]) { case VString(s): s; default: throw "getEnv expects string"; };
			var v = Sys.getEnv(key);
			return v == null ? VNull : VString(v);
		}));

		vm.natives.set("sleep", VNativeFunction("sleep", 1, (args) -> {
			var secs = switch (args[0]) { case VNumber(n): n; default: throw "sleep expects number"; };
			Sys.sleep(secs);
			return VNull;
		}));

		vm.natives.set("time", VNativeFunction("time", 0, (_) -> VNumber(Sys.time())));
		vm.natives.set("cpuTime", VNativeFunction("cpuTime", 0, (_) -> VNumber(Sys.cpuTime())));
		vm.natives.set("args", VNativeFunction("args", 0, (_) ->
			VArray([for (a in Sys.args()) VString(a)])
		));
		vm.natives.set("cwd", VNativeFunction("cwd", 0, (_) -> VString(Sys.getCwd())));
	}


	static function registerFile(vm:VM):Void {
		vm.globals.set("File", VNativeObject(sys.io.File));
		vm.globals.set("FileSystem", VNativeObject(sys.FileSystem));

		vm.natives.set("readFile", VNativeFunction("readFile", 1, (args) -> {
			var path = switch (args[0]) { case VString(s): s; default: throw "readFile expects string"; };
			return VString(sys.io.File.getContent(path));
		}));
		vm.natives.set("writeFile", VNativeFunction("writeFile", 2, (args) -> {
			var path    = switch (args[0]) { case VString(s): s; default: throw "writeFile: path must be string"; };
			var content = switch (args[1]) { case VString(s): s; default: vm.valueToString(args[1]); };
			sys.io.File.saveContent(path, content);
			return VNull;
		}));
		vm.natives.set("fileExists", VNativeFunction("fileExists", 1, (args) -> {
			var path = switch (args[0]) { case VString(s): s; default: throw "fileExists expects string"; };
			return VBool(sys.FileSystem.exists(path));
		}));
	}
	#end
}
