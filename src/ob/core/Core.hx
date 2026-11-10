package ob.core;

import haxe.io.Bytes;

class ByteBuf {
	var b:Bytes;
	var len:Int;

	public function new(?capacity:Int = 256) {
		if (capacity < 1) capacity = 1;
		b = Bytes.alloc(capacity);
		len = 0;
	}

	public static function fromBytes(src:Bytes):ByteBuf {
		var r = new ByteBuf(src.length < 1 ? 1 : src.length);
		r.addBytes(src, 0, src.length);
		return r;
	}

	public var length(get, never):Int;

	inline function get_length():Int {
		return len;
	}

	inline public function get(i:Int):Int {
		if (i < 0 || i >= len) throw 'ByteBuf read out of range @$i (len $len)';
		return b.get(i);
	}

	inline public function set(i:Int, v:Int):Void {
		if (i < 0 || i >= len) throw 'ByteBuf write out of range @$i (len $len)';
		b.set(i, v & 0xFF);
	}

	public function addByte(v:Int):Void {
		ensure(len + 1);
		b.set(len, v & 0xFF);
		len++;
	}

	public function addBytes(src:Bytes, pos:Int, n:Int):Void {
		if (n <= 0) return;
		ensure(len + n);
		b.blit(len, src, pos, n);
		len += n;
	}

	public function append(src:Bytes):Void {
		addBytes(src, 0, src.length);
	}

	public function addArray(a:Array<Int>):Void {
		ensure(len + a.length);
		for (v in a) b.set(len++, v & 0xFF);
	}

	public function toBytes():Bytes {
		return b.sub(0, len);
	}

	public function sub(pos:Int, n:Int):Bytes {
		if (pos < 0 || n < 0 || pos + n > len) throw 'ByteBuf sub out of range @$pos+$n (len $len)';
		return b.sub(pos, n);
	}

	public function insert(pos:Int, src:Bytes, srcPos:Int, srcLen:Int):Void {
		if (pos < 0 || pos > len) throw 'ByteBuf insert out of range @$pos (len $len)';
		if (srcLen == 0) return;
		var nb = Bytes.alloc(len + srcLen);
		nb.blit(0, b, 0, pos);
		nb.blit(pos, src, srcPos, srcLen);
		nb.blit(pos + srcLen, b, pos, len - pos);
		b = nb;
		len += srcLen;
	}

	public function remove(pos:Int, n:Int):Void {
		if (pos < 0 || n < 0 || pos + n > len) throw 'ByteBuf remove out of range @$pos+$n (len $len)';
		if (n == 0) return;
		var nb = Bytes.alloc(len - n);
		nb.blit(0, b, 0, pos);
		nb.blit(pos, b, pos + n, len - pos - n);
		b = nb;
		len -= n;
	}

	function ensure(n:Int):Void {
		if (n <= b.length) return;
		var cap = b.length;
		while (cap < n) cap *= 2;
		var nb = Bytes.alloc(cap);
		nb.blit(0, b, 0, len);
		b = nb;
	}
}



/** What the supported game build looks like (target.json next to the exe). */
class PatchTarget {
	public var swfAssetPath:String;
	public var swfSha256:String;
	public var abcName:String;

	public function new(swfAssetPath:String, swfSha256:String, abcName:String) {
		this.swfAssetPath = swfAssetPath;
		this.swfSha256 = swfSha256;
		this.abcName = abcName;
	}

	public function toString():String {
		return '${abcName} / ${swfSha256}';
	}
}


