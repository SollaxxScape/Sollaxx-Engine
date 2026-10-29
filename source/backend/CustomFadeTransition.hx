package backend;

import haxe.Json;
import objects.HealthIcon;

typedef StickerData =
{
	var char:String;
	var x:Float;
	var y:Float;
	var scale:Float;
	var angle:Float;
	var losing:Bool;
	var order:Float;
	// Solid backing tile (0 = this sticker is decoration only). The backing tiles split the screen exactly, so nothing can peek through
	var cx:Float;
	var cy:Float;
	var backW:Float;
	var backH:Float;
}

typedef StickerConfig =
{
	var soundFolder:String;
	var soundPrefix:String;
	var soundCount:Int;
	var volume:Float;
}

/**
 * V-Slice style sticker transition (replaces the fade).
 *
 * Leaving a state covers the screen with icons that pop up one by one, entering a state pops the same icons away again.
 * - Base game: icons come from images/Icons (then images/icons)
 * - Mods: icons come from the mod you're in (mods/<mod>/images/icons or Icons)
 * - Every icon is randomly the normal or the losing icon
 * - Every icon sits on a solid tile, the tiles cover the whole screen, so you never see the old screen between the icons
 *
 * Every pop plays a random sound out of a folder. Defaults to
 *   assets/shared/sounds/stickersounds/keys/KeyClick1.ogg ... KeyClick9.ogg
 * and can be changed with a data/stickerTransition.json file (assets/shared/data or a mod's data folder):
 *   { "soundFolder": "stickersounds/keys", "soundPrefix": "KeyClick", "soundCount": 9, "volume": 0.7 }
 * (soundFolder is relative to the "sounds" folder, soundCount = how many files there are, set it to 0 for no sounds)
 */
class CustomFadeTransition extends MusicBeatSubstate {
	public static var finishCallback:Void->Void;

	// The sticker layout is kept so the next state can pop the exact same stickers away
	static var lastLayout:Array<StickerData> = null;

	// Color of the tiles behind the icons
	static var tileColor:FlxColor = 0xFF000000;

	var isTransIn:Bool = false;
	var duration:Float;

	var data:Array<StickerData> = [];
	var stickers:Array<HealthIcon> = [];
	var backings:Array<FlxSprite> = [];
	var config:StickerConfig;
	var timeIn:Float = 0;
	var nextIndex:Int = 0;
	var lastSoundTime:Float = -1;
	var handedOver:Bool = false;
	var transCam:FlxCamera;

	public function new(duration:Float, isTransIn:Bool)
	{
		this.duration = duration;
		this.isTransIn = isTransIn;
		super();
	}

	override function create()
	{
		// The stickers live on their own camera layer on top of everything, so state camera zooms/shakes never touch them
		transCam = new FlxCamera();
		transCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(transCam, false);
		cameras = [transCam];
		var width:Int = FlxG.width;
		var height:Int = FlxG.height;

		config = loadConfig();

		if(isTransIn && lastLayout != null) data = lastLayout;
		else data = lastLayout = buildLayout(width, height);
		data.sort(function(a:StickerData, b:StickerData) return (a.order < b.order) ? -1 : 1);

		// Backing tiles first, so every icon is drawn above every tile
		for (d in data)
		{
			if(d.backW > 0)
			{
				var tile:FlxSprite = new FlxSprite().makeGraphic(Std.int(Math.ceil(d.backW)), Std.int(Math.ceil(d.backH)), tileColor);
				tile.scrollFactor.set();
				tile.antialiasing = false;
				tile.setPosition(d.cx - tile.width / 2, d.cy - tile.height / 2);
				tile.scale.set(isTransIn ? 1 : 0, isTransIn ? 1 : 0);
				tile.visible = isTransIn;
				add(tile);
				backings.push(tile);
			}
			else backings.push(null);
		}

		for (d in data)
		{
			var icon:HealthIcon = new HealthIcon(d.char);
			icon.scrollFactor.set();
			if(d.losing) icon.setIconState('losing');
			icon.angle = d.angle;
			icon.setPosition(d.x - 75, d.y - 75); // icons are drawn around the middle of a 150x150 box
			icon.scale.set(isTransIn ? d.scale : 0, isTransIn ? d.scale : 0);
			icon.visible = isTransIn;
			add(icon);
			stickers.push(icon);
		}

		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if(handedOver) return;

		timeIn += elapsed;
		var total:Float = Math.max(duration, 0.1) * 1.5;
		var lastPop:Float = total * 0.8;
		while(nextIndex < data.length && timeIn >= data[nextIndex].order * lastPop)
		{
			popSticker(nextIndex);
			nextIndex++;
		}

		// Wait until the last sticker finished popping before handing over
		if(nextIndex >= data.length && timeIn >= Math.max(total, lastPop + 0.2))
		{
			handedOver = true;
			if(isTransIn)
				close();
			else
			{
				// Leaving the state: the stickers stay on screen until the next state takes over (no flash in between)
				if(finishCallback != null)
				{
					var callback:Void->Void = finishCallback;
					finishCallback = null;
					callback();
				}
			}
		}
	}

