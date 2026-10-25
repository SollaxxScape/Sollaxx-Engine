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
}

typedef StickerConfig =
{
	var soundFolder:String;
	var soundPrefix:String;
	var soundCount:Int;
	var volume:Float;
}

/**
 * V-Slice style sticker transition (replaces the old fade).
 *
 * Leaving a state covers the screen with icons that pop up one by one, entering a state pops the same icons away again.
 * - Base game: icons come from images/Icons (then images/icons)
 * - Mods: icons come from the mod you're in (mods/<mod>/images/icons or Icons)
 * - Every icon is randomly the normal or the losing icon
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

	var isTransIn:Bool = false;
	var duration:Float;

	var data:Array<StickerData> = [];
	var stickers:Array<HealthIcon> = [];
	var config:StickerConfig;
	var timeIn:Float = 0;
	var nextIndex:Int = 0;
	var lastSoundTime:Float = -1;
	var handedOver:Bool = false;

	public function new(duration:Float, isTransIn:Bool)
	{
		this.duration = duration;
		this.isTransIn = isTransIn;
		super();
	}

	override function create()
	{
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length-1]];
		var width:Int = Std.int(FlxG.width / Math.max(camera.zoom, 0.001));
		var height:Int = Std.int(FlxG.height / Math.max(camera.zoom, 0.001));

		config = loadConfig();

		if(isTransIn && lastLayout != null) data = lastLayout;
		else data = lastLayout = buildLayout(width, height);
		data.sort(function(a:StickerData, b:StickerData) return (a.order < b.order) ? -1 : 1);

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
		while(nextIndex < data.length && timeIn >= data[nextIndex].order * total * 0.8)
		{
			popSticker(nextIndex);
			nextIndex++;
		}

		if(nextIndex >= data.length && timeIn >= total)
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
		var d:StickerData = data[index];
		playClick();

		if(isTransIn)
		{
			FlxTween.tween(icon.scale, {x: 0, y: 0}, 0.12, {ease: FlxEase.quadIn, onComplete: function(_) icon.visible = false});
		}
		else
		{
			icon.visible = true;
			FlxTween.tween(icon.scale, {x: d.scale, y: d.scale}, 0.15, {ease: FlxEase.backOut});
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
		if(names.length < 1) names.push('face');
		FlxG.random.shuffleArray(names, 2);
		var pool:Array<String> = names.slice(0, 12);

		var list:Array<StickerData> = [];
		var cols:Int = Math.ceil(width / 170);
		var rows:Int = Math.ceil(height / 170);
		for (r in 0...rows + 1)
		{
			for (c in 0...cols + 1)
			{
				list.push({
					char: FlxG.random.getObject(pool),
					x: (c * width / cols) + FlxG.random.float(-30, 30),
					y: (r * height / rows) + FlxG.random.float(-30, 30),
					scale: FlxG.random.float(2.0, 2.6),
					angle: FlxG.random.float(-25, 25),
					losing: FlxG.random.bool(35),
					order: FlxG.random.float(0, 1)
				});
			}
		}
		return list;
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
