package backend;

import haxe.Json;
import openfl.media.Sound;
#if sys
import sys.thread.Thread;
import sys.thread.Mutex;
#end

typedef PreloadSong =
{
	var folder:String;
	var song:String;
}

/**
 * Preloads the audio of every song in Freeplay (base game and mods) in a background thread.
 * Started when you press ENTER on a song in Freeplay. The selected song is skipped, the normal loading screen handles it.
 *
 * The decoded audio is kept in memory, so it can use a lot of RAM. A memory limit stops the preloading when it is reached.
 * Config (data/preloadSongs.json, a mod can ship its own):
 *   { "enabled": true, "maxMemoryMB": 1024, "includeVoices": false, "startDelay": 2 }
 *   - maxMemoryMB: stops preloading after this much audio was decoded (estimated)
 *   - includeVoices: also preload Voices.ogg (doubles the memory use)
 *   - startDelay: seconds to wait before starting, so the song you picked loads without competition
 */
class SongPreloader
{
	#if sys
	static var mutex:Mutex = new Mutex();
	#end
	static var finished:Array<{file:String, sound:Sound}> = [];
	static var attempted:Map<String, Bool> = [];
	static var usedBytes:Float = 0;
	static var running:Bool = false;
	static var hasPending:Bool = false;

	public static function start(entries:Array<PreloadSong>, selectedIndex:Int)
	{
		#if sys
		if(running) return;

		var enabled:Bool = true;
		var maxBytes:Float = 1024 * 1024 * 1024;
		var includeVoices:Bool = false;
		var startDelay:Float = 2;
		try
		{
			var raw:String = Paths.getTextFromFile('data/preloadSongs.json');
			if(raw != null)
			{
				var json:Dynamic = Json.parse(raw);
				if(json.enabled != null) enabled = json.enabled;
				if(json.maxMemoryMB != null) maxBytes = json.maxMemoryMB * 1024.0 * 1024.0;
				if(json.includeVoices != null) includeVoices = json.includeVoices;
				if(json.startDelay != null) startDelay = json.startDelay;
			}
		}
		catch(e:Dynamic) {}
		if(!enabled || entries.length < 2) return;

		// Everything after the selected song first (wrapping around), the selected song itself is left to the loading screen
		var order:Array<PreloadSong> = [];
		for (i in 1...entries.length)
			order.push(entries[(selectedIndex + i) % entries.length]);

		running = true;
		var names:Array<String> = includeVoices ? ['Inst', 'Voices'] : ['Inst'];
		Thread.create(function()
		{
			try
			{
				if(startDelay > 0) Sys.sleep(startDelay);
				for (entry in order)
				{
					var songPath:String = Paths.formatToSongPath(entry.song);
					for (name in names)
					{
						if(usedBytes >= maxBytes)
						{
							trace('Song preloading stopped: memory limit reached');
							running = false;
							return;
						}

						var file:String = findSongFile(entry.folder, songPath, name);
						if(file == null || attempted.exists(file)) continue;
						attempted.set(file, true);

						try
						{
							var sound:Sound = Sound.fromFile(file);
							if(sound == null) continue;
							usedBytes += (sound.length / 1000) * 44100 * 4; // decoded size estimate (16 bit stereo)
							mutex.acquire();
							finished.push({file: file, sound: sound});
							hasPending = true;
							mutex.release();
							trace('preloaded song audio: $file');
						}
						catch(e:Dynamic) {
							trace('failed to preload song audio: $file');
						}
					}
				}
			}
			catch(e:Dynamic) {}
			running = false;
		});
		#end
	}

	// Called every frame from the main thread: moves finished sounds into the sound cache and protects them from being cleared
	public static function flush()
	{
		#if sys
		if(!hasPending) return;
		mutex.acquire();
		var items = finished;
		finished = [];
		hasPending = false;
		mutex.release();

		for (item in items)
		{
			if(!Paths.currentTrackedSounds.exists(item.file))
				Paths.currentTrackedSounds.set(item.file, item.sound);
			Paths.excludeAsset(item.file);
		}
		#end
	}

	// Same lookup order as Paths.getPath, without touching Mods.currentModDirectory (this runs off the main thread)
	static function findSongFile(folder:String, songPath:String, name:String):String
	{
		var relative:String = 'songs/' + songPath + '/' + name + '.' + Paths.SOUND_EXT;
		#if MODS_ALLOWED
		if(folder != null && folder.length > 0)
		{
			var inFolder:String = Paths.mods(folder + '/' + relative);
			if(FileSystem.exists(inFolder)) return inFolder;
		}
		for (mod in Mods.getGlobalMods())
		{
			var inGlobal:String = Paths.mods(mod + '/' + relative);
			if(FileSystem.exists(inGlobal)) return inGlobal;
		}
		var inMods:String = Paths.mods(relative);
		if(FileSystem.exists(inMods)) return inMods;
		#end

		var base:String = Paths.getFolderPath(songPath + '/' + name + '.' + Paths.SOUND_EXT, 'songs');
		#if sys
		if(FileSystem.exists(base)) return base;
		#end
		return null;
	}
}
