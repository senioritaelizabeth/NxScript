import sys.FileSystem;
import sys.io.File;
import Date;

using StringTools;
class MakeSnapshot {
    static function main() {
        var srcDir = "src";
        var testDir = "test";
        var snapshotBaseDir = "snapshot";
        var date = Date.now().toString().replace(" ", "_").replace(":", "-");
        var snapshotDir = snapshotBaseDir + "/" + date;
        if (!FileSystem.exists(snapshotDir)) FileSystem.createDirectory(snapshotDir);
        FileSystemNative.copyDirectory(srcDir, snapshotDir + "/src");
        FileSystemNative.copyDirectory(testDir, snapshotDir + "/test");
        trace("Snapshot created at " + snapshotDir);
    }
}

// Helper for recursive copy
class FileSystemNative {
    public static function copyDirectory(src:String, dest:String) {
        if (!FileSystem.exists(dest)) FileSystem.createDirectory(dest);
        for (entry in FileSystem.readDirectory(src)) {
            var srcPath = src + "/" + entry;
            var destPath = dest + "/" + entry;
            if (FileSystem.isDirectory(srcPath)) {
                copyDirectory(srcPath, destPath);
            } else {
                File.copy(srcPath, destPath);
            }
        }
    }
}
