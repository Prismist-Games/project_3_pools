@tool
extends SceneTree

func _init():
	var dir = DirAccess.open("res://assets/sprites/city_bg")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !file_name.begins_with(".") and file_name.ends_with(".png"):
				var texture = load("res://assets/sprites/city_bg/" + file_name)
				if texture is Texture2D:
					print("ANTIGRAVITY_SIZE:" + file_name + "|" + str(texture.get_width()) + "|" + str(texture.get_height()))
			file_name = dir.get_next()
	quit()
