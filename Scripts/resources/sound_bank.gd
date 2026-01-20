extends Resource
class_name SoundBank

## 音效库资源
## 用于在编辑器中批量配置音效映射

@export var entries: Array[SoundBankEntry] = []

@export_dir var scan_path: String = ""

func load_from_dir(path: String = "") -> void:
	if path == "":
		path = scan_path
	if path == "":
		return

	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				# 尝试加载资源
				var res_path = path + "/" + file_name
				var res = load(res_path)
				if res is SoundBankEntry:
					# 检查 stream 是否有效
					if not res.stream:
						push_warning("SoundBank: Entry '%s' has no audio stream, skipping" % res.id)
					elif not _has_entry(res):
						entries.append(res)
				elif res == null:
					push_warning("SoundBank: Failed to load resource at '%s'" % res_path)
			file_name = dir.get_next()
		
		# 排序以便于管理
		entries.sort_custom(func(a, b): return a.id < b.id)

func _has_entry(entry: SoundBankEntry) -> bool:
	for e in entries:
		if e.id == entry.id:
			return true
	return false
