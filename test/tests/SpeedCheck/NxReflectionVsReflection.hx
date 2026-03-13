package;

import nx.script.nativeReflection.NxReflect;
import haxe.Timer;
@:structInit
class Obj {
    public var foo:Int;
    // public var bar:Dynamic;
    public function bar(x:Int):Int return x + 1;
}
class NxReflectionVsReflection {
    static public function main() {
        var ITER = 1000;
        var obj:Obj = {
            foo: 123,
        };
        var t0:Float;
        var t1:Float;
        var dummy:Int = 0;
// Simula lo que debería hacer la VM: cachear el fn, solo llamar
var fn = NxReflect.get(obj, "bar");
var rfn = Reflect.field(obj, "bar");

t0 = Timer.stamp();
for (i in 0...ITER) dummy += NxReflect.callMethod( fn, [i]);
t1 = Timer.stamp();
trace('NxReflect.callMethod (cached fn): ' + ((t1-t0)*1000) + ' ms');

t0 = Timer.stamp();
for (i in 0...ITER) dummy += Reflect.callMethod(obj, rfn, [i]);
t1 = Timer.stamp();
trace('Reflect.callMethod (cached fn): ' + ((t1-t0)*1000) + ' ms');
    }
}