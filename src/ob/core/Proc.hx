package ob.core;

import haxe.io.Bytes;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.Json;
import sys.io.Process;
import sys.thread.Lock;
import sys.thread.Thread;

class ProcResult {
	public var exitCode:Int;
	public var stdout:String;
	public var stderr:String;
	public var timedOut:Bool;

	public function new(exitCode:Int, stdout:String, stderr:String, timedOut:Bool) {
		this.exitCode = exitCode;
		this.stdout = stdout;
		this.stderr = stderr;
		this.timedOut = timedOut;
	}
}

class Proc {
	public static function run(exe:String, args:Array<String>, workdir:String, log:String->Void, ?timeoutMs:Int = 0, ?echo:Bool = true):ProcResult {
		if (echo) log("$ " + Util.fileName(exe) + (args.length == 0 ? "" : " " + join(args)));
		var p = start(exe, args, workdir);

		var outLock = new Lock();
		var errLock = new Lock();
		var outText = "";
		var errText = "";
		Thread.create(function() {
			try outText = p.stdout.readAll().toString() catch (e:Dynamic) {};
			outLock.release();
		});
		Thread.create(function() {
			try errText = p.stderr.readAll().toString() catch (e:Dynamic) {};
			errLock.release();
		});

		var status = waitForExit(p, timeoutMs);
		outLock.wait();
		errLock.wait();
		try p.close() catch (e:Dynamic) {};

		if (echo) logOutput(log, outText, errText);
		return new ProcResult(status.code == null ? -1 : status.code, outText, errText, status.timedOut);
	}

	static function start(exe:String, args:Array<String>, workdir:String):Process {
	    var previous = enterWorkdir(workdir);
	    var process:Process = null;
	
	    try {
	        process = isBatchFile(exe)
	            ? new Process(cmdLine(exe, args), null)
	            : new Process(exe, args);
	    } catch (e:Dynamic) {
	        if (previous != null) {
	            try {
	                Sys.setCwd(previous);
	            } catch (e:Dynamic) {}
	        }
		
	        throw 'Could not start $exe: $e';
	    }
	
	    if (previous != null) {
	        try {
	            Sys.setCwd(previous);
	        } catch (e:Dynamic) {}
	    }
	
	    return process;
	}

	static function enterWorkdir(workdir:String):Null<String> {
		if (workdir == null || workdir.length == 0 || !sys.FileSystem.exists(workdir) || !sys.FileSystem.isDirectory(workdir)) return null;
		try {
			var previous = Sys.getCwd();
			Sys.setCwd(workdir);
			return previous;
		} catch (e:Dynamic) {
			return null;
		}
	}

	static inline function isBatchFile(exe:String):Bool {
		var ext = Util.extOf(exe);
		return Util.eqi(ext, ".bat") || Util.eqi(ext, ".cmd");
	}

	static function waitForExit(process:Process, timeoutMs:Int):{code:Null<Int>, timedOut:Bool} {
		var started = Sys.time();
		while (true) {
			var code = process.exitCode(false);
			if (code != null) return {code: code, timedOut: false};
			if (timeoutMs > 0 && (Sys.time() - started) * 1000.0 > timeoutMs) {
				try process.kill() catch (e:Dynamic) {};
				return {code: null, timedOut: true};
			}
			Sys.sleep(0.05);
		}
	}

	static function logOutput(log:String->Void, stdout:String, stderr:String):Void {
		logLines(log, "  ", stdout);
		logLines(log, "  [err] ", stderr);
	}

	static function logLines(log:String->Void, prefix:String, text:String):Void {
		if (StringTools.trim(text).length == 0) return;
		for (line in text.split("\n")) log(prefix + StringTools.rtrim(line));
	}

	static function join(args:Array<String>):String {
		var parts = new Array<String>();
		for (a in args) parts.push(quote(a));
		return parts.join(" ");
	}

	static function quote(a:String):String {
		if (a.length == 0) return "\"\"";
		var need = false;
		for (i in 0...a.length) {
			var c = a.charAt(i);
			if (c == " " || c == "\t" || c == "\"") {
				need = true;
				break;
			}
		}
		return need ? "\"" + StringTools.replace(a, "\"", "\\\"") + "\"" : a;
	}

	/** A command line for cmd.exe, with the program itself quoted if needed. */
	static function cmdLine(exe:String, args:Array<String>):String {
		var sb = new StringBuf();
		sb.add(quote(exe));
		for (a in args) {
			sb.add(" ");
			sb.add(quote(a));
		}
		return sb.toString();
	}
}



