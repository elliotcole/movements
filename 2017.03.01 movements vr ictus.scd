/*

MOVEMENTS
ecc draft 03/01/2017
-interactivity method 1: ictus
-ictus is the word conductors use to talk about the exact point at which their hand shows the beat.
-here it refers specifically to a 'down beat' -- ie the hand moving down and bouncing up to show when something is supposed to happen.
-this gesture triggers an event: a single note or a chord, depending on how hard you shake (harder: more notes + more volume)




Overall architecture plan:

I'm going do all sound production via the program Ableton Live.
This keeps me from having to re-invent the wheel: there's no time to code samplers, instruments, effects and sounds from scratch.
This way I'll be able to use professional instrument libraries and make it sound really good.

I'll use SuperCollider to interpret the interactivity data and code the high level algorithmic music stuff -- notes, rhythms, patterns, etc.
It will send MIDI data to Ableton and it'll work great.  That's how I got the nice piano sound going in my little video demo.

For now, since I don't expect you have this program, I've set up SuperCollider to play simple sounds instead.

*/




/*

SETUP

1.  You need to set up the touch controller and Unreal to send accelerometer data out via OSC.


2.  Set up OSC routing -- IP and port information should be this:  */

// INPUT IP AND PORT (accelerometer data coming into SuperCollider)
NetAddr.localAddr // run this line by putting cursor anywhere in it and pressing SHIFT-RETURN.  Look in the Post window (bottom right)
// this is where Unreal needs to send accelerometer data

// OUTPUT IP AND PORT (sound data going to Unreal)
// find the variable ~output_osc_address below (at the top of INIT) and put your Unreal port there.

/*


3.  OSC messages are sent with a path that names the message.
You'll need to configure yours to send to this path: /gyrosc/accel
OR change the variable ~osc_accelerometer_msg_path to match yours (specified near the top of the INIT block below)


4.  If you want to check to see if your messages are coming through,
and see the values the accelerometer is sending, go to the bottom of this code, find Utilities, and run Accelerometer Visualizer


5.  My iPhone sends accelerometer data as a 3 value array, one for each dimension [x, y, z]
-- set up your touch controllers to do this if you can
-- if yours can't be set up like this I'll need to tweak the code.


6.  My iPhone accelerometer sends values roughly from -6 to 6.  My thresholds are set up to work in this range.
If yours aren't, you can set '~gyrosc.ictus.max' to whatever your maximum is (this can be an approximation: I've found there's no hard limit on these things)


7.  Set up your end to receive OSC messages, so you can use my sounds to trigger your images.
-- This will work exactly the same way as our demos before, except the data will be a little simpler:

// for each sound playing, there will be a stream (30 messages / second) of data sent out via OSC:

// you will receive an array with this information: ['/note', noteID, -1, amp, freq]
//   '/note',
//   nodeID -- a number that identifies this synth (each note will have a unique noteID)
//   -1, for some reason, I don't know why
//   amp (volume 0 to 1),
//   freq (pitch of the note in Hz)


8.  Boot the server -- Language menu: Boot server, or run */

s.boot;

// if it says "server failed to start" just try a few times --

/*

9.  Run the INIT block by double clicking on the line containing the initial parenthesis and pressing SHIFT-RETURN

10.  Then run these commands to turn it on and off and shake the touch controller:  */

~gyrosc.ictus.start;
~gyrosc.ictus.end;




// ******************* INIT:

