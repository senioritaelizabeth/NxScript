package nx.script.nativeReflection.backend;
/**
 * HashLink (HL) reflection helpers for NxScript.
 *
 * HL represents all dynamic field access through field IDs (hashed strings).
 * The runtime functions hl_dyn_get / hl_dyn_set / hl_dyn_call skip the
 * Haxe-level Reflect wrappers and operate directly on HL objects.
 *
 * How HL dynamic fields work:
 *   - Every field name is hashed at compile time to an integer ID.
 *   - hl_dyn_get(obj, field_id)    — reads a field by hash
 *   - hl_dyn_set(obj, field_id, v) — writes a field by hash
 *   - hl_dyn_call(fn, args, n)     — calls a hl closure/method with n args
 *
 * We use `@:hlNative` externs to bind these directly.
 * On non-HL targets the class falls back to standard Reflect.
 */
#if hl
@:hlNative("std")
class HlReflect {
    /**
     * Read an object field using HL dynamic get.
     * Equivalent to Reflect.field but avoids the Haxe wrapper overhead.
     */
    @:hlNative("dyn_get_field")
    static function _dynGet(obj:Dynamic, field:String):Dynamic return null;

    /**
     * Write an object field using HL dynamic set.
     */
    @:hlNative("dyn_set_field")
    static function _dynSet(obj:Dynamic, field:String, value:Dynamic):Void {}

    /**
     * Call a HL dynamic function.
     */
    @:hlNative("call_method")
    static function _callMethod(fn:Dynamic, args:hl.NativeArray<Dynamic>):Dynamic return null;

    public static inline function get(obj:Dynamic, field:String):Dynamic {
        return _dynGet(obj, field);
    }

    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void {
        _dynSet(obj, field, value);
    }

    public static inline function callMethod(obj:Dynamic, fn:Dynamic, args:Array<Dynamic>):Dynamic {
        var na = hl.NativeArray.alloc(args.length);
        for (i in 0...args.length) na[i] = args[i];
        return _callMethod(fn, na);
    }

    public static inline function isFunction(v:Dynamic):Bool {
        return Reflect.isFunction(v);
    }
}
#else
// Stub for non-HL targets.
class HlReflect {
    public static inline function get(obj:Dynamic, field:String):Dynamic return Reflect.field(obj, field);
    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void Reflect.setField(obj, field, value);
    public static inline function callMethod(obj:Dynamic, fn:Dynamic, args:Array<Dynamic>):Dynamic return Reflect.callMethod(obj, fn, args);
    public static inline function isFunction(v:Dynamic):Bool return Reflect.isFunction(v);
}
#end
