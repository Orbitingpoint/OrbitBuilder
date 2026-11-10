package ob.core;

import haxe.io.Bytes;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.Json;
import sys.io.Process;
import sys.thread.Lock;
import sys.thread.Thread;

/** Filesystem, path and text helpers shared by the builder. */
class Util {
	public static function baseDir():String {
		return Path.directory(Sys.programPath());
	}

	/** Joins path parts with the native separator. */
	public static function join(parts:Array<String>):String {
		var sep = Sys.systemName() == "Windows" ? "\\" : "/";
		var out = "";
		for (p in parts) {
			if (p == null || p.length == 0) continue;
			var s = p;
			// Only the first part may keep a leading separator.
			while (out.length > 0 && s.length > 0 && (s.charAt(0) == "/" || s.charAt(0) == "\\")) s = s.substr(1);
			if (s.length == 0) continue;
			if (out.length > 0) {
				var last = out.charAt(out.length - 1);
				if (last != "/" && last != "\\") out += sep;
			}
			out += s;
		}
		return out;
	}

	public static function fileName(p:String):String {
		return Path.withoutDirectory(p);
	}

	public static function fileStem(p:String):String {
		var n = fileName(p);
		var i = n.lastIndexOf(".");
		return i > 0 ? n.substr(0, i) : n;
	}

	public static function extOf(name:String):String {
		var i = name.lastIndexOf(".");
		return i < 0 ? "" : name.substr(i);
	}

	public static function tempDir():String {
		var t = Sys.getEnv("TEMP");
		if (t == null || t.length == 0) t = Sys.getEnv("TMP");
		if (t == null || t.length == 0) t = ".";
		return t;
	}

	public static function relPath(base:String, full:String):String {
		var b = normalizeSlashes(stripTrailingSep(Path.normalize(base)));
		var f = normalizeSlashes(Path.normalize(full));
		if (eqi(f, b)) return "";
		var prefix = b + "/";
		if (f.toLowerCase().indexOf(prefix.toLowerCase()) == 0) {
			return f.substr(prefix.length).split("/").join("\\");
		}
		return f.split("/").join("\\");
	}

	public static function normalizeSlashes(p:String):String {
		return StringTools.replace(p, "\\", "/");
	}

	static function stripTrailingSep(p:String):String {
		while (p.length > 1 && (StringTools.endsWith(p, "\\") || StringTools.endsWith(p, "/"))) {
			if (p.length == 3 && p.charAt(1) == ":") break;
			p = p.substr(0, p.length - 1);
		}
		return p;
	}

	public static function mkdirs(p:String):Void {
		if (p == null || p.length == 0) return;
		p = stripTrailingSep(p);
		if (p.length == 0 || FileSystem.exists(p)) return;
		var parent = Path.directory(p);
		if (parent != null && parent.length > 0 && parent != p) mkdirs(parent);
		if (!FileSystem.exists(p)) FileSystem.createDirectory(p);
	}

	public static function readText(p:String):String {
		return File.getContent(p);
	}

	public static function readBytes(p:String):Bytes {
		return File.getBytes(p);
	}

	public static function writeText(p:String, s:String):Void {
		File.saveContent(p, s);
	}

	public static function writeBytes(p:String, b:Bytes):Void {
		File.saveBytes(p, b);
	}

	public static function copyFile(src:String, dst:String):Void {
		mkdirs(Path.directory(dst));
		File.saveBytes(dst, File.getBytes(src));
	}

	public static function copyDir(src:String, dst:String):Void {
		mkdirs(dst);
		if (!FileSystem.exists(src) || !FileSystem.isDirectory(src)) return;
		for (name in FileSystem.readDirectory(src)) {
			var s = join([src, name]);
			var d = join([dst, name]);
			if (FileSystem.isDirectory(s)) copyDir(s, d);
			else copyFile(s, d);
		}
	}

	/** All files below dir (recursive), full paths, sorted for determinism. */
	public static function filesRecursive(dir:String):Array<String> {
		var out = new Array<String>();
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return out;
		for (name in FileSystem.readDirectory(dir)) {
			var p = join([dir, name]);
			if (FileSystem.isDirectory(p)) {
				for (f in filesRecursive(p)) out.push(f);
			} else out.push(p);
		}
		out.sort(Reflect.compare);
		return out;
	}

