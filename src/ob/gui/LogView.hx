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

class LogView extends VBox {
	var area:TextArea;
	var queue:Array<String> = [];
	var mutex = new Mutex();
	var finished = false;
	var failed = false;
	var result:String = null;
	var error:String = null;
	var timer:Timer;

	public var onActionDone:String->String->Void; // (error, result)

	public function new() {
		super();
		percentWidth = 100;
		percentHeight = 100;

		area = new TextArea();
		area.percentWidth = 100;
		area.percentHeight = 100;
		area.autoScrollToBottom = true;
		area.styleString = "font-name: Consolas; font-size: 14px;";
		addComponent(area);

		area.registerEvent(UIEvent.READY, function(_) {
			// The log is for reading, not editing. TextArea has no read-only
			// property, but the wx backend's control does.
			var ctrl:hx.widgets.TextCtrl = cast(area.window, hx.widgets.TextCtrl);
			if (ctrl != null) ctrl.editable = false;
		});

		timer = new Timer(100, tick);
	}

	/** Safe to call from any thread. */
	public function log(s:String):Void {
		mutex.acquire();
		queue.push(s);
		mutex.release();
	}

	/**`error == null` means success. */
	public function finish(error:String, result:String):Void {
		mutex.acquire();
		this.error = error;
		this.result = result;
		finished = true;
		mutex.release();
	}

	public function clear():Void {
		mutex.acquire();
		queue = [];
		mutex.release();
		area.text = "";
	}

	function tick():Void {
		var lines:Array<String>;
		var done = false, fail = false, err:String = null, res:String = null;
		mutex.acquire();
		lines = queue;
		queue = [];
		if (finished) {
			finished = false;
			done = true;
			fail = error != null;
			err = error;
			res = result;
			error = null;
			result = null;
		}
		mutex.release();

		if (lines.length > 0) {
			var sb = new StringBuf();
			for (l in lines) {
				sb.add("[");
				sb.add(DateTools.format(Date.now(), "%H:%M:%S"));
				sb.add("] ");
				sb.add(l);
				sb.add("\r\n");
			}
			area.text += sb.toString();
		}
		if (done && onActionDone != null) onActionDone(fail ? err : null, fail ? null : res);
	}
}




