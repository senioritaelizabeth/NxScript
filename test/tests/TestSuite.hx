package;

import nx.script.Interpreter;
import nx.script.VM;
import nx.script.VM.GcKind;
import nx.script.Bytecode.Value;
import nx.bridge.NxStd;
import nx.bridge.NxDate;

/**
 * NxScript unified test suite.
 * 30 sections covering everything: basics, classes, methods, bug fixes,
 * imports, error format, lambdas, templates, match, destructuring,
 * GC, sandbox, using, enums, abstractss, braceless syntax, is, bridges.
 *
 * Run: haxe test_suite.hxml
 */
class TestSuite {

	static var passed  = 0;
	static var failed  = 0;


	static function ok(cond:Bool, label:String) {
		if (cond) { passed++; trace('  \u2713 ' + label); }
		else      { failed++; trace('  \u2717 FAIL: ' + label); }
	}

	static function approx(a:Float, b:Float, label:String, eps:Float = 0.01)
		ok(Math.abs(a - b) < eps, label);

	static function throws(fn:Void->Void, label:String) {
		var t = false;
		try { fn(); } catch (_:Dynamic) { t = true; }
		ok(t, label);
	}

	static function sec(name:String)
		Sys.println('\n--- ' + name + ' ---');

	static function captureError(fn:Void->Void):String {
		try { fn(); return ""; } catch (e:Dynamic) { return Std.string(e); }
	}


	static function main() {
		trace("\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557");
		trace("\u2551       NxScript Test Suite            \u2551");
		trace("\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d");

		testBasics();
		testClasses();
		testMethods();
		testBugFixes();
		testImports();
		testErrorFormat();
		testNewFeatures();
		testTrailingCommas();
		testLambdas();
		testTemplateStrings();
		testArrayMethods();
		testStringMethods();
		testDictMethods();
		testGlobals();
		testGcControl();
		testNestedScopes();
		testMatch();
		testDestructuring();
		testSafeCall();
		testSandbox();
		testUsing();
		testIntFloat();
		testConversions();
		testNxStd();
		testNxDate();
		testScopePerfAndCorrectness();
		testEnums();
		testIsOperator();
		testBracelessSyntax();
		testAbstracts();

		Sys.println("\n\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557");
		Sys.println('\u2551  Results: ' + passed + ' passed, ' + failed + ' failed');
		Sys.println("\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d");
		Sys.exit(failed > 0 ? 1 : 0);
	}

