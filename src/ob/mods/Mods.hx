package ob.mods;

import haxe.io.Bytes;
import haxe.Json;
import haxe.Resource;
import sys.FileSystem;

/** Shared helpers: hashing and the target record. */
class Patcher {
	public static function sha256(b:Bytes):String {
		return haxe.crypto.Sha256.make(b).toHex();
	}

	/** target.json next to the exe (falls back to the embedded copy). */
	public static function loadTarget(appDir:String):PatchTarget {
		var path = Util.join([appDir, "target.json"]);
		var text = FileSystem.exists(path) ? Util.readText(path) : Resource.getString("target.json");
		if (text == null) throw 'target.json missing next to the exe ($path).';
		var root:Dynamic = Json.parse(text);
		if (root == null) throw "target.json is not valid JSON.";
		var a:Dynamic = Reflect.field(root, "swfAssetPath");
		var b:Dynamic = Reflect.field(root, "swfSha256");
		var c:Dynamic = Reflect.field(root, "abcName");
		if (!Std.isOfType(a, String) || !Std.isOfType(b, String) || !Std.isOfType(c, String)) {
			throw "target.json needs swfAssetPath, swfSha256 and abcName.";
		}
		return new PatchTarget(cast a, cast b, cast c);
	}
}


class ConfigSpec {
	public var key:String;
	public var dflt:String;
	public var desc:String;

	public function new(key:String, dflt:String, desc:String) {
		this.key = key;
		this.dflt = dflt;
		this.desc = desc;
	}
}

/**
 * A mod is one zip file under mods/. The zip contains a mod.json metadata file
 * and one .as source file:
 *
 *   mod.json     name, description, target, platform, enabled and config[]
 *   *.as         whole-class ActionScript replacement
 */
class Mod {
	public var id:String;
	public var name:String;
	public var desc:String;
	public var target:String;
	public var platform:String;
	public var enabled:Bool;
	public var source:String;
	public var file:String;
	public var config:Array<ConfigSpec>;

	public function new(id:String, name:String, desc:String, target:String, platform:String,
			enabled:Bool, source:String, file:String, config:Array<ConfigSpec>) {
		this.id = id;
		this.name = name;
		this.desc = desc;
		this.target = target;
		this.platform = platform;
		this.enabled = enabled;
		this.source = source;
		this.file = file;
		this.config = config;
	}
}

private class ModState {
	public var enabled:Null<Bool> = null;
	public var values:Map<String, String> = new Map();

	public function new() {}
}

/** Persisted enabled flags and per-mod config values */
class ModConfig {
	static var cache:Map<String, ModState> = null;

	static function storePath():String {
		return Util.join([Util.baseDir(), "mods.json"]);
	}

	static function all():Map<String, ModState> {
		if (cache != null) return cache;
		cache = new Map();
		try {
			var path = storePath();
			if (!FileSystem.exists(path)) return cache;
			var root:Dynamic = Json.parse(Util.readText(path));
			if (root == null) return cache;
			for (id in Reflect.fields(root)) {
				var st = new ModState();
				var sub:Dynamic = Reflect.field(root, id);
				for (k in Reflect.fields(sub)) {
					var v:Dynamic = Reflect.field(sub, k);
					if (k == "enabled" && Std.isOfType(v, Bool)) st.enabled = cast v;
					else if (Std.isOfType(v, String)) st.values.set(k, cast v);
				}
				cache.set(id, st);
			}
		} catch (e:Dynamic) {
			cache = new Map();
		}
		return cache;
	}

	static function state(id:String, create:Bool = false):Null<ModState> {
		var all = all();
		if (all.exists(id)) return all.get(id);
		if (!create) return null;
		var st = new ModState();
		all.set(id, st);
		return st;
	}

	public static function isEnabled(m:Mod):Bool {
		var st = state(m.id);
		return st != null && st.enabled != null ? st.enabled : m.enabled;
	}

	public static function setEnabled(id:String, enabled:Bool):Void {
		state(id, true).enabled = enabled;
		save();
	}

	public static function get(id:String, spec:ConfigSpec):String {
		var st = state(id);
		if (st != null) {
			var v = st.values.get(spec.key);
			if (v != null && v.length > 0) return v;
		}
		return spec.dflt;
	}

	public static function set(id:String, key:String, value:String):Void {
		state(id, true).values.set(key, value);
		save();
	}

	static function save():Void {
		var all = all();
		var t = new StringBuf();
		t.add("{\n");
		var ids = [for (k in all.keys()) k];
		ids.sort(Reflect.compare);
		for (i in 0...ids.length) {
			var id = ids[i];
			var st = all.get(id);
			t.add('  "${Util.escapeJson(id)}": {\n');
			var parts = new Array<String>();
			if (st.enabled != null) parts.push('"enabled": ${st.enabled}');
			var keys = [for (k in st.values.keys()) k];
			keys.sort(Reflect.compare);
			for (k in keys) parts.push('"${Util.escapeJson(k)}": "${Util.escapeJson(st.values.get(k))}"');
			for (j in 0...parts.length) t.add("    " + parts[j] + (j + 1 < parts.length ? "," : "") + "\n");
			t.add("  }" + (i + 1 < ids.length ? "," : "") + "\n");
		}
		t.add("}\n");
		Util.writeText(storePath(), t.toString());
	}

