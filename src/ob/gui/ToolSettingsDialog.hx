package ob.gui;

import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.HBox;
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.containers.dialogs.Dialog.DialogButton;
import haxe.ui.containers.dialogs.Dialog.DialogEvent;
import haxe.ui.containers.dialogs.Dialogs.FileDialogExtensionInfo;
import haxe.ui.containers.dialogs.OpenFileDialog;
import haxe.ui.core.Component;
import haxe.ui.core.Screen;
import haxe.ui.events.UIEvent;
import sys.FileSystem;

private class ToolRow {
	public var key:String;
	public var field:TextField;
	public var status:Label;

	public function new(key:String, field:TextField, status:Label) {
		this.key = key;
		this.field = field;
		this.status = status;
	}
}

class ToolSettingsDialog extends Dialog {
	var appDir:String;
	var source:ObSettings;
	var rows:Array<ToolRow> = [];
	var deobf:CheckBox;
	var summary:Label;

	public var onSaved:ObSettings->Void;

	public function new(appDir:String, current:ObSettings) {
		super();
		this.appDir = appDir;
		this.source = current.copy();

		title = "Tool paths and build settings";
		autoWidth = false;
		autoHeight = false;
		width = 1010;
		height = 650;
		closable = true;
		centerDialog = true;
		buttons = DialogButton.OK | DialogButton.CANCEL;

		dialogContent.padding = 10;
		dialogContent.styleString = "spacing: 4px;";

		var intro = new Label();
		intro.text = "Paths pointing towards files used to build the game. "
			+ "they are saved to " + ObSettings.filePath(appDir) + ".";
		intro.percentWidth = 100;
		intro.wordWrap = true;
		dialogContent.addComponent(intro);

		addHeading("External programs");
		addRow("airSdk", "AIR SDK folder", source.airSdk, "dir",
			"Folder containing bin\\adt.bat, the AIR Developer Tool used to package and sign the game.");
		addRow("javaExe", "Java executable", source.javaExe, "file",
			"java.exe from a JDK/JRE. A bare name such as java.exe is looked up on PATH.",
			[{label: "Java executable", extension: "exe"}]);
		addRow("ffdecJar", "FFDec jar", source.ffdecJar, "file",
			"JPEXS Free Flash Decompiler jar, used to decompile and replace ActionScript classes.",
			[{label: "FFDec jar", extension: "jar"}]);

		addHeading("External files");
		addRow("aneDir", "ANE folder", source.aneDir, "dir",
			"Folder holding the Windows .ane files listed by the app descriptor (at least 15 are required).");
		addRow("appDesc", "App descriptor XML", source.appDesc, "file",
			"The AIR application descriptor (application-win.xml). Its window size is rewritten at build time.",
			[{label: "AIR descriptor", extension: "xml"}]);
		addRow("iconsDir", "Icons folder", source.iconsDir, "dir",
			"Folder of icons copied into the packaged application.");
		addRow("certP12", "Signing certificate (.p12)", source.certP12, "file",
			"PKCS#12 certificate used by adt to sign the Windows bundle.",
			[{label: "PKCS#12 certificate", extension: "p12"}]);
		addRow("certPass", "Certificate password", source.certPass, "password",
			"Password for the .p12 certificate.");

		addHeading("Output");
		addRow("outDir", "Output folder", source.outDir, "dir",
			"Build jobs and decompiled exports are written here.");

		deobf = new CheckBox();
		deobf.text = "Deobfuscate identifiers before building (recommended)";
		deobf.selected = source.deobfuscate;
		deobf.tooltip = "Renames the game's obfuscated identifiers before mods run, so the readable "
			+ "class names in the mod sources match the game.";
		deobf.styleString = "margin-top: 6px;";
		dialogContent.addComponent(deobf);

		var footer = new HBox();
		footer.percentWidth = 100;
		footer.styleString = "spacing: 8px; margin-top: 8px;";
		var checkBtn = new Button();
		checkBtn.text = "Check paths";
		checkBtn.width = 110;
		checkBtn.onClick = function(_) checkAll();
		footer.addComponent(checkBtn);
		summary = new Label();
		summary.percentWidth = 100;
		summary.tooltip = "Status updates as you edit. Hover a status for details.";
		footer.addComponent(summary);
		dialogContent.addComponent(footer);

		onDialogClosed = function(e:DialogEvent) {
			if (e.button == DialogButton.OK) {
				var s = result();
				if (onSaved != null) onSaved(s);
			}
		};

		checkAll();
	}

