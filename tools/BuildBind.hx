package tools;

import sys.FileSystem;

class BuildBind {
    public static function main() {
        trace("Building NxBinding...");
        var result = Sys.command("haxe", ["build.hxml", "-cpp", get_os_path( )]);
        if (result == 0) {
            trace("Build successful!");
        } else {
            trace("Build failed with exit code " + result);
            trace("Error output: " + Sys.getEnv("HAXE_ERROR"));
            Sys.exit(result);
        }
        // rename output file to NxBinding.dll or .so to libNxBinding for easier loading
        var outputDir = get_os_path();
        var outputFile = switch (Sys.systemName()) {
            case "Windows": outputDir + "NxBinding.dll"; // Windows produces .exe for DLLs
            case "Linux":   outputDir + "NxBinding.dso";
            case "Mac":     outputDir + "NxBinding.dylib";
            default:       throw "Unsupported OS: " + Sys.systemName();
        };
        var read_name = get_arg("name", "libNxBinding");
        outputDir += read_name;
        var targetFile = switch (Sys.systemName()) {
            case "Windows": outputDir + ".dll";
            case "Linux":   outputDir + ".dso";
            case "Mac":     outputDir + ".dylib";
            default:       throw "Unsupported OS: " + Sys.systemName();
        };
        if (sys.FileSystem.exists(outputFile)) {
            sys.FileSystem.rename(outputFile, targetFile);
            trace("Renamed " + outputFile + " to " + targetFile);
        } else {
            Sys.exit(67); // SIX_SEVEN = "im autistic"
            trace("Expected output file not found: " + outputFile);
        }

        var read_platform = get_arg("platform", "unknown");
        var read_outdir = get_arg("outdir", "unknown");
        trace("Read platform argument: " + read_platform);
        trace("Read outdir argument: " + read_outdir);
        // zip targetFile to outdir for uploading as artifact
        if (!FileSystem.exists(read_outdir)) {
            FileSystem.createDirectory(read_outdir);
        }
        var zipPath = read_outdir + "/" + read_platform + ".zip";
        // var zipResult = Sys.command("zip", ["-j", zipPath, targetFile]);
        // just zip the .sdo/.dll/.dylib file without the directory structure
        var zipResult = Sys.command("zip", ["-j", zipPath, targetFile]);
        if (zipResult == 0) {
            trace("Created zip archive: " + zipPath);
        } else {
            trace("Failed to create zip archive with exit code " + zipResult);
            trace("Error output: " + Sys.getEnv("HAXE_ERROR"));
            Sys.exit(zipResult);
        }

    }
  static function get_arg(name:String, deft:String = ""):String {
        // for (arg in Sys.args()) {
        //     if (StringTools.startsWith(arg, "--" + name )) {
                
        //     }
        // }
        var i = 0;
        while (i < Sys.args().length) {
            var arg = Sys.args()[i];
            if (arg == "--" + name && i + 1 < Sys.args().length) {
                return Sys.args()[i + 1];
            } else if (StringTools.startsWith(arg, "--" + name + "=")) {
                return arg.substr(name.length + 3); // length of "--" + name + "="
            }
            i++;
        }
        return deft;
    }
    public static function get_os_path() {
        return switch (Sys.systemName()) {
            case "Windows": "bin/windows/";
            case "Linux":   "bin/linux/";
            case "Mac":     "bin/mac/";
            default:       throw "Unsupported OS: " + Sys.systemName();
        };
    }
}