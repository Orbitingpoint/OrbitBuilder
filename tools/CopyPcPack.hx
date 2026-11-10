import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class CopyPcPack {
	static var FILES:Array<Array<String>> = [
		["certificate/cert.p12", "cert.p12"],
		["icons/icon-48.png", "icons/icon-48.png"],
		["icons/icon-192.png", "icons/icon-192.png"],
		["icons/README.md", "icons/README.md"],
		["xml/application-win.xml", "application-win.xml"],
	];

	public static function main():Void {
		var args = Sys.args();
		var outDir = args.length > 0 && args[0].length > 0 ? args[0] : "bin";
		var root = "OrbitExtraResources";
		var pcPack = Path.join([outDir, "pc-pack"]);
		for (f in FILES) {
			var src = Path.join([root, f[0]]);
			var dst = Path.join([pcPack, f[1]]);
			if (!FileSystem.exists(src)) {
				Sys.println('copy-pc-pack: missing $src');
				Sys.exit(1);
			}
			mkdirs(Path.directory(dst));
			File.saveBytes(dst, File.getBytes(src));
		}
		Sys.println('copy-pc-pack: ${FILES.length} files -> $pcPack');
	}

	static function mkdirs(dir:String):Void {
		if (dir == null || dir.length == 0 || FileSystem.exists(dir)) return;
		var parent = Path.directory(dir);
		if (parent != null && parent.length > 0 && parent != dir) mkdirs(parent);
		FileSystem.createDirectory(dir);
	}
}
