extends Node
## Процедурный синтез звуков: никаких внешних файлов, всё генерируется при запуске.

const RATE := 22050

var streams := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1337
	streams["blaster"] = _make(0.20, _blaster)
	streams["laser_loop"] = _make(1.0, _laser, true)
	streams["rocket"] = _make(0.7, _rocket)
	streams["explosion"] = _make(1.9, _explosion)
	streams["boom_small"] = _make(0.8, _boom_small)
	streams["clang"] = _make(0.55, _clang)
	streams["hit"] = _make(0.09, _hit)
	streams["step"] = _make(0.16, _step)
	streams["whoosh"] = _make(0.45, _whoosh)
	streams["impact"] = _make(1.1, _impact)
	streams["robot_shot"] = _make(0.22, _robot_shot)
	streams["hurt"] = _make(0.3, _hurt)
	streams["pickup"] = _make(0.35, _pickup)
	streams["crumble"] = _make(0.45, _crumble)
	streams["alarm"] = _make(1.3, _alarm)
	streams["charge"] = _make(1.0, _charge)
	streams["servo"] = _make(0.3, _servo)
	streams["overheat"] = _make(0.6, _overheat)
	streams["reload"] = _make(0.5, _reload)
	streams["thruster"] = _make(1.0, _thruster, true)
	streams["rifle"] = _make(0.9, _rifle)
	streams["shotgun"] = _make(0.9, _shotgun)
	streams["minigun"] = _make(0.12, _minigun)
	streams["launcher"] = _make(0.5, _launcher)
	streams["lever"] = _make(0.35, _lever)
	streams["spin_loop"] = _make(0.5, _spin, true)


