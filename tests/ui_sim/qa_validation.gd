class_name QAValidation
extends RefCounted

## UI runner 與主場景共用的輸入驗證；兩邊不得各自維護一份規則。

static func validate_state_json(data: Dictionary, template: Dictionary, phases: Array) -> String:
	var dict_err := validate_dict_shape(data, template, "")
	if not dict_err.is_empty():
		return dict_err

	var run: Dictionary = data.get("run", {}) as Dictionary
	var day_val: Variant = run.get("day")
	if day_val == null:
		return "run.day 遺失"
	if typeof(day_val) != TYPE_INT and typeof(day_val) != TYPE_FLOAT:
		return "run.day 應為數字"
	var day_float := float(day_val)
	if is_nan(day_float) or is_inf(day_float) or floor(day_float) != day_float:
		return "run.day 應為有限整數: %s" % str(day_val)
	var day_int := int(day_val)
	if day_int < 1 or day_int > 45:
		return "run.day 超出範圍 (1..45): %d" % day_int

	var phase_val: Variant = run.get("phase")
	if phase_val == null or not phases.has(str(phase_val)):
		return "run.phase 不合法: %s" % str(phase_val)
	return ""


static func validate_dict_shape(data: Dictionary, template: Dictionary, prefix: String) -> String:
	for key: Variant in template.keys():
		var k := str(key)
		var full_key := (prefix + "." + k) if not prefix.is_empty() else k
		if not data.has(k):
			return "必要欄位遺失: %s" % full_key

		var val: Variant = data[k]
		var tpl_val: Variant = template[k]
		if typeof(tpl_val) == TYPE_INT or typeof(tpl_val) == TYPE_FLOAT:
			if typeof(val) != TYPE_INT and typeof(val) != TYPE_FLOAT:
				return "欄位型別錯誤: %s 應為數字，實際為 %s" % [full_key, typeof(val)]
			var numeric_val := float(val)
			if is_nan(numeric_val) or is_inf(numeric_val):
				return "欄位型別錯誤: %s 應為有限數字，實際為 %s" % [full_key, str(val)]
			if typeof(tpl_val) == TYPE_INT and floor(numeric_val) != numeric_val:
				return "欄位型別錯誤: %s 應為整數，實際為 %s" % [full_key, str(val)]
		elif typeof(tpl_val) == TYPE_DICTIONARY:
			if typeof(val) != TYPE_DICTIONARY:
				return "欄位型別錯誤: %s 應為 Dictionary，實際為 %s" % [full_key, typeof(val)]
			var tpl_sub := tpl_val as Dictionary
			if not tpl_sub.is_empty():
				var sub_err := validate_dict_shape(val as Dictionary, tpl_sub, full_key)
				if not sub_err.is_empty():
					return sub_err
		elif typeof(tpl_val) == TYPE_ARRAY and typeof(val) != TYPE_ARRAY:
			return "欄位型別錯誤: %s 應為 Array，實際為 %s" % [full_key, typeof(val)]
		elif typeof(tpl_val) == TYPE_STRING and typeof(val) != TYPE_STRING:
			return "欄位型別錯誤: %s 應為 String，實際為 %s" % [full_key, typeof(val)]
		elif typeof(tpl_val) == TYPE_BOOL and typeof(val) != TYPE_BOOL:
			return "欄位型別錯誤: %s 應為 bool，實際為 %s" % [full_key, typeof(val)]
	return ""
