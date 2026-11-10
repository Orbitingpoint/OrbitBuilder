package ob.swf;

import haxe.io.Bytes;

/** Checks that the input SWF is the supported game version*/
class SwfCheck {
	public static function check(swf:Bytes, target:PatchTarget, log:String->Void):Void {
		var sha = Patcher.sha256(swf);
		if (!Util.eqi(sha, target.swfSha256)) {
			throw 'SWF sha256 $sha does not match supported version ${target.swfSha256}. Modding aborted safely.';
		}
		log('SWF identity OK (${sha.substr(0, 16)}...).');
	}
}
