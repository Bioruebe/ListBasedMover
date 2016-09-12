package;
import haxe.Utf8;
import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;

/**
 * ...
 * @author Bioruebe
 */
class Main {
	static var recurse:Bool = false;
	static var fuzzy = false;
	static var noCopy = false;
	static var zip = -1;
	static var fuzzyTolerance:Int = 0;
	
	static var searchList:Array<String>;
	static var searchPaths = new Array<String>();
	static var files = new StringMap<Array<Int>>();
	static var destination:String;
	
	static function main() {
		var index = 0;
		var argHandler = Args.generate([
		
			@doc("Enable recursion for input paths")
			["-r", "--recurse"] => recurse,
			
			@doc("Enable fuzzy search if files not found")
			["-f", "--fuzzy"] => fuzzy,
			
			//@doc("Zip-compress matched files with specified compression level, destination specifies the file to write to")
			//["-z", "--zip"] => zip,
			
			@doc("Dont' copy matched files, only display report")
			["-nc", "--no-copy"] => noCopy,
			
			@doc("Overwrite automatic tolerance for fuzzy search with specified value")
			["-ft", "--fuzzy-tolerance"] => fuzzyTolerance,
			
			_ => function(arg:String) {
				index++;
				//trace(arg + "  " + index);
				if (index != 2 && !FileSystem.exists(arg)) {
					Bio.Cout("Input path " + arg + " does not exist", Bio.LogSeverity.CRITICAL);
				}
				
				switch(index) {
					case 1:
						var content = File.getContent(arg);
						try {
							content = Utf8.decode(content);
						} 
						catch (err:Dynamic) {
							Bio.Cout("Failed to decode UTF8", Bio.LogSeverity.WARNING);
						}
						searchList = StringTools.replace(content, "\r\n", "\n").split(Bio.StringInStr(content, "\n")? "\n": "\r");
					case 2:
						destination = arg;
					case _:
						if (!FileSystem.isDirectory(arg)) Bio.Cout("Search path " + arg + " is not a directory", Bio.LogSeverity.CRITICAL);
						searchPaths.push(arg);
				}
			}
		], false, "<filelist> <destination> <searchpath> [searchpath...]");
		
		Sys.println(FIGlet.write("BioLBM", CompileTime.readFile('./../fonts/standard.flf')));
		
		var args = Sys.args();
		//args.push("-ft");
		//args.push("1");
		//args.push("-f");
		//args.push("-r");
		//args.push("C:\\Users\\Bioruebe\\Documents");
		//args.push("C:\\Users\\Bioruebe\\Downloads");
		//args.push("C:\\Users\\Bioruebe\\Documents\\ördner");
		
		for (i in 0...args.length) {
			try {
				args[i] = Utf8.decode(args[i]);
			} 
			catch (err:Dynamic) {
				//Bio.Cout("Failed to decode UTF8", Bio.LogSeverity.WARNING);
			}
			//trace(args[i]);
		}
		
		//return;
		
		Bio.Header("Bioruebe's List Based Mover (BioLBM)", "1.1.0", "A tool to move files matching a given list of names from specified input path(s) to a destination directory.");
		if (args.length == 0) {
			Sys.println("\n" + argHandler.getDoc());
			Sys.exit(0);
		}
		Bio.Seperator();
		
		argHandler.parse(args);
		
		if (searchList == null || searchList.length == 0) Bio.Cout("Please specify a valid list with files to search for", Bio.LogSeverity.CRITICAL);
		if (destination == null) Bio.Cout("No destination directory specified", Bio.LogSeverity.CRITICAL);
		if (searchPaths.length < 1) Bio.Cout("No search paths specified", Bio.LogSeverity.CRITICAL);
		
		//Bio.profile(function(){
		getFileList();
		//});
		
		Bio.Cout(Lambda.count(files) + " files found", Bio.LogSeverity.MESSAGE);
		Bio.Cout("Processing...", Bio.LogSeverity.MESSAGE);
		
		var notFound = new Array<String>();
		var iFound = 0;
		
		for (f in searchList) {
			//trace(f);
			//try {
				//f = Utf8.decode(f);
			//}
			//catch (err:Dynamic) {}
			//trace(f);
			var found = files.get(f);
			//trace(f + " - " + found + " " + files.exists(f));
			if (found == null) {
				notFound.push(f);
				continue;
			}
			
			iFound++;
			Bio.Cout(f, Bio.LogSeverity.MESSAGE);
			
			// Move file
			copy(f, found);
		}
		
		Bio.Seperator();
		Bio.Cout('\t$iFound/${searchList.length} files found' + (noCopy? "": " and copied to destination directory"), Bio.LogSeverity.MESSAGE);
		Bio.Seperator();
		
		if (notFound.length > 0) {
			Bio.Cout(notFound.length + " unmatched files:\n - " + notFound.join("\n - "));
			if (fuzzy) compareUnmatched(notFound);
		}
		else {
			Bio.Cout("All files found", Bio.LogSeverity.MESSAGE);
		}
		
		Bio.Cout("Finished", Bio.LogSeverity.MESSAGE);
	}
	
