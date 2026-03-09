package;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.input.keyboard.FlxKey;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import haxe.Json;
import nz.script.Bytecode.Value;
import nz.script.Interpreter;
import openfl.utils.Assets;
#if sys
import sys.io.File;
#end

class RhythmGameState extends FlxState {
	static inline var HIT_Y:Float = 540;
	static inline var NOTE_SPAWN_Y:Float = -40;
	static inline var NOTE_SIZE:Int = 28;
	static inline var CHART_DIVISION:Int = 16;
	static inline var CHART_PATH:String = "assets/data/chart_steps16.json";

	var interp:Interpreter;
	var notes:FlxTypedGroup<FlxSprite>;
	var lanes:Array<Float> = [250, 340, 430, 520];
	var receptors:Array<FlxSprite> = [];
	var songTime:Float = 0.0;
	var beatIndex:Int = 0;
	var score:Int = 0;
	var combo:Int = 0;
	var hud:FlxText;
	var laneKeys:Array<FlxKey> = [D, F, J, K];
	var noteSpeed:Float = 280;
	var speedStep:Float = 20;
	var speedMin:Float = 80;
	var speedMax:Float = 900;
	var hitWindowFrames:Int = 10;

	var songMain:FlxSound;
	var songGuitar:FlxSound;
	var guitarMuteTimer:Float = 0;

	var bpm:Float = 148;
	var stepSeconds:Float = 60.0 / 148.0 / 4.0;

	var chartDebug:Bool = false;
	var chartNotes:Array<{step:Int, lane:Int}> = [];
	var chartSpawnIndex:Int = 0;
	var useChart:Bool = false;
	var chartDirty:Bool = false;
	var audioStarted:Bool = false;

	var lastSpawnSongTime:Float = -9999;
	var lastSpawnLane:Int = -1;
	var lastSpawnSource:String = "none";
	var debugTrace:Bool = true;

	override public function create():Void {
		super.create();
		FlxG.camera.bgColor = 0xFF101521;

		notes = new FlxTypedGroup<FlxSprite>();
		add(notes);

		interp = new Interpreter(false);
		interp.runFile("assets/scripts/game.nx");
		reloadGameplayConfigFromScript();

		initAudioTracks();
		loadChartData();
		rebuildReceptors();

		hud = new FlxText(16, 16, 760, "");
		hud.setFormat(null, 16, FlxColor.LIME, LEFT);
		add(hud);

		startPlaybackWithPreroll();
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		updateSongClock(elapsed);
		handleChartDebugControls();
		handleGameplayControls();

		if (safeNxBool("allowGameplay", [chartDebug], !chartDebug)) {
			if (useChart) {
				spawnFromChart();
			} else {
				if (nxBool("shouldSpawn", [songTime])) {
					var laneIdx = nxInt("laneForBeat", [beatIndex]);
					dbg('procedural beat=' + beatIndex + ' lane=' + laneIdx + ' t=' + songTime);
					spawnNote(laneIdx, "procedural");
					beatIndex++;
				}
			}
		}

		ensureFailsafeSpawn();

		for (note in notes.members) {
			if (note == null || !note.alive)
				continue;

			if (chartDebug) {
				note.kill();
				continue;
			}

			note.y += noteSpeed * elapsed;
			if (note.y > HIT_Y + 90) {
				note.kill();
				combo = 0;
				score -= nxInt("missScorePenalty", []);
				onMiss(nxFloatCall("missMuteDuration", [], 0.35));
			}
		}

		updateGuitarMute(elapsed);

		var hudFromScript = safeNxString("buildHud", [score, combo, bpm, noteSpeed, hitWindowFrames, chartDebug], "");
		if (hudFromScript == "" || hudFromScript == "null") {
			var mode = chartDebug ? "CHART DEBUG [DFJK]" : "PLAY";
			hud.text = 'SCORE: $score  COMBO: $combo\nBPM: $bpm  SPEED(px/s): $noteSpeed  HIT: ${hitWindowFrames}f\nMODE: $mode\nTAB chart | ENTER save | R restart | F3/F4 speed';
		} else {
			hud.text = hudFromScript;
		}
		hud.text += '\nDBG useChart=' + useChart + ' notes=' + chartNotes.length + ' src=' + lastSpawnSource + ' lane=' + lastSpawnLane;
	}

