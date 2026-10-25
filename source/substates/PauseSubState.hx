package substates;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import flixel.util.FlxStringUtil;
import states.StoryMenuState;
import states.FreeplayState;
import options.OptionsState;
import objects.HealthIcon;
//Nick: i just put this here, it's the same version of Reflection engine xdd
class PauseSubState extends MusicBeatSubstate
{
	var grpMenuShit:FlxTypedGroup<Alphabet>;
	var menuItems:Array<String> = [];
	var menuItemsOG:Array<String> = ['Resume', 'Restart Song', 'Options', 'Exit to menu'];
	var debugChoices:Array<String> = [
		'Toggle Practice Mode',
		'Toggle Botplay',
		'Leave Charting Mode',
		'Skip Time',
		'End Song',
		'BACK'
	];
	var curSelected:Int = 0;
	var pauseMusic:FlxSound;
	var practiceText:FlxText;
	var skipTimeText:FlxText;
	var skipTimeTracker:Alphabet;
	var curTime:Float = Math.max(0, Conductor.songPosition);
	var missingTextBG:FlxSprite;
	var missingText:FlxText;
	var opponentIcon:HealthIcon;
	var bg:FlxSprite;
	var levelInfo:FlxText;
	var levelDifficulty:FlxText;
	var blueballedTxt:FlxText;
	var chartingText:FlxText;

	public static var songName:String = null;
	public static var mustRestart:Bool = false;

	var holdTime:Float = 0;
	var cantUnpause:Float = 0.1;
	var iconTimer:Float = 0;

