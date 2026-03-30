// Engine_QuietFire
// generative modal jazz engine for norns
// voices: muted trumpet, rhodes ep, brush hint
//
// by jamminstein

Engine_QuietFire : CroneEngine {
  var <trumpetGroup, <rhodesGroup, <brushGroup;
  var <trumpetBus, <rhodesBus, <reverbBus;
  var <reverbSynth;
  var <trumpetSynths, <rhodesSynths;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    trumpetSynths = Dictionary.new;
    rhodesSynths = Dictionary.new;

    reverbBus = Bus.audio(context.server, 2);
    trumpetBus = Bus.audio(context.server, 2);
    rhodesBus = Bus.audio(context.server, 2);

    trumpetGroup = Group.new(context.server);
    rhodesGroup = Group.new(context.server);
    brushGroup = Group.new(context.server);

    // --- muted trumpet ---
    // filtered saw + breath noise, vibrato, soft attack
    SynthDef(\qf_trumpet, {
      arg out, freq=440, amp=0.3, gate=1, breath=0.15,
          vibRate=5.2, vibDepth=0.008, cutoff=1800, res=0.2, pan=0;
      var sig, env, vib, noise, filt;

      env = EnvGen.kr(
        Env.adsr(0.12, 0.2, 0.7, 0.8, curve: [2, -1, -3]),
        gate, doneAction: Done.freeSelf
      );

      // vibrato — slightly irregular like a human player
      vib = SinOsc.kr(vibRate + LFNoise1.kr(0.3).range(-0.4, 0.4)) * vibDepth * freq;

      // core tone: mix of saw and pulse for brass character
      sig = VarSaw.ar(freq + vib, 0, SinOsc.kr(0.07).range(0.3, 0.5)) * 0.6;
      sig = sig + Pulse.ar(freq + vib, SinOsc.kr(0.11).range(0.35, 0.55)) * 0.3;

      // breath noise — filtered, amplitude-following
      noise = PinkNoise.ar(breath) * EnvGen.kr(Env.perc(0.05, 0.3), gate);
      noise = BPF.ar(noise, freq * 2.5, 0.8);
      sig = sig + noise;

      // mute filter — the core of the miles sound
      filt = MoogFF.ar(sig, cutoff * EnvGen.kr(Env.perc(0.01, 0.6), gate).range(0.4, 1), res);
      filt = filt + (RLPF.ar(sig, cutoff * 0.5, 0.6) * 0.2);

      sig = filt * env * amp;
      sig = Pan2.ar(sig, pan + LFNoise1.kr(0.2).range(-0.05, 0.05));
      Out.ar(out, sig);
    }).add;

    // --- rhodes electric piano ---
    // fm synthesis + tremolo + soft bell
    SynthDef(\qf_rhodes, {
      arg out, freq=440, amp=0.25, gate=1, pan=0,
          fmIndex=2.5, fmRatio=1.0, trem=3.5, tremDepth=0.06, tone=0.7;
      var sig, env, mod, trem_osc;

      env = EnvGen.kr(
        Env.adsr(0.005, 1.2, 0.3, 1.5, curve: [0, -4, -4]),
        gate, doneAction: Done.freeSelf
      );

      // fm pair for bell/tine character
      mod = SinOsc.ar(freq * fmRatio) * fmIndex * freq;
      sig = SinOsc.ar(freq + mod) * 0.5;

      // second partial for warmth
      sig = sig + SinOsc.ar(freq * 2 + (mod * 0.3)) * 0.15;
      sig = sig + SinOsc.ar(freq * 0.5) * 0.1; // sub

      // tremolo
      trem_osc = SinOsc.kr(trem + LFNoise1.kr(0.15).range(-0.3, 0.3));
      sig = sig * (1 + (trem_osc * tremDepth));

      // tone control — lp filter
      sig = RLPF.ar(sig, freq * tone.linexp(0, 1, 2, 12), 0.5);

      sig = sig * env * amp;
      sig = Pan2.ar(sig, pan);
      Out.ar(out, sig);
    }).add;

    // --- brush percussion ---
    // filtered noise burst, very subtle
    SynthDef(\qf_brush, {
      arg out, amp=0.08, pan=0, tone=5000, decay=0.12;
      var sig, env;
      env = EnvGen.kr(Env.perc(0.003, decay, curve: -6), doneAction: Done.freeSelf);
      sig = PinkNoise.ar + (Dust.ar(800) * 0.3);
      sig = BPF.ar(sig, tone, 0.6) * env * amp;
      sig = Pan2.ar(sig, pan + LFNoise0.kr(10).range(-0.15, 0.15));
      Out.ar(out, sig);
    }).add;

    // --- reverb ---
    SynthDef(\qf_reverb, {
      arg in, out, mix=0.35, room=0.8, damp=0.4;
      var sig, verb;
      sig = In.ar(in, 2);
      verb = FreeVerb2.ar(sig[0], sig[1], mix, room, damp);
      // add subtle tape-like warmth
      verb = RLPF.ar(verb, 6000, 0.8);
      Out.ar(out, verb);
    }).add;

    context.server.sync;

    reverbSynth = Synth(\qf_reverb, [
      \in, reverbBus, \out, context.out_b, \mix, 0.35, \room, 0.8, \damp, 0.4
    ], brushGroup, \addAfter);

    // --- commands ---

    // trumpet: voice_id, hz, amp, cutoff, breath, pan
    this.addCommand("trumpet_on", "ifffff", { arg msg;
      var id = msg[1].asInteger;
      var synth;
      if(trumpetSynths[id].notNil, { trumpetSynths[id].set(\gate, 0) });
      synth = Synth(\qf_trumpet, [
        \out, reverbBus, \freq, msg[2], \amp, msg[3],
        \cutoff, msg[4], \breath, msg[5], \pan, msg[6], \gate, 1
      ], trumpetGroup);
      trumpetSynths[id] = synth;
    });

    this.addCommand("trumpet_off", "i", { arg msg;
      var id = msg[1].asInteger;
      if(trumpetSynths[id].notNil, {
        trumpetSynths[id].set(\gate, 0);
        trumpetSynths[id] = nil;
      });
    });

    // rhodes: voice_id, hz, amp, fm_index, pan
    this.addCommand("rhodes_on", "iffff", { arg msg;
      var id = msg[1].asInteger;
      var synth;
      if(rhodesSynths[id].notNil, { rhodesSynths[id].set(\gate, 0) });
      synth = Synth(\qf_rhodes, [
        \out, reverbBus, \freq, msg[2], \amp, msg[3],
        \fmIndex, msg[4], \pan, msg[5], \gate, 1
      ], rhodesGroup);
      rhodesSynths[id] = synth;
    });

    this.addCommand("rhodes_off", "i", { arg msg;
      var id = msg[1].asInteger;
      if(rhodesSynths[id].notNil, {
        rhodesSynths[id].set(\gate, 0);
        rhodesSynths[id] = nil;
      });
    });

    // brush: amp, tone, decay, pan
    this.addCommand("brush", "ffff", { arg msg;
      Synth(\qf_brush, [
        \out, reverbBus, \amp, msg[1], \tone, msg[2],
        \decay, msg[3], \pan, msg[4]
      ], brushGroup);
    });

    // reverb controls
    this.addCommand("reverb_mix", "f", { arg msg; reverbSynth.set(\mix, msg[1]); });
    this.addCommand("reverb_room", "f", { arg msg; reverbSynth.set(\room, msg[1]); });
    this.addCommand("reverb_damp", "f", { arg msg; reverbSynth.set(\damp, msg[1]); });
  }

  free {
    trumpetGroup.free;
    rhodesGroup.free;
    brushGroup.free;
    reverbBus.free;
    trumpetBus.free;
    rhodesBus.free;
  }
}
