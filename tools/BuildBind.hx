package tools;

import sys.FileSystem;
using StringTools;
class BuildBind {
    static final OS_PATHS = [
        "Windows" => "bin/windows/",
        "Linux" => "bin/linux/",
        "Mac" => "bin/mac/"
    ];
    
    static final OS_EXTENSIONS = [
        "Windows" => ".dll",
        "Linux" => ".dso",
        "Mac" => ".dylib"
    ];

    public static function main() {
        trace("Building NxBinding...");
        
        var osPath = getOsPath();
        var result = Sys.command("haxe", ["build.hxml", "-cpp", osPath]);
        
        if (result != 0) {
            trace("Build failed with exit code " + result);
            Sys.exit(result);
        }
        
        trace("Build successful!");
        
        var outputFile = osPath + "NxBinding" + getExtension();
        var libName = getArg("name", "libNxBinding");
        var outDir = getArg("out", "binaries/");
        var targetFile = outDir + libName + getExtension();
        
        if (!FileSystem.exists(outDir)) {
            FileSystem.createDirectory(outDir);
        }
        
        if (FileSystem.exists(outputFile)) {
            FileSystem.rename(outputFile, targetFile);
            trace("Renamed " + outputFile + " to " + targetFile);
        } else {
            trace("Expected output file not found: " + outputFile);
            Sys.exit(1);
        }
    }

    static function getArg(name:String, defaultValue:String = ""):String {
        var args = Sys.args();
        for (i in 0...args.length) {
            if (args[i] == "--" + name && i + 1 < args.length) {
                return args[i + 1];
            } else if (args[i].startsWith("--" + name + "=")) {
                return args[i].substr(name.length + 3);
            }
        }
        return defaultValue;
    }

    static function getOsPath():String {
        var os = Sys.systemName();
        return OS_PATHS.get(os) ?? throw "Unsupported OS: " + os;
    }

    static function getExtension():String {
        var os = Sys.systemName();
        return OS_EXTENSIONS.get(os) ?? throw "Unsupported OS: " + os;
    }
}
