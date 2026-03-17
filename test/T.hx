import nx.bridge.NxStd;
import nx.script.Interpreter;
import struc.Module;

class T {
	static function main() {
		var i = new Interpreter();
		NxStd.registerAll(i.vm);
		// i.globals.set("Module", i.vm.haxeToValue(Module));
		var result = i.run('
			import struc.Module;
			var m = Module.struct;
			m.a + m.b.length + Std.int(m.c) + (m.d ? 1 : 0)
			trace("Result: " + m.a + ", " + m.b + ", " + m.c + ", " + m.d);
  		');
	}
}
