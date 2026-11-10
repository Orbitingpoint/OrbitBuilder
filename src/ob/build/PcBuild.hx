package ob.build;

import sys.FileSystem;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Uncompress;

/** Windows (AIR bundle) build. */
class PcBuild {
	public static function checkPrereqs(s:ObSettings, log:String->Void):Void {
		var adt = Util.join([s.airSdk, "bin", "adt.bat"]);
		if (!FileSystem.exists(adt)) throw 'AIR SDK adt.bat not found: $adt (Tools > Tool paths and build settings).';
		var anes = FileSystem.exists(s.aneDir) && FileSystem.isDirectory(s.aneDir)
			? Util.filesWithExt(s.aneDir, ".ane")
			: [];
		if (anes.length < 15) throw 'Need 15 Windows .ane files in AneDir, found ${anes.length} in ${s.aneDir} (Tools > Tool paths and build settings).';
		if (!FileSystem.exists(s.certP12)) throw 'Signing cert not found: ${s.certP12} (Tools > Tool paths and build settings).';
		if (!FileSystem.exists(s.appDesc)) throw 'App descriptor not found: ${s.appDesc} (Tools > Tool paths and build settings).';
		log('Prereqs OK: adt + ${anes.length} ANEs + cert + descriptor.');
	}

	static function prepareExtDir(aneDir:String, appDesc:String, job:String, log:String->Void):String {
		// Copy only the ANEs listed in the app descriptor
		var ids = new Map<String, Bool>();
		var re = new EReg("<extensionID>([^<]+)</extensionID>", "");
		var xml = Util.readText(appDesc);
		while (re.match(xml)) {
			ids.set(StringTools.trim(re.matched(1)), true);
			xml = re.matchedRight();
		}
		var ext = Util.join([job, "extdir"]);
		Util.mkdirs(ext);
		var n = 0;
		for (id in ids.keys()) {
			var src = Util.join([aneDir, id + ".ane"]);
			if (!FileSystem.exists(src)) throw 'Missing ANE for $id (expected $src).';
			Util.copyFile(src, Util.join([ext, id + ".ane"]));
			n++;
		}
		log('Staged $n descriptor-listed ANEs.');
		return ext;
	}

	/**
	 * Builds from an extracted SWF or an Android APK
	 */
	public static function run(input:String, mods:Array<Mod>, target:PatchTarget,
			s:ObSettings, log:String->Void):String {
		checkPrereqs(s, log);
		var job = Util.join([s.outDir, "pc-" + Util.stamp()]);
		var stage = Util.join([job, "app"]);
		Util.mkdirs(stage);
		var files = GameAssets.load(input, target, log);
		var swf = files.swf;
		if (!files.fromApk) log('Source SWF: ${swf.length} bytes, sha256 ${Patcher.sha256(swf).substr(0, 16)}...');
		SwfCheck.check(swf, target, log);
		if (s.deobfuscate) swf = Deobfuscator.run(swf, target, Util.join([job, "deobf-names.tsv"]), log);
		else log("Deobfuscation disabled in settings; identifiers stay obfuscated.");
		swf = CodePatcher.apply(swf, mods, s, Util.join([job, "codework"]), log);
		Util.writeBytes(Util.join([stage, "worldflipper_android_release.swf"]), swf);
		for (name in GameAssets.COMPANIONS) Util.writeBytes(Util.join([stage, name]), files.assets.get(name));
		var desc = Util.join([stage, "application-win.xml"]);
		Util.copyFile(s.appDesc, desc);
		var liveResize = false;
		for (m in mods) {
			if (ModConfig.isEnabled(m) && (m.platform == "all" || m.platform == "pc")
				&& StringTools.startsWith(m.id.toLowerCase(), "live-resize")) liveResize = true;
		}
		Descriptor.setWindowSize(desc, s, log, liveResize);
		if (liveResize) log("Live resize/maximize enabled (live-resize mod).");
		if (!FileSystem.exists(s.iconsDir)) throw 'Icons folder not found: ${s.iconsDir}';
		Util.copyDir(s.iconsDir, Util.join([stage, "icons"]));
		var extdir = prepareExtDir(s.aneDir, Util.join([stage, "application-win.xml"]), job, log);
		var adt = Util.join([s.airSdk, "bin", "adt.bat"]);
		var bundle = Util.join([job, "WorldFlipperPC"]);
		Proc.run(adt, [
			"-package", "-storetype", "pkcs12", "-keystore", s.certP12, "-storepass", s.certPass,
			"-target", "bundle", bundle, Util.join([stage, "application-win.xml"]),
			"-C", stage, "worldflipper_android_release.swf", "icons", "bundle.zip", "bundle.zip.sha1",
			"firebase-messaging.properties", "kakao_game_sdk_configuration.xml",
			"-extdir", extdir
		], job, log);
		var exe = Util.join([bundle, "WorldFlipper.exe"]);
		if (!FileSystem.exists(exe)) throw "ADT finished but WorldFlipper.exe is missing.";
		writeShimServer(bundle, mods, log);
		log('WINDOWS BUILD OK: $exe');
		return exe;
	}

	/** The PC ANE shim that stands in for the Kakao SDK reads the private server
	 * URL from wfshim_server.txt next to the game exe. Reuse whatever the user
	 * set as a mod's serverUrl so the URL lives in one place only. */
	static function writeShimServer(bundleDir:String, mods:Array<Mod>, log:String->Void):Void {
		for (m in mods) {
			if (!ModConfig.isEnabled(m)) continue;
			for (spec in m.config) {
				if (!Util.eqi(spec.key, "serverUrl")) continue;
				var url = StringTools.trim(ModConfig.get(m.id, spec));
				if (url.length == 0) continue;
				Util.writeText(Util.join([bundleDir, "wfshim_server.txt"]), url + "\r\n");
				log('Kakao SDK shim server URL: $url (wfshim_server.txt)');
				return;
			}
		}
		log("No serverUrl mod config found; the Kakao SDK shim falls back to http://127.0.0.1:8000.");
	}
}




