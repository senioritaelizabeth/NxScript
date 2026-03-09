package;

import flixel.FlxGame;
import openfl.display.Sprite;
import openfl.display.FPS;

class Main extends Sprite {
	public function new() {
		super();
		addChild(new FlxGame(0, 0, PlayState, 1000, 1000));

		// aChild(new FPS(10, 10, 0xFFFFFF));
		addChild(new FPS(10, 10, 0xFFFFFF));
	}
}
