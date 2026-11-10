package ob.build;

import sys.FileSystem;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Uncompress;

typedef GameFiles = {
	var swf:Bytes;
	var assets:Map<String, Bytes>;
	var fromApk:Bool;
}

/**
 * Loads the game from either an extracted SWF or directly from an Android APK.
 */
class GameAssets {
	public static var COMPANIONS:Array<String> = [
		"bundle.zip",
		"bundle.zip.sha1",
		"firebase-messaging.properties",
		"kakao_game_sdk_configuration.xml"
	];

	public static function load(input:String, target:PatchTarget, log:String->Void):GameFiles {
		var assets = new Map<String, Bytes>();
		if (ZipFile.isZip(input)) {
			log("Extracting game files from APK...");
			var apk = new ZipFile(input);
			var paths = gameAssetPaths(target.swfAssetPath);
			var swf = apk.read(paths.swf);
			log('SWF in APK: ${swf.length} bytes, sha256 ${Patcher.sha256(swf).substr(0, 16)}...');
			for (name in COMPANIONS) assets.set(name, apk.read(paths.prefix + name));
			return {swf: swf, assets: assets, fromApk: true};
		}

		var dir = Path.directory(input);
		if (dir == null || dir.length == 0) dir = ".";
		for (name in COMPANIONS) {
			var p = Util.join([dir, name]);
			if (!sys.FileSystem.exists(p)) throw 'Missing required game asset: $p';
			assets.set(name, Util.readBytes(p));
		}
		return {swf: Util.readBytes(input), assets: assets, fromApk: false};
	}

	public static function readSwf(input:String, target:PatchTarget, log:String->Void):Bytes {
		if (!ZipFile.isZip(input)) return Util.readBytes(input);
		var apk = new ZipFile(input);
		var swf = apk.read(target.swfAssetPath);
		log('SWF in APK: ${swf.length} bytes, sha256 ${Patcher.sha256(swf).substr(0, 16)}...');
		return swf;
	}

	static function gameAssetPaths(swfAssetPath:String):{swf:String, prefix:String} {
		var dir = Path.directory(swfAssetPath);
		return {swf: swfAssetPath, prefix: dir == null || dir.length == 0 ? "" : dir + "/"};
	}
}




