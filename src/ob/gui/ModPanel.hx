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

class ModRow extends HBox {
	public var check:CheckBox;
	public var label:Label;
	public var combinedIndex:Int;

	public function new(text:String, enabled:Bool, combinedIndex:Int, tip:String = null) {
		super();
		this.combinedIndex = combinedIndex;
		percentWidth = 100;
		height = 24;

		check = new CheckBox();
		check.width = 24;
		check.selected = enabled;
		addComponent(check);

		label = new Label();
		label.text = text;
		label.percentWidth = 100;
		label.wordWrap = false;
		label.tooltip = tip;
		label.styleString = "padding-left: 3px;";
		addComponent(label);
	}

	public function selectedStyle(on:Bool):Void {
		backgroundColor = on ? 0xCBE4F7 : null;
	}
}

/**
 * Mod list: every mod zip is one row. Clicking a row selects it (for Configure);
 * ticking the checkbox toggles it.
 */
class ModPanel extends VBox {
	var rows:Array<ModRow> = [];
	public var selectedIndex = -1;

	public var onToggle:Int->Bool->Void;
	public var onSelect:Int->Void;

	public function new() {
		super();
		percentWidth = 100;
		percentHeight = 100;
		styleString = "spacing: 0px;";
	}

	public function populate(mods:Array<Mod>):Void {
		removeAllComponents();
		rows = [];
		selectedIndex = -1;
		var i = 0;
		for (m in mods) {
			var text = "[as3] " + m.name + " -> " + m.target
				+ (m.config.length > 0 ? "  (" + m.config.length + " setting" + (m.config.length == 1 ? "" : "s") + ")" : "");
			addRow(new ModRow(text, ModConfig.isEnabled(m), i, m.desc));
			i++;
		}
	}

	function addRow(row:ModRow):Void {
		row.check.onChange = function(_) {
			select(row.combinedIndex);
			if (onToggle != null) onToggle(row.combinedIndex, row.check.selected);
		};
		// Clicking the row selects it; only the checkbox changes the state. The
		// row handler does not toggle, so a checkbox click bubbling up cannot
		// flip it twice.
		row.onClick = function(e:MouseEvent) select(row.combinedIndex);
		rows.push(row);
		addComponent(row);
	}

	public function select(index:Int):Void {
		selectedIndex = index;
		for (r in rows) r.selectedStyle(r.combinedIndex == index);
		if (onSelect != null) onSelect(index);
	}
}




