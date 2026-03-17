package tools;

class BuildJS {
    // similar a BuildBind, pero genera un JS output para usarlo en general en cualquier lado
    public static function main():Void {
        var result = Sys.command("haxe", ["build.hxml", "--js", "bin/nxscript.js"]);
    }
}