	function reloadGameplayConfigFromScript():Void {
		bpm = nxFloat("bpm", 148);
		noteSpeed = nxFloat("noteSpeed", 280);
		speedStep = nxFloat("speedStep", 20);
		speedMin = nxFloat("speedMin", 80);
		speedMax = nxFloat("speedMax", 900);
		hitWindowFrames = Std.int(nxFloat("hitWindowFrames", 10));
		if (hitWindowFrames <= 0)
			hitWindowFrames = 10;

		var laneCount = nxInt("laneCountValue", []);
		if (laneCount <= 0)
			laneCount = 4;

		lanes = [];
		for (i in 0...laneCount) {
			lanes.push(nxFloatCall("laneX", [i], 250 + i * 90));
		}

		stepSeconds = 60.0 / bpm / 4.0;
		dbg('config lanes=' + lanes + ' bpm=' + bpm + ' noteSpeed=' + noteSpeed + ' stepSeconds=' + stepSeconds);
	}

	function rebuildReceptors():Void {
		for (r in receptors)
			remove(r, true);
		receptors = [];

		for (x in lanes) {
			var receptor = new FlxSprite(x, HIT_Y);
			receptor.makeGraphic(NOTE_SIZE, NOTE_SIZE, FlxColor.WHITE);
			add(receptor);
			receptors.push(receptor);
		}
	}

	function spawnNote(lane:Int, source:String):Void {
		var laneIdx = lane;
		if (laneIdx < 0)
			laneIdx = 0;
		if (laneIdx >= lanes.length)
			laneIdx = lanes.length - 1;

		var note = new FlxSprite(lanes[laneIdx], NOTE_SPAWN_Y);
		note.ID = laneIdx;
		note.makeGraphic(NOTE_SIZE, NOTE_SIZE, FlxColor.CYAN);
		notes.add(note);

		lastSpawnSongTime = songTime;
		lastSpawnLane = laneIdx;
		lastSpawnSource = source;
		dbg('spawn src=' + source + ' laneRaw=' + lane + ' lane=' + laneIdx + ' x=' + lanes[laneIdx] + ' t=' + songTime);
	}

	function ensureFailsafeSpawn():Void {
		if (chartDebug || useChart)
			return;
		if (songTime < 0.8)
			return;
		if (songTime - lastSpawnSongTime < 1.2)
			return;

		var laneIdx = nxInt("laneForBeat", [beatIndex]);
		dbg('failsafe beat=' + beatIndex + ' lane=' + laneIdx + ' t=' + songTime);
		spawnNote(laneIdx, "failsafe");
		beatIndex++;
	}

	function handleGameplayControls():Void {
		if (FlxG.keys.justPressed.F3)
			noteSpeed = nxFloatCall("adjustSpeed", [noteSpeed, -1], Math.max(speedMin, noteSpeed - speedStep));
		if (FlxG.keys.justPressed.F4)
			noteSpeed = nxFloatCall("adjustSpeed", [noteSpeed, 1], Math.min(speedMax, noteSpeed + speedStep));

		if (chartDebug)
			return;

		for (lane in 0...laneKeys.length) {
			if (FlxG.keys.anyJustPressed([laneKeys[lane]]))
				handleHitLane(lane);
		}
	}

	function handleHitLane(lane:Int):Void {
		var target:FlxSprite = null;
		var bestDist = 999999.0;

		for (note in notes.members) {
			if (note == null || !note.alive)
				continue;
			if (note.ID != lane)
				continue;
			var d = Math.abs(note.y - HIT_Y);
			if (d < bestDist) {
				bestDist = d;
				target = note;
			}
		}

		if (target == null) {
			var emptyPenalty = nxInt("emptyHitPenalty", []);
			if (emptyPenalty > 0) {
				score -= emptyPenalty;
				combo = 0;
			}
			return;
		}

		var hitWindowPx = hitWindowPixels();
		var result = nxString("judgeDistance", [bestDist, hitWindowPx]);
		if (result == "none")
			return;

		score += nxInt("scoreDelta", [result, combo]);
		var comboStep = nxInt("comboDelta", [result]);
		if (comboStep < 0)
			combo = 0;
		else
			combo += comboStep;

		target.color = (result == "good") ? FlxColor.YELLOW : FlxColor.GREEN;
		target.kill();
	}

	function hitWindowPixels():Float {
		return nxFloatCall("hitWindowPixels", [noteSpeed], noteSpeed * (hitWindowFrames / 60.0));
	}

	function initAudioTracks():Void {
		var mainPath = findMusicAsset("tv_time");
		var guitarPath = findMusicAsset("tv_time_guitar");
		if (mainPath != null)
			songMain = FlxG.sound.load(mainPath, 0.8, true, false);
		if (guitarPath != null)
			songGuitar = FlxG.sound.load(guitarPath, 1.0, true, false);
	}

	function findMusicAsset(base:String):String {
		var exts = ["ogg", "mp3", "wav"];
		for (ext in exts) {
			var p = 'assets/music/' + base + '.' + ext;
			if (Assets.exists(p))
				return p;
		}
		return null;
	}

