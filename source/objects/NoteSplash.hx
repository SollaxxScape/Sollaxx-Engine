package objects;

import states.editors.NoteSplashEditorState;
import haxe.Json;
import backend.animation.PsychAnimationController;

import flixel.util.FlxColor;

private typedef RGB = {
	r:Null<Int>,
	g:Null<Int>,
	b:Null<Int>
}

private typedef NoteSplashAnim = {
	name:String,
	prefix:String,
	maxFps:Int,
	minFps:Int,
	noteData:Int,
	offsets:Array<Int>,
	indices:Array<Int>,
}

typedef NoteSplashConfig = {
	animations:Map<String, NoteSplashAnim>,
	scale:Array<Float>,
	affectedByShader:Bool,
	rgb:Array<Null<RGB>>
}

class NoteSplash extends FlxSprite
{
	public var skin:String;
	public var config(default, set):NoteSplashConfig;
	public static var DEFAULT_SKIN:String = "noteSplashes";
	public static var configs:Map<String, NoteSplashConfig> = new Map();

	public var babyArrow:StrumNote;
	var centerOnStrum:Bool = false; // old style splashes are centered on the strum, whatever size the art is

	var noteDataMap:Map<Int, String> = new Map();

	public function new(?splash:String)
	{
		super();
        animation = new PsychAnimationController(this);

		loadSplash(splash);
	}

	// Psych 0.6.3 splashes: images/<skin>.png + images/<skin>.xml with the animations "note splash purple 1", "note splash blue 2", ...
	// The RGB splash folder (images/noteSplashes/...) is not used anymore
	static function oldSplashExists(skin:String):Bool
	{
		return skin != null && skin.length > 0
			&& Paths.fileExists('images/' + skin + '.png', IMAGE)
			&& Paths.fileExists('images/' + skin + '.xml', TEXT);
	}

	// A mod's own splash: "noteSplash" (png + xml, "noteSplashes" works too) in the mod's images folder (mods/<mod>/images)
	// or in the shared mods images folder (mods/images). It replaces the default splash while that mod is active.
	static function findModSplash():String
	{
		#if MODS_ALLOWED
		var names:Array<String> = ['noteSplashes'];
		var mod:String = Mods.currentModDirectory;
		if (mod != null && mod.length > 0)
		{
			for (name in names)
				if (FileSystem.exists(Paths.mods(mod + '/images/' + name + '.png')) && FileSystem.exists(Paths.mods(mod + '/images/' + name + '.xml')))
					return name;
		}
		for (name in names)
			if (FileSystem.exists(Paths.mods('images/' + name + '.png')) && FileSystem.exists(Paths.mods('images/' + name + '.xml')))
				return name;
		#end
		return null;
	}

	function loadSplash(?splash:String)
	{
		config = null; // Reset config to the default so when reloaded it can be set properly
		skin = null;
		centerOnStrum = false;

		var skin:String = splash;

		if (skin == null || skin.length < 1)
			skin = try PlayState.SONG.splashSkin catch(e) null;

		if (skin == null || skin.length < 1 || !oldSplashExists(skin))
			skin = DEFAULT_SKIN; // not set or not found, back to the default

		// Mods can bring their own splash
		if (skin == DEFAULT_SKIN)
		{
			var modSplash:String = findModSplash();
			if (modSplash != null) skin = modSplash;
		}

		this.skin = skin;
		if (!oldSplashExists(skin))
		{
			active = visible = false;
			return;
		}

		frames = Paths.getSparrowAtlas(skin);

		// Same animations and positions as Psych 0.6.3: two variations for every direction
		var colors:Array<String> = ['purple', 'blue', 'green', 'red'];
		var oldConfig:NoteSplashConfig = createConfig();
		oldConfig.affectedByShader = false;
		for (variation in 1...3)
		{
			for (direction in 0...4)
			{
				var name:String = 'note' + direction + '-' + variation;
				oldConfig.animations.set(name, {
					name: name,
					prefix: 'note splash ' + colors[direction] + ' ' + variation,
					maxFps: 26,
					minFps: 22,
					noteData: direction + (variation - 1) * 4,
					offsets: [Std.int(Note.swagWidth * 0.95 + 10), Std.int(Note.swagWidth + 10)],
					indices: null
				});
			}
		}
		this.config = oldConfig;
		centerOnStrum = true;
	}

