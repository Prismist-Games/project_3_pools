@tool
extends SceneTree

# 配置要处理的场景路径
const TARGET_SCENES = [
	"res://scenes/Game2D.tscn",
    "res://scenes/ui/the_rabbit_animator.tscn", # Hypothetical, but based on user request
    "res://scenes/main.tscn"
]

# 最小节省比例，只有当裁切能节省超过 20% 的面积时才执行
const SAVING_THRESHOLD = 0.2

func _init() -> void:
	print("========== 开始执行 Region 自动裁切 (CLI Mode) ==========")
	
	for scene_path in TARGET_SCENES:
		if FileAccess.file_exists(scene_path):
			process_scene(scene_path)
		else:
			print("Could not find scene: " + scene_path)
	
	print("========== 全部处理完成 ==========")
	quit()

func process_scene(path: String) -> void:
	print("正在加载场景: ", path)
	var scene = load(path)
	if not scene:
		printerr("无法加载场景: ", path)
		return
		
	var root = scene.instantiate()
	if not root:
		printerr("无法实例化场景: ", path)
		return
	
	var nodes_modified = 0
	
	# 获取所有节点（递归）
	var all_nodes = _get_all_children(root)
	all_nodes.append(root)
	
	for node in all_nodes:
		if node is Sprite2D:
			if _process_sprite(node):
				nodes_modified += 1
	
	if nodes_modified > 0:
		print("  -> 保存场景: ", path, " (修改了 ", nodes_modified, " 个节点)")
		var packed_scene = PackedScene.new()
		packed_scene.pack(root)
		ResourceSaver.save(packed_scene, path)
	else:
		print("  -> 未发现需要优化的节点")
	
	root.queue_free()

func _get_all_children(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child in node.get_children():
		nodes.append(child)
		if child.get_child_count() > 0:
			nodes.append_array(_get_all_children(child))
	return nodes

func _process_sprite(sprite: Sprite2D) -> bool:
	# 0. 基础检查
	if sprite.region_enabled:
		return false
	
	var texture = sprite.texture
	if not texture:
		return false
		
	# 1. 获取图片数据
	var image = texture.get_image()
	if not image:
		# printerr("  [警告] 无法获取纹理数据: ", sprite.name)
		return false
	
	# 2. 计算非透明区域
	var texture_w = texture.get_width()
	var texture_h = texture.get_height()
	var total_area = float(texture_w * texture_h)
	
	if total_area == 0: return false
	
	# 使用内置的 get_used_rect() 获取非透明包围盒
	var used_rect = image.get_used_rect()
	
	if used_rect.size == Vector2i.ZERO:
		return false
		
	var used_area = float(used_rect.size.x * used_rect.size.y)
	
	# 防止除以零或其他错误
	if total_area < 1.0: return false
	
	var saving_ratio = 1.0 - (used_area / total_area)
	
	# 3. 检查是否值得优化
	if saving_ratio < SAVING_THRESHOLD:
		return false
	
	print("  [优化] ", sprite.name)
	print("    - 原尺寸: ", texture_w, "x", texture_h)
	print("    - 有效区: ", used_rect)
	print("    - 节省率: ", int(saving_ratio * 100), "%")
	
	# 4. 应用修改
	sprite.region_enabled = true
	sprite.region_rect = Rect2(used_rect)
	
	# 5. 修正偏移量
	var old_center_x = float(texture_w) / 2.0
	var old_center_y = float(texture_h) / 2.0
	
	var new_center_x = used_rect.position.x + float(used_rect.size.x) / 2.0
	var new_center_y = used_rect.position.y + float(used_rect.size.y) / 2.0
	
	var diff = Vector2(new_center_x - old_center_x, new_center_y - old_center_y)
	
	if sprite.centered:
		sprite.offset += diff
	else:
		sprite.offset += Vector2(used_rect.position)
		
	return true
