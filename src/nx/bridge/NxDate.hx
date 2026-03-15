package nx.bridge;

import nx.script.VM;
import nx.script.Bytecode.Value;

/**
 * Registers Date and DateTools as usable types in NxScript.
 *
 * Usage in script:
 *   import Date;
 *   var now = Date.now()
 *   print(now.getFullYear())
 *   print(now.toString())
 *
 *   var d = new Date(2025, 0, 1, 0, 0, 0)
 *   print(DateTools.format(d, "%Y-%m-%d"))
 */
class NxDate {
	public static function registerAll(vm:VM):Void {
		registerDate(vm);
		registerDateTools(vm);
		registerTimer(vm);
	}

	static function registerDate(vm:VM):Void {
		// Expose Date class — Date.now(), Date.fromTime(), etc. work via reflection
		vm.globals.set("Date", VNativeObject(Date));

		// Convenience natives
		vm.natives.set("dateNow", VNativeFunction("dateNow", 0, (_) ->
			vm.haxeToValue(Date.now())
		));
		vm.natives.set("dateFromTime", VNativeFunction("dateFromTime", 1, (args) -> {
			var t = switch (args[0]) { case VNumber(n): n; default: throw "dateFromTime expects number"; };
			return vm.haxeToValue(Date.fromTime(t));
		}));
		vm.natives.set("dateFromString", VNativeFunction("dateFromString", 1, (args) -> {
			var s = switch (args[0]) { case VString(s): s; default: throw "dateFromString expects string"; };
			return vm.haxeToValue(Date.fromString(s));
		}));
		vm.natives.set("timestamp", VNativeFunction("timestamp", 0, (_) ->
			VNumber(Date.now().getTime())
		));
	}

	static function registerDateTools(vm:VM):Void {
		vm.globals.set("DateTools", VNativeObject(DateTools));

		vm.natives.set("dateFormat", VNativeFunction("dateFormat", 2, (args) -> {
			var date = switch (args[0]) {
				case VNativeObject(d): (d : Date);
				default: throw "dateFormat: first arg must be a Date object";
			};
			var fmt = switch (args[1]) { case VString(s): s; default: throw "dateFormat: format must be string"; };
			return VString(DateTools.format(date, fmt));
		}));

		vm.natives.set("dateDelta", VNativeFunction("dateDelta", 2, (args) -> {
			var date = switch (args[0]) {
				case VNativeObject(d): (d : Date);
				default: throw "dateDelta: first arg must be a Date";
			};
			var ms = switch (args[1]) { case VNumber(n): n; default: throw "dateDelta: delta must be number (ms)"; };
			return vm.haxeToValue(DateTools.delta(date, ms));
		}));
	}

	static function registerTimer(vm:VM):Void {
		vm.natives.set("timerStamp", VNativeFunction("timerStamp", 0, (_) ->
			VNumber(haxe.Timer.stamp())
		));
	}
}
