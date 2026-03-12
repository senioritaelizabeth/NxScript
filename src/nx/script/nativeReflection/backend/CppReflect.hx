package nx.script.nativeReflection.backend;

/**
 * C++ (hxcpp) reflection helpers for NxScript.
 *
 * These map directly to hxcpp internal object operations, bypassing the
 * Haxe Reflect wrappers and their overhead.
 *
 * Compiled ONLY on `-cpp` targets. On other targets this class is empty
 * and NxReflect falls through to the appropriate backend.
 *
 * hxcpp internals used:
 *   __Field(name, acc)     — read field; acc=hx::paccDynamic skips property getters
 *   __SetField(name, v, acc) — write field
 *   fn->__Run(args)        — call a Dynamic function value with an Array<Dynamic>
 *   cpp::Function_obj::IsFunction(v) — fast callable check
 *
 * Reference: hxcpp/include/hx/Object.h
 */
#if cpp
class CppReflect {
    /**
     * Read a field using hxcpp __Field with paccDynamic.
     * Equivalent to obj.fieldName but fully dynamic and bypasses Haxe boxing.
     */
    public static inline function get(obj:Dynamic, field:String):Dynamic {
        return untyped __cpp__("({0})->__Field(({1}), hx::paccDynamic)", obj, field);
    }

    /**
     * Write a field using hxcpp __SetField with paccDynamic.
     */
    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void {
        untyped __cpp__("({0})->__SetField(({1}), ({2}), hx::paccDynamic)", obj, field, value);
    }

    /**
     * Call an already-fetched function value using __Run.
     * fn should be the result of a prior get() call.
     * args is a Haxe Array<Dynamic> — hxcpp maps this directly.
     */
    public static inline function callMethod(fn:Dynamic, args:Array<Dynamic>):Dynamic {
       return untyped __cpp__("({0})->__Run({1})", fn, args);
}   

    /**
     * Fast callable check using hxcpp's internal function type check.
     */
public static inline function isFunction(v:Dynamic):Bool {
    return v != null && untyped __cpp__("{0}.mPtr && {0}.mPtr->__GetType() == 2", v);
}


}
#else
// Stub so code that imports CppReflect directly still compiles on other targets.
class CppReflect {
    public static inline function get(obj:Dynamic, field:String):Dynamic return Reflect.field(obj, field);
    public static inline function set(obj:Dynamic, field:String, value:Dynamic):Void Reflect.setField(obj, field, value);
    public static inline function callMethod(fn:Dynamic, args:Array<Dynamic>):Dynamic return Reflect.callMethod(null, fn, args);
    public static inline function isFunction(v:Dynamic):Bool return Reflect.isFunction(v);
}
#end
