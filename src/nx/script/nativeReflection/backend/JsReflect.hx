package nx.script.nativeReflection.backend;
/**
 * JavaScript reflection helpers for NxScript.
 *
 * JS objects are plain property bags — bracket syntax `obj[field]` is the
 * fastest possible field access, far cheaper than Haxe's Reflect wrappers
 * which add existence checks, prototype traversal guards, and boxing overhead.
 *
 * Method calls use `fn.apply(obj, args)` to keep the correct `this` binding
 * without creating an intermediate bound-function object.
 *
 * `typeof v === "function"` is the canonical JS function check — zero overhead.
 */
#if js
class JsReflect {
    /**
     * Direct bracket property read: obj[field]
     */
    public static inline function get(obj:Dynamic, field:String):Dynamic {
        return (cast obj : Dynamic)[field];
    }

    /**
     * Direct bracket property write: obj[field] = value
     */
    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void {
        (cast obj : Dynamic)[field] = value;
    }

    /**
     * Call an already-fetched function with apply to preserve `this`.
     * fn must be the result of a prior get() call on obj.
     */
    public static inline function callMethod(obj:Dynamic, fn:Dynamic, args:Array<Dynamic>):Dynamic {
        return (cast fn : Dynamic).apply(obj, args);
    }

    /**
     * typeof check — the fastest function test in JS.
     */
    public static inline function isFunction(v:Dynamic):Bool {
        return v != null && js.Syntax.typeof(v) == "function";
    }
}
#else
// Stub for non-JS targets.
class JsReflect {
    public static inline function get(obj:Dynamic, field:String):Dynamic return Reflect.field(obj, field);
    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void Reflect.setField(obj, field, value);
    public static inline function callMethod(obj:Dynamic, fn:Dynamic, args:Array<Dynamic>):Dynamic return Reflect.callMethod(obj, fn, args);
    public static inline function isFunction(v:Dynamic):Bool return Reflect.isFunction(v);
}
#end
