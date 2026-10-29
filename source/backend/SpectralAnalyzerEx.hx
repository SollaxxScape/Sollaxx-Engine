package backend;

import lime.media.AudioBuffer;

typedef VizLevel =
{
	var value:Float;
	var peak:Float;
}

/**
 * Self-contained spectrum analyzer for the A-Bot speaker visualizer (Nene / Pico stages).
 * It reads the decoded audio of the song's instrumental (FlxG.sound.music) at the current playback position
 * and measures a few frequency bands with the Goertzel algorithm. No funkin.vis / grig.audio libraries needed.
 */
class SpectralAnalyzerEx
{
	// Analysis window in samples. Bigger = better bass resolution (never goes below 1024)
	public var fftN:Int = 1024;

	// Quietest / loudest level (in dB) that is mapped to 0 / 1
	public var minDb:Float = -60;
	public var maxDb:Float = -20;

	var sound:FlxSound;
	var barCount:Int;
	var maxDelta:Float;
	var peakHold:Int;

	var levels:Array<VizLevel> = [];
	var barFrequencies:Array<Array<Float>> = [];
	var peakAge:Array<Int> = [];
	var samples:Array<Float> = [];
	var window:Array<Float> = [];
	var windowSize:Int = 0;

	public function new(?sound:FlxSound, barCount:Int = 7, maxDelta:Float = 0.1, peakHold:Int = 40)
	{
		this.sound = sound;
		this.barCount = barCount;
		this.maxDelta = maxDelta;
		this.peakHold = peakHold;

		// Log spaced bands between 50 Hz and 7 kHz, 3 measuring points inside every band
		var lowest:Float = 50;
		var highest:Float = 7000;
		for (i in 0...barCount)
		{
			var lo:Float = lowest * Math.pow(highest / lowest, i / barCount);
			var hi:Float = lowest * Math.pow(highest / lowest, (i + 1) / barCount);
			barFrequencies.push([lo * Math.pow(hi / lo, 0.2), lo * Math.pow(hi / lo, 0.5), lo * Math.pow(hi / lo, 0.8)]);
			levels.push({value: 0, peak: 0});
			peakAge.push(0);
		}
	}

	public function recycledLevels():Array<VizLevel>
	{
		var buffer:AudioBuffer = null;
		if(sound != null && sound.playing)
		{
			@:privateAccess
			if(sound._sound != null) buffer = sound._sound.__buffer;
		}

		if(buffer == null || buffer.data == null || buffer.channels < 1 || buffer.bitsPerSample != 16)
		{
			fall();
			return levels;
		}

		var n:Int = Std.int(Math.max(fftN, 1024));
		if(n != windowSize)
		{
			windowSize = n;
			window = [for (i in 0...n) 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (n - 1))]; // Hann window
			samples = [for (i in 0...n) 0.0];
		}

		var channels:Int = buffer.channels;
		var totalFrames:Int = Std.int(buffer.data.length / (2 * channels));
		var start:Int = Std.int((sound.time / 1000) * buffer.sampleRate);
		if(start < 0) start = 0;
		if(start + n > totalFrames) start = totalFrames - n;
		if(start < 0)
		{
			fall();
			return levels;
		}

		// Mix down to mono (16 bit samples)
		var data = buffer.data;
		for (i in 0...n)
		{
			var sum:Float = 0;
			var byteIndex:Int = (start + i) * channels * 2;
			for (c in 0...channels)
			{
				var value:Int = data[byteIndex] | (data[byteIndex + 1] << 8);
				if(value >= 32768) value -= 65536;
				sum += value / 32768.0;
				byteIndex += 2;
			}
			samples[i] = (sum / channels) * window[i];
		}

		var rate:Float = buffer.sampleRate;
		for (bar in 0...barCount)
		{
			var magnitude:Float = 0;
			for (freq in barFrequencies[bar])
				magnitude = Math.max(magnitude, goertzel(freq, rate, n));

			var db:Float = 20 * Math.log(magnitude + 0.000000001) / Math.log(10);
			var target:Float = (db - minDb) / (maxDb - minDb);
			target = target < 0 ? 0 : (target > 1 ? 1 : target);

			// Rises fast, falls slowly
			var level:VizLevel = levels[bar];
			var delta:Float = target - level.value;
			var maxRise:Float = maxDelta * 3;
			delta = delta > maxRise ? maxRise : (delta < -maxDelta ? -maxDelta : delta);
			level.value += delta;

			if(level.value >= level.peak)
			{
				level.peak = level.value;
				peakAge[bar] = 0;
			}
			else if(++peakAge[bar] > peakHold)
				level.peak = Math.max(level.value, level.peak - maxDelta);
		}
		return levels;
	}

	// Nothing is playing (or the audio can't be read): let the bars settle down
	function fall()
	{
		for (i in 0...levels.length)
		{
			levels[i].value = Math.max(0, levels[i].value - maxDelta);
			levels[i].peak = levels[i].value;
		}
	}

	// Amplitude of one frequency inside the (windowed) samples, 1.0 = a full scale sine
	function goertzel(frequency:Float, sampleRate:Float, n:Int):Float
	{
		var k:Float = (n * frequency) / sampleRate;
		var coeff:Float = 2 * Math.cos(2 * Math.PI * k / n);
		var s1:Float = 0;
		var s2:Float = 0;
		for (i in 0...n)
		{
			var s:Float = samples[i] + coeff * s1 - s2;
			s2 = s1;
			s1 = s;
		}
		var power:Float = s1 * s1 + s2 * s2 - coeff * s1 * s2;
		if(power < 0) power = 0;
		return Math.sqrt(power) / (n * 0.25); // Hann window has an average gain of 0.5, /2 for the one sided spectrum
	}
}
