package ob.swf;

import haxe.io.Bytes;
import haxe.crypto.Adler32;
import haxe.io.BytesBuffer;
import haxe.zip.Compress;
import haxe.zip.Uncompress;

/**
 * SWF facade kept for the rest of the builder. The low-level parts are in
 * `ob.Swf.Cws` (zlib/CWS container) and `ob.Swf.Tags` (tag walking, DoABC
 * splicing and symbol-table renaming).
 */
class Swf {
	public static function parseCws(file:Bytes):{ver:Int, body:Bytes} {
		return Cws.parse(file);
	}

	public static function toCws(ver:Int, body:Bytes):Bytes {
		return Cws.toCws(ver, body);
	}

	public static function findAbc(body:Bytes, name:String):AbcLoc {
		return Tags.findAbc(body, name);
	}

	public static function listAbc(body:Bytes):Array<AbcLoc> {
		return Tags.listAbc(body);
	}

	public static function replaceAbc(body:Bytes, loc:AbcLoc, newAbc:Bytes):Bytes {
		return Tags.replaceAbc(body, loc, newAbc);
	}

	public static function countTags(body:Bytes):Int {
		return Tags.countTags(body);
	}

	public static function rewriteTagNames(body:Bytes, map:Map<String, String>, log:String->Void = null):Bytes {
		return SymbolTags.rewrite(body, map, log);
	}

	public static function validateCws(file:Bytes, log:String->Void = null):Void {
		if (file.length < 8 || file.get(0) != 0x43 || file.get(1) != 0x57 || file.get(2) != 0x53) {
			throw "Not a CWS SWF.";
		}
		var parsed = Cws.parse(file);
		var declared = Le.u32(file, 4);
		if (declared != 8 + parsed.body.length) {
			throw 'SWF FileLength mismatch: header says $declared, actual ${8 + parsed.body.length}.';
		}
		var tags = Tags.countTags(parsed.body);
		if (tags < 100) throw 'Suspicious tag count $tags; SWF likely corrupt.';
		if (log != null) log('SWF validated: v${parsed.ver}, $tags tags, FileLength OK.');
	}
}




/** Little-endian integer helpers for SWF and ZIP structures. */
class Le {
	public static inline function u16(b:Bytes, p:Int):Int {
		return b.get(p) | (b.get(p + 1) << 8);
	}

	public static inline function u32(b:Bytes, p:Int):Int {
		return b.get(p) | (b.get(p + 1) << 8) | (b.get(p + 2) << 16) | (b.get(p + 3) << 24);
	}

	public static inline function i32(b:Bytes, p:Int):Int {
		return u32(b, p);
	}

	public static function writeU32(b:Bytes, p:Int, v:Int):Void {
		b.set(p, v & 0xFF);
		b.set(p + 1, (v >>> 8) & 0xFF);
		b.set(p + 2, (v >>> 16) & 0xFF);
		b.set(p + 3, (v >>> 24) & 0xFF);
	}
}




/**
 * zlib/CWS container support.
 *
 * The SWF body is byte-for-byte data; only the wrapper is compressed here. The
 * reference tool re-compressed with .NET's "optimal" setting, while this port
 * uses zlib level 9, so the inflated body is identical but the compressed
 * stream is not.
 */
class Cws {
	public static function parse(file:Bytes):{ver:Int, body:Bytes} {
		if (file.length < 8 || file.get(0) != 0x43 || file.get(1) != 0x57 || file.get(2) != 0x53) {
			throw "Not a CWS SWF (only compressed SWFs are supported).";
		}
		var ver = file.get(3);
		var declared = Le.u32(file, 4);
		var bodyLen = declared - 8;
		// zlib header 2 bytes + raw deflate + adler32 4 bytes
		if (file.length < 14) throw "Not a CWS SWF (truncated zlib stream).";
		var comp = file.sub(10, file.length - 10 - 4);
		// The declared length is only a sizing hint: a bad header should not stop
		// us from reading a SWF the reference tool accepted. ValidateCws still
		// reports the mismatch afterwards.
		var hint = bodyLen > 0 && bodyLen < (1 << 30) ? bodyLen : 0;
		return {ver: ver, body: inflateRaw(comp, hint)};
	}

	/**
	 * Raw-inflate (windowBits -15). `hint` pre-sizes the output buffer when the
	 * caller knows the expected length; the stream is grown in place if the hint
	 * was too small, so a lying header cannot truncate the result.
	 *
	 * hxcpp's Uncompress.execute reports cumulative total_in/total_out, so the
	 * deltas below (rather than the raw fields) drive the loop.
	 */
	public static function inflateRaw(src:Bytes, hint:Int = 0):Bytes {
		var chunk = hint >= 1024 && hint < (1 << 30) ? hint : (1 << 16);
		var tmp = Bytes.alloc(chunk);
		var out = new BytesBuffer();
		var u = new Uncompress(-15);
		var pos = 0;
		var total = 0;
		try {
			while (true) {
				var r = u.execute(src, pos, tmp, 0);
				var produced = r.write - total;
				if (produced > 0) out.addBytes(tmp, 0, produced);
				pos = r.read;
				total = r.write;
				if (r.done) break;
				if (produced == 0 && pos >= src.length) break; // truncated input
			}
		} catch (e:Dynamic) {
			u.close();
			throw e;
		}
		u.close();
		return out.getBytes();
	}

