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


class SettingsController {
	var appDir:String;
	var deobfCheck:CheckBox;
	var winField:TextField;
	var log:String->Void;

	var settings:ObSettings;

	public function new(appDir:String, deobfCheck:CheckBox, winField:TextField, log:String->Void) {
		this.appDir = appDir;
		this.deobfCheck = deobfCheck;
		this.winField = winField;
		this.log = log;
		load();
	}

	function load():Void {
		apply(ObSettings.load(appDir));
	}

	public function apply(s:ObSettings):Void {
		settings = s.copy();
		deobfCheck.selected = settings.deobfuscate;
		winField.text = settings.windowWidth + "x" + settings.windowHeight;
	}

	public function current():ObSettings {
		var wh = windowSize();
		var s = settings.copy();
		s.deobfuscate = deobfCheck.selected;
		s.windowWidth = wh.w;
		s.windowHeight = wh.h;
		return s;
	}

	public function save():Void {
		settings = current();
		ObSettings.save(appDir, settings);
	}

	function windowSize():{w:Int, h:Int} {
		var t = StringTools.trim(winField.text);
		var re = new EReg("^(\\d{2,5})\\s*[xX*]\\s*(\\d{2,5})$", "");
		if (re.match(t)) return {w: Std.parseInt(re.matched(1)), h: Std.parseInt(re.matched(2))};
		var s = settings;
		log('Window size \'$t\' is not WxH; keeping ${s.windowWidth}x${s.windowHeight}.');
		winField.text = s.windowWidth + "x" + s.windowHeight;
		return {w: s.windowWidth, h: s.windowHeight};
	}

	public function fitToScreen():Void {
		var wh = windowSize();
		var sw = hx.widgets.SystemSettings.getMetric(hx.widgets.SystemMetric.SCREEN_X);
		var sh = hx.widgets.SystemSettings.getMetric(hx.widgets.SystemMetric.SCREEN_Y);
		var nh = Std.int(Math.max(480, sh - 80));
		var nw = Std.int(Math.round(nh * wh.w / wh.h));
		var maxW = Std.int(Math.max(360, sw - 48));
		if (nw > maxW) {
			nw = maxW;
			nh = Std.int(Math.round(nw * wh.h / wh.w));
		}
		winField.text = nw + "x" + nh;
		log('Window size ${nw}x${nh} - fits a ${sw}x${sh} desktop, aspect kept from ${wh.w}x${wh.h}.');
	}
}




/**
 * Owns the loaded mods and their list-pane interactions: loading from mods/,
 */
class ModController {
	public var mods(default, null):Array<Mod> = [];
	public var target(default, null):PatchTarget;

	var appDir:String;
	var panel:ModPanel;
	var log:String->Void;

	public function new(appDir:String, panel:ModPanel, log:String->Void) {
		this.appDir = appDir;
		this.panel = panel;
		this.log = log;
	}

	public function load():Void {
		target = Patcher.loadTarget(appDir);
		ModStore.extractDefaults(appDir, log);
		mods = ModStore.load(appDir, log);
		panel.populate(mods);
	}

	public function toggle(index:Int, enabled:Bool):Void {
		if (index < 0 || index >= mods.length) return;
		try ModConfig.setEnabled(mods[index].id, enabled)
		catch (e:Dynamic) log("Could not save toggle: " + Util.describe(e));
	}

	public function configureSelected():Void {
		var i = panel.selectedIndex;
		if (i < 0 || i >= mods.length) {
			log("Select a mod in the list, then click Configure.");
			return;
		}
		var m = mods[i];
		if (m.config.length == 0) {
			log("'" + m.name + "' has no configurable settings.");
			log("  Add a config[] entry to mod.json inside " + m.file);
			return;
		}
		var d = new ConfigDialog(m.id, m.name, m.config);
		d.onSaved = function() log('Saved settings for ${m.id} -> mods.json');
		d.showDialog();
	}
}




/**
 * Edits the values a mod declares in mod.json
 */
class ConfigDialog extends Dialog {
	var patchId:String;
	var specs:Array<ConfigSpec>;
	var boxes:Array<TextField> = [];

	public var onSaved:Void->Void;

	public function new(patchId:String, patchName:String, specs:Array<ConfigSpec>) {
		super();
		this.patchId = patchId;
		this.specs = specs;
		title = "Configure - " + patchName;
		autoWidth = false;
		autoHeight = false;
		width = 760;
		height = Std.int(Math.min(620, 150 + Math.max(1, specs.length) * 34));
		closable = true;
		centerDialog = true;
		buttons = DialogButton.OK | DialogButton.CANCEL;

		dialogContent.padding = 8;
		dialogContent.styleString = "spacing: 4px;";

		for (s in specs) {
			var row = new HBox();
			row.percentWidth = 100;
			row.height = 28;
			row.styleString = "spacing: 6px;";

			var key = new Label();
			key.text = s.key;
			key.width = 150;
			row.addComponent(key);

			var field = new TextField();
			field.width = 300;
			field.text = ModConfig.get(patchId, s);
			row.addComponent(field);
			boxes.push(field);

			var hint = new Label();
			hint.text = s.desc + (s.dflt.length > 0 ? (s.desc.length > 0 ? "  " : "") + "(default: " + s.dflt + ")" : "");
			hint.percentWidth = 100;
			hint.tooltip = hint.text;
			row.addComponent(hint);

			addComponent(row);
		}

		onDialogClosed = function(e:DialogEvent) {
			if (e.button == DialogButton.OK) {
				save();
				if (onSaved != null) onSaved();
			}
		};
	}

	function save():Void {
		for (i in 0...specs.length) {
			var v = StringTools.trim(boxes[i].text);
			ModConfig.set(patchId, specs[i].key, v.length == 0 ? specs[i].dflt : v);
		}
	}
}