	/** Replaces {{key}} with escaped configured values; unknown keys fail loudly. */
	public static function expand(text:String, modId:String, specs:Array<ConfigSpec>):String {
		for (spec in specs) {
			var v = get(modId, spec);
			v = StringTools.replace(v, "\\", "\\\\");
			v = StringTools.replace(v, "\"", "\\\"");
			text = StringTools.replace(text, "{{" + spec.key + "}}", v);
		}
		var re = new EReg("\\{\\{[^{}]*\\}\\}", "");
		if (re.match(text)) {
			var declared = specs.length == 0 ? "none" : [for (s in specs) s.key].join(", ");
			throw '[$modId] ${re.matched(0)} has no matching config entry (declared: $declared).';
		}
		return text;
	}
}

/** Installs and loads mod zips from mods/ next to the exe. */
class ModStore {
	public static function dir(appDir:String):String {
		return Util.join([appDir, "mods"]);
	}

	public static function extractDefaults(appDir:String, log:String->Void):Void {
		var outDir = dir(appDir);
		Util.mkdirs(outDir);
		var names = Resource.listNames();
		names.sort(Reflect.compare);
		for (res in names) {
			if (!StringTools.startsWith(res, "mods/")) continue;
			if (!Util.eqi(Util.extOf(res), ".zip")) continue;
			var file = res.substr(5);
			if (file.indexOf("/") >= 0) continue;
			var dst = Util.join([outDir, file]);
			if (FileSystem.exists(dst)) continue;
			var bytes = Resource.getBytes(res);
			if (bytes == null) continue;
			Util.writeBytes(dst, bytes);
			log('Installed default mod: mods/$file');
		}
	}

	public static function load(appDir:String, log:String->Void):Array<Mod> {
		var out = new Array<Mod>();
		var d = dir(appDir);
		if (!FileSystem.exists(d)) {
			Util.mkdirs(d);
			return out;
		}
		for (f in Util.filesWithExt(d, ".zip")) {
			try out.push(loadZip(f))
			catch (e:Dynamic) log('  [mod] ${Util.fileName(f)}: ${Util.describe(e)}');
		}
		return out;
	}

	static function loadZip(file:String):Mod {
		var zip = new ZipFile(file);
		var metaName:String = null;
		var sourceNames = new Array<String>();
		var names = [for (n in zip.entries.keys()) n];
		names.sort(Reflect.compare);
		for (name in names) {
			var lower = name.toLowerCase();
			if (lower.indexOf("__macosx/") == 0) continue;
			if (lower == "mod.json") metaName = name;
			if (StringTools.endsWith(lower, ".as")) sourceNames.push(name);
		}
		if (metaName == null) {
			for (name in names) if (StringTools.endsWith(name.toLowerCase(), ".json")) { metaName = name; break; }
		}
		if (metaName == null) throw "mod zip has no mod.json";
		if (sourceNames.length != 1) throw "mod zip must contain exactly one .as source";
		var srcName = sourceNames[0];
		var meta:Dynamic = Json.parse(zip.read(metaName).toString());
		if (meta == null) throw "mod.json is not valid JSON";

		var type = str(meta, "type", "as3").toLowerCase();
		if (type != "as3") throw 'unsupported mod type "$type" (only as3 is supported)';
		var target = str(meta, "target", "");
		var platform = str(meta, "platform", "all").toLowerCase();
		if (target.length == 0) throw 'mod needs a "target" class';
		if (platform != "all" && platform != "pc") throw 'unknown platform "$platform"';

		var config = new Array<ConfigSpec>();
		var arr:Dynamic = Reflect.field(meta, "config");
		if (arr != null) {
			if (!Std.isOfType(arr, Array)) throw '"config" must be an array';
			for (entry in (cast arr:Array<Dynamic>)) {
				var key = str(entry, "key", "");
				if (key.length == 0) continue;
				config.push(new ConfigSpec(key, str(entry, "default", ""), str(entry, "description", "")));
			}
		}

		return new Mod(
			str(meta, "id", Util.fileStem(file)),
			str(meta, "name", Util.fileStem(file)),
			str(meta, "description", ""),
			target, platform, boolField(meta, "enabled", true),
			zip.read(srcName).toString(), file, config
		);
	}

	static function str(o:Dynamic, key:String, fallback:String):String {
		var v:Dynamic = Reflect.field(o, key);
		return v != null && Std.isOfType(v, String) ? cast v : fallback;
	}

	static function boolField(o:Dynamic, key:String, fallback:Bool):Bool {
		var v:Dynamic = Reflect.field(o, key);
		return v != null && Std.isOfType(v, Bool) ? cast v : fallback;
	}
}
