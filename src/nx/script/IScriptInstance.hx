package nx.script;

/**
 * Typed interface for script class instances.
 * Extend this when you want autocomplete on your script objects without losing your mind.
 *
 * **How syncing works:**
 * Fields are synced from Haxe → script automatically when you call any method.
 * You almost never need to call '__syncToScript__()' yourself. Almost.
 *
 * **Interpreter mode gotcha:**
 * On '--interp', you MUST use 'Dynamic' for the variable that performs operations.
 * Use the typed interface only for temporary autocomplete help.
 *
 * Example (interpreter mode — Neko, neko, neko):
 * '''haxe
 * interface MyCat extends IScriptInstance {
 *     var meow:Bool;
 *     function speak():String;
 * }
 *
 * var cat:Dynamic = interp.createInstance("MyCat");
 * cat.meow = false;
 * cat.speak(); // auto-syncs fields before calling
 *
 * var typedCat:MyCat = cat; // only for autocomplete, don't store this long-term on interp
 * trace(typedCat.meow);
 * '''
 *
 * Example (compiled targets — HL, C++, JS, etc.):
 * '''haxe
 * var cat:MyCat = interp.createInstance("MyCat");
 * cat.meow = false;
 * cat.speak(); // just works
 * '''
 */
interface IScriptInstance {
	/**
	 * Force-syncs Haxe-side field changes back into the script instance.
	 * You don't need this unless you modified a field from Haxe and need the script
	 * to see the new value BEFORE calling any method. Which is an unusual situation.
	 */
	public function __syncToScript__():Void;

	/**
	 * Sets a field value on the script instance.
	 * @param name The field name
	 * @param value The value to set
	 */
	public function __setField__(name:String, value:Dynamic):Void;

	/**
	 * Gets a field value from the script instance.
	 * @param name The field name
	 * @return The field value
	 */
	public function __getField__(name:String):Dynamic;
}
