class_name RichTextAutoScaler
extends RichTextLabel

## A utility script for RichTextLabel to automatically scale font size to fit its bounding box.
## 
## This script monitors text changes and size changes to adjust the 'normal_font_size' 
## theme override until the content fits within the vertical height of the label.

@export var max_font_size: int = 32
@export var min_font_size: int = 12
@export var auto_scale_on_ready: bool = true

var _last_text: String = ""
var _last_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Ensure the label doesn't show scrollbars which would interfere with our "fit" logic
	scroll_active = false
	
	if auto_scale_on_ready:
		update_font_size()
	
	item_rect_changed.connect(_on_item_rect_changed)

func _process(_delta: float) -> void:
	# Optimization: Don't process if not visible or not in tree
	if not is_visible_in_tree():
		return

	# Check for text changes since there's no 'text_changed' signal for RichTextLabel
	if text != _last_text:
		_last_text = text
		update_font_size()

func _on_item_rect_changed() -> void:
	if size != _last_size:
		_last_size = size
		update_font_size()

## Manually trigger the font size update.
func update_font_size() -> void:
	if not is_inside_tree() or text.is_empty():
		return
		
	var current_font_size: int = max_font_size
	var target_height: float = size.y
	var target_width: float = size.x
	
	# Get the font and handle potential nulls
	var font: Font = get_theme_font(&"normal_font")
	if not font:
		return

	# Iterate downwards from max_font_size to find the first size that fits
	# We use font.get_multiline_string_size for synchronous and accurate measurement
	var measure_text: String = get_parsed_text() if bbcode_enabled else text
	if measure_text.is_empty() and not text.is_empty():
		measure_text = text # Fallback if parsing hasn't happened yet
	
	while current_font_size > min_font_size:
		# Use -1.0 for width if autowrap is off to get the full line width
		var wrap_width: float = target_width if autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
		
		# RichTextLabel has horizontal_alignment in Godot 4.3+
		var text_size: Vector2 = font.get_multiline_string_size(
			measure_text,
			horizontal_alignment,
			wrap_width,
			current_font_size
		)
		
		# If wrap is off, we must check width as well.
		# If wrap is on, get_multiline_string_size will wrap it to target_width 
		# and increase height, so checking height is usually enough.
		if text_size.y <= target_height:
			if autowrap_mode == TextServer.AUTOWRAP_OFF:
				if text_size.x <= target_width:
					break
			else:
				break
			
		current_font_size -= 1
	
	_apply_font_size(current_font_size)

func _apply_font_size(p_size: int) -> void:
	add_theme_font_size_override("normal_font_size", p_size)
	# Also apply to other font types if they exist in the BBCode to keep it consistent
	add_theme_font_size_override("bold_font_size", p_size)
	add_theme_font_size_override("italics_font_size", p_size)
	add_theme_font_size_override("bold_italics_font_size", p_size)
	add_theme_font_size_override("mono_font_size", p_size)
