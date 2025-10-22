package nz.script;

/**
 * Base interface for all script class instances.
 * Extend this interface when defining type-safe interfaces for your script classes.
 * 
 * **Auto-Synchronization:**
 * Fields are automatically synchronized when you call methods on the instance.
 * You rarely need to call `__syncToScript__()` manually.
 * 
 * **Important for Interpreter Mode:**
 * When using `--interp`, you must use `Dynamic` type for the variable that performs
 * operations. Only use the typed interface for temporary autocomplete assistance.
 * 
 * Example (Interpreter Mode):
 * ```haxe
 * interface MyCat extends IScriptInstance {
 *     var meow:Bool;
 *     function speak():String;
 * }
 * 
 * // Use Dynamic for operations
 * var cat:Dynamic = interp.createInstance("MyCat");
 * cat.meow = false;
 * cat.speak(); // Auto-syncs fields before calling!
 * 
 * // Temporarily assign to typed variable for autocomplete
 * var typedCat:MyCat = cat;
 * trace(typedCat.meow); // IDE autocomplete works on 'meow'
 * ```
 * 
 * Example (Compiled Mode - Neko, HL, JS, C++):
 * ```haxe
 * // In compiled mode, you can use typed variables directly
 * var cat:MyCat = interp.createInstance("MyCat");
 * cat.meow = false;
 * cat.speak(); // Auto-syncs!
 * ```
 */
interface IScriptInstance {
	/**
	 * Manually synchronizes field changes from the Haxe proxy back to the script instance.
	 * Usually not needed - fields auto-sync when you call methods.
	 * Only call this if you need to force sync before accessing fields from within script code.
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
