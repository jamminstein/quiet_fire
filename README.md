# quiet_fire

generative modal jazz for norns + grid

## about

a muted trumpet drifts over shimmering rhodes chords while brushes whisper time. quiet_fire is a generative modal jazz system inspired by miles davis's kind of blue sessions — the space between notes, the patience of modal improvisation, the warmth of a late-night set at the village vanguard.

the system builds melodies through weighted random walks along scale degrees, with a gravitational pull toward chord tones. the rhodes re-voices itself every few bars, occasionally shifting root by fourths and fifths — the way a jazz trio moves through changes without announcing them. custom supercollider engine with three voices: a muted trumpet (filtered saw + breath noise + vibrato), an fm rhodes with tremolo, and filtered noise brushes.

## controls

| control | function |
|---------|----------|
| ENC1 | density — how often the trumpet speaks |
| ENC2 | trumpet cutoff — mute brightness |
| ENC3 | reverb mix |
| KEY2 | play / stop |
| KEY3 | cycle to next mode |

## grid

| rows | function |
|------|----------|
| 1-2 | mode select — 8 columns for dorian, mixolydian, aeolian, phrygian, lydian, blues, whole tone, diminished |
| 3-4 | root note — columns 1-12 for C through B |
| 5-6 | register — columns 1-3 for octave down, center, octave up |
| 7 | density slider — 16-step fader |
| 8 | intensity slider — 16-step dynamics control |

top-right led (16,1) pulses with trumpet activity when playing.

## params

- density — note probability (0-100%)
- intensity — dynamics range (0-100%)
- trumpet cutoff — mute filter frequency (200-6000 hz)
- trumpet breath — breath noise amount (0-0.5)
- rhodes fm index — tine brightness (0.5-6)
- reverb mix — wet/dry (0-1)
- reverb room — space size (0-1)
- root note — C through B
- mode — dorian, mixolydian, aeolian, phrygian, lydian, blues, whole tone, diminished

## install

```
;install https://github.com/jamminstein/quiet_fire
```

requires norns 2.0+ and grid (optional but recommended).