	/** Direct children matching an extension ("" = all), sorted. */
	public static function filesWithExt(dir:String, ext:String):Array<String> {
		var out = new Array<String>();
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return out;
		for (name in FileSystem.readDirectory(dir)) {
			var p = join([dir, name]);
			if (FileSystem.isDirectory(p)) continue;
			if (ext.length == 0 || eqi(extOf(name), ext)) out.push(p);
		}
		out.sort(Reflect.compare);
		return out;
	}

	public static function fileSize(p:String):Float {
		return FileSystem.stat(p).size;
	}

	/**
	 * Trims a path and removes the surrounding quotes Explorer's "Copy as path"
	 * produces, so a pasted value can be used directly by Proc and FileSystem.
	 */
	public static function unquotePath(p:String):String {
		if (p == null) return "";
		p = StringTools.trim(p);
		if (p.length > 1 && p.charAt(0) == '"' && p.charAt(p.length - 1) == '"') {
			p = p.substr(1, p.length - 2);
		}
		return p;
	}

	/**
	 * True when a tool path points at an existing file, or (for a bare command
	 * name such as "java.exe") when the command can be found on PATH. This lets
	 * users keep PATH-based tools instead of being forced to pick an absolute path.
	 */
	public static function toolExists(p:String):Bool {
		p = unquotePath(p);
		if (p.length == 0) return false;
		if (FileSystem.exists(p)) return !FileSystem.isDirectory(p);
		if (p.indexOf("\\") >= 0 || p.indexOf("/") >= 0 || p.indexOf(":") >= 0) return false;

		var pathSpec = Sys.getEnv("PATH");
		if (pathSpec == null || pathSpec.length == 0) return false;
		var windows = Sys.systemName() == "Windows";
		var names = [p];
		if (windows && extOf(p).length == 0) {
			var pathExt = Sys.getEnv("PATHEXT");
			if (pathExt != null) {
				for (ext in pathExt.split(";")) {
					if (ext.length > 0) names.push(p + ext);
				}
			}
		}
		for (dir in pathSpec.split(windows ? ";" : ":")) {
			dir = StringTools.trim(dir);
			if (dir.length > 1 && dir.charAt(0) == '"' && dir.charAt(dir.length - 1) == '"') {
				dir = dir.substr(1, dir.length - 2);
			}
			if (dir.length == 0) continue;
			for (name in names) {
				var candidate = join([dir, name]);
				if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate)) return true;
			}
		}
		return false;
	}

	/**
	 * Canonical UTF-8 form of a string, for use as a map key.
	 *
	 * hxcpp keeps either a narrow (UTF-8) or a wide (UTF-16) representation of
	 * the same text and hashes each representation separately, so a string built
	 * by concatenation can fail to match the identical text decoded from bytes -
	 * exactly what happens when comparing ABC strings with names assembled from
	 * an embedded resource. A UTF-8 round-trip pins the key to the narrow form.
	 */
	public static function key(s:String):String {
		if (s == null) return null;
		var b = Bytes.ofString(s);
		return b.getString(0, b.length);
	}

	public static function eqi(a:String, b:String):Bool {
		return a != null && b != null && a.toLowerCase() == b.toLowerCase();
	}

	public static function stamp():String {
		return DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
	}

	public static function escapeJson(s:String):String {
		var sb = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			switch (c) {
				case 0x22: sb.add("\\\"");
				case 0x5C: sb.add("\\\\");
				case 0x08: sb.add("\\b");
				case 0x0C: sb.add("\\f");
				case 0x0A: sb.add("\\n");
				case 0x0D: sb.add("\\r");
				case 0x09: sb.add("\\t");
				default:
					if (c < 0x20) sb.add("\\u" + StringTools.hex(c, 4).toLowerCase());
					else sb.add(String.fromCharCode(c));
			}
		}
		return sb.toString();
	}

	public static function describe(e:Dynamic):String {
		if (e == null) return "unknown error";
		if (Std.isOfType(e, String)) return cast e;
		return Std.string(e);
	}

	/** Signed byte-delta for build logs (`+8`, `-5`, `+0`). */
	public static function signed(n:Int):String {
		return n > 0 ? "+" + n : (n < 0 ? "" + n : "+0");
	}
}





/** Result of checking one external tool or input path. */
class ToolStatus {
	public var key:String;
	public var label:String;
	public var ok:Bool;
	public var detail:String;

	public function new(key:String, label:String, ok:Bool, detail:String) {
		this.key = key;
		this.label = label;
		this.ok = ok;
		this.detail = detail;
	}
}

