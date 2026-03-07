import nz.script.Interpreter;

class T {
	static function main() {
		var i = new Interpreter();
		var s = Sys.time();
		var result = i.run('
   var x = 0
        var y = 0
        func update() {
            
            var delta = 16
            var velocity = 2

            x = x + velocity * delta
            y = y + velocity * delta

            func checkHitbox() {}

            var i = 0 
            while(i < 5) {
                checkHitbox()
                i = i + 1
            }
        }
  ');

		trace("Execution time: " + (Sys.time() - s) + " seconds");
	}
}
