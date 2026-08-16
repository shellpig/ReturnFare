class_name Indulgence
extends RefCounted

## 縱慾相關純計算與查表邏輯（P2-B, P2-C）。

## 依據累計縱慾次數 n（主動＋強制合計）查表決定強度級（規格書第八節）。
## n <= forced_light_count (預設 1) -> "light"
## n <= forced_normal_until (預設 7) -> "normal"
## 否則 -> "heavy"
static func level_for(n: int, tuning: Dictionary) -> String:
	var ind: Dictionary = tuning.get("indulgence", {}) as Dictionary
	var light_count: int = int(ind.get("forced_light_count", 1))
	var normal_until: int = int(ind.get("forced_normal_until", 7))
	if n <= light_count:
		return "light"
	elif n <= normal_until:
		return "normal"
	else:
		return "heavy"