	// ══════════════════════════════════════════════════════════════════════
	// 1. BASICS
	// ══════════════════════════════════════════════════════════════════════
	static function testBasics() {
		sec("Basics");
		var i = new Interpreter();
		ok(i.runDynamic('var x=10\nvar y=20\nx+y') == 30,                          "variables and addition");
		ok(i.runDynamic('func add(a,b){return a+b}\nadd(15,25)') == 40,            "function call");
		ok(i.runDynamic('var x=10\nvar y=20\nvar m=0\nif(x>y){m=x}else{m=y}\nm') == 20, "if/else");
		ok(i.runDynamic('var i=0\nvar s=0\nwhile(i<10){s=s+i\ni=i+1}\ns') == 45,  "while loop");
		ok(i.runDynamic('var a=[1,2,3]\na.push(4)\na.length') == 4,                "array push+length");
		ok(i.runDynamic('var x=5\n++x\nx') == 6,  "prefix ++");
		ok(i.runDynamic('var x=5\n--x\nx') == 4,  "prefix --");
		ok(i.runDynamic('var x=5\nx++\nx') == 6,  "postfix ++");
		ok(i.runDynamic('var x=5\nx--\nx') == 4,  "postfix --");
		ok(i.runDynamic('var x=10\nvar y=3\nx%y') == 1, "modulo");
		ok(i.runDynamic('true && false') == false, "&& false");
		ok(i.runDynamic('true || false') == true,  "|| true");
		ok(i.runDynamic('!false') == true,          "! negation");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 2. CLASSES
	// ══════════════════════════════════════════════════════════════════════
	static function testClasses() {
		sec("Classes");
		var i = new Interpreter();
		i.runDynamic('
			class Point {
				var x\nvar y
				func new(px,py){this.x=px\nthis.y=py}
				func sum(){return this.x+this.y}
			}
		');
		var pt:Dynamic = i.createInstance("Point",[3.0,4.0]);
		ok(pt.x == 3.0,    "instantiation field x");
		ok(pt.y == 4.0,    "instantiation field y");
		ok(pt.sum() == 7.0,"method call sum()");
		pt.x = 10.0;
		ok(pt.sum() == 14.0,"field modify + method");
	
	}

	// ══════════════════════════════════════════════════════════════════════
	// 3. METHODS
	// ══════════════════════════════════════════════════════════════════════
	static function testMethods() {
		sec("Methods");
		var i = new Interpreter();
		// Number
		ok(i.runDynamic('(3.7).floor()') == 3,   "Number.floor()");
		ok(i.runDynamic('(-5).abs()') == 5,       "Number.abs()");
		ok(i.runDynamic('(2).pow(3)') == 8,       "Number.pow()");
		ok(i.runDynamic('(1.5).ceil()') == 2,     "Number.ceil()");
		ok(i.runDynamic('(3.7).round()') == 4,    "Number.round()");
		ok(i.runDynamic('(9).sqrt()') == 3,       "Number.sqrt()");
		// String
		ok(i.runDynamic('"hello".upper()') == "HELLO", "String.upper()");
		ok(i.runDynamic('"WORLD".lower()') == "world", "String.lower()");
		ok(i.runDynamic('"  hi  ".trim()') == "hi",    "String.trim()");
		ok(i.runDynamic('"hello".length') == 5,         "String.length");
		ok(i.runDynamic('"abc".charAt(1)') == "b",      "String.charAt()");
		ok(i.runDynamic('"hello world".indexOf("world")') == 6, "String.indexOf()");
		ok(i.runDynamic('"hello".substr(1,3)') == "ell","String.substr()");
		ok(i.runDynamic('"a,b,c".split(",").length') == 3,"String.split()");
		// Array
		ok(i.runDynamic('[1,2,3].length') == 3,          "Array.length");
		ok(i.runDynamic('[1,2,3].first()') == 1,         "Array.first()");
		ok(i.runDynamic('[1,2,3,4].last()') == 4,        "Array.last()");
		ok(i.runDynamic('var a=[1,2,3]\na.pop()\na.length') == 2, "Array.pop()");
		ok(i.runDynamic('var a=[2,3]\na.unshift(1)\na[0]') == 1,  "Array.unshift()");
		ok(i.runDynamic('[1,2,3].join("-")') == "1-2-3", "Array.join()");
		ok(i.runDynamic('[3,1,2].reverse()[0]') == 2,    "Array.reverse()");
		ok(i.runDynamic('[1,2,3].includes(2)') == true,  "Array.includes()");
		// Chaining
		ok(i.runDynamic('(-2000/2).abs().floor()') == 1000, "Number chain abs().floor()");
		ok(i.runDynamic('"  HELLO  ".trim().lower()') == "hello", "String chain trim().lower()");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 4. BUG FIX REGRESSIONS
	// ══════════════════════════════════════════════════════════════════════
	static function testBugFixes() {
		sec("Bug fix regressions");
		var i = new Interpreter();

		ok(i.runDynamic('var a=[1,2,3]\na[1]=99\na[1]') == 99,
			"array index assignment");
		ok(i.runDynamic('
			class Vec {
				var x\nvar y
				func new(px,py){this.x=px\nthis.y=py}
				func move(dx,dy){this.x=this.x+dx\nthis.y=this.y+dy\nreturn this.x+this.y}
			}
			var v=new Vec(1,2)\nv.move(10,20)
		') == 33, "sequential this.x= in method");

		var i2 = new Interpreter();
		for (_ in 0...10) i2.runDynamic('var i=0\nwhile(i<500){i=i+1}\ni');
		ok(i2.runDynamic('42') == 42, "instructionCount resets");

		ok(i.runDynamic('
			var s=0
			for(k from 0 to 5){if(k==2){continue}\ns=s+k}
			s
		') == 8, "for-from-to with continue");

		ok(i.runDynamic('
			var x=10
			if(x==5){return 1}
			elseif(x==10){return 2}
			else{return 3}
		') == 2, "elseif keyword");

		// postfix ++ evaluates target once
		var calls = 0;
		i.register("getVal", 0, function(_) { calls++; return VNumber(10); });
		var res:Array<Dynamic> = cast i.runDynamic('
			var obj={"x":10}
			func getObj(){getVal()\nreturn obj}
			var old=getObj().x++
			[old,obj.x]
		');
		ok(calls == 1,   "postfix++: getObj() called once");
		ok(res[0] == 10, "postfix++: returns old value");
		ok(res[1] == 11, "postfix++: target incremented");

		// 4.squared must NOT be tokenized as float 4.
		ok(i.runDynamic('class E{func squared(n){return n*n}}\nusing E\n4.squared()') == 16,
			"4.method() tokenizes correctly");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 5. IMPORTS
	// ══════════════════════════════════════════════════════════════════════
	static function testImports() {
		sec("Imports");
		var i = new Interpreter();
		ok(i.runDynamic('import "haxe.ds.StringMap"\nvar m=new StringMap()\nm.set("k",10)\nm.get("k")', "t.nx") == 10,
			'import "haxe.ds.StringMap"');
		ok(i.runDynamic('import haxe.ds.StringMap\nvar m=new StringMap()\nm.set("k",42)\nm.get("k")', "t.nx") == 42,
			"import bare identifier");
		ok(i.runDynamic('function add(a:Int,b:Int):Int{return a+b;}\nadd(8,9);', "t.nx") == 17,
			"Haxe-style :ReturnType syntax");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 6. ERROR FORMAT
	// ══════════════════════════════════════════════════════════════════════
	static function testErrorFormat() {
		sec("Error format");
		var i = new Interpreter();
		var msg = captureError(() -> i.run('ifx(true){\nvar x=1\n}', "t.nx"));
		ok(msg.indexOf("l |")    >= 0, "shows context lines 'l |'");
		ok(msg.indexOf("^")      >= 0, "shows caret ^");
		ok(msg.indexOf("Error:") >= 0, "shows 'Error:' label");
		ok(msg.indexOf("t.nx")   >= 0, "shows script path");

		var rt = captureError(() -> i.run('func boom(){\nvar x=undeclared\n}\nboom()', "t.nx"));
		ok(rt.indexOf("Stack trace") >= 0, "runtime error includes stack trace");
		ok(rt.indexOf("boom")        >= 0, "stack trace includes function name");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 7. NEW FEATURES (try/catch, strict mode)
	// ══════════════════════════════════════════════════════════════════════
	static function testNewFeatures() {
		sec("try/catch/throw + strict mode");
		var i = new Interpreter();
		ok(i.runDynamic('var r="none"\ntry{throw "oops"\nr="bad"}catch(e){r=e}\nr') == "oops",
			"try/catch catches thrown value");
		ok(i.runDynamic('var r=0\ntry{r=1\nr=2}catch(e){r=-1}\nr') == 2,
			"try runs normally when no throw");
		ok(i.runDynamic('func risky(n){if(n<0){throw "neg"}\nreturn n*2}\nvar out="none"\ntry{out=risky(-1)}catch(e){out=e}\nout') == "neg",
			"catch from function");

		var strict = new Interpreter(false,true);
		throws(() -> strict.run('var a=1\nvar b=2\na+b'), "strict rejects missing semicolons");
		ok(strict.runDynamic('var a=1;\nvar b=2;\na+b;') == 3, "strict accepts semicolons");

		var pragma = new Interpreter();
		throws(() -> pragma.run('"use strict";\nvar x=1\nvar y=2\nx+y'), '"use strict" enables strict');
		ok(pragma.runDynamic('"use strict";\nvar x=1;\nvar y=2;\nx+y;') == 3, '"use strict" with semicolons');
	}

	// ══════════════════════════════════════════════════════════════════════
	// 8–14. SYNTAX FEATURES
	// ══════════════════════════════════════════════════════════════════════
	static function testTrailingCommas() {
		sec("Trailing commas");
		var i = new Interpreter();
		ok(i.runDynamic('[1,2,3,].length') == 3,                       "array literal");
		ok(i.runDynamic('func f(a,b,){return a+b}\nf(10,20,)') == 30,  "params and call");
		ok(i.runDynamic('var d={"x":1,"y":2,}\nd["x"]+d["y"]') == 3,  "dict literal");
	}

	static function testLambdas() {
		sec("Shorthand lambdas =>");
		var i = new Interpreter();
		ok(i.runDynamic('var f=x=>x*2\nf(7)') == 14,                             "x => expr");
		ok(i.runDynamic('var f=(a,b)=>a+b\nf(3,4)') == 7,                        "(a,b) => expr");
		ok(i.runDynamic('var f=name=>{return "Hello "+name}\nf("World")') == "Hello World", "x => { block }");
		ok(i.runDynamic('[1,2,3,4,5].filter(x=>x>2).length') == 3,               "=> in filter");
	}

	static function testTemplateStrings() {
		sec("Template strings");
		var i = new Interpreter();
		ok(i.runDynamic("var n='NxScript'\n`Hello ${n}!`") == "Hello NxScript!", "backtick basic");
		ok(i.runDynamic("var a=3\nvar b=4\n`${a}+${b}=${a+b}`") == "3+4=7",     "backtick expr");
		ok(i.runDynamic('`no interp`') == "no interp",                             "plain backtick");
		ok(i.runDynamic("var x=42\n'value is ${x}'") == "value is 42",           "single-quote ${} ");
		ok(i.runDynamic("var a=10\nvar b=20\n'sum: ${a+b}'") == "sum: 30",       "single-quote expr");
		ok(i.runDynamic("var n='world'\n\"hello ${n}\"") == "hello world",          "double-quote ${}");
		ok(i.runDynamic("var x=5\n\"x^2=${x*x}\"") == "x^2=25",                   "double-quote computed"); // i forget abouyt thi, shit
	}

	// ══════════════════════════════════════════════════════════════════════
	// 15–17. COLLECTION METHODS
	// ══════════════════════════════════════════════════════════════════════
	static function testArrayMethods() {
		sec("Array methods (functional)");
		var i = new Interpreter();
		ok(i.runDynamic('[1,2,3].map(x=>x*2)[2]') == 6,                            "map");
		ok(i.runDynamic('[1,2,3,4,5,6].filter(x=>x%2==0).length') == 3,           "filter");
		ok(i.runDynamic('[1,2,3,4,5].reduce((acc,x)=>acc+x,0)') == 15,            "reduce");
		ok(i.runDynamic('var s=0\n[10,20,30].forEach(x=>{s=s+x})\ns') == 60,      "forEach");
		ok(i.runDynamic('[1,3,5,8,9].find(x=>x%2==0)') == 8,                      "find");
		ok(i.runDynamic('[10,20,30,40].findIndex(x=>x>25)') == 2,                 "findIndex");
		ok(i.runDynamic('[2,4,6,8].every(x=>x%2==0)') == true,                    "every true");
		ok(i.runDynamic('[2,4,5,8].every(x=>x%2==0)') == false,                   "every false");
		ok(i.runDynamic('[1,3,4,7].some(x=>x%2==0)') == true,                     "some");
		ok(i.runDynamic('[0,1,2,3,4].slice(1,4).length') == 3,                    "slice length");
		ok(i.runDynamic('[0,1,2,3,4].slice(1,4)[0]') == 1,                        "slice first");
		ok(i.runDynamic('[1,2].concat([3,4]).length') == 4,                        "concat");
		ok(i.runDynamic('[[1,2],[3,4],[5]].flat().length') == 5,                  "flat");
		ok(i.runDynamic('var a=[1,2,3]\nvar b=a.copy()\nb.push(4)\na.length') == 3,"copy independence");
		ok(i.runDynamic('[3,1,4,1,5,9].sort((a,b)=>a-b)[0]') == 1,               "sort ascending");
		ok(i.runDynamic('["banana","apple","cherry"].sortBy(w=>w.length)[0]') == "apple","sortBy");
	}

	static function testStringMethods() {
		sec("String methods (extended)");
		var i = new Interpreter();
		ok(i.runDynamic('"hello world".startsWith("hello")') == true,  "startsWith true");
		ok(i.runDynamic('"hello world".startsWith("world")') == false, "startsWith false");
		ok(i.runDynamic('"hello world".endsWith("world")') == true,    "endsWith");
		ok(i.runDynamic('"hello world".replace("world","NxScript")') == "hello NxScript","replace");
		ok(i.runDynamic('"ha".repeat(3)') == "hahaha",                 "repeat");
		ok(i.runDynamic('"5".padStart(4,"0")') == "0005",              "padStart");
		ok(i.runDynamic('"hi".padEnd(5,"-")') == "hi---",              "padEnd");
	}

	static function testDictMethods() {
		sec("Dict methods");
		var i = new Interpreter();
		ok(i.runDynamic('var d={"a":1,"b":2,"c":3}\nd.size()') == 3,              "size()");
		ok(i.runDynamic('var d={"a":1,"b":2}\nd.has("a")') == true,               "has() true");
		ok(i.runDynamic('var d={"a":1,"b":2}\nd.has("z")') == false,              "has() false");
		ok(i.runDynamic('var d={"a":1,"b":2}\nd.remove("a")\nd.has("a")') == false,"remove()");
		ok(i.runDynamic('var d={"a":1}\nd.set("b",99)\nd["b"]') == 99,            "set()");
		ok(i.runDynamic('var d={"x":10,"y":20}\nd.keys().length') == 2,           "keys()");
		ok(i.runDynamic('var d={"x":10,"y":20}\nd.values().reduce((a,v)=>a+v,0)') == 30,"values()");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 18. GLOBAL NATIVES
	// ══════════════════════════════════════════════════════════════════════
	static function testGlobals() {
		sec("Global natives");
		var i = new Interpreter();
		ok(i.runDynamic('range(5).length') == 5,     "range(5)");
		ok(i.runDynamic('range(2,6)[0]') == 2,       "range(2,6)[0]");
		ok(i.runDynamic('str(42)') == "42",           "str()");
		ok(i.runDynamic('int(3.9)') == 3,             "int()");
		ok(i.runDynamic('abs(-5)') == 5,              "abs()");
		ok(i.runDynamic('floor(3.9)') == 3,           "floor()");
		ok(i.runDynamic('sqrt(16)') == 4,             "sqrt()");
		ok(i.runDynamic('pow(2,10)') == 1024,         "pow()");
		ok(i.runDynamic('min(3,7)') == 3,             "min()");
		ok(i.runDynamic('max(3,7)') == 7,             "max()");
		ok(i.runDynamic('PI>3.14&&PI<3.15') == true,  "PI");
		ok(i.runDynamic('0.0/0.0') != 0.0,            "0/0 => NaN (not error)");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 19. GC CONTROL
	// ══════════════════════════════════════════════════════════════════════
	static function testGcControl() {
		sec("GC control");
		var i = new Interpreter();
		i.gc_kind = AGGRESSIVE;
		ok(i.runDynamic('[1,2,3].map(x=>x*2).length') == 3, "AGGRESSIVE gc");
		i.gc_kind = SOFT;
		i.gc_softThreshold = 1;
		ok(i.runDynamic('"hello".startsWith("he")') == true, "SOFT gc");
		i.gc_kind = VERY_SOFT;
		ok(i.runDynamic('range(3).reduce((a,x)=>a+x,0)') == 3, "VERY_SOFT gc");
		i.gc_kind = SOFT;
		i.gc_softThreshold = 512;
		i.gc();
		ok(i.runDynamic('str(99)') == "99", "manual gc() then run");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 20. NESTED SCOPES
	// ══════════════════════════════════════════════════════════════════════
	static function testNestedScopes() {
		sec("Nested scopes (let)");
		var i = new Interpreter();
		ok(i.runDynamic('var x=10\n{let y=99\nx=x+1}\nx') == 11, "outer var survives block");
		ok(i.runDynamic('let a=1\n{let a=42\na}') == 42, "inner let shadows outer");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 21. MATCH
	// ══════════════════════════════════════════════════════════════════════
	static function testMatch() {
		sec("match pattern matching");
		var i = new Interpreter();
		ok(i.runDynamic('var x=2\nmatch x{case 1=>"one"\ncase 2=>"two"\ndefault=>"other"}') == "two", "value");
		ok(i.runDynamic('match 99{case 1=>"one"\ndefault=>"other"}') == "other", "default");
		ok(i.runDynamic('var s=85\nmatch s{case 90...100=>"A"\ncase 80...89=>"B"\ndefault=>"F"}') == "B","range");
		ok(i.runDynamic('match 7{case 1=>"one"\ncase n=>n*10}') == 70, "bind match n*10");
		ok(i.runDynamic('var r=0\nmatch 3{case 1=>{r=100}\ncase 3=>{var t=300\nr=t+33}\ndefault=>{r=-1}}\nr') == 333, "block body");
		ok(i.runDynamic('var c="attack"\nmatch c{case "attack"=>"go"\ndefault=>"no"}') == "go","string values");
		ok(i.runDynamic('match [10,20,30]{case [a,b]=>a+b\ncase [a,b,c]=>a+b+c\ndefault=>0}') == 60,"array destructure");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 22. DESTRUCTURING
	// ══════════════════════════════════════════════════════════════════════
	static function testDestructuring() {
		sec("Destructuring");
		var i = new Interpreter();
		ok(i.runDynamic('var [a,b,c]=[10,20,30]\na+b+c') == 60,           "array [a,b,c]");
		ok(i.runDynamic('var [f,_,t]=[1,2,3]\nf+t') == 4,                 "array _ skip");
		ok(i.runDynamic('var {x,y}={"x":10,"y":20}\nx+y') == 30,          "dict {x,y}");
		i.reset_context();
		trace("NOTE: this test requires a new VM, calling reset_context()");		
		ok(i.runDynamic('func mp(a,b){return{"x":a,"y":b}}\nvar{x,y}=mp(5,15)\nx*y') == 75,"dict from fn");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 23. SAFECALL
	// ══════════════════════════════════════════════════════════════════════
	static function testSafeCall() {
		sec("safeCall");
		var i = new Interpreter();
		i.run('func greet(name){return "hi "+name}');
		var v = i.safeCall("greet",[VString("world")]);
		ok(v != null, "safeCall returns value");
		ok(i.vm.valueToString(v) == "hi world", "safeCall correct result");
		ok(i.safeCall("doesNotExist",[]) == null, "missing fn returns null");
		i.run('func broken(){throw "oops"}');
		ok(i.safeCall("broken",[]) == null, "error returns null");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 24. SANDBOX
	// ══════════════════════════════════════════════════════════════════════
	static function testSandbox() {
		sec("Sandbox mode");
		var i = new Interpreter();
		i.enableSandbox();
		ok(i.vm.maxInstructions == 500000, "maxInstructions = 500k");
		ok(i.vm.maxCallDepth == 256,       "maxCallDepth = 256");
		ok(i.vm.sandboxed == true,         "sandboxed = true");
	
		ok(false, "sandbox blocks Sys");
		// throws(() -> i.runDynamic('Sys.exit(3)'), "sandbox blocks Sys"); /
	}

	// ══════════════════════════════════════════════════════════════════════
	// 25. USING / EXTENSION METHODS
	// ══════════════════════════════════════════════════════════════════════
	static function testUsing() {
		sec("using — extension methods");
		var i = new Interpreter();
		ok(i.runDynamic('class M{func double(n){return n*2}}\nusing M\n5.double()') == 10,"number.double()");
		ok(i.runDynamic('class M{func naz(n){if(n==0){return "no"}\nreturn n}}\nusing M\n0.naz()') == "no","naz(0)");
		ok(i.runDynamic('class M{func naz(n){if(n==0){return "no"}\nreturn n}}\nusing M\n42.naz()') == 42,"naz(42)");
		ok(i.runDynamic('class S{func shout(s){return s.upper()+"!!!"}}\nusing S\n"hello".shout()') == "HELLO!!!","string shout()");
		ok(i.runDynamic('class S{func wrap(s,ch){return ch+s+ch}}\nusing S\n"world".wrap("*")') == "*world*","wrap()");
		ok(i.runDynamic('
			class N{func squared(n){return n*n}}
			class E{func exclaim(s){return s+"!"}}
			using N\nusing E
			var a=4.squared()\nvar b="nice".exclaim()
			a+b.length
		') == 21, "multiple using classes");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 26. INT / FLOAT SUBTYPES + CONVERSIONS
	// ══════════════════════════════════════════════════════════════════════
	static function testIntFloat() {
		sec("Int / Float subtypes");
		var i = new Interpreter();
		ok(i.runDynamic('type(42)') == "Number",   "42 is Number");
		ok(i.runDynamic('type(3.14)') == "Number", "3.14 is Number");
		ok(i.runDynamic('Int_from(7.0)') == 7,     "Int_from(7.0)=7");
		throws(() -> i.runDynamic('Int_from(3.5)'), "Int_from(3.5) throws");
		ok(i.runDynamic('Float_from(5)') == 5,     "Float_from(5)=5");
		approx(i.runDynamic('Float_from(2.718)'), 2.718, "Float_from(2.718)");
	}

	static function testConversions() {
		sec("fromNumber / fromInt / fromFloat");
		var i = new Interpreter();
		ok(i.runDynamic('fromNumber(42)') == 42,       "fromNumber(42)");
		ok(i.runDynamic('fromNumber(true)') == 1,      "fromNumber(true)=1");
		ok(i.runDynamic('fromNumber(false)') == 0,     "fromNumber(false)=0");
		approx(i.runDynamic('fromNumber("3.14")'), 3.14,'fromNumber("3.14")');
		ok(i.runDynamic('fromInt(10)') == 10,          "fromInt(10)");
		ok(i.runDynamic('fromInt("7")') == 7,          'fromInt("7")');
		throws(() -> i.runDynamic('fromInt(2.5)'),     "fromInt(2.5) throws");
		ok(i.runDynamic('fromFloat(5)') == 5,          "fromFloat(5)");
		approx(i.runDynamic('fromFloat("1.5")'), 1.5,  'fromFloat("1.5")');
	}

	// ══════════════════════════════════════════════════════════════════════
	// 27–28. BRIDGES
	// ══════════════════════════════════════════════════════════════════════
	static function testNxStd() {
		sec("NxStd bridge");
		var i = new Interpreter();
		NxStd.registerAll(i.vm);
		ok(i.runDynamic('parseInt("42")') == 42,       'parseInt("42")');
		approx(i.runDynamic('parseFloat("3.14")'), 3.14,'parseFloat("3.14")');
		ok(i.runDynamic('isNaN(0.0/0.0)') == true,     "isNaN(0/0)");
		ok(i.runDynamic('isNaN(NAN)') == true,          "isNaN(NAN)");
		ok(i.runDynamic('isNaN(42)') == false,          "isNaN(42)=false");
		ok(i.runDynamic('isFinite(42)') == true,        "isFinite(42)");
		ok(i.runDynamic('isFinite(INF)') == false,      "isFinite(INF)=false");
		ok(i.runDynamic('jsonStringify(42)') == "42",   "jsonStringify(42)");
		ok(i.runDynamic('var v=jsonParse("[1,2,3]")\nv.length') == 3,"jsonParse array");
	}

	static function testNxDate() {
		sec("NxDate bridge");
		var i = new Interpreter();
		NxDate.registerAll(i.vm);
		ok(i.runDynamic('timerStamp()>0') == true, "timerStamp() > 0");
		ok(i.runDynamic('var d=dateNow()\ntype(d)') == "Date", "dateNow() is Date");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 29. SCOPE PERFORMANCE
	// ══════════════════════════════════════════════════════════════════════
	static function testScopePerfAndCorrectness() {
		sec("ENTER_SCOPE only on blocks with let");
		var i = new Interpreter();
		var t0 = haxe.Timer.stamp();
		i.runDynamic('var i=0\nvar s=0\nwhile(i<10000){s=s+i\ni=i+1}\ns');
		var elapsed = haxe.Timer.stamp() - t0;
		ok(elapsed < 5.0, 'while 10k iters < 5s (${elapsed}s)');
		ok(i.runDynamic('var r=0\n{let inner=100\nr=inner+1}\nr') == 101, "block with let scoped");
		ok(i.runDynamic('var x=1\nif(true){var y=2\nx=x+y}\nx') == 3,    "if block no overhead");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 30. ENUMS
	// ══════════════════════════════════════════════════════════════════════
	static function testEnums() {
		sec("Enums");
		var i = new Interpreter();
		ok(i.runDynamic('enum Color{Red,Green,Blue}\nColor["Red"]') == "Color.Red","variant access");
		ok(i.runDynamic('enum D{N,S}\nvar d=D["N"]\nd.variant') == "N",            "enum.variant");
		ok(i.runDynamic('enum D{N,S}\nvar d=D["N"]\nd.enum') == "D",               "enum.enum");
		ok(i.runDynamic('enum R{Ok(msg),Err(code)}\nvar ok=R["Ok"]("hi")\nok.variant') == "Ok","payload variant");
		ok(i.runDynamic('enum R{Ok(msg),Err(code)}\nvar ok=R["Ok"]("hi")\nok.values[0]') == "hi","payload value");
		ok(i.runDynamic('
			enum Color{Red,Green,Blue}
			var c=Color["Green"]
			match c{case Red=>"r"\ncase Green=>"g"\ncase Blue=>"b"}
		') == "g", "match enum variant");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 31. IS OPERATOR
	// ══════════════════════════════════════════════════════════════════════
	static function testIsOperator() {
		sec("is operator");
		var i = new Interpreter();
		ok(i.runDynamic('42 is Number') == true,       "42 is Number");
		ok(i.runDynamic('"hi" is String') == true,     '"hi" is String');
		ok(i.runDynamic('42 is String') == false,      "42 is String=false");
		ok(i.runDynamic('true is Bool') == true,       "true is Bool");
		ok(i.runDynamic('[1,2,3] is Array') == true,   "[1,2,3] is Array");
		ok(i.runDynamic('null is Null') == true,       "null is Null");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 32. BRACELESS CONTROL FLOW
	// ══════════════════════════════════════════════════════════════════════
	static function testBracelessSyntax() {
		sec("Braceless control flow");
		var i = new Interpreter();
		ok(i.runDynamic('var x=5\nif(x>3) x=99\nx') == 99,           "braceless if");
		ok(i.runDynamic('var x=0\nif(x>10) x=1\nelse x=2\nx') == 2,  "braceless if/else");
		ok(i.runDynamic('var i=0\nwhile(i<3) i++\ni') == 3,            "braceless while");
		ok(i.runDynamic('var s=0\nfor(x in [1,2,3]) s=s+x\ns') == 6,  "braceless for-in");
	}

	// ══════════════════════════════════════════════════════════════════════
	// 33. ABSTRACT TYPES
	// ══════════════════════════════════════════════════════════════════════
	static function testAbstracts() {
		sec("Abstract types");
		var i = new Interpreter();
		approx(i.runDynamic('
			abstract Meters(Float){
				func new(v){this.value=v}
				func toKm(){return this.value*0.001}
			}
			var m=new Meters(1000)\nm.toKm()
		'), 1.0, "abstract Meters.toKm()");

		ok(i.runDynamic('
			abstract Email(String){
				func new(s){this.raw=s}
				func domain(){return this.raw.split("@").last()}
			}
			var e=new Email("user@example.com")\ne.domain()
		') == "example.com", "abstract Email.domain()");
	}
}

