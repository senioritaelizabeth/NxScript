import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;
import Date;

class MakeDocs {
    static function main() {
        // Find haxelib root
        var haxelibRoot = Sys.command("haxelib", ["config"]).trim();
        // Find latest dox dir
        var doxDir = findLatestDoxDir(haxelibRoot);
        if (doxDir != null) {
            var pkgJson = Path.join([doxDir, "package.json"]);
            if (!FileSystem.exists(pkgJson)) {
                File.saveContent(pkgJson, '{"type":"commonjs"}');
                trace("Created " + pkgJson + " (CommonJS override)");
            }
        } else {
            trace("Could not find dox installation under " + haxelibRoot);
        }
        // Run haxe doc.hxml
        Sys.command("haxe", ["doc.hxml"]);
        // Run dox
        Sys.command("haxelib", ["run", "dox", "-i", "doc.xml", "-o", "docs/", "--title", "NxScript", "--include", "nz"]);
    }

    static function findLatestDoxDir(haxelibRoot:String):String {
        var doxBase = Path.join([haxelibRoot, "dox"]);
        if (!FileSystem.exists(doxBase)) return null;
        var dirs = FileSystem.readDirectory(doxBase);
        var latest = null;
        for (d in dirs) {
            var full = Path.join([doxBase, d]);
            if (FileSystem.isDirectory(full)) latest = full;
        }
        return latest;
    }
}
