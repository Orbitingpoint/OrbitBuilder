package ob.deobf;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * Deobfuscates World Flipper's Haxe-obfuscated ABC identifiers.
 *
 * The shipped build names *every* obfuscated class literally "int" (one shared
 * string, which is also the built-in int) and keeps classes apart by giving
 * each one its own randomly generated package of 15 glyph segments. Method and
 * field names are glyph strings too.
 *
 * So a class rename cannot be a pure string-pool rename: the shared "int" is
 * the built-in int as well. Instead:
 *   * obfuscated package strings, method/field names and private-namespace
 *     names are unique per use, so they are renamed in the string pool;
 *   * class names are rewritten at the *multiname* level - every multiname whose
 *     namespace is some class's own package and whose name is "int" is
 *     repointed at a freshly added real-name string.
 *
 * Names come from deobf.map (real Haxe names recovered from the game's own
 * position-info literals) with stable generated names as a fallback, so the
 * result is fully ASCII, stable for this build, and addressable from patches.
 *
 * The passes live in DeobfClassPlan, DeobfMemberPlan and DeobfMultinamePlan;
 * DeobfWriter rebuilds and verifies the pools.
 */
class Deobf {
	public static function apply(abc:Bytes, map:NameMap, log:String->Void):DeobfResult {
		var plan = new DeobfPlan(AbcPoolReader.read(abc));
		DeobfClassPlan.apply(plan, map, log);
		DeobfMemberPlan.apply(plan, map);
		DeobfMultinamePlan.apply(plan);
		return DeobfWriter.write(plan, abc, log);
	}
}




/**
 * Mutable state shared by the deobfuscation passes: the parsed pools, the new
 * string values, the class table and the counters that end up in the result.
 */
class DeobfPlan {
	public var pools:AbcPools;

	/** string value -> pool index (first occurrence) */
	public var byValue:Map<String, Int>;
	public var intIdx:Int;

	/** string indices used as Haxe private-namespace names (kind 8) */
	public var otherNsStrings:Map<Int, Bool>;

	/** New value per string index; null leaves the original bytes untouched. */
	public var rename:Array<String>;

	public var classOf:Map<Int, {pkg:String, cls:String}>;
	/** Insertion order used when assigning new string-pool indices. */
	public var classOrder:Array<Int>;
	public var used:Map<String, Bool>;
	public var letter:Map<Int, Int>;

	public var added:Array<String>;
	public var fqcn:Map<String, String>;

	public var mapped = 0;
	public var unmapped = 0;
	public var members = 0;
	public var literals = 0;
	public var refPoints = 0;
	public var ambiguous = 0;

	public function new(pools:AbcPools) {
		this.pools = pools;

		byValue = new Map<String, Int>();
		for (i in 1...pools.strCount) {
			var v = pools.strVal[i];
			if (!byValue.exists(v)) byValue.set(v, i);
			if (v == "int") intIdx = i;
		}
		if (intIdx == 0) throw 'no "int" string: not the expected obfuscated build.';

		otherNsStrings = new Map<Int, Bool>();
		for (i in 1...pools.nsCount) {
			if (pools.nsKind[i] != 22) otherNsStrings.set(pools.nsName[i], true);
		}

		rename = new Array<String>();
		for (i in 0...pools.strCount) rename.push(null);

		classOf = new Map<Int, {pkg:String, cls:String}>();
		classOrder = new Array<Int>();
		used = new Map<String, Bool>();
		added = new Array<String>();
		fqcn = new Map<String, String>();
	}
}