	static function getFileList() {
		Bio.Cout("Reading input director" + (searchPaths.length > 1? "ies": "y"), Bio.LogSeverity.MESSAGE);
		
		var i = 0;
		var currentFiles:Array<String>;
		
		while (i < searchPaths.length) {
			//Bio.Cout("Reading directory " + searchPaths[i]);
			
			try {
				currentFiles = FileSystem.readDirectory(Utf8.encode(searchPaths[i]));
				if (currentFiles == null) throw "ReadDirectory returned null";
			}
			catch (e:Dynamic) {
				Bio.Cout("Failed to read directory " + searchPaths[i], Bio.LogSeverity.WARNING);
				i++;
				continue;
			}
			
			for (f in currentFiles) {
				//trace(f);
				//f = Utf8.decode(f);
				//trace(f);
				var currentPath = searchPaths[i] + "//" + f;
				//trace(currentPath);
				if (FileSystem.isDirectory(currentPath)) {
					if (recurse && currentPath != destination) searchPaths.push(currentPath);
					continue;
				}
				//trace(f + " " + FileSystem.isDirectory(searchPaths[i] + "//" + f));
				var existing = files.get(f);
				if (existing == null) {
					files.set(f, [i]);
				}
				else {
					existing.push(i);
					files.set(f, existing);
				}
				
			}
			i++;
		}
	}
	
	static function compareUnmatched(notFound:Array<String>) {
		var minDist:Float;
		var currDist:Float;
		var minFile:String;
		
		Bio.Cout("\nPreparing search tree, this may take a while", Bio.LogSeverity.MESSAGE);
		
		var bk = new BKTree();
		//Bio.profile(function(){
		for (f in files.keys()) {
			bk.set(f);
		}
		//});
		
		//trace(bk);
		
		for (nf in notFound) {
			var tolerance = fuzzyTolerance > 0? fuzzyTolerance: Std.int(nf.length * 0.3);
			//Bio.Cout("Searching matches for '" + nf + "' with tolerance " + tolerance);
			Bio.Cout("\n\n-- [" + nf + "] -- ", Bio.LogSeverity.MESSAGE);
			
			var results;
			//Bio.profile(function() {
				results = bk.search(nf, tolerance);
			//});
			
			if (results.length == 0) {
				Bio.Cout("--> No matches found", Bio.LogSeverity.MESSAGE);
				continue;
			}
			
			Bio.PrintArray(results);
			var index = Bio.IntPrompt("\nSelect index to use or 0 to skip the file", 0, results.length);
			if (index == 0) continue;
			index--;
			
			var f = results[index];
			//Bio.Cout("Selected file '" + f + "'");
			copy(f, files.get(f));
		}
	}
	
	static function copy(fname:String, indices:Array<Int>) {
		if (noCopy) return;
		
		var index = 0;
		if (indices.length > 1) {
			for (i in 0...indices.length) {
				Sys.println('\t[${i + 1}] ' + searchPaths[indices[i]]);
			}
			index = Bio.IntPrompt('The file $fname exists in multiple directories. Please choose the one to copy it from or use 0 to skip the file.', 0, indices.length) - 1;
			if (index < 0) return;
		}
		
		var path = searchPaths[indices[index]];
		try {
			fname = Utf8.decode(fname);
		}
		catch (err:Dynamic) {}
		var src = path + "/" + fname;
		
		if (zip > -1) {
			
		}
		else {
			if (!FileSystem.exists(destination)) FileSystem.createDirectory(destination);
			var currentDestination = destination + "/" + fname;
			if (FileSystem.exists(currentDestination) && !Bio.Prompt('File already exists. Overwrite?', "copy_overwrite")) return;
			//Bio.Cout('Copying file $src to $currentDestination', Bio.LogSeverity.DEBUG);
			File.copy(src, currentDestination);
		}
	}
}