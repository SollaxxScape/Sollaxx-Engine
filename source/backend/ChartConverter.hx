package backend;

import haxe.io.Path;
#if sys
import sys.thread.Thread;
#end

/**
 * Built in chart converter: changes the chart format of every chart / events json from Psych V1 to Sollaxx V1.
 *
 *   "format": "psych_v1"          ->  "format": "sollaxx_v1"
 *   "format": "psych_v1_convert"  ->  "format": "sollaxx_v1_convert"
 *
 * It runs by itself in the background every time the game starts, so new charts and mods get converted too.
 * Only the format value is changed, the rest of the file stays exactly as it is.
 * It looks in the "assets" and "mods" folders next to the game and, while you are developing (the game runs from
 * export/.../bin), also in the project folder (the one with Project.xml), so the files of your source are converted as well.
 * Charts in older layouts are converted by Song.hx the first time they are loaded.
 */
class ChartConverter
{
	static var started:Bool = false;

	public static function convertAll()
	{
		#if sys
		if (started) return;
		started = true;

		Thread.create(function()
		{
			var changed:Int = 0;
			try
			{
				var done:Array<String> = [];
				for (root in findRoots())
				{
					for (folder in ['assets', 'mods'])
					{
						var path:String = root + folder;
						if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) continue;

						var full:String = FileSystem.fullPath(path);
						if (done.contains(full)) continue; // the game folder and the project folder can be the same one
						done.push(full);

						changed += convertFolder(path);
					}
				}
			}
			catch (e:Dynamic)
			{
				trace('Chart converter stopped: $e');
			}

			if (changed > 0) trace('Chart converter: $changed chart file(s) changed to the Sollaxx V1 format');
		});
		#end
	}

	#if sys
	// "" = next to the game, plus the project folder when the game runs from export/.../bin
	static function findRoots():Array<String>
	{
		var roots:Array<String> = [''];

		var dir:String = Path.removeTrailingSlashes(Sys.getCwd());
		for (i in 0...8)
		{
			if (FileSystem.exists(Path.join([dir, 'Project.xml'])))
			{
				roots.push(Path.addTrailingSlash(dir));
				break;
			}
			var parent:String = Path.directory(dir);
			if (parent == null || parent == '' || parent == dir) break;
			dir = parent;
		}
		return roots;
	}

	static function convertFolder(folder:String):Int
	{
		var count:Int = 0;
		for (name in FileSystem.readDirectory(folder))
		{
			var path:String = folder + '/' + name;
			if (FileSystem.isDirectory(path))
				count += convertFolder(path);
			else if (name.toLowerCase().endsWith('.json') && convertFile(path))
				count++;
		}
		return count;
	}

	static function convertFile(path:String):Bool
	{
		try
		{
			var size:Int = FileSystem.stat(path).size;
			if (size < 20 || size > 8000000) return false;

			var text:String = File.getContent(path);
			if (text.indexOf('"psych_v1') < 0) return false; // fast check, most files are not charts
			if (text.indexOf('"notes"') < 0 && text.indexOf('"events"') < 0) return false; // only charts and events files

			var newText:String = text.split('"psych_v1_convert"').join('"sollaxx_v1_convert"').split('"psych_v1"').join('"sollaxx_v1"');
			if (newText == text) return false;

			File.saveContent(path, newText);
			return true;
		}
		catch (e:Dynamic) {}
		return false;
	}
	#end
}
