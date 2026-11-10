package ob.gui;

import haxe.ui.containers.VBox;
import haxe.ui.data.ArrayDataSource;
import haxe.ui.events.UIEvent;
import haxe.ui.components.CheckBox;
import haxe.ui.components.Label;
import haxe.ui.containers.HBox;
import haxe.ui.events.MouseEvent;
import haxe.ui.components.TextArea;
import haxe.ui.core.Component;
import haxe.ui.util.Timer;
import sys.thread.Mutex;
import haxe.ui.components.TextField;
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.containers.dialogs.Dialog.DialogButton;
import haxe.ui.containers.dialogs.Dialog.DialogEvent;
import haxe.ui.containers.dialogs.OpenFileDialog;
import sys.FileSystem;
import sys.thread.Thread;

class MainView extends MainLayout {
	var settings:SettingsController;
	var mods:ModController;
	var inputPath:String;
	var busy = false;

	public function new() {
		super();
		var appDir = Util.baseDir();
		settings = new SettingsController(appDir, deobfCheck, winField, log);
		mods = new ModController(appDir, modPanel, log);

		modPanel.onToggle = mods.toggle;
		modPanel.onSelect = function(_) {};
		logView.onActionDone = onActionDone;
		onToolPaths = openToolSettings;
		onCheckTools = function() checkTools(false);
		onOpenSettings = function() openFolder(Util.baseDir());
		browseBtn.onClick = function(_) browse();
		buildBtn.onClick = function(_) runBuild();
		decompBtn.onClick = function(_) runDecompile();
		cfgBtn.onClick = function(_) mods.configureSelected();
		toolPathsBtn.onClick = function(_) openToolSettings();
		fitBtn.onClick = function(_) settings.fitToScreen();
		saveBtn.onClick = function(_) {
			settings.save();
			log("Settings saved.");
		};
		checkTools(true);
	}

	function browse():Void {
		var d = new OpenFileDialog({
			title: "Select World Flipper APK or game SWF",
			extensions: [
				{label: "World Flipper APK", extension: "apk"},
				{label: "Game SWF", extension: "swf"}
			]
		}, function(button, files) {
			if (button == DialogButton.OK && files != null && files.length > 0) setInput(files[0].fullPath);
		});
		d.show();
	}

	function setInput(path:String):Void {
		if (path == null || path.length == 0) return;
		if (!FileSystem.exists(path)) {
			log("File not found: " + path);
			return;
		}
		var ext = Util.extOf(path);
		if (!Util.eqi(ext, ".swf") && !Util.eqi(ext, ".apk")) {
			log("Not an APK or SWF file: " + path);
			return;
		}
		inputPath = path;
		swfField.text = path;
		try {
			mods.load();
			log('Game selected: ${Util.fileName(path)} (${FileSystem.stat(path).size} bytes).');
		} catch (e:Dynamic) {
			log("ERROR: " + Util.describe(e));
		}
	}

	/** Opens the dialog that owns every external tool path, then saves on OK. */
	function openToolSettings():Void {
		if (busy) {
			log("Wait for the current operation to finish before changing settings.");
			return;
		}
		var d = new ToolSettingsDialog(Util.baseDir(), settings.current());
		d.onSaved = function(s) {
			settings.apply(s);
			settings.save();
			log("Tool settings saved: " + ObSettings.filePath(Util.baseDir()));
			checkTools(true);
		};
		d.showDialog();
	}

	/** Logs one line per required tool/input, or just a summary when quiet. */
	function checkTools(quiet:Bool = false):Void {
		var list = ObSettings.check(settings.current());
		var missing = 0;
		if (!quiet) log("Tool setup check:");
		for (status in list) {
			if (!status.ok) missing++;
			if (!quiet) log((status.ok ? "  OK       " : "  MISSING  ") + status.label + (status.ok ? "" : " - " + status.detail));
		}
		if (missing == 0) log("All required tools and paths look good.");
		else log('$missing required item(s) missing. Open Tools > Tool paths and build settings to fix them.');
	}

	function openFolder(dir:String):Void {
		try Sys.command("explorer.exe", [dir])
		catch (e:Dynamic) log("Could not open folder: " + Util.describe(e));
	}

	function runBuild():Void {
		if (busy) return;
		if (inputPath == null || !FileSystem.exists(inputPath)) {
			log("Select the game APK or SWF first.");
			return;
		}
		if (mods.target == null) {
			log("Target manifest not loaded.");
			return;
		}
		var s = settings.current();
		setBusy(true);
		log("----------------------------------------");
		log("Build Windows start.");
		var input = inputPath;
		var t = mods.target;
		var list = mods.mods;
		Thread.create(function() {
			try {
				var r = PcBuild.run(input, list, t, s, function(line) logView.log(line));
				logView.finish(null, r);
			} catch (e:Dynamic) {
				logView.finish(Util.describe(e), null);
			}
		});
	}

	function runDecompile():Void {
		if (busy) return;
		if (inputPath == null || !FileSystem.exists(inputPath)) {
			log("Select the game APK or SWF first.");
			return;
		}
		var s = settings.current();
		setBusy(true);
		log("----------------------------------------");
		log("Decompile start.");
		var input = inputPath;
		Thread.create(function() {
			try {
				var r = Decompiler.run(input, s, function(line) logView.log(line));
				logView.finish(null, r);
			} catch (e:Dynamic) {
				logView.finish(Util.describe(e), null);
			}
		});
	}

	function setBusy(value:Bool):Void {
		busy = value;
		disabled = value;
	}

	function onActionDone(error:String, result:String):Void {
		setBusy(false);
		if (error != null) log("FAILED: " + error);
		else log("DONE: " + result);
	}

	function log(s:String):Void {
		logView.log(s);
	}
}