	function popSticker(index:Int)
	{
		var icon:HealthIcon = stickers[index];
		var tile:FlxSprite = backings[index];
		var d:StickerData = data[index];
		playClick();

		if(isTransIn)
		{
			FlxTween.tween(icon.scale, {x: 0, y: 0}, 0.12, {ease: FlxEase.quadIn, onComplete: function(_) icon.visible = false});
			if(tile != null)
				FlxTween.tween(tile.scale, {x: 0, y: 0}, 0.12, {ease: FlxEase.quadIn, onComplete: function(_) tile.visible = false});
		}
		else
		{
			icon.visible = true;
			FlxTween.tween(icon.scale, {x: d.scale, y: d.scale}, 0.15, {ease: FlxEase.backOut});
			if(tile != null)
			{
				tile.visible = true;
				FlxTween.tween(tile.scale, {x: 1, y: 1}, 0.1, {ease: FlxEase.quadOut});
			}
		}
	}

	function playClick()
	{
		if(config.soundCount <= 0 || timeIn - lastSoundTime < 0.03) return;
		lastSoundTime = timeIn;

		var number:Int = FlxG.random.int(1, config.soundCount);
		var snd = Paths.returnSound('sounds/' + config.soundFolder + '/' + config.soundPrefix + number, null, true, false);
		if(snd != null) FlxG.sound.play(snd, config.volume * FlxG.random.float(0.7, 1));
	}

	static function loadConfig():StickerConfig
	{
		var cfg:StickerConfig = {soundFolder: 'stickersounds/keys', soundPrefix: 'KeyClick', soundCount: 9, volume: 0.7};
		try
		{
			var raw:String = Paths.getTextFromFile('data/stickerTransition.json');
			if(raw != null)
			{
				var json:Dynamic = Json.parse(raw);
				if(json.soundFolder != null) cfg.soundFolder = json.soundFolder;
				if(json.soundPrefix != null) cfg.soundPrefix = json.soundPrefix;
				if(json.soundCount != null) cfg.soundCount = Std.int(json.soundCount);
				if(json.volume != null) cfg.volume = json.volume;
			}
		}
		catch(e:Dynamic) {}
		return cfg;
	}

	// Icons that are never used for stickers (matched anywhere in the icon name). Add more names here if needed
	static var blockedIcons:Array<String> = ['senpai', 'thorns', 'spirit'];
	static function isBlocked(name:String):Bool
	{
		for (blocked in blockedIcons)
			if(name.contains(blocked)) return true;
		return false;
	}