class ObSettings {
	public var airSdk:String;
	public var aneDir:String;
	public var appDesc:String;
	public var iconsDir:String;
	public var certP12:String;
	public var certPass:String;
	public var outDir:String;
	public var ffdecJar:String;
	public var javaExe:String;
	public var deobfuscate:Bool;
	public var windowWidth:Int;
	public var windowHeight:Int;

	public function new(airSdk:String, aneDir:String, appDesc:String, iconsDir:String, certP12:String, certPass:String, outDir:String,
			ffdecJar:String, javaExe:String, deobfuscate:Bool = true, windowWidth:Int = 540, windowHeight:Int = 960) {
		this.airSdk = airSdk;
		this.aneDir = aneDir;
		this.appDesc = appDesc;
		this.iconsDir = iconsDir;
		this.certP12 = certP12;
		this.certPass = certPass;
		this.outDir = outDir;
		this.ffdecJar = ffdecJar;
		this.javaExe = javaExe;
		this.deobfuscate = deobfuscate;
		this.windowWidth = windowWidth;
		this.windowHeight = windowHeight;
	}

	public function copy():ObSettings {
		return new ObSettings(airSdk, aneDir, appDesc, iconsDir, certP12, certPass, outDir, ffdecJar, javaExe, deobfuscate,
			windowWidth, windowHeight);
	}

	public static function filePath(appDir:String):String {
		return Util.join([appDir, "orbitbuilder.settings.json"]);
	}

	public static function defaults(appDir:String):ObSettings {
		return new ObSettings(
			envOr("AIRSDK", "C:\\AIRSDK\\AIRSDK_51.4.1"),
			Util.join([appDir, "ane"]),
			Util.join([appDir, "pc-pack", "application-win.xml"]),
			Util.join([appDir, "pc-pack", "icons"]),
			Util.join([appDir, "pc-pack", "cert.p12"]),
			"password",
			Util.join([appDir, "out"]),
			Util.join([appDir, "tools", "ffdec", "ffdec.jar"]),
			javaDefault()
		);
	}

	static function envOr(name:String, fallback:String):String {
		var v = Sys.getEnv(name);
		return v != null && v.length > 0 ? v : fallback;
	}

	static function javaDefault():String {
		var home = Sys.getEnv("JAVA_HOME");
		if (home != null && home.length > 0) {
			var name = Sys.systemName() == "Windows" ? "java.exe" : "java";
			var p = Util.join([home, "bin", name]);
			if (FileSystem.exists(p)) return p;
		}
		return Sys.systemName() == "Windows" ? "java.exe" : "java";
	}

	/** One entry per external tool or build input, in the order the UI shows them. */
	public static function check(s:ObSettings):Array<ToolStatus> {
		var out = new Array<ToolStatus>();

		var airSdk = Util.unquotePath(s.airSdk);
		var adt = airSdk.length == 0 ? "" : Util.join([airSdk, "bin", "adt.bat"]);
		var adtOk = adt.length > 0 && FileSystem.exists(adt);
		out.push(new ToolStatus("airSdk", "AIR SDK (bin\\adt.bat)", adtOk,
			adtOk ? adt : (adt.length == 0 ? "not set" : "not found: " + adt)));

		var aneDir = Util.unquotePath(s.aneDir);
		var aneOk = aneDir.length > 0 && FileSystem.exists(aneDir) && FileSystem.isDirectory(aneDir);
		var aneCount = aneOk ? Util.filesWithExt(aneDir, ".ane").length : 0;
		out.push(new ToolStatus("aneDir", "ANE folder", aneOk && aneCount >= 15,
			!aneOk ? (aneDir.length == 0 ? "not set" : "not found: " + aneDir)
				: '$aneCount .ane file(s), need 15'));

		var java = Util.unquotePath(s.javaExe);
		var javaOk = Util.toolExists(java);
		out.push(new ToolStatus("javaExe", "Java executable", javaOk,
			javaOk ? java : (java.length == 0 ? "not set" : "not found: " + java)));

		var ffdec = Util.unquotePath(s.ffdecJar);
		var ffdecOk = Util.toolExists(ffdec);
		out.push(new ToolStatus("ffdecJar", "FFDec jar", ffdecOk,
			ffdecOk ? ffdec : (ffdec.length == 0 ? "not set" : "not found: " + ffdec)));

		out.push(fileStatus("appDesc", "App descriptor XML", s.appDesc));
		out.push(dirStatus("iconsDir", "Icons folder", s.iconsDir));
		out.push(fileStatus("certP12", "Signing certificate (.p12)", s.certP12));

		var outDir = Util.unquotePath(s.outDir);
		out.push(new ToolStatus("outDir", "Output folder", outDir.length > 0, outDir.length > 0 ? outDir : "not set"));

		var passOk = s.certPass != null && s.certPass.length > 0;
		out.push(new ToolStatus("certPass", "Certificate password", passOk, passOk ? "set" : "empty"));

		return out;
	}

