package backend;

import states.editors.content.PsychJsonPrinter;
import haxe.Json;
import lime.utils.Assets;
import objects.Note;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var offset:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	var format:String;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;

	@:optional var disableNoteRGB:Bool;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
}

typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var mustHitSection:Bool;
	@:optional var altAnim:Bool;
	@:optional var gfSection:Bool;
	@:optional var bpm:Float;
	@:optional var changeBPM:Bool;
	@:optional var crossfadeBf:Bool;
	@:optional var crossfadeDad:Bool;
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'sollaxx_v1';

	public static function convert(songJson:Dynamic) // Convert old charts (anything before the Psych V1 layout) to the Sollaxx V1 layout
	{
		if (songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			if (Reflect.hasField(songJson, 'player3'))
				Reflect.deleteField(songJson, 'player3');
		}

		if (songJson.events == null)
		{
			songJson.events = [];
			for (secNum in 0...songJson.notes.length)
			{
				var sec:SwagSection = songJson.notes[secNum];

				var i:Int = 0;
				var notes:Array<Dynamic> = sec.sectionNotes;
				var len:Int = notes.length;
				while (i < len)
				{
					var note:Array<Dynamic> = notes[i];
					if (note[1] < 0)
					{
						songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						notes.remove(note);
						len = notes.length;
					}
					else
						i++;
				}
			}
		}

		var sectionsData:Array<SwagSection> = songJson.notes;
		if (sectionsData == null)
			return;

		for (section in sectionsData)
		{
			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats))
			{
				section.sectionBeats = 4;
				if (Reflect.hasField(section, 'lengthInSteps'))
					Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes)
			{
				var gottaHitNote:Bool = (note[1] < 4) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % 4) + (gottaHitNote ? 0 : 4);

				if (note[3] != null && !Std.isOfType(note[3], String))
					note[3] = Note.defaultNoteTypes[note[3]]; // compatibility with Week 7 and 0.1-0.3 psych charts
			}
		}
	}

	public static var chartPath:String;
	public static var loadedSongName:String;

	public static function loadFromJson(jsonInput:String, ?folder:String):SwagSong
	{
		if (folder == null)
			folder = jsonInput;
		PlayState.SONG = getChart(jsonInput, folder);
		loadedSongName = folder;
		chartPath = _lastPath.replace('/', '\\');
		StageData.loadDirectory(PlayState.SONG);
		return PlayState.SONG;
	}

	static var _lastPath:String;

	public static function getChart(jsonInput:String, ?folder:String):SwagSong
	{
		if (folder == null)
			folder = jsonInput;
		var rawData:String = null;

		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);
		_lastPath = Paths.json('$formattedFolder/$formattedSong');

		#if MODS_ALLOWED
		if (FileSystem.exists(_lastPath))
			rawData = File.getContent(_lastPath);
		else
		#end
		rawData = Assets.getText(_lastPath);

		if (rawData == null) return null;

		var chart:SwagSong = parseJSON(rawData, jsonInput);

		// The chart had to be converted to Sollaxx V1: write it back, so the format in the json file says sollaxx_v1 from now on
		#if MODS_ALLOWED
		if (chart != null && lastParseConverted && FileSystem.exists(_lastPath))
		{
			try
			{
				File.saveContent(_lastPath, PsychJsonPrinter.print(chart, ['sectionNotes', 'events']));
				trace('saved converted chart "$_lastPath" as ${chart.format}');
			}
			catch (e:Dynamic)
			{
				trace('could not save the converted chart "$_lastPath": $e');
			}
		}
		#end
		return chart;
	}

	// true when the last parseJSON had to convert the chart to Sollaxx V1
	static var lastParseConverted:Bool = false;

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'sollaxx_v1'):SwagSong
	{
		lastParseConverted = false;
		var songJson:SwagSong = cast Json.parse(rawData);
		if (Reflect.hasField(songJson, 'song'))
		{
			var subSong:SwagSong = Reflect.field(songJson, 'song');
			if (subSong != null && Type.typeof(subSong) == TObject)
				songJson = subSong;
		}

		if (convertTo != null && convertTo.length > 0)
		{
			var fmt:String = songJson.format;
			if (fmt == null)
				fmt = songJson.format = 'unknown';

			switch (convertTo)
			{
				case 'sollaxx_v1':
					if (fmt.startsWith('sollaxx_v1'))
					{
						// already the Sollaxx V1 layout
					}
					else if (fmt.startsWith('psych_v1'))
					{
						// The Psych V1 layout is the same layout, it only gets the Sollaxx V1 name
						trace('converting chart $nameForError from Psych V1 to Sollaxx V1...');
						songJson.format = 'sollaxx_v1';
						lastParseConverted = true;
					}
					else
					{
						// Unknown or old layout: convert it to Sollaxx V1
						// (this is also the place to add other layouts later, like V-Slice charts)
						trace('converting chart $nameForError with format $fmt to Sollaxx V1...');
						songJson.format = 'sollaxx_v1_convert';
						lastParseConverted = true;
						convert(songJson);
					}
			}
		}
		return songJson;
	}
}
