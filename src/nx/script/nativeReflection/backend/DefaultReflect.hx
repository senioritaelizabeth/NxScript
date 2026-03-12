package nx.script.nativeReflection.backend;

class DefaultReflect {
    public static inline function get(obj:Dynamic, field:String):Dynamic 
        return Reflect.field(obj, field);
    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void 
        Reflect.setField(obj, field, value);
    public static inline function callMethod(obj:Dynamic, fn:Dynamic, args:Array<Dynamic>):Dynamic 
        return Reflect.callMethod(obj, fn, args);
    public static inline function isFunction(v:Dynamic):Bool 
        return Reflect.isFunction(v);
    public static inline function probe(obj:Dynamic, field:String):Dynamic
        return Reflect.field(obj, field);
}