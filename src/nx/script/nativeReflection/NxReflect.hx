package nx.script.nativeReflection;
#if cpp
import nx.script.nativeReflection.backend.CppReflect as B;
#elseif js
import nx.script.nativeReflection.backend.JsReflect as B;
#elseif hl
import nx.script.nativeReflection.backend.HlReflect as B;
#else
import nx.script.nativeReflection.backend.DefaultReflect as B;
#end

class NxReflect {
    public static inline function get(obj:Dynamic, field:String):Dynamic
        return B.get(obj, field);
    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void
        B.set(obj, field, value);
    public static inline function callMethod(obj:Dynamic, fn:Dynamic, args:Array<Dynamic>):Dynamic
        return #if (cpp || js || hl) B.callMethod(fn, args) #else B.callMethod(obj, fn, args) #end;
    public static inline function isFunction(v:Dynamic):Bool
        return B.isFunction(v);
    public static inline function probe(obj:Dynamic, field:String):Dynamic
        return B.get(obj, field);
}