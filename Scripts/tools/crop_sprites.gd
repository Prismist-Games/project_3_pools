@tool
extends EditorScript

# 目标目录
const TARGET_DIR: String = "res://assets/sprites/the_machine/"

func _run() -> void:
	var dir = DirAccess.open(TARGET_DIR)
	if not dir:
		push_error("无法打开目录: " + TARGET_DIR)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	var processed_count: int = 0
	var skipped_count: int = 0

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			var success = _crop_image(TARGET_DIR + file_name)
			if success:
				processed_count += 1
			else:
				skipped_count += 1
		file_name = dir.get_next()
	
	print("--- 处理完成 ---")
	print("成功裁切: ", processed_count)
	print("无需处理/跳过: ", skipped_count)
	
	# 刷新资源面板
	EditorInterface.get_resource_filesystem().scan()

func _crop_image(path: String) -> bool:
	var image: Image = Image.load_from_file(path)
	if not image:
		push_error("无法加载图片: " + path)
		return false
	
	# 获取有像素的最小矩形区域
	var used_rect: Rect2i = image.get_used_rect()
	
	# 修正后的判断逻辑：
	# 如果宽度或高度为0（全透明），或者裁切大小等于原图大小（已裁切），则跳过
	if used_rect.size.x == 0 or used_rect.size.y == 0 or used_rect.size == image.get_size():
		return false
	
	# 执行裁切
	var cropped_image: Image = Image.create(used_rect.size.x, used_rect.size.y, false, image.get_format())
	cropped_image.blit_rect(image, used_rect, Vector2i.ZERO)
	
	# 保存覆盖原文件
	var err = cropped_image.save_png(path)
	if err == OK:
		print("裁切成功: ", path.get_file(), " (新尺寸: ", used_rect.size, ")")
		return true
	else:
		push_error("保存失败: ", path, " 错误代码: ", err)
		return false
