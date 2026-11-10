package ob.core;

import haxe.io.Bytes;
import haxe.zip.Uncompress;

/** One file entry in a zip central directory. */
class ZipEntry {
	public var name:String;
	public var method:Int;
	public var csize:Int;
	public var usize:Int;
	public var dataOffset:Int;

	public function new(name:String, method:Int, csize:Int, usize:Int, dataOffset:Int) {
		this.name = name;
		this.method = method;
		this.csize = csize;
		this.usize = usize;
		this.dataOffset = dataOffset;
	}
}

/**
 * Read-only ZIP access through the central directory.
 *
 * Reading only selected entries avoids a huge temporary extraction, and using
 * the central directory instead of walking local headers means an APK signing
 * block (which sits between the last file and the central directory) does not
 * stop the reader. The same reader handles mod zips.
 */
class ZipFile {
	public var path(default, null):String;
	public var entries(default, null):Map<String, ZipEntry>;
	var bytes:Bytes;

	public function new(path:String) {
		this.path = path;
		bytes = Util.readBytes(path);
		entries = new Map<String, ZipEntry>();
		readCentralDirectory();
	}

	public static function isZip(path:String):Bool {
		try {
			if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return false;
			var f = sys.io.File.read(path, true);
			var sig = Bytes.alloc(2);
			f.readFullBytes(sig, 0, 2);
			f.close();
			return sig.get(0) == 0x50 && sig.get(1) == 0x4B;
		} catch (e:Dynamic) {
			return false;
		}
	}

	public function has(name:String):Bool {
		return entries.exists(name);
	}

	/** Reads (and, for deflated entries, inflates) one entry. */
	public function read(name:String):Bytes {
		var e = entries.get(name);
		if (e == null) throw 'ZIP lacks $name.';
		if (e.usize == 0) return Bytes.alloc(0);
		if (e.method == 0) return bytes.sub(e.dataOffset, e.csize);
		var comp = bytes.sub(e.dataOffset, e.csize);
		var out = Bytes.alloc(e.usize);
		var u = new Uncompress(-15);
		var r = u.execute(comp, 0, out, 0);
		u.close();
		if (!r.done || r.write != e.usize) throw 'Corrupt ZIP entry $name.';
		return out;
	}

	function readCentralDirectory():Void {
		var b = bytes;
		var eocd = -1;
		var i = b.length - 22;
		var min = b.length - 65557;
		if (min < 0) min = 0;
		while (i >= min) {
			if (u32(b, i) == 0x06054B50 && u16(b, i + 20) == b.length - i - 22) {
				eocd = i;
				break;
			}
			i--;
		}
		if (eocd < 0) throw 'Not a ZIP (no end-of-central-directory): $path';

		var count = u16(b, eocd + 10);
		var p = u32(b, eocd + 16);
		for (n in 0...count) {
			if (u32(b, p) != 0x02014B50) throw 'Corrupt ZIP central directory at $p.';
			var method = u16(b, p + 10);
			var csize = u32(b, p + 20);
			var usize = u32(b, p + 24);
			var nameLen = u16(b, p + 28);
			var extraLen = u16(b, p + 30);
			var commentLen = u16(b, p + 32);
			var local = u32(b, p + 42);
			var name = b.getString(p + 46, nameLen);

			if (csize == 0xFFFFFFFF || usize == 0xFFFFFFFF || local == 0xFFFFFFFF) {
				throw 'ZIP64 archives are not supported: $name';
			}
			if (method != 0 && method != 8) throw 'Unsupported ZIP compression $method for $name.';
			if (u32(b, local) != 0x04034B50) throw 'Corrupt ZIP local header for $name.';
			var dataOffset = local + 30 + u16(b, local + 26) + u16(b, local + 28);
			entries.set(name, new ZipEntry(name, method, csize, usize, dataOffset));
			p += 46 + nameLen + extraLen + commentLen;
		}
	}

	inline static function u16(b:Bytes, p:Int):Int {
		return b.get(p) | (b.get(p + 1) << 8);
	}

	inline static function u32(b:Bytes, p:Int):Int {
		return b.get(p) | (b.get(p + 1) << 8) | (b.get(p + 2) << 16) | (b.get(p + 3) << 24);
	}
}
