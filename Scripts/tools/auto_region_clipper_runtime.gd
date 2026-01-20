extends Node

# 配置要处理的场景路径
const TARGET_SCENES = [
	"res://scenes/Game2D.tscn",
	"res://scenes/main.tscn",
]

const SAVING_THRESHOLD = 0.2

func _ready() -> void:
	print("========== 开始执行 Region 自动裁切 (Debug Mode) ==========")
	await get_tree().process_frame
	
	for scene_path in TARGET_SCENES:
		if FileAccess.file_exists(scene_path):
			_process_scene(scene_path)
		else:
			print("找不到场景: " + scene_path)
	
	print("========== 完成 ==========")
	get_tree().quit()

func _process_scene(path: String) -> void:
	print("正在加载场景: ", path)
	var scene = load(path)
	if not scene: return
		
	var root = scene.instantiate()
	if not root: return
	
	var nodes_modified = 0
	var all_nodes = _get_all_children(root)
	all_nodes.append(root)
	
	for node in all_nodes:
		if node is Sprite2D:
			# DEBUG PRINT
			# print("Checking sprite: ", node.name)
			if _process_sprite(node):
				nodes_modified += 1
	
	if nodes_modified > 0:
		print("保存场景: ", path)
		var packed = PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, path)
	
	root.queue_free()

func _get_all_children(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child in node.get_children():
		nodes.append(child)
		if child.get_child_count() > 0:
			nodes.append_array(_get_all_children(child))
	return nodes

func _process_sprite(sprite: Sprite2D) -> bool:
	if sprite.region_enabled: return false
	var texture = sprite.texture
	if not texture: return false
	
	var texture_w = texture.get_width()
	var texture_h = texture.get_height()
	
	# Basic check
	if texture_w == 0: return false

	var used_rect = Rect2()
	var loaded_from_source = false
	
	# Try get_image
	var image = texture.get_image()
	if image and not image.is_compressed():
		used_rect = Rect2(image.get_used_rect())
	else:
		# Fallback
		var path = texture.resource_path
		if path.begins_with("res://"):
			var abs_path = ProjectSettings.globalize_path(path)
			var source_img = Image.load_from_file(abs_path)
			if source_img:
				var src_rect = source_img.get_used_rect()
				var src_size = source_img.get_size()
				var scale_x = float(texture_w) / float(src_size.x)
				var scale_y = float(texture_h) / float(src_size.y)
				used_rect = Rect2(
					src_rect.position.x * scale_x,
					src_rect.position.y * scale_y,
					src_rect.size.x * scale_x,
					src_rect.size.y * scale_y
				)
				used_rect.position = used_rect.position.floor()
				used_rect.size = used_rect.size.ceil()
				loaded_from_source = true
			else:
				# DEBUG
				if "TheRabbit" in sprite.name:
					print("Failed to load source image for: ", sprite.name, " Path: ", abs_path)
				return false
		else:
			return false

	var total_area = float(texture_w * texture_h)
	var used_area = float(used_rect.size.x * used_rect.size.y)
	var ratio = 1.0 - (used_area / total_area)
	
	# Verify optimization
	if ratio > SAVING_THRESHOLD:
		print("  [优化] ", sprite.name, " 节省率: ", int(ratio * 100), "%")
		sprite.region_enabled = true
		sprite.region_rect = used_rect
		
		# Offset logic
		var old_center = Vector2(texture_w / 2.0, texture_h / 2.0)
		var new_center = used_rect.position + used_rect.size / 2.0
		var diff = new_center - old_center
		
		if sprite.centered:
			sprite.offset += diff
		else:
			sprite.offset += used_rect.position
		return true
	else:
		# DEBUG
		if "TheRabbit" in sprite.name:
			print("Skipped ", sprite.name, " Ratio: ", ratio)
		return false
