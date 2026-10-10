extends SceneTree

# Deterministic modal synthesis. No external samples or runtime generation needed.
const RATE := 44100
func _initialize() -> void:
	write_tone("res://Assets/Audio/block.wav", false)
	write_tone("res://Assets/Audio/parry.wav", true)
	quit()

func write_tone(path: String, bright: bool) -> void:
	var duration := 0.65 if bright else 0.32
	var samples := PackedByteArray()
	samples.resize(int(RATE * duration) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 724
	var peak := 0.0
	for i in range(samples.size() / 2):
		var t := float(i) / RATE
		var attack := minf(t / 0.0015, 1.0)
		var sample: float
		if bright:
			sample = (sin(TAU * 1760 * t) * exp(-9 * t) * 0.46
				+ sin(TAU * 2871 * t) * exp(-13 * t) * 0.23
				+ sin(TAU * 4319 * t) * exp(-21 * t) * 0.12)
		else:
			sample = (sin(TAU * 510 * t) * exp(-22 * t) * 0.56
				+ sin(TAU * 823 * t) * exp(-32 * t) * 0.19
				+ sin(TAU * 1327 * t) * exp(-47 * t) * 0.07)
		sample += rng.randf_range(-1, 1) * exp(-160 * t) * 0.1
		sample *= attack * minf((duration - t) / 0.02, 1.0)
		peak = maxf(peak, absf(sample))
		samples.encode_s16(i * 2, int(clampf(sample, -0.95, 0.95) * 32767))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = RATE
	wave.data = samples
	var result := wave.save_to_wav(path)
	print(path, " result=", result, " peak=", peak)
