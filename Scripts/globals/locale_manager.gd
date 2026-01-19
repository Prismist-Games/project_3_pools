extends Node

## 本地化管理器 Autoload
##
## 提供统一的语言状态管理和本地化资源加载功能。
## 封装 TranslationServer，提供便捷的语言查询和切换方法。

## 语言变更信号，参数为新的 locale 代码（如 "zh", "en"）
signal locale_changed(new_locale: String)

## 教程图片的基础路径
const TUTORIAL_BASE_PATH: String = "res://assets/sprites/tutorial/"

## 支持的 locale 列表
const SUPPORTED_LOCALES: Array[String] = ["zh", "en"]


func _ready() -> void:
	# 确保初始 locale 是支持的
	var current = TranslationServer.get_locale()
	if not _is_supported_locale(current):
		TranslationServer.set_locale("en")


## 获取当前 locale（简化版，只返回主语言代码）
func get_locale() -> String:
	var full_locale = TranslationServer.get_locale()
	# 处理类似 "zh_CN" 的情况，只返回 "zh"
	if full_locale.begins_with("zh"):
		return "zh"
	return "en"


## 设置新的 locale
func set_locale(new_locale: String) -> void:
	if not _is_supported_locale(new_locale):
		push_warning("[LocaleManager] 不支持的 locale: %s，回退到 en" % new_locale)
		new_locale = "en"
	
	var current = get_locale()
	if current == new_locale:
		return
	
	TranslationServer.set_locale(new_locale)
	locale_changed.emit(new_locale)
	print("[LocaleManager] 语言切换至: %s" % new_locale)


## 切换语言（在中英文之间切换）
func toggle_locale() -> void:
	var current = get_locale()
	var new_locale = "en" if current == "zh" else "zh"
	set_locale(new_locale)


## 是否为中文环境
func is_chinese() -> bool:
	return get_locale() == "zh"


## 是否为英文环境
func is_english() -> bool:
	return get_locale() == "en"


## 根据当前语言获取本地化的纹理资源
## base_path: 基础路径，不含语言后缀，如 "res://assets/sprites/tutorial/1"
## 返回对应语言版本的纹理，如 "res://assets/sprites/tutorial/1_zh.png"
func get_localized_texture(base_path: String) -> Texture2D:
	var locale_suffix = get_locale()
	var full_path = "%s_%s.png" % [base_path, locale_suffix]
	
	if ResourceLoader.exists(full_path):
		return load(full_path) as Texture2D
	else:
		push_error("[LocaleManager] 找不到本地化纹理: %s" % full_path)
		return null


## 获取教程幻灯片图片
## slide_index: 1-5 的幻灯片索引
func get_tutorial_slide_texture(slide_index: int) -> Texture2D:
	if slide_index < 1 or slide_index > 5:
		push_error("[LocaleManager] 无效的幻灯片索引: %d" % slide_index)
		return null
	
	var base_path = "%s%d" % [TUTORIAL_BASE_PATH, slide_index]
	return get_localized_texture(base_path)


## 检查 locale 是否受支持
func _is_supported_locale(locale: String) -> bool:
	for supported in SUPPORTED_LOCALES:
		if locale.begins_with(supported):
			return true
	return false
