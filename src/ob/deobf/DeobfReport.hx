package ob.deobf;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** Rebuilds the pools, verifies the new layout, and writes the name report. */
class DeobfWriter {
	public static function write(p:DeobfPlan, abc:Bytes, log:String->Void):DeobfResult {
		var newStrBytes = AbcPoolWriter.writeStrings(p.pools, abc, p.rename, p.added);
		var newMnBytes = AbcPoolWriter.writeMultinames(p.pools);

		var out = new BytesBuffer();
		out.addBytes(abc, 0, p.pools.strCountPos);
		out.addBytes(newStrBytes, 0, newStrBytes.length);
		out.addBytes(abc, p.pools.strPoolEnd, p.pools.mnCountPos - p.pools.strPoolEnd);
		out.addBytes(newMnBytes, 0, newMnBytes.length);
		out.addBytes(abc, p.pools.mnPoolEnd, abc.length - p.pools.mnPoolEnd);
		var resultAbc = out.getBytes();

		// Self-check: the rewritten ABC must parse back to exactly the layout
		// that was written - a wrong pool count shifts every pool after it and
		// corrupts the file in ways the SWF-level validation cannot see.
		var probe = AbcPoolReader.read(resultAbc);
		if (probe.strCount != p.pools.strCount + p.added.length) {
			throw 'deobf self-check: string count ${probe.strCount}, expected ${p.pools.strCount + p.added.length}.';
		}
		var wantStrEnd = p.pools.strCountPos + newStrBytes.length;
		if (probe.strPoolEnd != wantStrEnd) {
			throw 'deobf self-check: string pool ends at ${probe.strPoolEnd}, expected $wantStrEnd.';
		}
		// The namespace and namespace-set pools are copied verbatim, so the
		// multiname pool must start where they end and be exactly as long as
		// the bytes written for it (its own entries may re-encode differently).
		var wantMnEnd = wantStrEnd + (p.pools.mnCountPos - p.pools.strPoolEnd) + newMnBytes.length;
		if (probe.mnPoolEnd != wantMnEnd) {
			throw 'deobf self-check: multiname pool ends at ${probe.mnPoolEnd}, expected $wantMnEnd.';
		}

		var sb = new StringBuf();
		sb.add("# deobfuscated names (obfuscated -> readable)\n");
		var keys = [for (k in p.classOf.keys()) k];
		keys.sort(function(a, b) {
			var x = p.pools.strVal[a], y = p.pools.strVal[b];
			return x < y ? -1 : (x > y ? 1 : 0);
		});
		for (k in keys) {
			var c = p.classOf.get(k);
			sb.add(p.pools.strVal[k]);
			sb.add("\t");
			sb.add(c.pkg.length == 0 ? c.cls : c.pkg + "." + c.cls);
			sb.add("\n");
		}

		log('Deobfuscation: ${p.mapped} classes renamed from real names, ${p.unmapped} given generated names, ' +
			'${p.members} members renamed, ${p.literals} class-name literal(s) rewritten, ${p.refPoints} class references repointed' +
			(p.ambiguous > 0 ? ', ${p.ambiguous} ambiguous multinames skipped' : "") + '.');

		return new DeobfResult(resultAbc, p.classOf.keys().hasNext() ? DeobfNames.countKeys(p.classOf) : 0, p.unmapped, p.members,
			p.refPoints, sb.toString(), p.fqcn);
	}
}



/** Naming helpers shared by the deobfuscation passes. */
class DeobfNames {
	public static function isGlyph(s:String):Bool {
		for (i in 0...s.length) if (s.charCodeAt(i) > 0x7F) return true;
		return false;
	}

	/** Turn an obfuscated glyph string into short ASCII using `letter`. */
	public static function code(s:String, letter:Map<Int, Int>):String {
		var sb = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			if (c == 0xA7 || c == 0x2E) continue; // '§' and '.'
			sb.add(String.fromCharCode(letter.exists(c) ? letter.get(c) : 0x7A));
		}
		var r = sb.toString();
		return r.length == 0 ? "x" : r;
	}

	public static function unique(want:String, used:Map<String, Bool>):String {
		if (!used.exists(want)) {
			used.set(want, true);
			return want;
		}
		var i = 2;
		while (true) {
			var w = want + "_" + i;
			if (!used.exists(w)) {
				used.set(w, true);
				return w;
			}
			i++;
		}
	}

	public static function countKeys(m:Map<Int, Dynamic>):Int {
		var n = 0;
		for (k in m.keys()) n++;
		return n;
	}
}




class DeobfResult {
	public var abc:Bytes;
	public var classes:Int;
	public var unmapped:Int;
	public var members:Int;
	public var refPoints:Int;
	public var map:String;

	/** Obfuscated fully qualified class name -> readable one. The ABC is not the
	 * only place a class name is written down: the SWF's own tags (SymbolClass,
	 * ExportAssets, ImportAssets) name classes as dotted strings too, and those
	 * are resolved by the player at load time. Callers must apply the same
	 * rename there or the symbol table points at classes that no longer exist. */
	public var fqcn:Map<String, String>;

	public function new(abc:Bytes, classes:Int, unmapped:Int, members:Int, refPoints:Int, map:String, fqcn:Map<String, String>) {
		this.abc = abc;
		this.classes = classes;
		this.unmapped = unmapped;
		this.members = members;
		this.refPoints = refPoints;
		this.map = map;
		this.fqcn = fqcn;
	}
}



/**
 * deobf.map: obfuscated identifier -> readable Haxe name, generated from the
 * supported build's own position-info literals. Format (tab separated):
 *   C<TAB>obfuscated-package-string<TAB>real.package.ClassName
 *   M<TAB>obfuscated-member-string<TAB>realMemberName
 * '#' starts a comment.
 */
class NameMap {
	public var classes:Map<String, {pkg:String, cls:String}>;
	public var members:Map<String, String>;

	public function new() {
		classes = new Map<String, {pkg:String, cls:String}>();
		members = new Map<String, String>();
	}

	/** FFDec renders the ABC's odd glyph identifiers wrapped in U+00A7 ("§");
	 * the ABC itself contains no U+00A7, so the marker is stripped here. */
	static function glyph(s:String):String {
		s = StringTools.replace(s, "\u00A7", "");
		// hxcpp stores strings either narrow (UTF-8) or wide (UTF-16) and hashes
		// the two representations differently, so a string that came out of an
		// embedded resource can miss a Map lookup for the very same characters
		// decoded from ABC bytes. Round-tripping through UTF-8 pins every map key
		// to the representation Bytes.getString produces.
		return Util.key(s);
	}

	public static function load(text:String):NameMap {
		var m = new NameMap();
		for (raw in text.split("\n")) {
			var line = StringTools.trim(raw);
			if (line.length == 0 || line.charAt(0) == "#") continue;
			var p = line.split("\t");
			if (p.length < 3) continue;
			if (p[0] == "C") {
				var dot = p[2].lastIndexOf(".");
				if (dot < 0) m.classes.set(glyph(p[1]), {pkg: "", cls: p[2]});
				else m.classes.set(glyph(p[1]), {pkg: p[2].substr(0, dot), cls: p[2].substr(dot + 1)});
			} else if (p[0] == "M") {
				m.members.set(glyph(p[1]), p[2]);
			}
		}
		return m;
	}

	public static function loadEmbedded():NameMap {
		var text = haxe.Resource.getString("deobf.map");
		if (text == null) throw "deobf.map resource missing from the builder.";
		return load(text);
	}
}


