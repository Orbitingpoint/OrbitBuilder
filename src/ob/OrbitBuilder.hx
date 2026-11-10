package ob;

import haxe.ui.HaxeUIApp;

class OrbitBuilder {
	static function main():Void {
		var appDir = Util.baseDir();
		Util.mkdirs(ModStore.dir(appDir));

		try {
			Native.hideConsole();
			var app = new HaxeUIApp();
			app.ready(function() {
				app.icon = "icon.ico";
				app.addComponent(new MainView());
				app.start();
			});
		} catch (e:Dynamic) {
			Sys.println("FAILED: " + Util.describe(e));
			Sys.exit(1);
		}
	}
}