(
// midi
//MIDIClient.init;    // if not already done
//m = MIDIOut.newByName("IAC Driver", "Bus 1").latency_(Server.default.latency);

~osc_accelerometer_msg_path = '/gyrosc/accel';  // make sure this path matches the OSC data you're sending from Unreal

~output_osc_address = NetAddr.new("127.0.0.1", 7771); // put your Unreal port here

~gyrosc = ();
~gyrosc.ictus = ();
~gyrosc.ictus.max = 5; // the peak value the accelerometer might send (approx -- I've found there's no hard limit).
~gyrosc.ictus.plunge_thresh = ~gyrosc.ictus.max*(-1)/5; // negative means it only will register downstrokes (not entirely true but close enough for now)
~gyrosc.ictus.pause_duration = 0.1; // each stroke generates several triggers; this filters out everything for a short amount of time after the first trigger
~gyrosc.ictus.recent_time_window = 0.3; // how far apart the 'wind up' and 'plunge down' might be
~gyrosc.ictus.time = TempoClock.new;


/*
~gyrosc.ictus attempts to detect a downstroke ('plunge down') from the accelerometer, and also measure its intensity
it doesn't measure the intensity of the downstroke itself
-- (measuring the intensity of the downstroke is problematic because you don't know when the peak of the downstroke is until its over;
-- measurements can be accurate but a little too late to feel a good body/sound connection)
instead, it measures the 'wind up' -- the snap UP before the plunge DOWN, which is a natural

it's not perfect but it works well enough for now
*/


~gyrosc.ictus.start = {arg self;
	var last_ictus = 0;
	var recent_peak = (time: 0, magnitude:0), recent_time_window = ~gyrosc.ictus.recent_time_window;

	self.oscfunc = OSCFunc.newMatching({|msg, time, addr, recvPort|
		var y = msg[2], time_now = ~gyrosc.ictus.time.seconds, plunge_thresh = ~gyrosc.ictus.plunge_thresh;
		var pause_duration = ~gyrosc.ictus.pause_duration;

		// this OSC responder triggers when the accelerometer is swiftly pushed down AFTER being swiftly pushed up (like a 'wind up')

		if (time_now - recent_peak.time > recent_time_window, {
			recent_peak.magnitude = 0; // forget old peaks (magnitudes of the up-snap)
		});

		if (y > recent_peak.magnitude, {recent_peak = (time:time_now, magnitude:y)});  // keep track of recent maximum snap-up magnitudes

		if ((y < plunge_thresh), { // if you plunge down harder than the threshold
			if ((time_now - last_ictus) > pause_duration, {  // and it didn't just trigger a split second ago
				~gyrosc.ictus.trigger(recent_peak.magnitude);  // trigger
				last_ictus = time_now;
				recent_peak = (time:0, magnitude:0);
			});
		});

	}, ~osc_accelerometer_msg_path);

	"gyrosc.ictus listener on";
};
~gyrosc.ictus.end = {arg self; self.oscfunc.free; "gyrosc.ictus listener off"};
~gyrosc.ictus.trigger = {arg self, magnitude;
	magnitude = magnitude.linlin(0, ~gyrosc.ictus.max, 0, 1);
	~play.value(magnitude).play;
	"Ictus! magnitude: %".format(magnitude).postln;
};


// MUSIC
(
(
SynthDef(\warm, {arg freq=440, amp=0.2, pan=0, sustain=1;
	var sound, env, report, mix;
	sound = Ringz.ar(PinkNoise.ar(0.1), freq, sustain) + Blip.ar(freq,4, mul:0.5);
	env = EnvGen.kr(
		Env.perc(0.01, 1-0.01),
		timeScale: sustain,
		doneAction:2);
	sound = sound * amp * env * 0.2;
	sound = Pan2.ar(sound, pan);

	Out.ar(0, sound);

	mix = Mix.ar(sound);
	report = Array.with(Amplitude.kr(mix), freq); // send
	SendReply.kr(Impulse.kr(30), '/note', report);

}).add
);

~play = {arg magnitude = 1;
	Pbind(
		//\type, \midi,
		//\midiout, m,
		\instrument, \warm,
		\degree, ~chordize.(~melody.next, magnitude),
		\dur, Pseq([1]),
		\amp, 0.5 * magnitude,
		\strum, magnitude.linlin(0,1,0,0.05),
		\legato, 4
)};


~melody = Routine({var melody = ((0..8).scramble ! 4) ++ ((-3..3).scramble ! 2) ++ ((5..10).scramble ! 2) ++ ((0..8).scramble ! 4);
	loop {melody.flatten.do{|x| x.yield}}
});

(
~chordize = {arg root, magnitude;
	var triads = [
		[1,3,5], // major triad
		[1,5,10], // major triad open spacing
		[1,3,6], // 6
		[1,3,7], // maj7 (no 5)
		[1,5,9]], // stacked fifths
	added_notes_1 = [7,8,10,12,13],
	added_notes_2 = [10,12,7,6,-4],
	added_notes_3 = [6,-2,-4,-2,12];

	var i = triads.size.rand; // which chord index
	var chord = (triads[i] ++ added_notes_1[i] ++ added_notes_2[i] ++ added_notes_3[i]) - 1; // for base 0
	var how_many_notes = magnitude.linlin(0,1,0,chord.size).round.asInteger;

	(root + chord).keep(how_many_notes);
}
)
); // end MUSIC



(
OSCresponder.all.do({|x| x.remove});

OSCresponder(nil, '/note', {|time, resp, message, addr|
	//("received %").format(message).postln;
	~output_osc_address.sendMsg("/note", message);
}).add;
)




) // end INIT


















/// UTILITIES

// run this if you haven't run the INIT code above:
~osc_accelerometer_msg_path = '/gyrosc/accel';



// Accelerometer visualizer.  Run whole block (double click line that contains the opening parenthesis to select)

(
Window.closeAll;
~accelWindow = Window("flow", Rect(90, 50, 170, 220))
.front
.alwaysOnTop_(true);


~accelWindow.view.decorator_(FlowLayout(bounds:~accelWindow.bounds, margin:Point(15,15), gap:7@7)); // = Point(7,7)


// StaticText.new(c, 150@10)
// .background_(Color.rand)
// .string("Accelerometer (x, y, z)");

a = Array.fill(3, {EZSlider.new(~accelWindow, 40@180,controlSpec:ControlSpec.new(-5,5), layout:\vert)});


// OSC listener
(
~oscToSlider = OSCFunc.newMatching({|msg, time, addr, recvPort|
	{
		a[0].value_(msg[1]);
		a[1].value_(msg[2]);
		a[2].value_(msg[3]);
	}.fork(AppClock)


}, ~osc_accelerometer_msg_path)
)
)