	public function spawnSplashNote(note:Note, ?noteData:Int, ?randomize:Bool = true)
	{	
		if (note != null && note.noteSplashData.texture != null)
			loadSplash(note.noteSplashData.texture);

		if (note != null && note.noteSplashData.disabled)
			return;

		if (babyArrow != null)
			setPosition(babyArrow.x, babyArrow.y); // To prevent it from being misplaced for one game tick

		var noteData:Null<Int> = noteData;
		if (noteData == null)
			noteData = note != null ? note.noteData : 0;

		if (randomize)
		{
			var anims:Int = 0;
			var datas:Int = 0;
			var animArray:Array<Int> = [];
			while (true)
			{
				var data:Int = noteData % 4 + (datas * 4); 
				if (!noteDataMap.exists(data) || !animation.exists(noteDataMap[data]))
					break;
				datas++;
				anims++;
			}
			if (anims > 1)
			{
				for (i in 0...anims)
				{
					var data = noteData % 4 + (i * 4);
					if (!animArray.contains(data))
						animArray.push(data);
				}
			}

			if (animArray.length > 1)
				noteData = animArray[FlxG.random.bool() ? 0 : 1];
		}

		var anim:String = null;
		function playDefaultAnim()
		{
			var animation:String = noteDataMap.get(noteData);
			if (animation != null && this.animation.exists(animation))
			{
				this.animation.play(animation);
				anim = animation;
			}
			else
				visible = false;
		}

		playDefaultAnim();

		var conf = config.animations.get(anim);
		var offsets = [0, 0];
		if (conf != null)
			offsets = conf.offsets;
		if (centerOnStrum)
		{
			// Middle of the splash on the middle of the strum
			var strumWidth:Float = (babyArrow != null) ? babyArrow.width : Note.swagWidth;
			var strumHeight:Float = (babyArrow != null) ? babyArrow.height : Note.swagWidth;
			offset.set(frameWidth / 2 - strumWidth / 2, frameHeight / 2 - strumHeight / 2);
		}
		else if (offsets != null)
		{
			centerOffsets();
			offset.set(offsets[0], offsets[1]);
		}
		animation.finishCallback = function(name:String)
		{
			kill();
		};
		
        alpha = ClientPrefs.data.splashAlpha;
		if(note != null) alpha = note.noteSplashData.a;

		if(note != null) antialiasing = note.noteSplashData.antialiasing;
		if(PlayState.isPixelStage) antialiasing = false;

		if(animation.curAnim != null && conf != null)
		{
			var minFps = conf.minFps;
			if (minFps < 0)
				minFps = 0;
			var maxFps = conf.maxFps;
			if (maxFps < 0)
				maxFps = 0;
			animation.curAnim.frameRate = FlxG.random.int(minFps, maxFps);
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (babyArrow != null)
		{
			//cameras = babyArrow.cameras;
			setPosition(babyArrow.x, babyArrow.y);
		}
	}

    public static function getSplashSkinPostfix()
	{
		return ''; // no splash skin selector anymore (Psych 0.6.3 note splashes)
	}

	public static function createConfig():NoteSplashConfig
	{
		return {
			animations: new Map(),
			scale: [1, 1],
			affectedByShader: true,
			rgb: null
		}
	}

	public static function addAnimationToConfig(scale:Array<Float>, config:NoteSplashConfig, name:String, prefix:String, minFps:Int, maxFps:Int, offsets:Array<Int>, indices:Array<Int>, noteData:Int):NoteSplashConfig
	{
		if (config == null)
			config = createConfig();

		config.animations.set(name, {name: name, prefix: prefix, indices: indices, minFps: minFps, maxFps: maxFps, offsets: offsets, noteData: noteData});
		config.scale = scale;
		return config;
	}

	function set_config(value:NoteSplashConfig):NoteSplashConfig 
	{
		if (value == null)
			value = createConfig();

		noteDataMap.clear();

		for (i in value.animations)
		{
			var key:String = i.name;
			if (i.prefix.length > 0 && key != null && key.length > 0)
			{
				if (i.indices != null && i.indices.length > 0 && key != null && key.length > 0)
					animation.addByIndices(key, i.prefix, i.indices, "", i.maxFps, false);
				else
					animation.addByPrefix(key, i.prefix, i.maxFps, false);
				noteDataMap.set(i.noteData, key);
			}
		}
		scale.set(value.scale[0], value.scale[1]);
		return config = value;
	}
}