	function updateSongClock(elapsed:Float):Void {
		if (!audioStarted) {
			songTime += elapsed;
			if (songTime >= 0) {
				audioStarted = true;
				songTime = 0;
				if (songMain != null) {
					songMain.stop();
					songMain.time = 0;
					songMain.play();
				}
				if (songGuitar != null) {
					songGuitar.stop();
					songGuitar.time = 0;
					songGuitar.volume = 1;
					songGuitar.play();
				}
			}
			return;
		}

		if (songMain != null) {
			songTime = songMain.time / 1000.0;
			if (songTime < 0)
				songTime = 0;
			if (songGuitar != null && songGuitar.playing) {
				var delta = Math.abs(songGuitar.time - songMain.time);
				if (delta > nxFloatCall("syncThresholdMs", [], 20))
					songGuitar.time = songMain.time;
			}
		} else {
			songTime += elapsed;
		}
	}

	function onMiss(?muteSecs:Float):Void {
		if (muteSecs == null)
			muteSecs = nxFloatCall("missMuteDuration", [], 0.35);
		guitarMuteTimer = muteSecs;
		if (songGuitar != null)
			songGuitar.volume = 0;
	}

	function updateGuitarMute(elapsed:Float):Void {
		if (songGuitar == null)
			return;
		if (guitarMuteTimer > 0) {
			guitarMuteTimer -= elapsed;
			if (guitarMuteTimer <= 0)
				songGuitar.volume = 1;
		}
	}

	function currentStep16():Int {
		return nxInt("stepAtTime", [songTime, stepSeconds]);
	}

	function handleChartDebugControls():Void {
		var prevChartMode = chartDebug;
		chartDebug = safeNxBool("nextChartMode", [chartDebug, FlxG.keys.justPressed.TAB], chartDebug);
		if (!prevChartMode && chartDebug)
			clearActiveNotes();

		if (safeNxBool("wantsRestart", [FlxG.keys.justPressed.R], FlxG.keys.justPressed.R))
			restartFromChart();

		if (!safeNxBool("wantsChartInput", [chartDebug], chartDebug))
			return;

		for (lane in 0...laneKeys.length) {
			if (FlxG.keys.anyJustPressed([laneKeys[lane]]))
				addChartNote(currentStep16(), lane);
		}

		if (safeNxBool("wantsSaveChart", [chartDebug, FlxG.keys.justPressed.ENTER], chartDebug && FlxG.keys.justPressed.ENTER))
			saveChartData();
	}

	function addChartNote(step:Int, lane:Int):Void {
		for (n in chartNotes) {
			if (n.step == step && n.lane == lane)
				return;
		}
		chartNotes.push({step: step, lane: lane});
		chartNotes.sort(function(a, b) {
			if (a.step == b.step)
				return a.lane - b.lane;
			return a.step - b.step;
		});
		chartDirty = true;
		useChart = true;
	}

	function spawnFromChart():Void {
		while (chartSpawnIndex < chartNotes.length) {
			var next = chartNotes[chartSpawnIndex];
			var spawnAt = nxFloatCall("noteSpawnTime", [next.step, noteSpeed, stepSeconds, HIT_Y, NOTE_SPAWN_Y], next.step * stepSeconds
				- noteTravelSeconds());
			if (songTime < spawnAt)
				break;
			var laneIdx = next.lane;
			if (laneIdx < 0)
				laneIdx = 0;
			if (laneIdx >= lanes.length)
				laneIdx = lanes.length - 1;
			dbg('chart idx=' + chartSpawnIndex + ' step=' + next.step + ' laneRaw=' + next.lane + ' lane=' + laneIdx + ' t=' + songTime + ' spawnAt=' +
				spawnAt);
			spawnNote(laneIdx, "chart");
			chartSpawnIndex++;
		}
	}

	function loadChartData():Void {
		chartNotes = [];
		chartSpawnIndex = 0;
		chartDirty = false;

		#if sys
		if (!sys.FileSystem.exists(CHART_PATH)) {
			useChart = false;
			dbg('chart missing path=' + CHART_PATH);
			return;
		}

		var raw = File.getContent(CHART_PATH);
		if (raw == null || StringTools.trim(raw) == "") {
			useChart = false;
			dbg('chart empty');
			return;
		}

		var parsed:Dynamic = Json.parse(raw);
		if (parsed != null && Reflect.hasField(parsed, "notes")) {
			var arr:Array<Dynamic> = cast Reflect.field(parsed, "notes");
			for (entry in arr) {
				if (entry == null)
					continue;
				var step = Std.int(Reflect.field(entry, "step"));
				var lane = Std.int(Reflect.field(entry, "lane"));
				if (step >= 0 && lane >= 0 && lane < lanes.length)
					chartNotes.push({step: step, lane: lane});
			}
		}
		#end

		chartNotes.sort(function(a, b) {
			if (a.step == b.step)
				return a.lane - b.lane;
			return a.step - b.step;
		});
		useChart = chartNotes.length > 0;
		if (chartNotes.length > 0) {
			var head = [for (i in 0...Std.int(Math.min(8, chartNotes.length))) chartNotes[i].lane].join(",");
			dbg('chart loaded notes=' + chartNotes.length + ' lanes(head)=' + head + ' useChart=' + useChart);
		} else {
			dbg('chart loaded notes=0 useChart=false');
		}
	}

