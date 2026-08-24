@tool
extends Node2D

const CHUNK_TILES: int = 33
const TILE_SIZE: int = 16
const CHUNK_SIZE: int = CHUNK_TILES * TILE_SIZE

enum Enabled {
	ON,
	OFF
}

@export_category("Visualização")

@export var enabled: Enabled = Enabled.ON:
	set(value):
		enabled = value
		queue_redraw()

@export var show_grid: bool = true:
	set(value):
		show_grid = value
		queue_redraw()

@export var show_border: bool = true:
	set(value):
		show_border = value
		queue_redraw()

@export var show_connectors: bool = true:
	set(value):
		show_connectors = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if enabled == Enabled.OFF:
		return

	if show_grid:
		_draw_grid()

	if show_border:
		_draw_border()

	if show_connectors:
		_draw_connectors()


func _draw_grid() -> void:
	var grid_color := Color(0.0, 1.0, 1.0, 0.35)

	for x in range(CHUNK_TILES + 1):
		var px := float(x * TILE_SIZE)

		draw_line(
			Vector2(px, 0.0),
			Vector2(px, CHUNK_SIZE),
			grid_color,
			1.0
		)

	for y in range(CHUNK_TILES + 1):
		var py := float(y * TILE_SIZE)

		draw_line(
			Vector2(0.0, py),
			Vector2(CHUNK_SIZE, py),
			grid_color,
			1.0
		)


func _draw_border() -> void:
	var border_color := Color(1.0, 0.2, 0.8, 1.0)

	draw_rect(
		Rect2(
			Vector2.ZERO,
			Vector2(CHUNK_SIZE, CHUNK_SIZE)
		),
		border_color,
		false,
		4.0
	)


func _draw_connectors() -> void:
	var connector_color := Color(1.0, 0.85, 0.0, 1.0)

	var center_tile := 16
	var connector_tiles := 3

	var center_px := center_tile * TILE_SIZE
	var connector_size := connector_tiles * TILE_SIZE
	var half_size := connector_size / 2.0

	# NORTH
	draw_rect(
		Rect2(
			center_px - half_size,
			-16.0,
			connector_size,
			16.0
		),
		connector_color,
		true
	)

	# SOUTH
	draw_rect(
		Rect2(
			center_px - half_size,
			CHUNK_SIZE,
			connector_size,
			16.0
		),
		connector_color,
		true
	)

	# WEST
	draw_rect(
		Rect2(
			-16.0,
			center_px - half_size,
			16.0,
			connector_size
		),
		connector_color,
		true
	)

	# EAST
	draw_rect(
		Rect2(
			CHUNK_SIZE,
			center_px - half_size,
			16.0,
			connector_size
		),
		connector_color,
		true
	)
