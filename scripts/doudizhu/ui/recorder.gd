class_name DdzRecorderStrip
extends Control
const Kit = preload("res://scripts/ui/ui_kit.gd")
const Cards = preload("res://scripts/doudizhu/core/cards.gd")
const Recorder = preload("res://scripts/doudizhu/core/recorder.gd")
var counts: Array = []
var total = 0
var count_labels: Array = []

func _ready() -> void:
	size = Vector2(840, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel = Kit.table_panel(self, Rect2(Vector2.ZERO, size), false, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(15):
		var rank_value = 17 - index
		var x = index * 56.0
		var rank_text = Kit.label(panel, Rect2(x, 1, 56, 24), Cards.rank_label(rank_value), 20, Kit.CORAL if rank_value == 17 else Kit.MUTED)
		rank_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var count = Kit.label(panel, Rect2(x, 24, 56, 32), "—", 26, Kit.ACCENT)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_labels.append(count)
	_refresh()

func set_view(view: Dictionary) -> void:
	counts = Recorder.remaining(view)
	total = counts.reduce(func(sum, value): return sum + value, 0)
	_refresh()

func _refresh() -> void:
	for index in range(count_labels.size()):
		var count = int(counts[14 - index]) if counts.size() == 15 else -1
		count_labels[index].text = str(count) if count >= 0 else "—"
		count_labels[index].add_theme_color_override("font_color", Kit.ACCENT if count > 0 else Color("789087"))