	function saveChartData():Void {
		#if sys
		var out = {
			bpm: bpm,
			division: CHART_DIVISION,
			notes: chartNotes
		};
		File.saveContent(CHART_PATH, Json.stringify(out, "\t"));
		chartDirty = false;
		#end
	}

	function clearActiveNotes():Void {
		for (note in notes.members) {
			if (note != null && note.alive)
				note.kill();
		}
	}

	function noteTravelSeconds():Float {
		return nxFloatCall("songLeadSeconds", [noteSpeed, stepSeconds, HIT_Y, NOTE_SPAWN_Y], (HIT_Y - NOTE_SPAWN_Y) / noteSpeed);
	}

	function startPlaybackWithPreroll():Void {
		audioStarted = false;
		var lead = noteTravelSeconds();
		songTime = -lead;
		nxCall("resetSongTimeline", [lead]);
		if (songMain != null) {
			songMain.stop();
			songMain.time = 0;
		}
		if (songGuitar != null) {
			songGuitar.stop();
			songGuitar.time = 0;
			songGuitar.volume = 1;
		}
		dbg('start preroll lead=' + lead + ' useChart=' + useChart + ' notes=' + chartNotes.length);
	}

	function restartFromChart():Void {
		if (chartDirty)
			saveChartData();

		loadChartData();
		clearActiveNotes();
		songTime = 0;
		beatIndex = 0;
		chartSpawnIndex = 0;
		combo = 0;
		score = 0;
		guitarMuteTimer = 0;
		startPlaybackWithPreroll();
		dbg('restart chart notes=' + chartNotes.length + ' useChart=' + useChart + ' lanes=' + lanes);
	}

	function nxCall(name:String, args:Array<Dynamic>):Dynamic {
		var vals:Array<Value> = [];
		for (arg in args)
			vals.push(interp.vm.haxeToValue(arg));
		return interp.vm.valueToHaxe(interp.call(name, vals));
	}

	inline function nxBool(name:String, args:Array<Dynamic>):Bool {
		var raw = Std.string(nxCall(name, args)).toLowerCase();
		if (raw == "true" || raw == "1")
			return true;
		if (raw == "false" || raw == "0")
			return false;
		var n = Std.parseFloat(raw);
		if (!Math.isNaN(n))
			return n != 0;
		return false;
	}

	inline function nxInt(name:String, args:Array<Dynamic>):Int {
		return Std.int(nxCall(name, args));
	}

	inline function nxString(name:String, args:Array<Dynamic>):String {
		return Std.string(nxCall(name, args));
	}

	inline function nxFloat(name:String, fallback:Float):Float {
		var v = interp.getDynamic(name);
		if (v == null)
			return fallback;
		var parsed = Std.parseFloat(Std.string(v));
		if (Math.isNaN(parsed))
			return fallback;
		return parsed;
	}

	inline function nxFloatCall(name:String, args:Array<Dynamic>, fallback:Float):Float {
		var v = nxCall(name, args);
		if (v == null)
			return fallback;
		var parsed = Std.parseFloat(Std.string(v));
		if (Math.isNaN(parsed))
			return fallback;
		return parsed;
	}

	inline function safeNxBool(name:String, args:Array<Dynamic>, fallback:Bool):Bool {
		try {
			var v = nxCall(name, args);
			if (v == null)
				return fallback;

			var raw = Std.string(v).toLowerCase();
			if (raw == "true" || raw == "1")
				return true;
			if (raw == "false" || raw == "0")
				return false;

			var n = Std.parseFloat(raw);
			if (!Math.isNaN(n))
				return n != 0;

			return fallback;
		} catch (_:Dynamic) {
			return fallback;
		}
	}

	inline function safeNxString(name:String, args:Array<Dynamic>, fallback:String):String {
		try {
			return nxString(name, args);
		} catch (_:Dynamic) {
			return fallback;
		}
	}

	inline function dbg(msg:String):Void {
		if (!debugTrace)
			return;
		#if sys
		Sys.println('[RHYTHM-DBG] ' + msg);
		#else
		trace('[RHYTHM-DBG] ' + msg);
		#end
	}
}