	function addHeading(text:String):Void {
		var label = new Label();
		label.text = text;
		label.styleString = "font-size: 15px; color: #1F4E79; margin-top: 4px;";
		dialogContent.addComponent(label);
	}

	function addRow(key:String, label:String, value:String, kind:String, tip:String,
			?extensions:Array<FileDialogExtensionInfo>):Void {
		var row = new HBox();
		row.percentWidth = 100;
		row.height = 28;
		row.styleString = "spacing: 6px;";

		var name = new Label();
		name.text = label;
		name.width = 185;
		name.tooltip = tip;
		row.addComponent(name);

		var field = new TextField();
		field.percentWidth = 100;
		field.text = value == null ? "" : value;
		field.tooltip = tip;
		if (kind == "password") field.password = true;
		row.addComponent(field);

		var r = new ToolRow(key, field, null);

		if (kind == "file" || kind == "dir") {
			var browse = new Button();
			browse.text = "Browse...";
			browse.width = 90;
			browse.onClick = function(_) {
				if (kind == "dir") browseDir(field);
				else browseFile(field, extensions);
				refresh(r);
			};
			row.addComponent(browse);
		} else {
			var spacer = new Component();
			spacer.width = 90;
			row.addComponent(spacer);
		}

		var status = new Label();
		status.width = 120;
		row.addComponent(status);
		r.status = status;

		rows.push(r);
		field.registerEvent(UIEvent.CHANGE, function(_) refresh(r));
		dialogContent.addComponent(row);
	}

	function browseFile(field:TextField, extensions:Array<FileDialogExtensionInfo>):Void {
		var d = new OpenFileDialog({
			title: "Select file",
			extensions: extensions
		}, function(button, files) {
			if (button == DialogButton.OK && files != null && files.length > 0) {
				field.text = files[0].fullPath;
				refreshFor(field);
			}
		});
		d.show();
	}

	function browseDir(field:TextField):Void {
		var start = Util.unquotePath(field.text);
		if (start.length == 0 || !FileSystem.exists(start) || !FileSystem.isDirectory(start)) start = appDir;
		try {
			var d = new hx.widgets.DirDialog(Screen.instance.frame, "Select folder", start);
			if (d.showModal() == hx.widgets.StandardId.OK) {
				field.text = d.path;
				refreshFor(field);
			}
		} catch (e:Dynamic) {
			summary.text = "Could not open the folder picker - type the path instead.";
			summary.styleString = "color: #C62828;";
		}
	}

	function refreshFor(field:TextField):Void {
		for (r in rows) {
			if (r.field == field) {
				refresh(r);
				return;
			}
		}
	}

	function refresh(r:ToolRow):Void {
		var status = findStatus(result(), r.key);
		if (status == null) return;
		applyStatus(r, status);
		updateSummary();
	}

	function checkAll():Void {
		var s = result();
		for (r in rows) {
			var status = findStatus(s, r.key);
			if (status != null) applyStatus(r, status);
		}
		updateSummary();
	}

	function applyStatus(r:ToolRow, status:ToolStatus):Void {
		r.status.text = status.ok ? "OK" : "Missing";
		r.status.tooltip = status.detail;
		r.status.styleString = status.ok ? "color: #2E7D32;" : "color: #C62828;";
	}

	function updateSummary():Void {
		var missing = 0;
		for (r in rows) {
			if (r.status.text == "Missing") missing++;
		}
		if (missing == 0) {
			summary.text = "All required tools and paths found.";
			summary.styleString = "color: #2E7D32;";
		} else {
			summary.text = '$missing required item(s) missing - hover a status for details.';
			summary.styleString = "color: #C62828;";
		}
	}

	function findStatus(s:ObSettings, key:String):ToolStatus {
		for (status in ObSettings.check(s)) {
			if (status.key == key) return status;
		}
		return null;
	}

	function result():ObSettings {
		var s = source.copy();
		for (r in rows) {
			var text = r.field.text == null ? "" : r.field.text;
			var v = r.key == "certPass" ? text : Util.unquotePath(text);
			switch (r.key) {
				case "airSdk": s.airSdk = v;
				case "aneDir": s.aneDir = v;
				case "appDesc": s.appDesc = v;
				case "iconsDir": s.iconsDir = v;
				case "certP12": s.certP12 = v;
				case "certPass": s.certPass = v;
				case "outDir": s.outDir = v;
				case "ffdecJar": s.ffdecJar = v;
				case "javaExe": s.javaExe = v;
			}
		}
		s.deobfuscate = deobf.selected;
		return s;
	}
}
