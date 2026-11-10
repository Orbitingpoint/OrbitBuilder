package ob.abc;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** Low-level ABC varint helpers shared by the parser and patch API. */
class AbcIo {
	public static function readU30(d:Bytes, pos:Pos):Int {
		var r = 0, sh = 0;
		for (k in 0...5) {
			var b = d.get(pos.p++);
			r |= (b & 0x7F) << sh;
			if ((b & 0x80) == 0) break;
			sh += 7;
		}
		return r;
	}

	public static function writeU30(b:BytesBuffer, v:Int):Void {
		while (true) {
			var x = v & 0x7F;
			v >>>= 7;
			if (v != 0) b.addByte(x | 0x80);
			else {
				b.addByte(x);
				break;
			}
		}
	}
}



/** The parsed ABC constant pools that deobfuscation rewrites. */
class AbcPools {
	public var strCountPos:Int;
	public var strCount:Int;
	public var strVal:Array<String>;
	public var strStart:Array<Int>;
	public var strTotal:Array<Int>;
	public var strPoolEnd:Int;

	public var nsCount:Int;
	public var nsKind:Array<Int>;
	public var nsName:Array<Int>;

	public var nssCount:Int;
	public var nsSet:Array<Array<Int>>;

	public var mnCountPos:Int;
	public var mnCount:Int;
	public var mns:Array<Mn>;
	public var mnPoolEnd:Int;

	public function new() {}
}




/**
 * Parses the ABC string/namespace/multiname pools and validates every
 * cross-pool index as it goes, so a corrupt file fails here rather than in a
 * later rewrite.
 */
class AbcPoolReader {
	public static function read(d:Bytes):AbcPools {
		var p = new AbcPools();
		var pos = new Pos(4); // minor/major
		var n = AbcIo.readU30(d, pos);
		for (i in 0...n - 1) AbcIo.readU30(d, pos); // ints
		n = AbcIo.readU30(d, pos);
		for (i in 0...n - 1) AbcIo.readU30(d, pos); // uints
		n = AbcIo.readU30(d, pos);
		pos.p += 8 * (n - 1); // doubles

		p.strCountPos = pos.p;
		p.strCount = AbcIo.readU30(d, pos);
		p.strVal = new Array<String>();
		p.strStart = new Array<Int>();
		p.strTotal = new Array<Int>();
		for (i in 0...p.strCount) p.strVal.push(null);
		for (i in 1...p.strCount) {
			var entry = pos.p;
			var len = AbcIo.readU30(d, pos);
			p.strVal[i] = d.getString(pos.p, len);
			pos.p += len;
			p.strStart[i] = entry;
			p.strTotal[i] = pos.p - entry;
		}
		p.strPoolEnd = pos.p;

		p.nsCount = AbcIo.readU30(d, pos);
		p.nsKind = new Array<Int>();
		p.nsName = new Array<Int>();
		for (i in 0...p.nsCount) {
			p.nsKind.push(0);
			p.nsName.push(0);
		}
		for (i in 1...p.nsCount) {
			p.nsKind[i] = d.get(pos.p++);
			p.nsName[i] = AbcIo.readU30(d, pos);
		}

		p.nssCount = AbcIo.readU30(d, pos);
		p.nsSet = new Array<Array<Int>>();
		for (i in 0...p.nssCount) p.nsSet.push(null);
		for (i in 1...p.nssCount) {
			var c = AbcIo.readU30(d, pos);
			var l = new Array<Int>();
			for (j in 0...c) {
				var ns = AbcIo.readU30(d, pos);
				bad(ns >= p.nsCount, 'ns set $i -> namespace out of range');
				l.push(ns);
			}
			p.nsSet[i] = l;
		}

		p.mnCountPos = pos.p;
		p.mnCount = AbcIo.readU30(d, pos);
		p.mns = new Array<Mn>();
		for (i in 0...p.mnCount) p.mns.push(null);
		for (i in 1...p.mnCount) {
			var m = new Mn();
			m.kind = d.get(pos.p++);
			switch (m.kind) {
				case 0x07, 0x0D:
					m.ns = AbcIo.readU30(d, pos);
					bad(m.ns >= p.nsCount, 'multiname $i namespace out of range');
					m.nameIdx = AbcIo.readU30(d, pos);
					bad(m.nameIdx >= p.strCount, 'multiname $i name out of range');
					m.hasName = true;
				case 0x0F, 0x10:
					m.nameIdx = AbcIo.readU30(d, pos);
					bad(m.nameIdx >= p.strCount, 'multiname $i name out of range');
					m.hasName = true;
				case 0x11, 0x12:
					// no operands
				case 0x09, 0x0E:
					m.nameIdx = AbcIo.readU30(d, pos);
					bad(m.nameIdx >= p.strCount, 'multiname $i name out of range');
					m.nsSet = AbcIo.readU30(d, pos);
					bad(m.nsSet >= p.nssCount, 'multiname $i ns set out of range');
					m.hasName = true;
				case 0x1B, 0x1C:
					m.nsSet = AbcIo.readU30(d, pos);
					bad(m.nsSet >= p.nssCount, 'multiname $i ns set out of range');
				case 0x1D:
					m.nameIdx = AbcIo.readU30(d, pos);
					bad(m.nameIdx >= p.strCount, 'typenamemultiname $i name out of range');
					m.hasName = true;
					var c = AbcIo.readU30(d, pos);
					m.params = new Array<Int>();
					for (j in 0...c) {
						var param = AbcIo.readU30(d, pos);
						bad(param >= p.mnCount, 'typename param $j out of range');
						m.params.push(param);
					}
				default:
					throw 'unsupported multiname kind ${StringTools.hex(m.kind)}';
			}
			p.mns[i] = m;
		}
		p.mnPoolEnd = pos.p;
		return p;
	}

