package ob.gui;

import haxe.ui.containers.VBox;
import haxe.ui.data.ArrayDataSource;
import haxe.ui.events.UIEvent;
import haxe.ui.events.MenuEvent;
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




@:xml('
<vbox width="100%" height="100%" style="padding:8px;spacing:6px;">
  <menubar id="mainMenu">
    <menu text="Tools">
      <menuitem id="menuToolPaths" text="Tool paths and build settings..." />
      <menuitem id="menuCheckTools" text="Check tool setup" />
      <menuitem id="menuOpenSettings" text="Open settings folder" />
    </menu>
  </menubar>

  <hbox width="100%" height="30" style="spacing:6px;">
    <label text="Game APK/SWF:" width="90" />
    <textfield id="swfField" width="100%" height="24" />
    <button id="browseBtn" text="Browse..." width="90" height="26" />
  </hbox>

  <vbox id="modBox" width="100%" height="176" style="spacing:2px;">
    <label text="Mods (mods/*.zip: mod.json + one .as)" />
  </vbox>

  <vbox id="logBox" width="100%" height="100%" style="spacing:2px;">
    <label text="Log" />
  </vbox>

  <hbox width="100%" height="42" style="spacing:8px;">
    <button id="buildBtn" text="Build Windows (.exe)" width="180" height="32" />
    <button id="decompBtn" text="Decompile" width="130" height="32" />
    <button id="cfgBtn" text="Configure mod..." width="130" height="32" />
    <checkbox id="deobfCheck" text="Deobfuscate (readable names)" />
    <label text="  APK is input only - no Android output." />
  </hbox>

  <hbox width="100%" height="70" style="spacing:6px;">
    <vbox width="100%" style="spacing:4px;">
      <hbox width="100%" style="spacing:6px;">
        <label text="Window size:" width="80" />
        <textfield id="winField" width="130" />
        <dropdown id="winPresets" width="210" />
        <button id="fitBtn" text="Fit screen" width="90" height="26" />
      </hbox>
    </vbox>
    <vbox width="120" style="spacing:4px;">
      <button id="saveBtn" text="Save" height="26" />
      <button id="toolPathsBtn" text="Tool paths..." height="26" tooltip="Configure AIR SDK, Java, FFDec, ANE folder, descriptor, icons, certificate and output folder." />
    </vbox>
  </hbox>
</vbox>
')
class MainLayout extends VBox {
	public static var WIN_PRESETS:Array<String> = [
		"540x960 (9:16 game design)",
		"675x1200 (9:16 bigger)",
		"600x960 (5:8 wider)",
		"720x1280 (9:16 HD)",
		"900x1600 (9:16 large)",
		"1080x1920 (9:16 full)",
		"1280x720 (16:9 desktop)",
		"1600x900 (16:9 desktop)",
		"1920x1080 (16:9 desktop)"
	];

	public var modPanel:ModPanel;
	public var logView:LogView;

	public var onToolPaths:Void->Void;
	public var onCheckTools:Void->Void;
	public var onOpenSettings:Void->Void;

	public function new() {
		super();

		modPanel = new ModPanel();
		modPanel.percentHeight = 100;
		modBox.addComponent(modPanel);

		logView = new LogView();
		logView.percentHeight = 100;
		logBox.addComponent(logView);

		swfField.registerEvent(UIEvent.READY, function(_) {
			var ctrl:hx.widgets.TextCtrl = cast(swfField.window, hx.widgets.TextCtrl);
			if (ctrl != null) ctrl.editable = false;
		});

		deobfCheck.tooltip = "Rewrites the game's obfuscated identifiers to readable names before mods run.\n"
			+ "This is what makes the decompiled ActionScript and .as class replacements usable.\n"
			+ "Turn it off to build with the original obfuscated identifiers.";

		winPresets.dataSource = ArrayDataSource.fromArray(WIN_PRESETS);
		winPresets.selectedIndex = -1;
		winPresets.onChange = function(_) {
			if (winPresets.selectedIndex < 0) return;
			winField.text = WIN_PRESETS[winPresets.selectedIndex].split(" ")[0];
		};

		mainMenu.onMenuSelected = function(e:MenuEvent) {
			if (e.menuItem == null) return;
			switch (e.menuItem.id) {
				case "menuToolPaths": if (onToolPaths != null) onToolPaths();
				case "menuCheckTools": if (onCheckTools != null) onCheckTools();
				case "menuOpenSettings": if (onOpenSettings != null) onOpenSettings();
			}
		};
	}
}




/** One checkbox row in the mod list. */