	override function create()
	{
		menuItems = menuItemsOG;

		if (mustRestart)
		{
			mustRestart = false;
			restartSong(true);
			return;
		}

		pauseMusic = new FlxSound();
		try
		{
			var pauseSong:String = getPauseSong();
			if (pauseSong != null)
				pauseMusic.loadEmbedded(Paths.music(pauseSong), true, true);
		}
		catch (e:Dynamic)
		{
		}
		pauseMusic.volume = 0;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));
		FlxG.sound.list.add(pauseMusic);

		// --- CAMBIO: Obtener color del ícono del oponente y oscurecerlo ---
		var dadColor:FlxColor = FlxColor.BLACK;
		if (PlayState.instance != null && PlayState.instance.dad != null)
		{
			if (PlayState.instance.dad.healthColorArray != null)
			{
				// Oscurecer los colores multiplicándolos por 0.35 (puedes ajustar este valor)
				var r:Int = Std.int(PlayState.instance.dad.healthColorArray[0] * 0.35);
				var g:Int = Std.int(PlayState.instance.dad.healthColorArray[1] * 0.35);
				var b:Int = Std.int(PlayState.instance.dad.healthColorArray[2] * 0.35);
				dadColor = FlxColor.fromRGB(r, g, b);
			}
		}

		bg = new FlxSprite().makeGraphic(1, 1, dadColor);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);

		var formattedSong:String = PlayState.SONG.song;
		if (formattedSong.toLowerCase().endsWith('-old'))
		{
			formattedSong = formattedSong.substring(0, formattedSong.length - 4);
		}
		formattedSong = formattedSong.replace('-', ' ');

		levelInfo = new FlxText(0, -50, 0, formattedSong, 32);
		levelInfo.scrollFactor.set();
		levelInfo.setFormat(Paths.font("vcr.ttf"), 32);
		levelInfo.updateHitbox();
		levelInfo.x = FlxG.width - levelInfo.width - 20;
		add(levelInfo);

		levelDifficulty = new FlxText(0, -50, 0, Difficulty.getString().toUpperCase(), 32);
		levelDifficulty.scrollFactor.set();
		levelDifficulty.setFormat(Paths.font('vcr.ttf'), 32);
		levelDifficulty.updateHitbox();
		levelDifficulty.x = FlxG.width - levelDifficulty.width - 20;
		add(levelDifficulty);

		blueballedTxt = new FlxText(0, -50, 0, Language.getPhrase("blueballed", "Blueballed: {1}", [PlayState.deathCounter]), 32);
		blueballedTxt.scrollFactor.set();
		blueballedTxt.setFormat(Paths.font('vcr.ttf'), 32);
		blueballedTxt.updateHitbox();
		blueballedTxt.x = FlxG.width - blueballedTxt.width - 20;
		add(blueballedTxt);

		practiceText = new FlxText(0, 0, 0, Language.getPhrase("Practice Mode").toUpperCase(), 32);
		practiceText.scrollFactor.set();
		practiceText.setFormat(Paths.font('vcr.ttf'), 32);
		practiceText.x = FlxG.width - practiceText.width - 20;
		practiceText.y = 15 + 101;
		practiceText.updateHitbox();
		practiceText.visible = PlayState.instance.practiceMode;
		add(practiceText);

		chartingText = new FlxText(0, 0, 0, Language.getPhrase("Charting Mode").toUpperCase(), 32);
		chartingText.scrollFactor.set();
		chartingText.setFormat(Paths.font('vcr.ttf'), 32);
		chartingText.x = FlxG.width - chartingText.width - 20;
		chartingText.y = FlxG.height - chartingText.height - 20;
		chartingText.updateHitbox();
		chartingText.visible = PlayState.chartingMode;
		add(chartingText);

		levelInfo.alpha = 0;
		levelDifficulty.alpha = 0;
		blueballedTxt.alpha = 0;

		opponentIcon = new HealthIcon(PlayState.instance.dad.healthIcon, false);
		opponentIcon.scrollFactor.set();
		opponentIcon.x = FlxG.width + 180;
		opponentIcon.y = FlxG.height - opponentIcon.height - 70;
		opponentIcon.alpha = 0;
		add(opponentIcon);

		FlxTween.tween(bg, {alpha: 0.45}, 0.5, {ease: FlxEase.quartOut});
		FlxTween.tween(levelInfo, {alpha: 1, y: 20}, 0.5, {ease: FlxEase.backOut, startDelay: 0.1});
		FlxTween.tween(levelDifficulty, {alpha: 1, y: 20 + 35}, 0.5, {ease: FlxEase.backOut, startDelay: 0.2});
		FlxTween.tween(blueballedTxt, {alpha: 1, y: 20 + 70}, 0.5, {ease: FlxEase.backOut, startDelay: 0.3});
		FlxTween.tween(opponentIcon, {alpha: 1, x: FlxG.width - opponentIcon.width - 40}, 0.6, {ease: FlxEase.backOut, startDelay: 0.2});

		grpMenuShit = new FlxTypedGroup<Alphabet>();
		add(grpMenuShit);

		missingTextBG = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		missingTextBG.scale.set(FlxG.width, FlxG.height);
		missingTextBG.updateHitbox();
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		regenMenu();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		super.create();
	}

	function getPauseSong()
	{
		var formattedSongName:String = (songName != null ? Paths.formatToSongPath(songName) : '');
		var formattedPauseMusic:String = Paths.formatToSongPath(ClientPrefs.data.pauseMusic);
		if (formattedSongName == 'none' || (formattedSongName != 'none' && formattedPauseMusic == 'none'))
			return null;
		return (formattedSongName != '') ? formattedSongName : formattedPauseMusic;
	}

	override function update(elapsed:Float)
	{
		cantUnpause -= elapsed;
		if (pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		iconTimer += elapsed;
		opponentIcon.scale.set(1 + Math.sin(iconTimer * 4) * 0.05, 1 + Math.sin(iconTimer * 4) * 0.05);

		super.update(elapsed);

		if (FlxG.keys.justPressed.R && menuItems != debugChoices)
		{
			menuItems = debugChoices;
			deleteSkipTimeText();
			regenMenu();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		}

		if (controls.BACK)
		{
			if (menuItems == debugChoices)
			{
				menuItems = menuItemsOG;
				deleteSkipTimeText();
				regenMenu();
			}
			else
			{
				animateAndClose();
			}
			return;
		}

		if (FlxG.keys.justPressed.F5)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			MusicBeatState.resetState();
		}

		updateSkipTextStuff();
		if (controls.UI_UP_P)
		{
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			changeSelection(1);
		}

		var daSelected:String = menuItems[curSelected];
		switch (daSelected)
		{
			case 'Skip Time':
				if (controls.UI_LEFT_P)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime -= 1000;
					holdTime = 0;
				}
				if (controls.UI_RIGHT_P)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime += 1000;
					holdTime = 0;
				}

				if (controls.UI_LEFT || controls.UI_RIGHT)
				{
					holdTime += elapsed;
					if (holdTime > 0.5)
					{
						curTime += 45000 * elapsed * (controls.UI_LEFT ? -1 : 1);
					}

					if (curTime >= FlxG.sound.music.length)
						curTime -= FlxG.sound.music.length;
					else if (curTime < 0)
						curTime += FlxG.sound.music.length;
					updateSkipTimeText();
				}
		}

		if (controls.ACCEPT && (cantUnpause <= 0 || !controls.controllerMode))
		{
			switch (daSelected)
			{
				case "Resume":
					animateAndClose();
				case "BACK":
					menuItems = menuItemsOG;
					deleteSkipTimeText();
					regenMenu();
				case 'Toggle Practice Mode':
					PlayState.instance.practiceMode = !PlayState.instance.practiceMode;
					PlayState.changedDifficulty = true;
					practiceText.visible = PlayState.instance.practiceMode;
				case "Restart Song":
					restartSong();
				case "Leave Charting Mode":
					restartSong();
					PlayState.chartingMode = false;
				case 'Skip Time':
					if (curTime < Conductor.songPosition)
					{
						PlayState.startOnTime = curTime;
						restartSong(true);
					}
					else
					{
						if (curTime != Conductor.songPosition)
						{
							PlayState.instance.clearNotesBefore(curTime);
							PlayState.instance.setSongTime(curTime);
						}
						animateAndClose();
					}
				case 'End Song':
					close();
					PlayState.instance.notes.clear();
					PlayState.instance.unspawnNotes = [];
					PlayState.instance.finishSong(true);
				case 'Toggle Botplay':
					PlayState.instance.cpuControlled = !PlayState.instance.cpuControlled;
					PlayState.changedDifficulty = true;
					PlayState.instance.botplayTxt.visible = PlayState.instance.cpuControlled;
					PlayState.instance.botplayTxt.alpha = 1;
					PlayState.instance.botplaySine = 0;
				case 'Options':
					PlayState.instance.paused = true;
					PlayState.instance.vocals.volume = 0;
					PlayState.instance.canResync = false;
					MusicBeatState.switchState(new OptionsState());
					if (ClientPrefs.data.pauseMusic != 'None')
					{
						FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)), pauseMusic.volume);
						FlxTween.tween(FlxG.sound.music, {volume: 1}, 0.8);
						FlxG.sound.music.time = pauseMusic.time;
					}
					OptionsState.onPlayState = true;
				case "Exit to menu":
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
					PlayState.deathCounter = 0;
					PlayState.seenCutscene = false;
					PlayState.instance.canResync = false;
					Mods.loadTopMod();
					if (PlayState.isStoryMode)
						MusicBeatState.switchState(new StoryMenuState());
					else
						MusicBeatState.switchState(new FreeplayState());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					PlayState.changedDifficulty = false;
					PlayState.chartingMode = false;
					FlxG.camera.followLerp = 0;
			}
		}
	}

	function animateAndClose()
	{
		cantUnpause = 100;

		FlxTween.tween(bg, {alpha: 0}, 0.4, {ease: FlxEase.quartIn});
		FlxTween.tween(levelInfo, {alpha: 0, y: -50}, 0.3, {ease: FlxEase.backIn});
		FlxTween.tween(levelDifficulty, {alpha: 0, y: -50}, 0.3, {ease: FlxEase.backIn, startDelay: 0.05});
		FlxTween.tween(blueballedTxt, {alpha: 0, y: -50}, 0.3, {ease: FlxEase.backIn, startDelay: 0.1});
		FlxTween.tween(opponentIcon, {alpha: 0, x: FlxG.width + 180}, 0.4, {ease: FlxEase.backIn});

		if (practiceText.visible)
			FlxTween.tween(practiceText, {alpha: 0}, 0.3);
		if (chartingText.visible)
			FlxTween.tween(chartingText, {alpha: 0}, 0.3);
		if (skipTimeText != null && skipTimeText.visible)
			FlxTween.tween(skipTimeText, {alpha: 0}, 0.2);

		for (num => item in grpMenuShit.members)
		{
			FlxTween.cancelTweensOf(item);
			FlxTween.tween(item, {x: -300, alpha: 0}, 0.35 + (num * 0.04), {
				ease: FlxEase.backIn,
				onComplete: function(twn:FlxTween)
				{
					if (num == grpMenuShit.members.length - 1)
					{
						close();
					}
				}
			});
		}
	}

	function deleteSkipTimeText()
	{
		if (skipTimeText != null)
		{
			skipTimeText.kill();
			remove(skipTimeText);
			skipTimeText.destroy();
		}
		skipTimeText = null;
		skipTimeTracker = null;
	}

	public static function restartSong(noTrans:Bool = false)
	{
		PlayState.instance.paused = true;
		FlxG.sound.music.volume = 0;
		PlayState.instance.vocals.volume = 0;

		if (noTrans)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
		}
		MusicBeatState.resetState();
	}

	override function destroy()
	{
		pauseMusic.destroy();
		super.destroy();
	}

	function changeSelection(change:Int = 0):Void
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, menuItems.length - 1);
		for (num => item in grpMenuShit.members)
		{
			item.targetY = num - curSelected;
			item.alpha = (item.targetY == 0) ? 1 : 0.4;
			item.x = (item.targetY == 0) ? 80 : 60;
			if (item == skipTimeTracker)
			{
				curTime = Math.max(0, Conductor.songPosition);
				updateSkipTimeText();
			}
		}
		missingText.visible = false;
		missingTextBG.visible = false;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function regenMenu():Void
	{
		for (i in 0...grpMenuShit.members.length)
		{
			var obj:Alphabet = grpMenuShit.members[0];
			obj.kill();
			grpMenuShit.remove(obj, true);
			obj.destroy();
		}

		for (num => str in menuItems)
		{
			var item = new Alphabet(80, 240 + (num * 45), Language.getPhrase('pause_$str', str), true);
			item.isMenuItem = true;
			item.targetY = num;
			item.alpha = (num == 0) ? 1 : 0.4;
			grpMenuShit.add(item);

			if (str == 'Skip Time')
			{
				skipTimeText = new FlxText(0, 0, 0, '', 64);
				skipTimeText.setFormat(Paths.font("vcr.ttf"), 64, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				skipTimeText.scrollFactor.set();
				skipTimeText.borderSize = 2;
				skipTimeTracker = item;
				add(skipTimeText);

				updateSkipTextStuff();
				updateSkipTimeText();
			}
		}
		curSelected = 0;
		changeSelection();
	}

	function updateSkipTextStuff()
	{
		if (skipTimeText == null || skipTimeTracker == null)
			return;

		skipTimeText.x = skipTimeTracker.x + skipTimeTracker.width + 30;
		skipTimeText.y = skipTimeTracker.y;
		skipTimeText.visible = (skipTimeTracker.alpha >= 1);
	}

	function updateSkipTimeText()
	{
		skipTimeText.text = FlxStringUtil.formatTime(Math.max(0, Math.floor(curTime / 1000)), false)
			+ ' / '
			+ FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false);
	}
}