	static function bad(condition:Bool, what:String):Void {
		if (condition) throw "deobf self-check: " + what;
	}
}




/** Re-serialises the ABC pools that deobfuscation modifies. */
class AbcPoolWriter {
	/** Rebuild the string pool, keeping untouched entries byte-for-byte. */
	public static function writeStrings(p:AbcPools, original:Bytes, rename:Array<String>, added:Array<String>):Bytes {
		var out = new BytesBuffer();
		AbcIo.writeU30(out, p.strCount + added.length);
		for (i in 1...p.strCount) {
			if (rename[i] == null) {
				out.addBytes(original, p.strStart[i], p.strTotal[i]);
			} else {
				var b = Bytes.ofString(rename[i]);
				AbcIo.writeU30(out, b.length);
				out.addBytes(b, 0, b.length);
			}
		}
		for (a in added) {
			var b = Bytes.ofString(a);
			AbcIo.writeU30(out, b.length);
			out.addBytes(b, 0, b.length);
		}
		return out.getBytes();
	}

	/** Rebuild the multiname pool after the class-name remapping. */
	public static function writeMultinames(p:AbcPools):Bytes {
		var out = new BytesBuffer();
		AbcIo.writeU30(out, p.mnCount);
		for (i in 1...p.mnCount) {
			var m = p.mns[i];
			out.addByte(m.kind);
			switch (m.kind) {
				case 0x07, 0x0D:
					AbcIo.writeU30(out, m.ns);
					AbcIo.writeU30(out, m.nameIdx);
				case 0x0F, 0x10:
					AbcIo.writeU30(out, m.nameIdx);
				case 0x11, 0x12:
					// no operands
				case 0x09, 0x0E:
					AbcIo.writeU30(out, m.nameIdx);
					AbcIo.writeU30(out, m.nsSet);
				case 0x1B, 0x1C:
					AbcIo.writeU30(out, m.nsSet);
				case 0x1D:
					AbcIo.writeU30(out, m.nameIdx);
					AbcIo.writeU30(out, m.params.length);
					for (q in m.params) AbcIo.writeU30(out, q);
			}
		}
		return out.getBytes();
	}
}

class Mn {
	public var kind:Int = 0;
	public var ns:Int = 0;
	public var nameIdx:Int = 0;
	public var nsSet:Int = 0;
	public var params:Array<Int> = [];
	public var hasName:Bool = false;

	public function new() {}
}



/** Cursor over an ABC byte array (the pools are all u30-prefixed). */
class Pos {
	public var p:Int;

	public function new(p:Int) {
		this.p = p;
	}
}
