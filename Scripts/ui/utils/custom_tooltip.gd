class_name CustomTooltip
extends Control


func _make_custom_tooltip(for_text: String):
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	# 使用 Constants 处理图标尺寸
	label.text = Constants.process_tooltip_text(for_text)
	label.set_custom_minimum_size(Vector2(300, 0))
	label.fit_content = true
	return label
