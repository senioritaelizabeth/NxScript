package nx.bridge;

class Reflection {
	public static inline function getField(obj:Dynamic, field:String):Dynamic {
		#if cpp
		return untyped __cpp__("({0})->__Field({1}, hx::paccAlways)", obj, field);
		#else
		var v = Reflect.getProperty(obj, field);
		return v != null ? v : Reflect.field(obj, field);
		#end
	}

	public static inline function setField(obj:Dynamic, field:String, value:Dynamic):Void {
		#if cpp
		untyped __cpp__("({0})->__SetField({1}, {2}, hx::paccAlways)", obj, field, value);
		#else
		Reflect.setProperty(obj, field, value);
		#end
	}

	public static inline function callMethod(obj:Dynamic = null, fn:Dynamic, args:Array<Dynamic>):Dynamic {
		#if cpp
		return switch (args.length) {
			case 0: untyped __cpp__('{0}()', fn);
			case 1: untyped __cpp__('{0}({1})', fn, args[0]);
			case 2: untyped __cpp__('{0}({1},{2})', fn, args[0], args[1]);
			case 3: untyped __cpp__('{0}({1},{2},{3})', fn, args[0], args[1], args[2]);
			default: Reflect.callMethod(obj, fn, args);
		}
		#else
		return Reflect.callMethod(obj, fn, args);
		#end
	}

	public static inline function isFunction(v:Dynamic):Bool {
		#if cpp
		return v != null && untyped __cpp__("{0}.mPtr && {0}.mPtr->__GetType() == 2", v);
		#else
		return Reflect.isFunction(v);
		#end
	}
}
