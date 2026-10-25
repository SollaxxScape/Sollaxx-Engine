package objects;

/**
 * Health icon with V-Slice style state transitions.
 *
 * Icon lookup:
 *  - Base game weeks (no mod folder active): images/Icons/<char>.png first, then images/icons/<char>.png
 *  - Mods: the active mod's own images/icons (or images/Icons) folder first, then global mods / base game
 *
 * Supported icon formats:
 *  - Classic sheets: 2 frames (normal, losing) or 3 frames (normal, losing, winning)
 *  - V-Slice style Sparrow atlases (<char>.png + <char>.xml) with the animations
 *    idle, losing, winning, toLosing, fromLosing, toWinning and fromWinning (all but "idle" are optional)
 */
class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	public var canBounce:Bool = false;
	private var isPlayer:Bool = false;
	private var char:String = '';
	private var loadedFromMod:String = null;

	// V-Slice style icon state: 'idle' (normal), 'losing' or 'winning'
	public var iconState(default, null):String = 'idle';
	private var frameCount:Int = 2;
	private var isAtlas:Bool = false;
	private var pendingState:String = null;

	public function new(char:String = 'face', isPlayer:Bool = false, ?allowGPU:Bool = true)
	{
		super();
		this.isPlayer = isPlayer;
		changeIcon(char, allowGPU);
		scrollFactor.set();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y - 30);

		if(canBounce) {
			var mult:Float = FlxMath.lerp(1, scale.x, CoolUtil.boundTo(1 - (elapsed * 9), 0, 1));
			scale.set(mult, mult);
			updateHitbox();
		}
	}

	/**
	 * Works out which image (relative to images/) should be used for a character icon.
	 * Base game -> "Icons" folder first. Mod -> the mod's own folder first.
	 */
	public static function resolveIconPath(char:String):String
	{
		var names:Array<String> = [char, 'icon-' + char]; // 'icon-' is the older psych engine naming
		var dirs:Array<String> = ['Icons', 'icons'];

		var modDir:String = Mods.currentModDirectory;
		if(modDir != null && modDir.length > 0)
		{
			dirs = ['icons', 'Icons'];
			#if MODS_ALLOWED
			// The mod you're playing always wins over everything else
			for (d in dirs)
				for (n in names)
					if(FileSystem.exists(Paths.mods(modDir + '/images/' + d + '/' + n + '.png')))
						return d + '/' + n;
			#end
		}

		for (d in dirs)
			for (n in names)
				if(Paths.fileExists('images/' + d + '/' + n + '.png', IMAGE))
					return d + '/' + n;

		// Prevents crash from missing icon
		for (d in dirs)
			for (n in ['icon-face', 'face'])
				if(Paths.fileExists('images/' + d + '/' + n + '.png', IMAGE))
					return d + '/' + n;

		return 'icons/icon-face';
	}

	private var iconOffsets:Array<Float> = [0, 0];
	public function changeIcon(char:String, ?allowGPU:Bool = true) {
		var modDir:String = Mods.currentModDirectory;
		if(this.char != char || loadedFromMod != modDir) {
			var name:String = resolveIconPath(char);

			isAtlas = Paths.fileExists('images/' + name + '.xml', TEXT);
			iconState = 'idle';
			pendingState = null;

			if(isAtlas)
			{
				frames = Paths.getSparrowAtlas(name, null, allowGPU);
				animation.finishCallback = onAnimFinished;

				addAtlasAnim('idle', ['idle', 'Idle', 'normal', 'Normal'], true);
				addAtlasAnim('losing', ['losing', 'Losing', 'lose'], true);
				addAtlasAnim('winning', ['winning', 'Winning', 'win'], true);
				addAtlasAnim('toLosing', ['toLosing', 'tolosing', 'ToLosing', 'to losing'], false);
				addAtlasAnim('fromLosing', ['fromLosing', 'fromlosing', 'FromLosing', 'from losing'], false);
				addAtlasAnim('toWinning', ['toWinning', 'towinning', 'ToWinning', 'to winning'], false);
				addAtlasAnim('fromWinning', ['fromWinning', 'fromwinning', 'FromWinning', 'from winning'], false);

				if(!animation.exists('idle')) // not a real V-Slice atlas, play whatever is first
				{
					var firstFrame = frames.frames[0];
					animation.addByPrefix('idle', firstFrame.name.substr(0, Std.int(Math.max(0, firstFrame.name.length - 4))), 24, true, isPlayer);
				}
				animation.play('idle', true);

				iconOffsets[0] = (frameWidth - 150) / 2;
				iconOffsets[1] = (frameHeight - 150) / 2;
			}
			else
			{
				var graphic = Paths.image(name, allowGPU);
				frameCount = (graphic.width / graphic.height >= 2.5) ? 3 : 2;
				loadGraphic(graphic, true, Math.floor(graphic.width / frameCount), Math.floor(graphic.height));
				iconOffsets[0] = (width - 150) / 2;
				iconOffsets[1] = (height - 150) / 2;

				animation.add(char, (frameCount == 3) ? [0, 1, 2] : [0, 1], 0, false, isPlayer);
				animation.play(char);
			}
			updateHitbox();

			this.char = char;
			this.loadedFromMod = modDir;

			if(char.endsWith('-pixel'))
				antialiasing = false;
			else
				antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	private function addAtlasAnim(name:String, prefixes:Array<String>, loop:Bool)
	{
		for (prefix in prefixes)
		{
			animation.addByPrefix(name, prefix, 24, loop, isPlayer);
			if(animation.exists(name)) return;
		}
	}

	/**
	 * Switches between the normal / losing / winning icon the way V-Slice does.
	 * Atlas icons play their toX / fromX transition animations when they have them,
	 * classic sheets swap frames with a quick squash. The host (PlayState) lerps the scale
	 * back to 1 every frame, which is what turns the squash into the smooth transition.
	 */
	public function setIconState(newState:String):Void
	{
		if(newState == iconState) return;

		var oldState:String = iconState;
		iconState = newState;

		if(isAtlas)
		{
			pendingState = null;
			var transition:String = null;
			if(oldState == 'idle')
				transition = (newState == 'losing') ? 'toLosing' : 'toWinning';
			else if(newState == 'idle')
				transition = (oldState == 'losing') ? 'fromLosing' : 'fromWinning';

			if(transition != null && animation.exists(transition))
			{
				pendingState = newState;
				animation.play(transition, true);
			}
			else
				playAtlasState(newState);
		}
		else
		{
			if(animation.curAnim != null)
			{
				var frame:Int = 0;
				if(newState == 'losing') frame = 1;
				else if(newState == 'winning') frame = (frameCount >= 3) ? 2 : 0;
				if(animation.curAnim.curFrame != frame) // 2-frame sheets have no winning icon, nothing to transition to
				{
					animation.curAnim.curFrame = frame;
					scale.set(0.8, 0.8);
					updateHitbox();
				}
			}
		}
	}

	private function playAtlasState(state:String)
	{
		if(animation.exists(state)) animation.play(state, true);
		else animation.play('idle', true);
	}

	private function onAnimFinished(name:String)
	{
		if(pendingState != null && (name == 'toLosing' || name == 'toWinning' || name == 'fromLosing' || name == 'fromWinning'))
		{
			var target:String = pendingState;
			pendingState = null;
			playAtlasState(target);
		}
	}

	public function bounce() {
		if(canBounce) {
			var mult:Float = 1.2;
			scale.set(mult, mult);
			updateHitbox();
		}
	}

	public var autoAdjustOffset:Bool = true;
	override function updateHitbox()
	{
		super.updateHitbox();
		if(autoAdjustOffset)
		{
			offset.x = iconOffsets[0];
			offset.y = iconOffsets[1];
		}
	}

	public function getCharacter():String {
		return char;
	}
}
