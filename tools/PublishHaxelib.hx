package tools;

import sys.io.File;

class PublishHaxelib {
    public static function main() {
        var version = getVersion();
        trace("Publishing NxScript version " + version + " to haxelib...");
        // zip all (excluding .github, node_modules, bin, build, dist, test, tools, and other non-essential , .git too)
        var exclude = [
            ".github",
            "node_modules",
            "bin",
            "build",
            "dist",
            "tools",
            ".git",
            ".vscode"
        ];
        var files = sys.FileSystem.readDirectory(".");
        // var includeFiles = [ for (f in files) if (!exclude.exists(f))];
        var includeFiles = [];
        for (f in files) {
            var skip = false;
            for (e in exclude) {
                if (StringTools.startsWith(f, e)) {
                    skip = true;
                    break;
                }
            }
            if (!skip) includeFiles.push(f);
        }
        var cmd = "zip -r NxScript-" + version + ".zip " + includeFiles.join(" ");  
        trace("Running command: " + cmd);
        var result = Sys.command("bash", ["-c", cmd]);
        if (result != 0) {
            trace("Failed to create zip file with exit code " + result);
            Sys.exit(result);
        }
    }

    static function getVersion():String {
        var json = File.getContent("haxelib.json");
        var data = haxe.Json.parse(json);
        return data.version;
    }
}