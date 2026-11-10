package ob.swf;

import haxe.io.Bytes;
import haxe.crypto.Adler32;
import haxe.io.BytesBuffer;
import haxe.zip.Compress;
import haxe.zip.Uncompress;

class Counters {
	public var renamed:Int = 0;
	public var stale:Int = 0;

	public function new() {}
}

/**
 * SymbolClass/ExportAssets/ImportAssets carry dotted class names outside the
 * ABC. They have to be renamed together with the ABC when deobfuscating, or the
 * player is handed symbols pointing at classes that no longer exist.
 */
class SymbolTags {
	public static function rewrite(body:Bytes, map:Map<String, String>, log:String->Void = null):Bytes {
		if (map == null || map.keys().hasNext() == false) return body;
		var pos = Tags.rectLen(body) + 2 + 2;
		var out = new BytesBuffer();
		out.addBytes(body, 0, pos);
		var tags = 0;
		var c = new Counters();
		while (pos < body.length) {
			var tagStart = pos;
			var h = Le.u16(body, pos);
			pos += 2;
			var tid = h >> 6, ln = h & 0x3F;
			if (ln == 0x3F) {
				ln = Le.i32(body, pos);
				pos += 4;
			}
			var hdr = pos - tagStart, dataStart = pos;
			if (tid == 0) {
				out.addBytes(body, tagStart, hdr + ln);
				pos = dataStart + ln;
				break;
			}
			var names = (tid == 76 || tid == 56 || tid == 57 || tid == 71)
				? rewriteNameList(body, tid, dataStart, ln, map, c)
				: null;
			if (names == null) out.addBytes(body, tagStart, hdr + ln);
			else {
				writeTag(out, tid, names);
				tags++;
			}
			pos = dataStart + ln;
		}
		if (pos < body.length) out.addBytes(body, pos, body.length - pos); // keep anything past End
		if (c.renamed > 0 && log != null) {
			var extra = c.stale > 0 ? '; ${c.stale} obfuscated name(s) had no mapping and were left alone.' : ".";
			log('SWF symbol table updated: ${c.renamed} class name(s) rewritten in $tags tag(s)$extra');
		}
		return out.getBytes();
	}

	static function writeTag(s:BytesBuffer, tid:Int, data:Bytes):Void {
		var n = data.length;
		if (n < 0x3F) {
			var h = (tid << 6) | n;
			s.addByte(h & 0xFF);
			s.addByte((h >>> 8) & 0xFF);
		} else {
			var h = (tid << 6) | 0x3F;
			s.addByte(h & 0xFF);
			s.addByte((h >>> 8) & 0xFF);
			s.addByte(n & 0xFF);
			s.addByte((n >>> 8) & 0xFF);
			s.addByte((n >>> 16) & 0xFF);
			s.addByte((n >>> 24) & 0xFF);
		}
		s.addBytes(data, 0, n);
	}

	/**
	 * SymbolClass (76) and ExportAssets (56): u16 count, then (u16 symbol, STR
	 * name) pairs. ImportAssets (57) / ImportAssets2 (71) start with a url [and
	 * a flags byte] and then the same list. Returns null when nothing needed
	 * renaming or when the tag is not exactly the shape assumed above, in which
	 * case it is copied untouched rather than corrupted.
	 */
	static function rewriteNameList(b:Bytes, tid:Int, start:Int, len:Int, map:Map<String, String>, c:Counters):Bytes {
		if (tid != 76 && tid != 56 && tid != 57 && tid != 71) return null;
		var p = start, end = start + len;
		var o = new BytesBuffer();

		function str(s:String):Void {
			var y = Bytes.ofString(s);
			o.addBytes(y, 0, y.length);
			o.addByte(0);
		}

		function read():String {
			var e = Tags.indexOfByte(b, 0, p);
			if (e < 0 || e >= end) throw "unterminated string in SWF name tag.";
			var s = b.getString(p, e - p);
			p = e + 1;
			return s;
		}

		var url:String = null;
		var flags = 0;
		if (tid == 57 || tid == 71) {
			url = read();
			if (tid == 71) flags = b.get(p++);
		}
		if (p + 2 > end) return null;
		var count = Le.u16(b, p);
		p += 2;
		var ids = new Array<Int>();
		var names = new Array<String>();
		for (i in 0...count) {
			if (p + 2 > end) return null;
			ids.push(Le.u16(b, p));
			p += 2;
			names.push(read());
		}
		if (p != end) return null;

		var changed = false;
		for (i in 0...count) {
			if (map.exists(names[i])) {
				var nn = map.get(names[i]);
				if (nn != names[i]) {
					names[i] = nn;
					c.renamed++;
					changed = true;
					continue;
				}
			}
			if (hasGlyph(names[i])) c.stale++;
		}
		if (!changed) return null;

		if (url != null) {
			str(url);
			if (tid == 71) o.addByte(flags);
		}
		o.addByte(count & 0xFF);
		o.addByte((count >>> 8) & 0xFF);
		for (i in 0...count) {
			var id = ids[i];
			o.addByte(id & 0xFF);
			o.addByte((id >>> 8) & 0xFF);
			str(names[i]);
		}
		return o.getBytes();
	}

	static function hasGlyph(s:String):Bool {
		for (i in 0...s.length) if (s.charCodeAt(i) > 0x7F) return true;
		return false;
	}
}


