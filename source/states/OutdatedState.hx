package states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.util.FlxGradient;
import flixel.group.FlxGroup;

class OutdatedState extends MusicBeatState
{
	public static var leftState:Bool = false;

	var warnText:FlxText;
	var titleText:FlxText;
	var hintText:FlxText;
	var bg:FlxSprite;
	var gradientBar:FlxSprite;
	var blackFade:FlxSprite;
	var gradientTimer:Float = 0;
	var canInteract:Bool = false;
	var leaving:Bool = false;

	override function create()
	{
		#if desktop
		MusicBeatState.windowNameSuffix = " - Outdated Warning";
		#end

		super.create();

		leftState = false;
		canInteract = false;
		leaving = false;

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);

		gradientBar = FlxGradient.createGradientFlxSprite(Math.round(FlxG.width), 512, [0x008300FF, 0x55311749, 0x88800080], 1, 90, true);
		gradientBar.y = FlxG.height - gradientBar.height;
		gradientBar.scale.y = 0;
		gradientBar.updateHitbox();
		add(gradientBar);
		FlxTween.tween(gradientBar, {'scale.y': 1.3}, 1.5, {ease: FlxEase.quadInOut});

		var topGrad:FlxSprite = FlxGradient.createGradientFlxSprite(FlxG.width, Std.int(FlxG.height * 0.6), [0xFF000000, 0x00000000], 1, 90, true);
		add(topGrad);

		titleText = new FlxText(0, 0, FlxG.width, "OUTDATED VERSION", 64);
		titleText.setFormat("VCR OSD Mono", 64, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.PURPLE);
		titleText.borderSize = 3;
		titleText.screenCenter(X);
		titleText.y = FlxG.height * 0.18;
		titleText.alpha = 0;
		titleText.y -= 60;
		add(titleText);

		warnText = new FlxText(0, 0, FlxG.width,
			"Notice, you're running an\n" +
			"outdated version of Sollaxx Engine (" + MainMenuState.SollaxxEngineVersion + ")\n" +
			"please update to " + TitleState.updateVersion + "!\n\n" +
			"Thank you for using the Engine	!",
			32);
		warnText.setFormat("VCR OSD Mono", 32, FlxColor.WHITE, CENTER);
		warnText.screenCenter(X);
		warnText.y = FlxG.height * 0.42;
		warnText.alpha = 0;
		warnText.y += 40;
		add(warnText);

		hintText = new FlxText(0, 0, FlxG.width, "Press ENTER to update  •  Press ESCAPE to proceed anyway", 24);
		hintText.setFormat("VCR OSD Mono", 24, 0xFFCC66FF, CENTER);
		hintText.screenCenter(X);
		hintText.y = FlxG.height * 0.78;
		hintText.alpha = 0;
		add(hintText);

		blackFade = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		blackFade.alpha = 1;
		add(blackFade);
		FlxTween.tween(blackFade, {alpha: 0}, 0.6, {ease: FlxEase.cubeOut, onComplete: function(_) {
			canInteract = true;
		}});

		FlxTween.tween(titleText, {alpha: 1, y: titleText.y + 60}, 0.7, {ease: FlxEase.cubeOut, startDelay: 0.2});
		FlxTween.tween(warnText, {alpha: 1, y: warnText.y - 40}, 0.7, {ease: FlxEase.cubeOut, startDelay: 0.5});
		FlxTween.tween(hintText, {alpha: 1}, 0.7, {ease: FlxEase.cubeOut, startDelay: 0.8});

		FlxG.camera.flash(FlxColor.PURPLE, 0.5);
	}

	override function update(elapsed:Float)
	{
		gradientTimer += 1;
		gradientBar.scale.y += Math.sin(gradientTimer / 10) * 0.001;
		gradientBar.updateHitbox();
		gradientBar.y = FlxG.height - gradientBar.height;

		if (!leaving && canInteract)
		{
			if (controls.ACCEPT)
			{
				leaving = true;
				CoolUtil.browserLoad("https://github.com/SollaxxScape/Sollaxx-Engine/releases");
				exitScreen();
			}
			else if (controls.BACK)
			{
				leaving = true;
				exitScreen();
			}
		}

		super.update(elapsed);
	}

	function exitScreen()
	{
		canInteract = false;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		FlxTween.tween(warnText, {alpha: 0, y: warnText.y - 60}, 0.5, {ease: FlxEase.cubeIn});
		FlxTween.tween(titleText, {alpha: 0, y: titleText.y - 60}, 0.5, {ease: FlxEase.cubeIn});
		FlxTween.tween(hintText, {alpha: 0}, 0.4);
		FlxTween.tween(gradientBar, {alpha: 0}, 0.6);
		FlxTween.tween(bg, {alpha: 0}, 0.6);
		new FlxTimer().start(0.7, function(_) {
			MusicBeatState.switchState(new MainMenuState());
		});
	}
}