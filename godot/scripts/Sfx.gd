## Tiny procedural sound effects (no audio files needed).
extends Node

const RATE := 22050
var _streams := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_streams["place"] = _make([[520, 0.06], [780, 0.08]], 0.35)
	_streams["remove"] = _make([[600, 0.06], [380, 0.1]], 0.3)
	_streams["portal"] = _sweep(300, 1400, 0.45)
	_streams["chat"] = _make([[880, 0.05], [1100, 0.05]], 0.2)
	_streams["step"] = _make([[220, 0.03]], 0.12)
	_streams["hello"] = _make([[523, 0.09], [659, 0.09], [784, 0.14]], 0.35)
	_streams["error"] = _make([[300, 0.08], [220, 0.14]], 0.3)
	_streams["click"] = _make([[1200, 0.025]], 0.15)


func play(name: String) -> void:
	if not _streams.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.play()
			return


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	s.data = bytes
	return s


## notes: [[freq, seconds], ...] played back-to-back with a soft envelope.
func _make(notes: Array, gain: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for n in notes:
		var freq: float = n[0]
		var len := int(n[1] * RATE)
		var phase := 0.0
		for i in len:
			var t := float(i) / len
			var env := minf(t * 12.0, 1.0) * (1.0 - t)
			phase += TAU * freq / RATE
			# soft square-ish tone: sine + a bit of 3rd harmonic
			out.append((sin(phase) + 0.25 * sin(phase * 3.0)) * env * gain)
	return _wav(out)


func _sweep(f0: float, f1: float, secs: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var len := int(secs * RATE)
	var phase := 0.0
	for i in len:
		var t := float(i) / len
		var f := lerpf(f0, f1, t * t)
		phase += TAU * f / RATE
		var env := minf(t * 8.0, 1.0) * (1.0 - t)
		out.append(sin(phase) * env * 0.35 + sin(phase * 0.5) * env * 0.15)
	return _wav(out)