	static function fileStatus(key:String, label:String, path:String):ToolStatus {
		path = Util.unquotePath(path);
		var ok = path.length > 0 && FileSystem.exists(path) && !FileSystem.isDirectory(path);
		return new ToolStatus(key, label, ok, ok ? path : (path.length == 0 ? "not set" : "not found: " + path));
	}

	static function dirStatus(key:String, label:String, path:String):ToolStatus {
		path = Util.unquotePath(path);
		var ok = path.length > 0 && FileSystem.exists(path) && FileSystem.isDirectory(path);
		return new ToolStatus(key, label, ok, ok ? path : (path.length == 0 ? "not set" : "not found: " + path));
	}

	public static function load(appDir:String):ObSettings {
		var d = defaults(appDir);
		var path = filePath(appDir);
		try {
			if (!sys.FileSystem.exists(path)) return d;
			var root:Dynamic = Json.parse(Util.readText(path));
			if (root == null || !Std.isOfType(root, Dynamic)) return d;
			return new ObSettings(
				Util.unquotePath(str(root, "AirSdk", d.airSdk)),
				Util.unquotePath(str(root, "AneDir", d.aneDir)),
				Util.unquotePath(str(root, "AppDesc", d.appDesc)),
				Util.unquotePath(str(root, "IconsDir", d.iconsDir)),
				Util.unquotePath(str(root, "CertP12", d.certP12)),
				str(root, "CertPass", d.certPass),
				Util.unquotePath(str(root, "OutDir", d.outDir)),
				Util.unquotePath(str(root, "FfdecJar", d.ffdecJar)),
				Util.unquotePath(str(root, "JavaExe", d.javaExe)),
				boolean(root, "Deobfuscate", d.deobfuscate),
				integer(root, "WindowWidth", d.windowWidth),
				integer(root, "WindowHeight", d.windowHeight)
			);
		} catch (e:Dynamic) {
			return d;
		}
	}

	static function str(o:Dynamic, k:String, fb:String):String {
		var v:Dynamic = Reflect.field(o, k);
		return (v != null && Std.isOfType(v, String)) ? cast v : fb;
	}

	static function boolean(o:Dynamic, k:String, fb:Bool):Bool {
		var v:Dynamic = Reflect.field(o, k);
		return (v != null && Std.isOfType(v, Bool)) ? cast v : fb;
	}

	static function integer(o:Dynamic, k:String, fb:Int):Int {
		var v:Dynamic = Reflect.field(o, k);
		if (v == null) return fb;
		if (Std.isOfType(v, Int)) return cast v;
		if (Std.isOfType(v, Float)) return Std.int(v);
		return fb;
	}

	public static function save(appDir:String, s:ObSettings):Void {
		var t = new StringBuf();
		t.add("{\n");
		field(t, "AirSdk", s.airSdk, true);
		field(t, "AneDir", s.aneDir, true);
		field(t, "AppDesc", s.appDesc, true);
		field(t, "IconsDir", s.iconsDir, true);
		field(t, "CertP12", s.certP12, true);
		field(t, "CertPass", s.certPass, true);
		field(t, "OutDir", s.outDir, true);
		field(t, "FfdecJar", s.ffdecJar, true);
		field(t, "JavaExe", s.javaExe, true);
		t.add('  "Deobfuscate": ${s.deobfuscate},\n');
		t.add('  "WindowWidth": ${s.windowWidth},\n');
		t.add('  "WindowHeight": ${s.windowHeight}\n');
		t.add("}\n");
		Util.writeText(filePath(appDir), t.toString());
	}

	static function field(t:StringBuf, key:String, value:String, comma:Bool):Void {
		t.add('  "${key}": "${Util.escapeJson(value)}"' + (comma ? "," : "") + "\n");
	}
}




