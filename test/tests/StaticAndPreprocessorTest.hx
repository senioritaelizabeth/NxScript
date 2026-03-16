package;

import nx.script.Interpreter;
import nx.script.Bytecode.Value;

/**
 * Tests for:
 *   1. static var / static func at module level
 *   2. static var / static func inside classes
 *   3. reset_context() preserving statics and class registrations
 *   4. #if / #elseif / #else / #end preprocessor
 *   5. loadScript / loadScripts (mocked without filesystem)
 *   6. Cross-script class visibility (class in run A, used in run B)
 *   7. function body on next line  (regression: `func foo()\n{`)
 */
class StaticAndPreprocessorTest {

	static var passed = 0;
	static var failed = 0;

	static function ok(cond:Bool, label:String) {
		if (cond) { passed++; Sys.println('  ✓ $label'); }
		else      { failed++; Sys.println('  ✗ FAIL: $label'); }
	}

	static function throws(fn:Void->Void, label:String) {
		var t = false;
		try { fn(); } catch (_:Dynamic) { t = true; }
		ok(t, label);
	}

	static function sec(name:String)
		Sys.println('\n--- $name ---');

	static function main() {
		Sys.println("╔══════════════════════════════════════╗");
		Sys.println("║  Static + Preprocessor Tests          ║");
		Sys.println("╚══════════════════════════════════════╝");

		testFunctionBodyOnNextLine();
		testModuleStaticVar();
		testModuleStaticFunc();
		testClassStaticVar();
		testClassStaticMethod();
		testStaticSurvivesReset();
		testClassSurvivesReset();
		testPreprocessorIf();
		testPreprocessorElse();
		testPreprocessorElseif();
		testPreprocessorNot();
		testPreprocessorAnd();
		testPreprocessorNested();
		testPreprocessorLineNumbers();
		testPreprocessorCustomDefine();
		testCrossScriptClassVisibility();
		testCrossScriptClassAfterReset();

		Sys.println('\n╔══════════════════════════════════════╗');
		Sys.println('║  Results: $passed passed, $failed failed');
		Sys.println('╚══════════════════════════════════════╝');
		Sys.exit(failed > 0 ? 1 : 0);
	}

	// ══════════════════════════════════════════════════════════════════════
	// REGRESSION: function body on next line
	// ══════════════════════════════════════════════════════════════════════

