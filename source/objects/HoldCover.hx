package objects;

import flixel.FlxG;
import flixel.FlxSprite;
import backend.Paths;
import backend.Mods;
import backend.Conductor;
import backend.ClientPrefs;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.utils.Assets as OpenFlAssets;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

typedef HoldCoverArt =
{
	var keys:Array<String>; // image key for purple, blue, green, red
}

class HoldCover extends FlxSprite
{
	public static var colors:Array<String> = ['Purple', 'Blue', 'Green', 'Red'];

	public var strum:StrumNote;
	public var isPlayer:Bool = false;
	public var valid:Bool = false;

	var lastHitTime:Float = -999999;

	// Image key of the art of one color (png + xml), null when there is none
	public static function findKey(color:String):String
	{
		var dirs:Array<String> = ['HoldNoteEffect', 'holdNoteEffect', 'holdnoteeffect'];
		var name:String = 'holdCover' + color;

		#if MODS_ALLOWED
		// The mod you're playing always wins over the base game
		var mod:String = Mods.currentModDirectory;
		if(mod != null && mod.length > 0)
		{
			for (dir in dirs)
				if(FileSystem.exists(Paths.mods(mod + '/images/' + dir + '/' + name + '.png'))
					&& FileSystem.exists(Paths.mods(mod + '/images/' + dir + '/' + name + '.xml')))
					return dir + '/' + name;
		}
		#end

		for (dir in dirs)
			if(Paths.fileExists('images/' + dir + '/' + name + '.png', IMAGE) && Paths.fileExists('images/' + dir + '/' + name + '.xml', TEXT))
				return dir + '/' + name;

		#if sys
		for (dir in dirs)
			if(FileSystem.exists('assets/shared/images/' + dir + '/' + name + '.png') && FileSystem.exists('assets/shared/images/' + dir + '/' + name + '.xml'))
				return dir + '/' + name;
		#end

		return null;
	}

	public function new(strum:StrumNote, isPlayer:Bool, color:String, key:String)
	{
		super();
		this.strum = strum;
		this.isPlayer = isPlayer;
		visible = false;
		scrollFactor.set();

		try
		{
			frames = loadAtlas(key);
			if(frames == null)
			{
				active = false;
				return;
			}

			// The animation names of your xml (the exact names "holdCover<Color>" / "holdCoverEnd<Color>" are tried first)
			var holdPrefix:String = findPrefix(color, false);
			var endPrefix:String = findPrefix(color, true);
			if(holdPrefix == null)
			{
				active = false;
				return;
			}

			animation.addByPrefix('hold', holdPrefix, 24, true);
			if(endPrefix != null) animation.addByPrefix('end', endPrefix, 24, false);

			valid = animation.exists('hold');
			if(!valid)
			{
				trace('Hold cover art "' + key + '": the animation "' + holdPrefix + '" has no frames');
				active = false;
				return;
			}

			antialiasing = ClientPrefs.data.antialiasing;
			animation.play('hold');
		}
		catch(e:Dynamic)
		{
			trace('Hold cover could not be loaded: ' + e);
			valid = false;
			active = false;
		}
	}

	// DO NOT PUT IT TO FALSE YOU WILL FUCKING BREAK IT
	public static var useFixedOffsets:Bool = true;

	// Loads png + xml without depending on the engine's asset lists, so the reason for a failure is always shown
	static function loadAtlas(key:String):FlxAtlasFrames
	{
		var graphic:FlxGraphic = Paths.image(key);
		if(graphic == null)
		{
			trace('Hold cover: the image "' + key + '" could not be loaded');
			return null;
		}

		var xmlText:String = null;
		var tried:Array<String> = [];

		#if MODS_ALLOWED
		var modXml:String = Paths.modsXml(key);
		tried.push(modXml);
		if(FileSystem.exists(modXml)) xmlText = File.getContent(modXml);
		#end

		if(xmlText == null)
		{
			var path:String = Paths.getPath('images/' + key + '.xml', TEXT);
			tried.push(path);
			#if sys
			if(FileSystem.exists(path)) xmlText = File.getContent(path);
			#end
			if(xmlText == null && OpenFlAssets.exists(path, TEXT)) xmlText = OpenFlAssets.getText(path);
		}

		if(xmlText == null || xmlText.length < 1)
		{
			trace('Hold cover: the xml of "' + key + '" was not found or is empty, looked at: ' + tried.join(' | '));
			return null;
		}

		return FlxAtlasFrames.fromSparrow(graphic, xmlText);
	}

