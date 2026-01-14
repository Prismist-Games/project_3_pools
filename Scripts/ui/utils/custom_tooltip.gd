class_name CustomTooltip
extends Control


func _make_custom_tooltip(for_text):
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = for_text
	label.set_custom_minimum_size(Vector2.RIGHT * 300)
	label.fit_content = true
	return label