	public static function toCws(ver:Int, body:Bytes):Bytes {
		var z = Compress.run(body, 9);
		var raw = z.sub(2, z.length - 6);
		var out = Bytes.alloc(8 + 2 + raw.length + 4);
		out.set(0, 0x43); // C
		out.set(1, 0x57); // W
		out.set(2, 0x53); // S
		out.set(3, ver);
		Le.writeU32(out, 4, 8 + body.length);
		out.set(8, 0x78);
		out.set(9, 0x9C);
		out.blit(10, raw, 0, raw.length);
		var adler = Adler32.make(body);
		var p = 10 + raw.length;
		out.set(p, (adler >>> 24) & 0xFF);
		out.set(p + 1, (adler >>> 16) & 0xFF);
		out.set(p + 2, (adler >>> 8) & 0xFF);
		out.set(p + 3, adler & 0xFF);
		return out;
	}
}




/** Location of one DoABC tag inside an uncompressed SWF body. */
class AbcLoc {
	public var tagStart:Int;
	public var longForm:Bool;
	public var contentStart:Int;
	public var contentLen:Int;
	public var abcStart:Int;
	public var name:String;

	public function new(tagStart:Int, longForm:Bool, contentStart:Int, contentLen:Int, abcStart:Int, name:String) {
		this.tagStart = tagStart;
		this.longForm = longForm;
		this.contentStart = contentStart;
		this.contentLen = contentLen;
		this.abcStart = abcStart;
		this.name = name;
	}
}

/** SWF tag walking and DoABC extraction/splicing. */
class Tags {
	public static inline function rectLen(body:Bytes):Int {
		var nbits = body.get(0) >> 3;
		return (5 + 4 * nbits + 7) >> 3;
	}

	public static function findAbc(body:Bytes, name:String):AbcLoc {
		for (a in listAbc(body)) if (a.name == name) return a;
		throw '$name ABC not found; unsupported build.';
	}

	public static function listAbc(body:Bytes):Array<AbcLoc> {
		var list = new Array<AbcLoc>();
		var pos = rectLen(body) + 2 + 2;
		while (pos < body.length) {
			var hs = pos;
			var h = Le.u16(body, pos);
			pos += 2;
			var tid = h >> 6, ln = h & 0x3F;
			var longForm = false;
			if (ln == 0x3F) {
				ln = Le.i32(body, pos);
				pos += 4;
				longForm = true;
			}
			if (tid == 0) break;
			if (tid == 82) {
				var e = indexOfByte(body, 0, pos + 4);
				if (e < 0) throw "Unterminated DoABC name.";
				var name = body.getString(pos + 4, e - pos - 4);
				list.push(new AbcLoc(hs, longForm, pos, ln, e + 1, name));
			}
			pos += ln;
		}
		return list;
	}

	public static function indexOfByte(b:Bytes, value:Int, from:Int):Int {
		var i = from;
		while (i < b.length) {
			if (b.get(i) == value) return i;
			i++;
		}
		return -1;
	}

	public static function replaceAbc(body:Bytes, loc:AbcLoc, newAbc:Bytes):Bytes {
		var out = ByteBuf.fromBytes(body);
		var rel = loc.abcStart;
		var oldAbcLen = loc.contentStart + loc.contentLen - loc.abcStart;
		var delta = newAbc.length - oldAbcLen;
		out.remove(rel, oldAbcLen);
		out.insert(rel, newAbc, 0, newAbc.length);
		var newLen = loc.contentLen + delta;
		if (loc.longForm) {
			writeU32At(out, loc.tagStart + 2, newLen);
		} else if (newLen < 0x3F) {
			var h = out.get(loc.tagStart) | (out.get(loc.tagStart + 1) << 8);
			h = (h & ~0x3F) | newLen;
			out.set(loc.tagStart, h & 0xFF);
			out.set(loc.tagStart + 1, (h >>> 8) & 0xFF);
		} else {
			throw "Tag grew past short form; unsupported.";
		}
		return out.toBytes();
	}

	static function writeU32At(b:ByteBuf, p:Int, v:Int):Void {
		b.set(p, v & 0xFF);
		b.set(p + 1, (v >>> 8) & 0xFF);
		b.set(p + 2, (v >>> 16) & 0xFF);
		b.set(p + 3, (v >>> 24) & 0xFF);
	}

	public static function countTags(body:Bytes):Int {
		var n = 0, pos = rectLen(body) + 2 + 2;
		while (pos < body.length) {
			var h = Le.u16(body, pos);
			pos += 2;
			var tid = h >> 6, ln = h & 0x3F;
			if (ln == 0x3F) {
				ln = Le.i32(body, pos);
				pos += 4;
			}
			if (tid == 0) break;
			n++;
			pos += ln;
		}
		return n;
	}
}




