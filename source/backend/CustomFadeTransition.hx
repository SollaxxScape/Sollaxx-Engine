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
 * Leaving a state covers the screen with icons, entering a state clears them away again.
 * - Base game: icons come from images/Icons (then images/icons)
 * - Mods: icons come from the mod you're in (mods/<mod>/images/icons or Icons)
 * - Every icon is randomly the normal or the losing icon
 * - Every icon sits on a solid tile, the tiles cover the whole screen, so you never see the old screen between the icons
 *
 * The style is picked in Options > Visuals ("Icon Transition Style"), the speed with "Icon Transition Speed":
 *  Pop          icons pop up at random
 *  Waves        a wavy front sweeps from the left to the right
 *  Ripple       icons pop outwards from the middle of the screen
 *  Diagonal     a swipe from the top left to the bottom right
 *  Rain         icons drop from the top, column by column, and bounce into place
 *  Checkerboard every other icon first, then the rest fills in
 *  Random       a different style every time
 *
 * Every pop plays a random sound out of a folder. Defaults to
 *   assets/shared/sounds/stickersounds/keys/KeyClick1.ogg ... KeyClick9.ogg
 * and can be changed with a data/stickerTransition.json file (assets/shared/data or a mod's data folder):
 *   { "soundFolder": "stickersounds/keys", "soundPrefix": "KeyClick", "soundCount": 9, "volume": 0.7 }
 * (soundFolder is relative to the "sounds" folder, soundCount = how many files there are, set it to 0 for no sounds)
 */
class CustomFadeTransition extends MusicBeatSubstate {
	public static var finishCallback:Void->Void;

	// Styles that can be picked in the options menu ("Random" picks one of the others every time)
	public static var styles:Array<String> = ['Pop', 'Waves', 'Ripple', 'Diagonal', 'Rain', 'Checkerboard', 'Random'];

	// The sticker layout (and style) is kept so the next state can clear away the exact same stickers
	static var lastLayout:Array<StickerData> = null;
	static var lastStyle:String = 'Pop';

	// Color of the tiles behind the icons
	static var tileColor:FlxColor = 0xFF000000;

	var isTransIn:Bool = false;
	var duration:Float;
	var style:String = 'Pop';

	var data:Array<StickerData> = [];
	var stickers:Array<HealthIcon> = [];
	var backings:Array<FlxSprite> = [];
	var iconBaseY:Array<Float> = [];
	var tileBaseY:Array<Float> = [];
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

		if(isTransIn && lastLayout != null)
		{
			data = lastLayout;
			style = lastStyle;
		}
		else
		{
			style = pickStyle();
			lastStyle = style;
			data = lastLayout = buildLayout(width, height, style);
		}
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
				tileBaseY.push(tile.y);
			}
			else
			{
				backings.push(null);
				tileBaseY.push(0);
			}
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
			iconBaseY.push(icon.y);
		}

		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if(handedOver) return;

		timeIn += elapsed;
		var speed:Float = Math.max(0.25, ClientPrefs.data.transitionSpeed);
		var total:Float = (Math.max(duration, 0.1) * 1.5) / speed;
		var lastPop:Float = total * 0.8;
		while(nextIndex < data.length && timeIn >= data[nextIndex].order * lastPop)
		{
			popSticker(nextIndex);
			nextIndex++;
		}

		// Wait until the last sticker finished its animation before handing over
		var settle:Float = (style == 'Rain') ? 0.55 : 0.4;
		if(nextIndex >= data.length && timeIn >= Math.max(total, lastPop + settle))
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
		var rain:Bool = (style == 'Rain');
		playClick();

		if(isTransIn)
		{
			if(rain)
			{
				// Everything flies back up
				FlxTween.tween(icon, {y: iconBaseY[index] - 900}, 0.3, {ease: FlxEase.quadIn, onComplete: function(_) icon.visible = false});
				if(tile != null)
					FlxTween.tween(tile, {y: tileBaseY[index] - 900}, 0.3, {ease: FlxEase.quadIn, onComplete: function(_) tile.visible = false});
			}
			else
			{
				FlxTween.tween(icon.scale, {x: 0, y: 0}, 0.12, {ease: FlxEase.quadIn, onComplete: function(_) icon.visible = false});
				if(tile != null)
					FlxTween.tween(tile.scale, {x: 0, y: 0}, 0.12, {ease: FlxEase.quadIn, onComplete: function(_) tile.visible = false});
			}
		}
		else
		{
			icon.visible = true;
			if(tile != null) tile.visible = true;

			if(rain)
			{
				// Drop from above the screen and bounce into place
				icon.scale.set(d.scale, d.scale);
				icon.y = iconBaseY[index] - 900;
				FlxTween.tween(icon, {y: iconBaseY[index]}, 0.45, {ease: FlxEase.bounceOut});
				if(tile != null)
				{
					tile.scale.set(1, 1);
					tile.y = tileBaseY[index] - 900;
					FlxTween.tween(tile, {y: tileBaseY[index]}, 0.45, {ease: FlxEase.bounceOut});
				}
			}
			else
			{
				var time:Float = 0.15;
				var ease:Float->Float = FlxEase.backOut;
				switch(style)
				{
					case 'Waves':
						time = 0.35;
						ease = FlxEase.elasticOut;
					case 'Ripple':
						time = 0.22;
					case 'Checkerboard':
						time = 0.28;
						ease = FlxEase.bounceOut;
					default:
				}
				FlxTween.tween(icon.scale, {x: d.scale, y: d.scale}, time, {ease: ease});
				if(tile != null)
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

	static function pickStyle():String
	{
		var chosen:String = ClientPrefs.data.transitionStyle;
		if(chosen == null || !styles.contains(chosen)) chosen = 'Pop';
		if(chosen == 'Random')
		{
			var options:Array<String> = styles.copy();
			options.remove('Random');
			chosen = FlxG.random.getObject(options);
		}
		return chosen;
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

	static function buildLayout(width:Int, height:Int, style:String):Array<StickerData>
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

		// When a sticker pops (0 = first, 1 = last) depends on the style
		var columnDelay:Array<Float> = [for (c in 0...cols + 1) FlxG.random.float(0, 0.55)];
		var maxDistance:Float = Math.sqrt((width / 2) * (width / 2) + (height / 2) * (height / 2));
		function orderFor(px:Float, py:Float):Float
		{
			var nx:Float = px / width;
			var ny:Float = py / height;
			var order:Float = FlxG.random.float(0, 1);
			switch(style)
			{
				case 'Waves':
					order = nx * 0.7 + 0.3 * (0.5 + 0.5 * Math.sin((py / cellH) * 1.1 + nx * 4)) + FlxG.random.float(0, 0.04);
				case 'Ripple':
					var dx:Float = px - width / 2;
					var dy:Float = py - height / 2;
					order = Math.sqrt(dx * dx + dy * dy) / maxDistance + FlxG.random.float(0, 0.05);
				case 'Diagonal':
					order = (nx + ny) / 2 + FlxG.random.float(0, 0.04);
				case 'Rain':
					var column:Int = Std.int(Math.max(0, Math.min(cols, Math.round(px / cellW - 0.5))));
					order = columnDelay[column] + ny * 0.4 + FlxG.random.float(0, 0.04);
				case 'Checkerboard':
					var cell:Int = Math.floor(px / cellW) + Math.floor(py / cellH);
					order = ((cell % 2 == 0) ? 0 : 0.5) + FlxG.random.float(0, 0.45);
				default:
			}
			return Math.max(0, Math.min(0.999, order));
		}

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
					order: orderFor(centerX, centerY),
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
				var cornerX:Float = c * cellW;
				var cornerY:Float = r * cellH;
				list.push({
					char: nextChar([lastChar]),
					x: cornerX + FlxG.random.float(-20, 20),
					y: cornerY + FlxG.random.float(-20, 20),
					scale: FlxG.random.float(2.0, 2.6),
					angle: FlxG.random.float(-25, 25),
					losing: FlxG.random.bool(35),
					order: orderFor(cornerX, cornerY),
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