func play3d(name: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(name) or G.world == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = 8.0
	p.max_distance = 140.0
	p.attenuation_filter_cutoff_hz = 9000.0
	G.world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func play2d(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------ инфраструктура

func _make(dur: float, gen: Callable, loop: bool = false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var state := {"lp": 0.0, "lp2": 0.0, "ph": 0.0, "ph2": 0.0, "ph3": 0.0}
	for i in n:
		var t := float(i) / RATE
		var v: float = gen.call(t, dur, state)
		# мягкое ограничение
		v = clamp(v, -1.5, 1.5)
		v = v - (v * v * v) / 6.75
		data.encode_s16(i * 2, int(clamp(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s


func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


func _osc(st: Dictionary, key: String, freq: float) -> float:
	st[key] = fmod(st[key] + freq / RATE, 1.0)
	return sin(st[key] * TAU)


func _lp(st: Dictionary, key: String, x: float, a: float) -> float:
	st[key] = st[key] + a * (x - st[key])
	return st[key]


# ------------------------------------------------------------ звуки

func _blaster(t: float, d: float, st: Dictionary) -> float:
	var f: float = lerp(1600.0, 260.0, pow(t / d, 0.5))
	var s := _osc(st, "ph", f)
	s = s + 0.35 * sign(s)
	var env: float = exp(-t * 22.0)
	return (s * 0.55 + _noise() * 0.2 * exp(-t * 60.0)) * env


func _laser(t: float, _d: float, st: Dictionary) -> float:
	var wob := 1.0 + 0.25 * sin(t * TAU * 8.0)
	var a := _osc(st, "ph", 110.0)
	var b := _osc(st, "ph2", 220.0) * 0.6
	var c := _osc(st, "ph3", 660.0) * 0.25 * wob
	var saw: float = fmod(t * 330.0, 1.0) * 2.0 - 1.0
	return (a * 0.35 + b + c + saw * 0.18 + _noise() * 0.08) * 0.45


func _rocket(t: float, d: float, st: Dictionary) -> float:
	var thump := sin(TAU * 70.0 * t) * exp(-t * 18.0)
	var hiss = _lp(st, "lp", _noise(), 0.25) * min(t * 20.0, 1.0) * exp(-t * 3.0)
	return thump * 0.9 + hiss * 1.4


func _explosion(t: float, _d: float, st: Dictionary) -> float:
	var n := _noise()
	var low := _lp(st, "lp", n, 0.05 + 0.25 * exp(-t * 6.0))
	var sub := sin(TAU * (55.0 - t * 15.0) * t) * exp(-t * 3.5)
	var crack := n * exp(-t * 40.0) * 0.6
	return (low * 3.2 * exp(-t * 2.2) + sub * 0.9 + crack)


func _boom_small(t: float, _d: float, st: Dictionary) -> float:
	var low := _lp(st, "lp", _noise(), 0.12)
	return low * 2.6 * exp(-t * 6.0) + sin(TAU * 80.0 * t) * exp(-t * 9.0) * 0.6


func _clang(t: float, _d: float, _st: Dictionary) -> float:
	var s := 0.0
	s += sin(TAU * 523.0 * t) * exp(-t * 7.0)
	s += sin(TAU * 1347.0 * t) * exp(-t * 10.0) * 0.6
	s += sin(TAU * 2213.0 * t) * exp(-t * 14.0) * 0.4
	s += sin(TAU * 3170.0 * t) * exp(-t * 20.0) * 0.3
	return s * 0.5 + _noise() * exp(-t * 90.0) * 0.6


func _hit(t: float, _d: float, _st: Dictionary) -> float:
	return (sin(TAU * 2400.0 * t) * 0.5 + _noise() * 0.6) * exp(-t * 55.0)


func _step(t: float, _d: float, st: Dictionary) -> float:
	return sin(TAU * 58.0 * t) * exp(-t * 25.0) + _lp(st, "lp", _noise(), 0.2) * exp(-t * 30.0) * 0.8


func _whoosh(t: float, d: float, st: Dictionary) -> float:
	var env := sin(PI * t / d)
	var a: float = lerp(0.04, 0.5, t / d)
	return _lp(st, "lp", _noise(), a) * env * 1.6


func _impact(t: float, d: float, st: Dictionary) -> float:
	return _explosion(t * 1.3, d, st) * 0.8 + _clang(t, d, st) * 0.7


func _robot_shot(t: float, d: float, st: Dictionary) -> float:
	var f: float = lerp(950.0, 180.0, t / d)
	var sq: float = sign(_osc(st, "ph", f))
	return (sq * 0.35 + _noise() * 0.15) * exp(-t * 14.0)


func _hurt(t: float, _d: float, st: Dictionary) -> float:
	var sq: float = sign(_osc(st, "ph", 90.0 - t * 80.0))
	return (_lp(st, "lp", sq, 0.2) * 0.8 + _noise() * 0.2) * exp(-t * 9.0)


func _pickup(t: float, _d: float, st: Dictionary) -> float:
	var notes := [660.0, 880.0, 1320.0]
	var idx = int(min(t / 0.09, 2.0))
	return _osc(st, "ph", notes[idx]) * 0.5 * exp(-fmod(t, 0.09) * 12.0)


func _crumble(t: float, _d: float, st: Dictionary) -> float:
	var grains: float = 1.0 if _rng.randf() < 0.08 else 0.25
	return _lp(st, "lp", _noise() * grains, 0.3) * 2.0 * exp(-t * 7.0) + sin(TAU * 70.0 * t) * exp(-t * 20.0) * 0.4


func _alarm(t: float, _d: float, st: Dictionary) -> float:
	var f := 620.0 if fmod(t, 0.32) < 0.16 else 465.0
	var s := _osc(st, "ph", f)
	return (s + 0.3 * sign(s)) * 0.3 * min(1.0, (1.3 - t) * 4.0)


func _charge(t: float, d: float, st: Dictionary) -> float:
	var f: float = lerp(120.0, 900.0, t / d)
	return (_osc(st, "ph", f) * 0.3 + _osc(st, "ph2", f * 1.5) * 0.2 + _noise() * 0.05) * min(t * 8.0, 1.0)


func _servo(t: float, d: float, st: Dictionary) -> float:
	var f: float = 300.0 + 120.0 * sin(t * 30.0)
	return sign(_osc(st, "ph", f)) * 0.12 * sin(PI * t / d)


func _overheat(t: float, _d: float, st: Dictionary) -> float:
	return _lp(st, "lp", _noise(), 0.6) * 0.9 * exp(-t * 4.0)


func _reload(t: float, _d: float, _st: Dictionary) -> float:
	var s := 0.0
	if t < 0.08:
		s += _noise() * exp(-t * 60.0)
	if t > 0.3:
		var tt := t - 0.3
		s += (sin(TAU * 1800.0 * tt) * 0.5 + _noise() * 0.6) * exp(-tt * 50.0)
	return s


func _thruster(_t: float, _d: float, st: Dictionary) -> float:
	return _lp(st, "lp", _noise(), 0.15) * 1.4 + _lp(st, "lp2", _noise(), 0.02) * 1.2



func _rifle(t: float, _d: float, st: Dictionary) -> float:
	var crack := _noise() * exp(-t * 70.0) * 1.4
	var boom := _lp(st, "lp", _noise(), 0.12) * exp(-t * 7.0) * 2.4
	var tail := _lp(st, "lp2", _noise(), 0.03) * exp(-t * 3.0) * 1.5
	return crack + boom + tail + sin(TAU * 60.0 * t) * exp(-t * 18.0) * 0.6


func _shotgun(t: float, _d: float, st: Dictionary) -> float:
	var crack := _noise() * exp(-t * 45.0) * 1.3
	var boom := _lp(st, "lp", _noise(), 0.09) * exp(-t * 5.0) * 3.0
	return crack + boom + sin(TAU * 48.0 * t) * exp(-t * 12.0) * 0.9


func _minigun(t: float, _d: float, st: Dictionary) -> float:
	return (_noise() * exp(-t * 60.0) + _lp(st, "lp", _noise(), 0.2) * exp(-t * 25.0) * 1.5) * 0.9


func _launcher(t: float, _d: float, st: Dictionary) -> float:
	var thunk := sin(TAU * (90.0 - t * 60.0) * t) * exp(-t * 14.0) * 1.2
	return thunk + _lp(st, "lp", _noise(), 0.15) * exp(-t * 10.0) * 1.2


func _lever(t: float, _d: float, _st: Dictionary) -> float:
	var s := 0.0
	for k in [0.0, 0.17]:
		if t > k:
			var tt: float = t - k
			s += (sin(TAU * 2600.0 * tt) * 0.4 + _noise() * 0.7) * exp(-tt * 70.0)
	return s


func _spin(t: float, _d: float, st: Dictionary) -> float:
	var whine := _osc(st, "ph", 440.0) * 0.25 + _osc(st, "ph2", 880.0) * 0.1
	var rattle: float = sign(sin(TAU * 60.0 * t)) * 0.08
	return whine + rattle + _lp(st, "lp", _noise(), 0.3) * 0.25