	// Every icon name that exists in the icon folder of the mod you're in (or the base game when you're not in a mod)
	static function collectIconNames():Array<String>
	{
		var names:Array<String> = [];
		function scan(dir:String)
		{
			#if sys
			if(!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return;
			for (file in FileSystem.readDirectory(dir))
			{
				if(!file.endsWith('.png')) continue;
				var name:String = file.substr(0, file.length - 4);
				if(name.startsWith('icon-')) name = name.substr(5);
				// Never use pixel icons or the placeholder face icon for stickers
				var lower:String = name.toLowerCase();
				if(lower.contains('pixel') || lower.contains('face')) continue;
				if(isBlocked(lower)) continue;
				// An icon that can't be found falls back to icon-face, never use those either
				var resolved:String = HealthIcon.resolveIconPath(name).toLowerCase();
				if(resolved.endsWith('face') || resolved.contains('pixel') || isBlocked(resolved)) continue;
				if(!names.contains(name)) names.push(name);
			}
			#end
		}

		var mod:String = Mods.currentModDirectory;
		#if MODS_ALLOWED
		if(mod != null && mod.length > 0)
		{
			scan(Paths.mods(mod + '/images/icons'));
			scan(Paths.mods(mod + '/images/Icons'));
		}
		#end

		if(names.length < 1) // base game, or a mod without icons
		{
			scan('assets/shared/images/Icons');
			scan('assets/shared/images/icons');
		}
		return names;
	}

	static function buildLayout(width:Int, height:Int):Array<StickerData>
	{
		var names:Array<String> = collectIconNames();
		if(names.length < 1) return []; // nothing usable to show, no stickers
		FlxG.random.shuffleArray(names, 2);
		var pool:Array<String> = names.slice(0, 30); // as many different icons as possible

		// Balanced picking: every icon is used once before any icon is used again, and an icon is never
		// placed next to (or on top of) the same icon
		var bag:Array<String> = [];
		var lastChar:String = '';
		function nextChar(avoid:Array<String>):String
		{
			if(bag.length < 1)
			{
				bag = pool.copy();
				FlxG.random.shuffleArray(bag, 2);
			}
			var pick:Int = 0;
			for (i in 0...bag.length)
			{
				if(!avoid.contains(bag[i]))
				{
					pick = i;
					break;
				}
			}
			lastChar = bag.splice(pick, 1)[0];
			return lastChar;
		}

		var list:Array<StickerData> = [];
		var cols:Int = Math.ceil(width / 170);
		var rows:Int = Math.ceil(height / 170);
		var cellW:Float = width / cols;
		var cellH:Float = height / rows;

		// One tile per cell. The tiles split the screen exactly (+2px overlap), so the whole screen is covered once they all popped
		var cellChars:Array<String> = [];
		for (r in 0...rows)
		{
			for (c in 0...cols)
			{
				var centerX:Float = (c + 0.5) * cellW;
				var centerY:Float = (r + 0.5) * cellH;
				var avoid:Array<String> = [lastChar];
				if(c > 0) avoid.push(cellChars[r * cols + c - 1]);
				if(r > 0) avoid.push(cellChars[(r - 1) * cols + c]);
				var chosen:String = nextChar(avoid);
				cellChars.push(chosen);
				list.push({
					char: chosen,
					x: centerX + FlxG.random.float(-20, 20),
					y: centerY + FlxG.random.float(-20, 20),
					scale: FlxG.random.float(2.0, 2.6),
					angle: FlxG.random.float(-25, 25),
					losing: FlxG.random.bool(35),
					order: FlxG.random.float(0, 1),
					cx: centerX,
					cy: centerY,
					backW: cellW + 2,
					backH: cellH + 2
				});
			}
		}

		// Extra decoration icons on the corners between the tiles, so the seams between tiles are covered by icons too
		for (r in 0...rows + 1)
		{
			for (c in 0...cols + 1)
			{
				list.push({
					char: nextChar([lastChar]),
					x: (c * cellW) + FlxG.random.float(-20, 20),
					y: (r * cellH) + FlxG.random.float(-20, 20),
					scale: FlxG.random.float(2.0, 2.6),
					angle: FlxG.random.float(-25, 25),
					losing: FlxG.random.bool(35),
					order: FlxG.random.float(0, 1),
					cx: 0,
					cy: 0,
					backW: 0,
					backH: 0
				});
			}
		}
		return list;
	}

	override function destroy()
	{
		if(transCam != null && FlxG.cameras.list.contains(transCam))
			FlxG.cameras.remove(transCam, true);
		transCam = null;
		super.destroy();
	}

	// Don't delete this
	override function close():Void
	{
		super.close();

		if(finishCallback != null)
		{
			finishCallback();
			finishCallback = null;
		}
	}
}
