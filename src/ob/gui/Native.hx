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

/**
 * The small native bits the HaxeUI build still needs.
 *
 * Haxe/hxcpp links a console subsystem exe (so helper tool output is visible),
 * so a GUI launch from Explorer would leave a console window behind. Hide it
 * only when this process owns the console; a console shared with cmd.exe or
 * PowerShell is left visible so build output stays readable.
 */
@:buildXml('<target id="haxe" tool="linker" toolid="exe">
<flag value="/SUBSYSTEM:CONSOLE" />
</target>')
@:headerCode('
#include <windows.h>

static inline void ob_hide_console() {
	DWORD pids[2];
	if (GetConsoleProcessList(pids, 2) == 1) {
		HWND c = GetConsoleWindow();
		if (c != NULL) ShowWindow(c, SW_HIDE);
	}
}
')
class Native {
	public static function hideConsole():Void {
		untyped __cpp__("ob_hide_console()");
	}
}


