package ob.build;

import sys.FileSystem;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Uncompress;

/** Runs enabled as3 mods through FFDec's whole-class replace. */
class CodePatcher {
	public static function apply(swf:Bytes, mods:Array<Mod>, s:ObSettings, workdir:String, log:String->Void):Bytes {
		var enabled = new Array<Mod>();
		var seen = new Map<String, Bool>();
		for (m in mods) {
			if (!ModConfig.isEnabled(m)) continue;
			if (m.platform != "all" && m.platform != "pc") {
				log('[as3 ${m.id}] skipped (platform ${m.platform})');
				continue;
			}
			if (seen.exists(m.target)) throw 'Multiple enabled mods target ${m.target}; enable only one.';
			seen.set(m.target, true);
			enabled.push(m);
		}
		if (enabled.length == 0) {
			log("No code mods enabled.");
			return swf;
		}
		if (!Util.toolExists(s.javaExe)) throw 'Java not found: ${s.javaExe} (Tools > Tool paths and build settings).';
		if (!Util.toolExists(s.ffdecJar)) throw 'FFDec jar not found: ${s.ffdecJar} (Tools > Tool paths and build settings).';
		Util.mkdirs(workdir);
		var cur = Util.join([workdir, "codebase.swf"]);
		Util.writeBytes(cur, swf);
		for (m in enabled) {
			var next = Util.join([workdir, "code_" + m.id + ".swf"]);
			log('[as3 ${m.id}] ${m.name} -> ${m.target} (FFDec recompile, slow on 31MB SWF...)');
			// Values from mods.json are substituted into the source before FFDec
			// sees it, so the mod zip stays untouched.
			var asFile = Util.join([workdir, "code_" + m.id + ".as"]);
			Util.writeText(asFile, ModConfig.expand(m.source, m.id, m.config));
			for (c in m.config) log('  [as3 ${m.id}] ${c.key} = ${ModConfig.get(m.id, c)}');
			// FFDec is Java, so on Windows it decodes command-line arguments with
			// the system code page. The argsfile form reads them as UTF-8 lines
			// instead, so non-ASCII class names survive intact.
			var argsFile = Util.join([workdir, "code_" + m.id + ".args.txt"]);
			Util.writeText(argsFile, m.target + "\n" + asFile + "\n");
			var res = Proc.run(s.javaExe, ["-Xmx4G", "-jar", s.ffdecJar, "-air", "-replace", cur, next, argsFile], null, log, 20 * 60 * 1000, false);
			if (res.timedOut) throw '[as3 ${m.id}] FFDec timed out after 20 min.';
			if (res.exitCode != 0 || !FileSystem.exists(next)) {
				throw '[as3 ${m.id}] FFDec failed (exit ${res.exitCode}): ${lastLine(res.stderr + res.stdout)}';
			}
			cur = next;
			log('[as3 ${m.id}] class replaced OK.');
		}
		var result = Util.readBytes(cur);
		Swf.validateCws(result, log);
		return result;
	}

	static function lastLine(s:String):String {
		var t = StringTools.trim(s);
		if (t.length == 0) return "";
		var lines = t.split("\n");
		return StringTools.trim(lines[lines.length - 1]);
	}
}




