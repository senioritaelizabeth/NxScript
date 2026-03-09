import nz.script.Interpreter;
import package_test.Module;

class T {
	static function main() {
		var i = new Interpreter();
		var s = Sys.time();
		var result = i.run('
        import package_test.Module;

        println("Hello from NxScript!");
        println("Module.foo: " + Module.foo);

        var x = 10;
        var y = 20;
        function update() {
            x = x + 1;
            y = y + 2;
            var mod_instance = new Module();
            println(mod_instance)

            println("baz is: " + mod_instance.baz);
            # change
            mod_instance.baz += 1;
            println("baz is now: " + mod_instance.baz);
        }


  ');
		// three update calls in 3 secconds
		for (j in 0...3) {
			i.call0('update');
			Sys.sleep(1);
		}
		var x = i.getVar('x');
		if (x.equals(VNumber(13))) {
			trace("x is correct: " + x);
		} else {
			trace("x is incorrect: " + x);
		}
		trace("Execution time: " + (Sys.time() - s) + " seconds");
	}
}
