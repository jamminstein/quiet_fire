-- quiet_fire
--
-- generative modal jazz
-- for norns + grid
--
-- inspired by miles davis,
-- kind of blue, late-night
-- sets at the vanguard.
--
-- muted trumpet drifts over
-- shimmering rhodes chords.
-- the system breathes.
--
-- ENC1: density
-- ENC2: trumpet cutoff
-- ENC3: reverb mix
-- KEY2: toggle play
-- KEY3: new chord
--
-- grid: mode select (rows 1-4),
-- register (rows 5-6),
-- density/intensity (rows 7-8)
--
-- v1.0 @jamminstein

engine.name = "QuietFire"

local musicutil = require "musicutil"
local lattice = require "lattice"

-- ─── state ───

local playing = false
local my_lattice = nil
local trumpet_sprocket = nil
local rhodes_sprocket = nil
local brush_sprocket = nil

-- musical state
local root = 48 -- C3
local current_mode = 1
local modes = {
  {name = "dorian",      scale = "dorian"},
  {name = "mixolydian",  scale = "mixolydian"},
  {name = "aeolian",     scale = "aeolian"},
  {name = "phrygian",    scale = "phrygian"},
  {name = "lydian",      scale = "lydian"},
  {name = "blues",       scale = "blues scale"},
  {name = "whole tone",  scale = "whole tone"},
  {name = "diminished",  scale = "diminished"},
}

local scale_notes = {}
local chord_tones = {}
local melody_pos = 1 -- index into scale
local density = 0.5 -- 0-1, controls note probability
local register = 0 -- octave offset: -1, 0, +1
local intensity = 0.5 -- controls dynamics

-- trumpet voice tracking
local trumpet_voice_id = 0
local trumpet_note_on = false

-- rhodes voice tracking
local rhodes_voices = {}
local rhodes_voice_id = 0

-- grid state
local g = grid.connect()
local grid_held = {}
local grid_dirty = true

-- screen animation
local screen_dirty = true
local breath_phase = 0
local last_trumpet_note = nil
local last_chord_name = ""
local particles = {}

-- ─── musical logic ───

local function build_scale()
  local mode = modes[current_mode]
  scale_notes = musicutil.generate_scale(root + (register * 12), mode.scale, 3)
  -- build chord tones from scale: 1, 3, 5, 7
  chord_tones = {}
  if #scale_notes >= 7 then
    table.insert(chord_tones, scale_notes[1])
    table.insert(chord_tones, scale_notes[3])
    table.insert(chord_tones, scale_notes[5])
    table.insert(chord_tones, scale_notes[7])
  end
end

