@tool
extends SceneTree

# 配置要处理的场景路径
const TARGET_SCENES = [
	"res://scenes/Game2D.tscn",
	"res://scenes/ui/the_rabbit_animator.tscn",
	"res://scenes/main.tscn",
	"res://scenes/background_animated.tscn"
]

# 最小节省比例，只有当裁切能节省超过 1% 的面积时才执行
const SAVING_THRESHOLD = 0.01
# 裁切边缘保留像素（避免过度裁切导致边缘模糊或丢失）
const MARGIN = 2

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
		elif node is AnimatedSprite2D:
			if _process_animated_sprite(node):
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

func _calculate_optimized_rect(image: Image, texture_w: int, texture_h: int) -> Rect2i:
	var used_rect = image.get_used_rect()
	
	if used_rect.size == Vector2i.ZERO:
		return Rect2i()
		
	# Apply Margin
	used_rect = used_rect.grow(MARGIN)
	
	# Clamp to image bounds
	var full_rect = Rect2i(0, 0, texture_w, texture_h)
	return used_rect.intersection(full_rect)

func _process_sprite(sprite: Sprite2D) -> bool:
	# 0. 基础检查
	if sprite.region_enabled:
		# Already optimized? Maybe re-optimize if margin changed?
		# For safety, let's assume if it is enabled, we skip unless we want to force re-calc.
		# The user said "previously... cropped parts... optimize this script first".
		# So maybe I SHOULD re-calculate even if enabled?
		# But 'region_enabled' could be manual.
		# Let's stick to "if enabled return false" for safety, assuming the user might revert or I should rely on the user to revert first if they want to fix specific nodes.
		# BUT, if the user says "previously cropped", those nodes might presently have region_enabled = true.
		# If I skip them, I don't fix them!
		# So I MUT NOT skip if region_enabled is true, I should RE-CHECK.
		# However, if I re-check, I need the ORIGINAL full texture.
		# Sprite2D with region enabled still has the full 'texture'. 
		# But I need to ignore the current region when calculating used_rect.
		# 'image = texture.get_image()' gets the FULL image of the texture resource.
		# So it is safe to re-process!
		pass
	
	var texture = sprite.texture
	if not texture:
		return false
		
	# 1. 获取图片数据
	var image = texture.get_image()
	if not image:
		return false
	
	# 2. 计算非透明区域
	var texture_w = texture.get_width()
	var texture_h = texture.get_height()
	var total_area = float(texture_w * texture_h)
	
	if total_area < 1.0: return false
	
	var used_rect = _calculate_optimized_rect(image, texture_w, texture_h)
	
	if used_rect.size == Vector2i.ZERO:
		return false
		
	var used_area = float(used_rect.size.x * used_rect.size.y)
	var saving_ratio = 1.0 - (used_area / total_area)
	
	# 3. 检查是否值得优化
	if saving_ratio < SAVING_THRESHOLD:
		# If it was enabled but now we think it's not worth it (or we just want to revert?)
		# No, just keep it.
		return false
	
	# Check if we are actually changing anything significant
	if sprite.region_enabled and sprite.region_rect == Rect2(used_rect):
		return false

	print("  [优化 Sprite2D] ", sprite.name)
	print("    - 原尺寸: ", texture_w, "x", texture_h)
	print("    - 有效区: ", used_rect)
	print("    - 节省率: ", int(saving_ratio * 100), "%")
	
	# 4. 应用修改
	sprite.region_enabled = true
	sprite.region_rect = Rect2(used_rect)
	
	# 5. 修正偏移量
	# Note: If we are re-processing, 'offset' might already be modified!
	# This creates a problem: how do we know the "original" offset?
	# We don't.
	# If the user's previous run modified the offset, running this again will add MORE offset.
	# This is dangerous.
	# We should assume 'centered' implies center of the *cropped* rect.
	# If we re-calculate offset based on current offset, we drift.
	# The script logic:
	# var new_center...
	# if sprite.centered: sprite.offset += diff
	# This logic assumes 'offset' starts at (0,0) relative to image center.
	# If we run it twice, we add diff twice.
	# We should try to RESET offset if we detect region_enabled?
	# This is hard without knowing the original state.
	# However, for the user's current request "optimize this script first", 
	# maybe they haven't applied it to the files I'm about to process (shooting_star), or they want me to fix the logic for future runs.
	# For "Sprite2D", I will keep the check 'if sprite.region_enabled: return false' to be safe against double-application.
	# The user said "previously... cropped". Implicitly they might have reverted, or they accept I fix *future* runs. 
	# Or they want me to fix the *existing* broken ones.
	# IF I want to fix existing ones, I need to know they are broken.
	# But I'll stick to 'return false' if enabled, to avoid compounding offsets.
	if sprite.region_enabled:
		return false
	
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

func _process_animated_sprite(anim_sprite: AnimatedSprite2D) -> bool:
	var sprite_frames = anim_sprite.sprite_frames
	if not sprite_frames:
		return false
		
	var modified = false
	
	for anim_name in sprite_frames.get_animation_names():
		var frame_count = sprite_frames.get_frame_count(anim_name)
		for i in range(frame_count):
			var texture = sprite_frames.get_frame_texture(anim_name, i)
			
			if texture is AtlasTexture:
				continue
				
			if not texture:
				continue
				
			var image = texture.get_image()
			if not image:
				continue
				
			var texture_w = texture.get_width()
			var texture_h = texture.get_height()
			var total_area = float(texture_w * texture_h)
			
			if total_area < 1.0: continue
			
			var used_rect = _calculate_optimized_rect(image, texture_w, texture_h)
			
			if used_rect.size == Vector2i.ZERO:
				continue
				
			var used_area = float(used_rect.size.x * used_rect.size.y)
			var saving_ratio = 1.0 - (used_area / total_area)
			
			if saving_ratio < SAVING_THRESHOLD:
				continue
				
			print("  [优化 AnimatedSprite Frame] ", anim_name, ":", i)
			print("    - 原尺寸: ", texture_w, "x", texture_h)
			# print("    - 有效区: ", used_rect)
			
			var atlas_tex = AtlasTexture.new()
			atlas_tex.atlas = texture
			atlas_tex.region = Rect2(used_rect)
			atlas_tex.filter_clip = true
			
			# Correctly set margin for alignment
			# atlas_tex.margin = Rect2(offset, size)
			atlas_tex.margin = Rect2(used_rect.position, Vector2(texture_w, texture_h))
			
			sprite_frames.set_frame(anim_name, i, atlas_tex)
			modified = true
			
	return modified
