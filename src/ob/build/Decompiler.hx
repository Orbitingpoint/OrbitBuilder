package ob.build;

import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Uncompress;

	/** Exports a game SWF and its ABC blocks for patch development. */
class Decompiler {
	public static function run(input:String, s:ObSettings, log:String->Void):String {
		Util.mkdirs(s.outDir);
		var job = Util.join([s.outDir, "decompiled-" + Util.stamp()]);
		Util.mkdirs(job);
		var target = Patcher.loadTarget(Util.baseDir());
		var swf = GameAssets.readSwf(input, target, log);
		Util.writeBytes(Util.join([job, "game.swf"]), swf);
		// Export readable scripts: rewrite the obfuscated identifiers first so the
		// ActionScript you get back is the same source the patches are written against.
		var exportSwf = Util.join([job, "game.swf"]);
		if (!s.deobfuscate) log("Deobfuscation disabled in settings; exporting the raw SWF.");
		else {
			try {
				var readable = Deobfuscator.run(swf, target, Util.join([job, "deobf-names.tsv"]), log);
				exportSwf = Util.join([job, "game-readable.swf"]);
				Util.writeBytes(exportSwf, readable);
			} catch (e:Dynamic) {
				log('Deobfuscation skipped (${Util.describe(e)}); exporting the raw SWF instead.');
			}
		}
		var parsed = Swf.parseCws(swf);
		var abcs = Swf.listAbc(parsed.body);
		var census = new StringBuf();
		census.add("{\r\n");
		census.add('  "swfVersion": ${parsed.ver}, "swfBytes": ${swf.length}, "swfSha256": "${Patcher.sha256(swf)}",\r\n');
		census.add('  "tags": ${Swf.countTags(parsed.body)}, "doAbc": [\r\n');
		for (i in 0...abcs.length) {
			var a = abcs[i];
			var abc = parsed.body.sub(a.abcStart, a.contentStart + a.contentLen - a.abcStart);
			var fn = 'game-$i.abc';
			Util.writeBytes(Util.join([job, fn]), abc);
			census.add('    {"index": $i, "name": "${a.name}", "bytes": ${abc.length}, "sha256": "${Patcher.sha256(abc)}"},\r\n');
		}
		census.add("    null\r\n");
		// The reference uses StreamWriter.WriteLine for the closing brace, so the
		// file ends with CRLF while the bracket line itself uses a bare LF.
		census.add("  ]\n}\r\n");
		Util.writeText(Util.join([job, "tags.json"]), census.toString());
		log('Decompiled: game.swf + ${abcs.length} ABC blocks + tags.json -> $job');
		if (Util.toolExists(s.javaExe) && Util.toolExists(s.ffdecJar)) {
			log("Running FFDec full script export (minutes on 31MB SWF)...");
			Proc.run(s.javaExe, ["-Xmx4G", "-jar", s.ffdecJar, "-export", "script", Util.join([job, "as3"]), exportSwf], job, log);
			log("FFDec export done.");
		} else log("FFDec/Java not configured; skipped readable-script export (see Tools > Tool paths and build settings).");
		return job;
	}
}




/** Rewrites the game's obfuscated identifiers to readable ASCII names. */
class Deobfuscator {
	/**
	 * Runs before code patches
	 * The ABC and the SWF tags that name classes
	 * are renamed with the same map.
	 */
	public static function run(swf:Bytes, target:PatchTarget, reportPath:String, log:String->Void):Bytes {
		var parsed = Swf.parseCws(swf);
		var loc = Swf.findAbc(parsed.body, target.abcName);
		var abc = parsed.body.sub(loc.abcStart, loc.contentStart + loc.contentLen - loc.abcStart);
		var res = Deobf.apply(abc, NameMap.loadEmbedded(), log);
		Util.mkdirs(Path.directory(reportPath));
		Util.writeText(reportPath, res.map);
		var newBody = Swf.replaceAbc(parsed.body, loc, res.abc);
		newBody = Swf.rewriteTagNames(newBody, res.fqcn, log);
		var outSwf = Swf.toCws(parsed.ver, newBody);
		Swf.validateCws(outSwf, log);
		log('Identifiers readable (${Util.signed(res.abc.length - abc.length)} bytes); name list: $reportPath');
		return outSwf;
	}
}