	// Finds the animation (frame name without the number at the end) of a color in the atlas
	function findPrefix(color:String, isEnd:Bool):String
	{
		var prefixes:Array<String> = [];
		for (frame in frames.frames)
		{
			var name:String = frame.name;
			var end:Int = name.length;
			while(end > 0 && name.charCodeAt(end - 1) >= 48 && name.charCodeAt(end - 1) <= 57) end--;
			var prefix:String = name.substr(0, end);
			if(!prefixes.contains(prefix)) prefixes.push(prefix);
		}

		var exact:String = isEnd ? 'holdCoverEnd' + color : 'holdCover' + color;
		if(prefixes.contains(exact)) return exact;

		// Not the exact name: take the closest one (any case, anything extra in the name)
		var wantedColor:String = color.toLowerCase();
		for (prefix in prefixes)
		{
			var lower:String = prefix.toLowerCase();
			if(lower.contains('holdcover') && lower.contains(wantedColor) && lower.contains('end') == isEnd)
				return prefix;
		}

		if(!isEnd)
			trace('Hold cover: no "' + exact + '" animation in the xml, the xml has: ' + prefixes.join(', '));
		return null;
	}

	function followStrum()
	{
		if(useFixedOffsets)
		{
			x = strum.x - 110;
			y = strum.y - 100;
		}
		else
		{
			x = strum.x + strum.width / 2 - frameWidth / 2;
			y = strum.y + strum.height / 2 - frameHeight / 2;
		}
		alpha = Math.max(strum.alpha, 0.001) < 0.05 ? 1 : strum.alpha; // a hidden (alpha 0) strum doesn't hide the cover forever
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if(!valid || !visible || strum == null) return;

		followStrum();

		var name:String = animation.curAnim != null ? animation.curAnim.name : '';
		if(name == 'end')
		{
			if(animation.curAnim.finished) visible = false;
		}
		else if(Conductor.songPosition - lastHitTime > Conductor.stepCrochet * 1.5)
		{
			// No sustain hit for a step: the player plays the end animation, the opponent just stops
			if(isPlayer && animation.exists('end'))
				animation.play('end', true);
			else
				visible = false;
		}
	}

	// A piece of a sustain was hit
	static var tracedFirstHit:Bool = false;
	static var tracedPosition:Bool = false;
	public function hit()
	{
		if(!valid || strum == null) return;
		if(!tracedFirstHit)
		{
			tracedFirstHit = true;
			trace('Hold cover: first sustain hit, cover starts playing (' + (isPlayer ? 'player' : 'opponent') + ')');
		}

		lastHitTime = Conductor.songPosition;
		followStrum();
		visible = true;
		exists = true;
		active = true;

		if(!tracedPosition)
		{
			tracedPosition = true;
			trace('Hold cover position: cover x=' + x + ' y=' + y + ' size=' + frameWidth + 'x' + frameHeight + ' alpha=' + alpha
				+ ' | strum x=' + strum.x + ' y=' + strum.y + ' size=' + strum.width + 'x' + strum.height + ' alpha=' + strum.alpha
				+ ' | cameras=' + cameras.length);
		}

		var name:String = animation.curAnim != null ? animation.curAnim.name : '';
		if(name != 'hold')
			animation.play('hold', true);
	}
}
