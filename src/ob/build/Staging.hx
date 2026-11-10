package ob.build;

/** Rewrites the packaged AIR descriptor's window size. */
class Descriptor {
	/**
	 * The PC window size is a build setting, not a compile-time constant:
	 * rewrite the packaged descriptor so AIR opens the window at the requested
	 * size. The game lays out against stage.stageWidth/Height (screen-fit-window),
	 * so a bigger or wider window changes the layout instead of cropping it.
	 */
	public static function setWindowSize(descPath:String, s:ObSettings, log:String->Void, resizable:Bool):Void {
		var xml = Util.readText(descPath);
		var replaced = 0;
		var outer = new EReg("<initialWindow>[\\s\\S]*?</initialWindow>", "");
		var widthRe = new EReg("<width>\\s*\\d+\\s*</width>", "");
		var heightRe = new EReg("<height>\\s*\\d+\\s*</height>", "");
		var resRe = new EReg("<resizable>\\s*(?:true|false)\\s*</resizable>", "");
		var maxRe = new EReg("<maximizable>\\s*(?:true|false)\\s*</maximizable>", "");

		var patched = outer.map(xml, function(m:EReg):String {
			var body = m.matched(0);
			body = widthRe.map(body, function(_:EReg):String {
				replaced++;
				return "<width>" + s.windowWidth + "</width>";
			});
			body = heightRe.map(body, function(_:EReg):String {
				replaced++;
				return "<height>" + s.windowHeight + "</height>";
			});
			if (replaced != 2) {
				throw 'Descriptor ${s.appDesc}: expected one <width> and one <height> inside <initialWindow>, found $replaced.';
			}
			var flag = resizable ? "true" : "false";
			var res = 0, max = 0;
			body = resRe.map(body, function(_:EReg):String {
				res++;
				return "<resizable>" + flag + "</resizable>";
			});
			body = maxRe.map(body, function(_:EReg):String {
				max++;
				return "<maximizable>" + flag + "</maximizable>";
			});
			if (res == 0) body = StringTools.replace(body, "</height>", "</height>\n        <resizable>" + flag + "</resizable>");
			if (max == 0) body = StringTools.replace(body, "</height>", "</height>\n        <maximizable>" + flag + "</maximizable>");
			return body;
		});
		if (replaced != 2) {
			throw 'Descriptor ${s.appDesc}: expected one <width> and one <height> inside <initialWindow>, found $replaced.';
		}
		Util.writeText(descPath, patched);
		log('Window size: ${s.windowWidth}x${s.windowHeight} (application-win.xml), resizable/maximizable=$resizable.');
	}
}




