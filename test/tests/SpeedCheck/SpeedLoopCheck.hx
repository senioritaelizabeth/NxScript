package;

import nx.script.Interpreter;

/**
    * Prueba de velocidad de ejecución de un bucle for con 1000000 iteraciones.
    *
    * @author johanna
**/
class FakeFlxSprite {
    public var x:Float = 0;
    public var y:Float = 0;
    public var width:Float = 0;
    public var height:Float = 0;
    public var scale:{x:Float, y:Float} = {x:1, y:1};
    public function new() {}
}
class SpeedLoopCheck {
    public static function main() {
        var code = "for (i in 0...1000000) { }";
        var interpreter = new Interpreter(false);
                var vm = interpreter.vm;
        @:privateAccess  trace('Stack size: ' + vm.stack.length);
        var startTime = Sys.time();
        interpreter.runDynamic(code);
        @:privateAccess  trace('Frames size: ' + vm.frames.length);

        var endTime = Sys.time();
        trace('Tiempo de ejecución: ' + (endTime - startTime) + ' segundos');
        // Diagnóstico: mostrar tamaño de stack y frames

        @:privateAccess trace('Stack size after execution: ' + vm.stack.length);
         @:privateAccess  trace('Frames size after execution: ' + vm.frames.length);

        var interp_2 = new Interpreter(false);
        trace('Going to test 1000 iterations of FlxSprite');
        var myFakeSprites:Array<FakeFlxSprite> = [];
        for (i in 0...1000) {
            var sprite = new FakeFlxSprite();
            myFakeSprites.push(sprite);
        }
        var startTime2 = Sys.time();
        var code2 = "func update() { for (sprite of myFakeSprites) { sprite.x += 1; sprite.y += 1; sprite.scale.x *= 1.01; sprite.scale.y *= 1.01; } }";
        interp_2.globals.set("myFakeSprites", interp_2.vm.haxeToValue(myFakeSprites));


        interp_2.runDynamic(code2);
        interp_2.call0("update");
        var endTime2 = Sys.time();
        trace('Tiempo de ejecución para 1000 sprites: ' + (endTime2 - startTime2) + ' segundos');
        trace('Now in ms: ' + ((endTime2 - startTime2) * 1000) + ' ms');

        @:privateAccess      trace('Stack size after sprite loop: ' + interp_2.vm.stack.length);
         @:privateAccess  trace('Frames size after sprite loop: ' + interp_2.vm.frames.length);
        // @:privateAccess trace('Globals size: ' + vm.globals);
        var single_code = "var sprite = myFakeSprites[0]; sprite.x += 1; sprite.y += 1; sprite.scale.x *= 1.01; sprite.scale.y *= 1.01;";
        var startTime3 = Sys.time();
        interp_2.runDynamic(single_code);
        var endTime3 = Sys.time();
        trace('Tiempo de ejecución para 1 sprite: ' + (endTime3 - startTime3) + ' segundos');
        trace('Now in ms: ' + ((endTime3 - startTime3) * 1000) + ' ms');
         @:privateAccess      trace('Stack size after single sprite: ' + interp_2.vm.stack.length);
         @:privateAccess  trace('Frames size after single sprite: ' + interp_2.vm.frames.length);
    }
}