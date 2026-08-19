extends Camera2D

@export_category("Zoom")
@export var default_zoom: float = 2.0
@export var min_zoom: float = 1.0
@export var max_zoom: float = 3.0
@export var zoom_step: float = 0.25
@export var zoom_speed: float = 10.0

var target_zoom: float


func _ready() -> void:
	target_zoom = default_zoom
	zoom = Vector2.ONE * default_zoom


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("zoom_in"):
		target_zoom += zoom_step

	if Input.is_action_just_pressed("zoom_out"):
		target_zoom -= zoom_step

	target_zoom = clamp(
		target_zoom,
		min_zoom,
		max_zoom
	)

	var target := Vector2.ONE * target_zoom

	zoom = zoom.lerp(
		target,
		zoom_speed * delta
	)
