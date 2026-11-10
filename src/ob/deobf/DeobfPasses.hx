package ob.deobf;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** Builds the glyph-character -> ASCII-letter map used by generated names. */
class DeobfAlphabet {
	public static function build(map:NameMap):Map<Int, Int> {
		var alphabet = new Map<Int, Bool>();
		for (k in map.classes.keys()) {
			for (i in 0...k.length) {
				var c = k.charCodeAt(i);
				if (c > 0x7F) alphabet.set(c, true);
			}
		}

		var letter = new Map<Int, Int>();
		var letters = [for (c in alphabet.keys()) c];
		letters.sort(function(a, b) return a - b);
		var pool = "abcdefghijklmnopqrstuvwxyz";
		var k = 0;
		for (c in letters) {
			letter.set(c, pool.charCodeAt(k % pool.length));
			k++;
		}
		return letter;
	}
}



/**
 * First deobfuscation pass: package strings become readable class packages,
 * and class names written down as dotted string literals are mapped too.
 */
class DeobfClassPlan {
	public static function apply(p:DeobfPlan, map:NameMap, log:String->Void):Void {
		var pools = p.pools;
		var classOf = p.classOf;
		var rename = p.rename;
		var used = p.used;
		p.letter = DeobfAlphabet.build(map);

		// Which string indices serve as namespace names (kind 22: one per
		// obfuscated class).
		var pkgStrings = new Array<Int>();
		for (i in 1...pools.nsCount) {
			if (pools.nsKind[i] == 22) pkgStrings.push(pools.nsName[i]);
		}

		// Names must stay *unique*, exactly as they are in the obfuscated build:
		// AVM2 links a subclass to its base class (and an implementer to its
		// interfaces) by name, so two classes that end up with one readable name
		// make the wrong class win and verification fails with "Illegal override
		// of ... in ..." The map is not guaranteed to be injective - it is derived
		// from the game's own position-info literals, and an inlined function logs
		// the class that *declares* it, so several classes can be credited with
		// one name (and template-generated bundles really do ship duplicates).
		// Keep the plain name for the first class (ordered by obfuscated package,
		// so builds are reproducible) and suffix the rest.
		var duplicates = 0;
		var dupNames = new Array<String>();
		pkgStrings.sort(function(a, b) {
			var x = pools.strVal[a], y = pools.strVal[b];
			return x < y ? -1 : (x > y ? 1 : 0);
		});
		for (si in pkgStrings) {
			var v = pools.strVal[si];
			if (!DeobfNames.isGlyph(v)) continue;
			if (map.classes.exists(v)) {
				var cls = map.classes.get(v);
				var pkg = cls.pkg, name = cls.cls;
				var want = pkg.length == 0 ? name : pkg + "." + name;
				var got = DeobfNames.unique(want, used);
				if (got != want) {
					name = got.substr(pkg.length == 0 ? 0 : pkg.length + 1);
					duplicates++;
					if (dupNames.indexOf(want) < 0) dupNames.push(want);
				}
				rename[si] = pkg;
				classOf.set(si, {pkg: pkg, cls: name});
				p.classOrder.push(si);
				p.mapped++;
			} else {
				rename[si] = "obf";
				classOf.set(si, {pkg: "obf", cls: DeobfNames.unique("C" + DeobfNames.code(v, p.letter), used)});
				p.classOrder.push(si);
				p.unmapped++;
			}
		}
		if (duplicates > 0) {
			var shown = dupNames.slice(0, 3).join(", ");
			var more = dupNames.length > 3 ? ', +${dupNames.length - 3} more' : "";
			log('Deobfuscation: $duplicates class name(s) recovered for more than one class; ' +
				'the extras got a numeric suffix to keep names unique ($shown$more).');
		}

		// Class names that are written down as *string literals*.
		// The game resolves several classes by their dotted runtime name - the
		// string Type.getClassName() returns, which for every obfuscated class is
		// its package string plus ".int" - and jp.sipo's gear registry (Diffuser)
		// is keyed by exactly that string. Such a literal has to be rewritten to
		// the class's *new* dotted name; the generic member scheme would give it a
		// unique but unrelated name and every one of those lookups would fail,
		// which shows up as a black screen (the production view's state machine
		// never gets its gears).
		for (k in classOf.keys()) {
			var c = classOf.get(k);
			p.fqcn.set(Util.key(pools.strVal[k] + "." + pools.strVal[p.intIdx]),
				c.pkg.length == 0 ? c.cls : c.pkg + "." + c.cls);
		}
		for (i in 1...pools.strCount) {
			if (rename[i] != null) continue;
			var lit = Util.key(pools.strVal[i]);
			if (p.fqcn.exists(lit)) {
				rename[i] = p.fqcn.get(lit);
				p.literals++;
			}
		}
	}
}



/** Second pass: private-namespace names and member names. */
class DeobfMemberPlan {
	public static function apply(p:DeobfPlan, map:NameMap):Void {
		for (i in 1...p.pools.strCount) {
			if (p.rename[i] != null) continue;
			var v = p.pools.strVal[i];
			if (!DeobfNames.isGlyph(v)) continue;
			if (p.otherNsStrings.exists(i)) p.rename[i] = DeobfNames.unique("priv" + DeobfNames.code(v, p.letter), p.used);
			else if (map.members.exists(v)) {
				p.rename[i] = map.members.get(v);
				p.members++;
			} else p.rename[i] = DeobfNames.unique("id" + DeobfNames.code(v, p.letter), p.used);
		}
	}
}



/**
 * Third pass: class names. Every multiname in a class's own package whose name
 * is the shared "int" string is repointed at the class's new name string.
 */
class DeobfMultinamePlan {
	public static function apply(p:DeobfPlan):Void {
		var pools = p.pools;

		// Reuse a name string that already exists in the pool (readable ones are
		// already there as position-info literals) and share one pending index
		// when several classes carry the same simple name.
		var nameIdxOf = new Map<String, Int>();
		var newName = new Map<Int, Int>();
		for (k in p.classOrder) {
			var cls = p.classOf.get(k).cls;
			var idx:Int;
			if (nameIdxOf.exists(cls)) idx = nameIdxOf.get(cls);
			else {
				if (p.byValue.exists(cls) && p.rename[p.byValue.get(cls)] == null) idx = p.byValue.get(cls);
				else {
					idx = pools.strCount + p.added.length;
					p.added.push(cls);
				}
				nameIdxOf.set(cls, idx);
			}
			newName.set(k, idx);
		}

		for (i in 1...pools.mnCount) {
			var m = pools.mns[i];
			if (!m.hasName || m.nameIdx != p.intIdx) continue;
			var si = -1;
			if (m.kind == 0x07 || m.kind == 0x0D) si = pools.nsName[m.ns];
			else if (m.kind == 0x09 || m.kind == 0x0E) {
				var cand = new Array<Int>();
				for (x in pools.nsSet[m.nsSet]) {
					if (x > 0 && p.classOf.exists(pools.nsName[x])) {
						var s = pools.nsName[x];
						if (cand.indexOf(s) < 0) cand.push(s);
					}
				}
				if (cand.length == 1) si = cand[0];
				else if (cand.length > 1) p.ambiguous++;
			}
			if (si >= 0 && newName.exists(si)) {
				m.nameIdx = newName.get(si);
				p.refPoints++;
			}
		}
	}
}