local function weighted_random_walk()
  -- drunk walk along scale with tendency toward chord tones
  local step = 0
  local r = math.random()
  if r < 0.15 then
    step = -2
  elseif r < 0.35 then
    step = -1
  elseif r < 0.55 then
    step = 0 -- rest / repeat
  elseif r < 0.75 then
    step = 1
  else
    step = 2
  end

  melody_pos = melody_pos + step
  melody_pos = util.clamp(melody_pos, 1, #scale_notes)

  -- occasionally jump to a chord tone
  if math.random() < 0.2 and #chord_tones > 0 then
    local target = chord_tones[math.random(#chord_tones)]
    -- find nearest scale position
    for i, n in ipairs(scale_notes) do
      if n == target or n == target + 12 or n == target - 12 then
        melody_pos = i
        break
      end
    end
  end

  return scale_notes[melody_pos]
end

local function pick_rhythm_division()
  -- miles plays with space — lots of rests, occasional flurries
  local r = math.random()
  local d = density
  if r < (1 - d) * 0.6 then
    return nil -- rest
  elseif r < 0.7 then
    return 1/4 -- quarter
  elseif r < 0.85 then
    return 1/8 -- eighth
  else
    return 1/2 -- half note (long tone)
  end
end

local function note_duration()
  -- how long the trumpet holds a note
  local r = math.random()
  if r < 0.3 then return 0.15 -- short staccato
  elseif r < 0.6 then return 0.4 -- medium
  elseif r < 0.85 then return 0.8 -- sustained
  else return 1.5 -- long breath
  end
end

local function spawn_particle(note)
  table.insert(particles, {
    x = math.random(20, 108),
    y = math.random(10, 54),
    life = 1.0,
    decay = 0.02 + math.random() * 0.03,
    note = note
  })
  -- keep particle count reasonable
  while #particles > 12 do
    table.remove(particles, 1)
  end
end

-- ─── voices ───

local function trumpet_play(note, dur)
  if not playing then return end
  local hz = musicutil.note_num_to_freq(note)
  local amp = util.linlin(0, 1, 0.08, 0.3, intensity)
  -- add human dynamics
  amp = amp * (0.85 + math.random() * 0.3)
  local cutoff = params:get("trumpet_cutoff")
  local breath = params:get("trumpet_breath")

  trumpet_voice_id = trumpet_voice_id + 1
  local vid = trumpet_voice_id

  engine.trumpet_on(vid, hz, amp, cutoff, breath, math.random() * 0.3 - 0.15)
  trumpet_note_on = true
  last_trumpet_note = note
  spawn_particle(note)
  screen_dirty = true

  -- schedule note off
  clock.run(function()
    clock.sleep(dur)
    engine.trumpet_off(vid)
    trumpet_note_on = false
    screen_dirty = true
  end)
end

local function rhodes_play_chord()
  if not playing then return end
  -- release previous chord
  for _, vid in ipairs(rhodes_voices) do
    engine.rhodes_off(vid)
  end
  rhodes_voices = {}

  if #chord_tones == 0 then return end

  -- voice the chord with some voicing variety
  local voicing = {}
  -- root in low register
  table.insert(voicing, chord_tones[1] - 12)
  -- other tones spread out
  for i = 2, #chord_tones do
    local oct_shift = 0
    if math.random() < 0.3 then oct_shift = 12 end
    table.insert(voicing, chord_tones[i] + oct_shift)
  end
  -- sometimes add a color tone (9th)
  if #scale_notes >= 9 and math.random() < 0.4 then
    table.insert(voicing, scale_notes[9])
  end

  local amp = util.linlin(0, 1, 0.06, 0.2, intensity)
  local fm = params:get("rhodes_fm")

  -- build chord name for display
  local root_name = musicutil.note_num_to_name(chord_tones[1], false)
  last_chord_name = root_name .. " " .. modes[current_mode].name

  for i, note in ipairs(voicing) do
    rhodes_voice_id = rhodes_voice_id + 1
    local vid = rhodes_voice_id
    local hz = musicutil.note_num_to_freq(note)
    local pan = util.linlin(1, #voicing, -0.4, 0.4, i)
    engine.rhodes_on(vid, hz, amp * (0.8 + math.random() * 0.4), fm, pan)
    table.insert(rhodes_voices, vid)
  end

  screen_dirty = true
end

local function brush_tick()
  if not playing then return end
  -- sparse brush pattern — ghostly time-keeping
  if math.random() < density * 0.4 then
    local amp = util.linlin(0, 1, 0.02, 0.08, intensity)
    amp = amp * (0.6 + math.random() * 0.8)
    local tone = 3000 + math.random() * 4000
    local decay = 0.05 + math.random() * 0.15
    local pan = math.random() * 0.6 - 0.3
    engine.brush(amp, tone, decay, pan)
  end
end

-- ─── grid ───

local function grid_redraw()
  g:all(0)

  -- rows 1-4: mode select (8 modes across columns 1-8)
  for m = 1, 8 do
    local brightness = 3
    if m == current_mode then brightness = 15
    elseif m <= #modes then brightness = 6 end
    -- light up column m, rows 1-2 for selected mode
    g:led(m, 1, m == current_mode and 15 or 4)
    g:led(m, 2, m == current_mode and 10 or 2)
  end

  -- rows 3-4: root note select (C through B, columns 1-12)
  local root_pc = root % 12
  for i = 0, 11 do
    local brightness = 3
    if i == root_pc then brightness = 15 end
    g:led(i + 1, 3, brightness)
    g:led(i + 1, 4, i == root_pc and 8 or 2)
  end

  -- rows 5-6: register select (-1, 0, +1 mapped to cols 1-3)
  for r = -1, 1 do
    local col = r + 2
    local brightness = r == register and 15 or 4
    g:led(col, 5, brightness)
    g:led(col, 6, brightness)
  end

  -- rows 7-8: density (columns 1-16 as slider)
  local dens_col = math.floor(density * 15) + 1
  for c = 1, 16 do
    local b = c <= dens_col and 8 or 2
    if c == dens_col then b = 15 end
    g:led(c, 7, b)
  end

  -- row 8: intensity slider
  local int_col = math.floor(intensity * 15) + 1
  for c = 1, 16 do
    local b = c <= int_col and 6 or 1
    if c == int_col then b = 12 end
    g:led(c, 8, b)
  end

  -- playing indicator
  if playing then
    g:led(16, 1, trumpet_note_on and 15 or 8)
  end

  g:refresh()
end

g.key = function(x, y, z)
  if z == 0 then return end

  -- rows 1-2: mode select
  if y <= 2 and x <= 8 then
    current_mode = x
    build_scale()
    rhodes_play_chord()
  -- rows 3-4: root select
  elseif y == 3 or y == 4 then
    if x <= 12 then
      root = 48 + (x - 1) -- C3 + offset
      build_scale()
      rhodes_play_chord()
    end
  -- rows 5-6: register
  elseif (y == 5 or y == 6) and x <= 3 then
    register = x - 2
    build_scale()
  -- row 7: density
  elseif y == 7 then
    density = (x - 1) / 15
    params:set("density", density * 100)
  -- row 8: intensity
  elseif y == 8 then
    intensity = (x - 1) / 15
    params:set("intensity", intensity * 100)
  end

  grid_dirty = true
  screen_dirty = true
end

-- ─── screen ───

function redraw()
  screen.clear()
  screen.aa(1)
  screen.font_face(1)

  -- background breath effect
  breath_phase = breath_phase + 0.02
  local breath_level = math.floor(util.linlin(-1, 1, 1, 3, math.sin(breath_phase)))

  -- script name
  screen.level(4)
  screen.font_size(8)
  screen.move(2, 8)
  screen.text("quiet fire")

  -- mode name
  screen.level(12)
  screen.font_size(10)
  screen.move(64, 26)
  screen.text_center(modes[current_mode].name)

  -- chord name
  if last_chord_name ~= "" then
    screen.level(7)
    screen.font_size(8)
    screen.move(64, 38)
    screen.text_center(last_chord_name)
  end

  -- current trumpet note
  if trumpet_note_on and last_trumpet_note then
    screen.level(15)
    screen.font_size(16)
    local name = musicutil.note_num_to_name(last_trumpet_note, true)
    screen.move(64, 56)
    screen.text_center(name)
  end

  -- particles — sparse dots that fade
  for _, p in ipairs(particles) do
    local lvl = math.floor(p.life * 10)
    if lvl > 0 then
      screen.level(lvl)
      screen.pixel(p.x, p.y)
      screen.fill()
    end
  end

  -- playing state
  if not playing then
    screen.level(breath_level + 2)
    screen.font_size(8)
    screen.move(64, 62)
    screen.text_center("K2 to begin")
  end

  -- density bar bottom-left
  screen.level(3)
  screen.rect(2, 61, density * 40, 2)
  screen.fill()

  screen.update()
end

-- ─── params ───

local function setup_params()
  params:add_separator("quiet_fire", "QUIET FIRE")

  params:add_control("density", "density",
    controlspec.new(0, 100, 'lin', 1, 50, "%"))
  params:set_action("density", function(v)
    density = v / 100
    grid_dirty = true
  end)

  params:add_control("intensity", "intensity",
    controlspec.new(0, 100, 'lin', 1, 50, "%"))
  params:set_action("intensity", function(v)
    intensity = v / 100
    grid_dirty = true
  end)

  params:add_control("trumpet_cutoff", "trumpet cutoff",
    controlspec.new(200, 6000, 'exp', 0, 1800, "hz"))

  params:add_control("trumpet_breath", "trumpet breath",
    controlspec.new(0, 0.5, 'lin', 0, 0.15, ""))

  params:add_control("rhodes_fm", "rhodes fm index",
    controlspec.new(0.5, 6, 'lin', 0, 2.5, ""))

  params:add_control("reverb_mix", "reverb mix",
    controlspec.new(0, 1, 'lin', 0, 0.35, ""))
  params:set_action("reverb_mix", function(v)
    engine.reverb_mix(v)
  end)

  params:add_control("reverb_room", "reverb room",
    controlspec.new(0, 1, 'lin', 0, 0.8, ""))
  params:set_action("reverb_room", function(v)
    engine.reverb_room(v)
  end)

  params:add_option("root_note", "root note",
    {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}, 1)
  params:set_action("root_note", function(v)
    root = 48 + (v - 1)
    build_scale()
    if playing then rhodes_play_chord() end
    grid_dirty = true
  end)

  params:add_option("mode", "mode",
    {"dorian","mixolydian","aeolian","phrygian","lydian","blues","whole tone","diminished"}, 1)
  params:set_action("mode", function(v)
    current_mode = v
    build_scale()
    if playing then rhodes_play_chord() end
    grid_dirty = true
  end)
end

-- ─── init ───

function init()
  setup_params()
  build_scale()

  -- lattice
  my_lattice = lattice:new{
    auto = true,
    ppqn = 96
  }

  -- trumpet: plays melody phrases with rests
  trumpet_sprocket = my_lattice:new_sprocket{
    action = function(t)
      if not playing then return end
      local div = pick_rhythm_division()
      if div then
        local note = weighted_random_walk()
        local dur = note_duration()
        trumpet_play(note, dur)
      end
    end,
    division = 1/4,
    enabled = true
  }

  -- rhodes: re-voices chord every few bars
  rhodes_sprocket = my_lattice:new_sprocket{
    action = function(t)
      if not playing then return end
      -- occasionally shift mode color
      if math.random() < 0.08 then
        -- subtle root movement: up or down a 4th/5th
        local shifts = {0, 5, 7, -5, -7}
        local shift = shifts[math.random(#shifts)]
        if shift ~= 0 then
          root = ((root - 48 + shift) % 12) + 48
          params:set("root_note", (root - 48) % 12 + 1, true)
          build_scale()
        end
      end
      rhodes_play_chord()
    end,
    division = 2, -- every 2 beats
    enabled = true
  }

  -- brush: quiet time-keeping
  brush_sprocket = my_lattice:new_sprocket{
    action = function(t)
      brush_tick()
    end,
    division = 1/8,
    enabled = true
  }

  my_lattice:start()

  -- screen refresh
  clock.run(function()
    while true do
      clock.sleep(1/15)
      -- update particles
      for i = #particles, 1, -1 do
        particles[i].life = particles[i].life - particles[i].decay
        if particles[i].life <= 0 then
          table.remove(particles, i)
        end
      end
      redraw()
      if grid_dirty then
        grid_redraw()
        grid_dirty = false
      end
    end
  end)
end

-- ─── controls ───

function enc(n, d)
  if n == 1 then
    params:delta("density", d)
  elseif n == 2 then
    params:delta("trumpet_cutoff", d)
  elseif n == 3 then
    params:delta("reverb_mix", d * 0.5)
  end
  screen_dirty = true
end

function key(n, z)
  if z == 0 then return end
  if n == 2 then
    playing = not playing
    if playing then
      build_scale()
      rhodes_play_chord()
    else
      -- release all
      for _, vid in ipairs(rhodes_voices) do
        engine.rhodes_off(vid)
      end
      rhodes_voices = {}
      last_chord_name = ""
      last_trumpet_note = nil
    end
  elseif n == 3 then
    -- trigger new chord / mode shift
    current_mode = (current_mode % #modes) + 1
    params:set("mode", current_mode, true)
    build_scale()
    if playing then rhodes_play_chord() end
  end
  grid_dirty = true
  screen_dirty = true
end

function cleanup()
  if my_lattice then my_lattice:destroy() end
  -- release voices
  for _, vid in ipairs(rhodes_voices) do
    engine.rhodes_off(vid)
  end
end