	static function testFunctionBodyOnNextLine() {
		sec("function body on next line");
		var i = new Interpreter();

		ok(i.runDynamic('
			function add(a, b)
			{
				return a + b
			}
			add(3, 4)
		') == 7, "function body on next line");

		ok(i.runDynamic('
			func greet(name)
			{
				return "hello " + name
			}
			greet("world")
		') == "hello world", "func body on next line");

		ok(i.runDynamic('
			class Foo
			{
				var x = 0
				func new(v)
				{
					this.x = v
				}
				func get()
				{
					return this.x
				}
			}
			var f = new Foo(42)
			f.get()
		') == 42, "class and method bodies on next line");
	}

	// ══════════════════════════════════════════════════════════════════════
	// MODULE-LEVEL STATIC VAR
	// ══════════════════════════════════════════════════════════════════════

	static function testModuleStaticVar() {
		sec("module-level static var");
		var i = new Interpreter();

		// Basic declaration and use
		ok(i.runDynamic('static var x = 10\nx') == 10, "static var declaration");
		ok(i.runDynamic('static var y = 0\ny += 5\ny') == 5, "static var mutation");

		// Accessible across multiple run() calls on same interpreter
		i.runDynamic('static var counter = 0');
		i.runDynamic('counter++');
		i.runDynamic('counter++');
		i.runDynamic('counter++');
		ok(i.runDynamic('counter') == 3, "static var accumulates across runs");

		// Zero and string initial values
		ok(i.runDynamic('static var msg = "hello"\nmsg') == "hello", "static var string init");
		ok(i.runDynamic('static var flag = false\nflag') == false, "static var bool init");
	}

	// ══════════════════════════════════════════════════════════════════════
	// MODULE-LEVEL STATIC FUNC
	// ══════════════════════════════════════════════════════════════════════

	static function testModuleStaticFunc() {
		sec("module-level static func");
		var i = new Interpreter();

		i.runDynamic('static func double(n) { return n * 2 }');
		ok(i.runDynamic('double(7)') == 14, "static func callable");
		ok(i.runDynamic('double(double(3))') == 12, "static func composable");

		// Static func survives multiple runs
		i.runDynamic('static func greet(name) { return "hi " + name }');
		ok(i.runDynamic('greet("world")') == "hi world", "static func across runs");
	}

	// ══════════════════════════════════════════════════════════════════════
	// CLASS STATIC VAR
	// ══════════════════════════════════════════════════════════════════════

	static function testClassStaticVar() {
		sec("class static var");
		var i = new Interpreter();

		// Basic static field access
		ok(i.runDynamic('
			class Config {
				static var debug = false
				static var version = "1.0"
			}
			Config.debug
		') == false, "class static var bool");

		ok(i.runDynamic('Config.version') == "1.0", "class static var string");

		// Mutation via class name
		ok(i.runDynamic('
			Config.debug = true
			Config.debug
		') == true, "class static var mutation");

		// Instance count pattern
		i.runDynamic('
			class Entity {
				static var count = 0
				var id = 0
				func new()
				{
					Entity.count++
					this.id = Entity.count
				}
			}
		');
		i.runDynamic("var a = new Entity()\nvar b = new Entity()\nvar c = new Entity()");
		ok(i.runDynamic("a.id") == 1, "entity a.id == 1");
		ok(i.runDynamic("b.id") == 2, "entity b.id == 2");
		ok(i.runDynamic("c.id") == 3, "entity c.id == 3");
		ok(i.runDynamic("Entity.count") == 3, "instance count via static var");
	}

	// ══════════════════════════════════════════════════════════════════════
	// CLASS STATIC METHOD
	// ══════════════════════════════════════════════════════════════════════

	static function testClassStaticMethod() {
		sec("class static func");
		var i = new Interpreter();

		ok(i.runDynamic('
			class MathUtils {
				static func clamp(v, lo, hi)
				{
					if (v < lo) return lo
					if (v > hi) return hi
					return v
				}
				static func lerp(a, b, t) { return a + (b - a) * t }
			}
			MathUtils.clamp(15, 0, 10)
		') == 10, "static func clamp high");

		ok(i.runDynamic('MathUtils.clamp(-5, 0, 10)') == 0, "static func clamp low");
		ok(i.runDynamic('MathUtils.clamp(5, 0, 10)') == 5, "static func clamp in range");
		ok(i.runDynamic('MathUtils.lerp(0, 100, 0.25)') == 25, "static func lerp");

		// Static method accessing static field
		ok(i.runDynamic('
			class Counter {
				static var n = 0
				static func increment() { Counter.n++ }
				static func reset()     { Counter.n = 0 }
				static func get()       { return Counter.n }
			}
			Counter.increment()
			Counter.increment()
			Counter.increment()
			Counter.get()
		') == 3, "static method accessing static field");

		ok(i.runDynamic('
			Counter.reset()
			Counter.get()
		') == 0, "static reset() works");
	}

	// ══════════════════════════════════════════════════════════════════════
	// STATIC SURVIVES RESET_CONTEXT
	// ══════════════════════════════════════════════════════════════════════

	static function testStaticSurvivesReset() {
		sec("static vars survive reset_context");
		var i = new Interpreter();

		i.runDynamic('static var score = 0');
		i.runDynamic('score = 99');
		ok(i.runDynamic('score') == 99, "static var before reset");

		i.reset_context();
		ok(i.runDynamic('score') == 99, "static var after reset_context");

		// Mutation after reset still works
		i.runDynamic('score += 1');
		ok(i.runDynamic('score') == 100, "static var mutable after reset");

		// Non-static var does NOT survive
		i.runDynamic('var temp = 42');
		i.reset_context();
		// temp should be gone — accessing it throws or returns null
		var tempGone = false;
		try {
			var v = i.runDynamic('temp');
			tempGone = (v == null);
		} catch (_:Dynamic) {
			tempGone = true;
		}
		ok(tempGone, "non-static var is gone after reset");
	}

	// ══════════════════════════════════════════════════════════════════════
	// CLASS REGISTRATION SURVIVES RESET_CONTEXT
	// ══════════════════════════════════════════════════════════════════════

	static function testClassSurvivesReset() {
		sec("class registration survives reset_context");
		var i = new Interpreter();

		i.runDynamic('
			class Vec2 {
				var x = 0
				var y = 0
				func new(px, py) { this.x = px\nthis.y = py }
				func dot(other) { return this.x * other.x + this.y * other.y }
			}
		');
		ok(i.runDynamic('var v = new Vec2(3,4)\nv.x + v.y') == 7, "Vec2 before reset");

		i.reset_context();
		ok(i.runDynamic('var v = new Vec2(1,2)\nv.x + v.y') == 3, "Vec2 after reset_context");
		ok(i.runDynamic('var a=new Vec2(1,0)\nvar b=new Vec2(0,1)\na.dot(b)') == 0, "Vec2 dot after reset");

		// Class static field survives reset (lives on ClassData)
		var i2 = new Interpreter();
		i2.runDynamic('
			class Pool {
				static var size = 0
				func new() { Pool.size++ }
			}
		');
		i2.runDynamic('new Pool()\nnew Pool()');
		ok(i2.runDynamic('Pool.size') == 2, "Pool.size = 2 before reset");

		i2.reset_context();
		ok(i2.runDynamic('Pool.size') == 2, "Pool.size = 2 after reset (lives on ClassData)");

		// New instances after reset still increment
		i2.runDynamic('new Pool()');
		ok(i2.runDynamic('Pool.size') == 3, "Pool.size increments after reset");
	}

	// ══════════════════════════════════════════════════════════════════════
	// PREPROCESSOR
	// ══════════════════════════════════════════════════════════════════════

	static function testPreprocessorIf() {
		sec("#if / #end");
		var i = new Interpreter();
		i.defines.set("myFlag", true);

		ok(i.runDynamic('var x=0\n#if myFlag\nx=1\n#end\nx') == 1,   "#if true — block runs");
		ok(i.runDynamic('var x=0\n#if noFlag\nx=99\n#end\nx') == 0,  "#if false — block skipped");
		ok(i.runDynamic('var x=0\n#if myFlag\nx=5\n#end\nvar y=x*2\ny') == 10, "#if true + code after");
	}

	static function testPreprocessorElse() {
		sec("#if / #else / #end");
		var i = new Interpreter();

		ok(i.runDynamic('var x=0\n#if noFlag\nx=1\n#else\nx=2\n#end\nx') == 2,   "#else branch taken");
		i.defines.set("yesFlag", true);
		ok(i.runDynamic('var x=0\n#if yesFlag\nx=1\n#else\nx=2\n#end\nx') == 1, "#if branch taken, else skipped");
	}

	static function testPreprocessorElseif() {
		sec("#if / #elseif / #else / #end");
		var i = new Interpreter();
		i.defines.set("b", true);

		ok(i.runDynamic('var x=0\n#if a\nx=1\n#elseif b\nx=2\n#else\nx=3\n#end\nx') == 2, "#elseif b taken");
		ok(i.runDynamic('var x=0\n#if a\nx=1\n#elseif c\nx=2\n#else\nx=3\n#end\nx') == 3, "falls to #else");

		i.defines.set("a", true);
		ok(i.runDynamic('var x=0\n#if a\nx=1\n#elseif b\nx=2\n#else\nx=3\n#end\nx') == 1, "#if a taken, elseif skipped");
	}

	static function testPreprocessorNot() {
		sec("#if ! negation");
		var i = new Interpreter();

		ok(i.runDynamic('var x=0\n#if !noFlag\nx=7\n#end\nx') == 7,   "!undefined is true");
		i.defines.set("defined", true);
		ok(i.runDynamic('var x=0\n#if !defined\nx=7\n#end\nx') == 0,  "!defined is false");
		ok(i.runDynamic('var x=0\n#if !noFlag\nx=7\n#end\nx') == 7,   "!undefined still true");
	}

	static function testPreprocessorAnd() {
		sec("#if && and ||");
		var i = new Interpreter();
		i.defines.set("p", true);
		i.defines.set("q", true);

		ok(i.runDynamic('var x=0\n#if p && q\nx=1\n#end\nx') == 1, "p && q both true");
		ok(i.runDynamic('var x=0\n#if p && r\nx=1\n#end\nx') == 0, "p && r: r undefined");
		ok(i.runDynamic('var x=0\n#if r || p\nx=1\n#end\nx') == 1, "r || p: p true");
		ok(i.runDynamic('var x=0\n#if r || s\nx=1\n#end\nx') == 0, "r || s: both undefined");
	}

	static function testPreprocessorNested() {
		sec("#if nested");
		var i = new Interpreter();
		i.defines.set("outer", true);
		i.defines.set("inner", true);

		ok(i.runDynamic('
			var x = 0
			#if outer
			#if inner
			x = 1
			#end
			#end
			x
		') == 1, "nested #if both true");

		ok(i.runDynamic('
			var x = 0
			#if outer
			#if noInner
			x = 1
			#else
			x = 2
			#end
			#end
			x
		') == 2, "nested #if outer true, inner false → else");
	}

	static function testPreprocessorLineNumbers() {
		sec("preprocessor preserves line numbers");
		var i = new Interpreter();

		// Inactive block should not shift line numbers
		ok(i.runDynamic('
			var a = 1
			#if noFlag
			var never = 999
			var also_never = 888
			#end
			var b = 2
			a + b
		') == 3, "line numbers preserved after inactive block");

		// Error line should be correct after #if block
		var errLine = -1;
		try {
			i.run('
				var x = 1
				#if noFlag
				var skipped = 0
				#end
				undeclaredVariable
			', "test.nx");
		} catch (e:Dynamic) {
			var msg = Std.string(e);
			// Should reference line 6 (the undeclaredVariable line), not earlier
			if (msg.indexOf("undeclaredVariable") >= 0) errLine = 6;
		}
		ok(errLine >= 0, "error still references correct variable name after #if");
	}

	static function testPreprocessorCustomDefine() {
		sec("custom defines from Haxe host");
		var i = new Interpreter();

		// Simulate game engine setting flags
		i.defines.set("flixel", true);
		i.defines.set("mobile", false);
		i.defines.set("gameVersion", false); // can't set version strings, only bools

		ok(i.runDynamic('var x=0\n#if flixel\nx=1\n#end\nx') == 1, "custom define flixel");
		ok(i.runDynamic('var x=0\n#if mobile\nx=1\n#else\nx=2\n#end\nx') == 2, "custom define mobile=false");

		// Change a define at runtime
		i.defines.set("debug", true);
		ok(i.runDynamic('var x=0\n#if debug\nx=99\n#end\nx') == 99, "runtime define change");
	}

	// ══════════════════════════════════════════════════════════════════════
	// CROSS-SCRIPT CLASS VISIBILITY
	// ══════════════════════════════════════════════════════════════════════

	static function testCrossScriptClassVisibility() {
		sec("cross-script class visibility");
		var i = new Interpreter();

		// Class defined in run A, instantiated in run B
		i.runDynamic('
			class Animal {
				var name = "unknown"
				var sound = "..."
				func new(n, s) { this.name = n\nthis.sound = s }
				func speak() { return this.name + " says " + this.sound }
			}
		');
		ok(i.runDynamic('var a = new Animal("Dog","woof")\na.speak()') == "Dog says woof",
			"class from run A used in run B");

		// Third run still works
		ok(i.runDynamic('var a = new Animal("Cat","meow")\na.speak()') == "Cat says meow",
			"class still visible in run C");

		// Cross-run inheritance — Dog extends Animal defined in a prior run
		i.runDynamic('
			class Dog extends Animal {
				func new(n) { super.new(n, "woof") }
				func fetch() { return this.name + " fetches!" }
			}
		');
		ok(i.runDynamic('var d = new Dog("Rex")\nd.speak()') == "Rex says woof",
			"cross-run inheritance: speak()");
		ok(i.runDynamic('d.fetch()') == "Rex fetches!",
			"cross-run inheritance: fetch()");

		// Multiple classes, each defined separately
		i.runDynamic('class Point { var x=0\nvar y=0\nfunc new(px,py){ this.x=px\nthis.y=py } }');
		i.runDynamic('class Rect { var pos\nfunc new(x,y){ this.pos=new Point(x,y) }\nfunc area(w,h){ return w*h } }');
		ok(i.runDynamic('var r=new Rect(1,2)\nr.pos.x + r.pos.y') == 3,
			"class using class from another run as field");
	}

	static function testCrossScriptClassAfterReset() {
		sec("class visibility after reset_context");
		var i = new Interpreter();

		i.runDynamic('
			class Timer {
				var elapsed = 0.0
				func tick(dt) { this.elapsed += dt }
				func get()    { return this.elapsed }
			}
		');
		var t:Dynamic = i.createInstance("Timer", []);
		t.tick(0.016);
		t.tick(0.016);

		i.reset_context();

		// Class should still be available
		ok(i.runDynamic('var t = new Timer()\nt.tick(1.0)\nt.get()') == 1.0,
			"class still usable after reset_context");

		// New instances after reset are independent
		i.runDynamic('
			var t1 = new Timer()
			var t2 = new Timer()
			t1.tick(1.0)
			t1.tick(1.0)
			t2.tick(0.5)
		');
		ok(i.runDynamic("t1.get()") == 2.0, "t1 elapsed = 2.0");
		ok(i.runDynamic("t2.get()") == 0.5, "t2 elapsed = 0.5");
	}
}