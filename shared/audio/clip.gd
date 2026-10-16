class_name AudioClip
extends RefCounted

# 一段 16 位单声道 PCM。放在 shared 而不是表现层，是因为"每个事件都有声可放、
# 而且不是静音"这件事必须能在无头自检里查，不该等到运行画面才发现。

var sample_rate := 22050
var samples := PackedInt32Array()


var seconds: float:
	get:
		return float(samples.size()) / float(sample_rate)


## 采样峰值（0..1）。自检用它判断这段是不是纯静音。
var peak: float:
	get:
		var highest := 0.0
		for s in samples:
			highest = maxf(highest, absf(float(s) / 32768.0))
		return highest


var root_mean_square: float:
	get:
		if samples.is_empty():
			return 0.0
		var sum := 0.0
		for s in samples:
			var v := float(s) / 32768.0
			sum += v * v
		return sqrt(sum / float(samples.size()))
