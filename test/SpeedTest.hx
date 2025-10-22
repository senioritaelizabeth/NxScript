package;

import nz.script.Interpreter;

class SpeedTest {
	static function main() {
		trace("═══════════════════════════════════════════════════════");
		trace("           Nz-Script Performance Benchmark");
		trace("═══════════════════════════════════════════════════════\n");

		// Benchmark 1: Arithmetic Operations
		benchmark("Arithmetic (10,000 iterations)", () -> {
			var interp = new Interpreter();
			interp.run('
                var sum = 0
                var i = 0
                while (i < 10000 ){
                    sum = sum + i * 2 - 1
                    i = i + 1
                }
            ');
		}, 10000);

		// Benchmark 2: Function Calls
		benchmark("Function Calls (factorial)", () -> {
			var interp = new Interpreter();
			interp.run('
                func factorial(n) {
                    if (n <= 1) {
                        return 1
                    }
                    return n * factorial(n - 1)
                }
                
                factorial(10)
            ');
		}, 1);

		// Benchmark 3: Array Operations
		benchmark("Array Operations (1,000 items)", () -> {
			var interp = new Interpreter();
			interp.run('
                var arr = []
                var i = 0
                while( i < 1000) {
                    arr.push(i)
                    i = i + 1
                }
                
                var sum = 0
                for (item in arr ){
                    sum = sum + item
                }
            ');
		}, 1000);

		// Benchmark 4: String Operations
		benchmark("String Operations (1,000 ops)", () -> {
			var interp = new Interpreter();
			interp.run('
                var s = "hello"
                var i = 0
                while (i < 1000) {
                    var upper = s.upper()
                    var lower = upper.lower()
                    i = i + 1
                }
            ');
		}, 1000);

		// Benchmark 5: Method Chaining
		benchmark("Method Chaining (10,000 chains)", () -> {
			var interp = new Interpreter();
			interp.run('
                var i = 0
                while (i < 10000) {
                    var result = i.add(5).mul(2).sub(3).div(2).floor()
                    i = i + 1
                }
            ');
		}, 10000);

		// Benchmark 6: Class Instantiation
		benchmark("Class Instantiation (1,000 instances)", () -> {
			var interp = new Interpreter();
			interp.run('
                class Point {
                    var x
                    var y
                    
                    func new(px, py) {
                        this.x = px
                        this.y = py
                    }
                    
                    func distance() {
                        return (this.x * this.x + this.y * this.y).sqrt()
                    }
                }
            ');

			var i = 0;
			while (i < 1000) {
				interp.createInstance("Point", [i * 1.0, (i + 1) * 1.0]);
				i++;
			}
		}, 1000);

		// Benchmark 7: Fibonacci (Iterative - no recursion)
		benchmark("Fibonacci(100) Iterative", () -> {
			var interp = new Interpreter();
			interp.run('
                func fib(n) {
                    var a = 0
                    var b = 1
                    var i = 0
                    while (i < n) {
                        var temp = a + b
                        a = b
                        b = temp
                        i = i + 1
                    }
                    return a
                }
                
                fib(100)
            ');
		}, 1);

		trace("\n═══════════════════════════════════════════════════════");
		trace("                Benchmark Complete");
		trace("═══════════════════════════════════════════════════════");
	}

	static function benchmark(name:String, fn:Void->Void, iterations:Int = 1) {
		trace('Running: $name');

		var startTime = Sys.time(); // Segundos con decimales (más preciso)
		try {
			fn();
		} catch (e:Dynamic) {
			trace('  ✗ Error during benchmark ($name): $e');
			return;
		}
		var endTime = Sys.time();

		var elapsedSec = endTime - startTime; // segundos (con decimales)
		var elapsedMs = elapsedSec * 1000; // convertir a ms

		trace('  Time: ${Math.round(elapsedMs * 100) / 100}ms');

		if (iterations > 1 && elapsedSec > 0) {
			var rate = iterations / elapsedSec; // ops/sec
			trace('  Rate: ${Math.round(rate)} ops/sec\n');
		} else if (iterations == 1) {
			trace('  (Single operation - no rate calculated)\n');
		} else {
			trace('  (Too fast to measure accurately)\n');
		}
	}
}
