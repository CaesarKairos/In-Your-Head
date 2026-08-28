@tool
extends Node2D

const CHUNK_TILES: int = 33
const TILE_SIZE: int = 16
const CHUNK_SIZE: int = CHUNK_TILES * TILE_SIZE

## Tipos de conectores usados para definir como esta Chunk se conecta às vizinhas.
enum ConnectorType {
	NONE,       # Sem exigência / sem conexão.
	ROAD,       # Estrada principal.
	DIRT_ROAD,  # Estrada de terra.
	FOREST      # Floresta / vegetação densa.
}

## Biomas possíveis para uma Chunk.
enum Biome {
	CITY,
	SUBURB,
	FOREST
}

## Liga/desliga a visualização de diagnóstico (grade, borda, conectores).
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

## Desenha as guias de diagnóstico (grade, borda, conectores) também quando o
## jogo roda (por exemplo no depurador). Por padrão é falso: fora do editor o
## mundo fica limpo, sem as guias coloridas de debug.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		queue_redraw()

@export_category("Identidade")

## Identificador único da Chunk (ex.: "crossroad_01").
## Usado pelo WorldGenerator e, futuramente, por chunks especiais.
@export var chunk_id: String = ""

@export_category("Bioma")

## Bioma a que esta Chunk pertence. Nesta etapa não afeta a geração.
@export var biome: Biome = Biome.CITY

@export_category("Conectores")

## Conector na borda NORTE (superior).
@export var north_connector: ConnectorType = ConnectorType.NONE

## Conector na borda SUL (inferior).
@export var south_connector: ConnectorType = ConnectorType.NONE

## Conector na borda LESTE (direita).
@export var east_connector: ConnectorType = ConnectorType.NONE

## Conector na borda OESTE (esquerda).
@export var west_connector: ConnectorType = ConnectorType.NONE

@export_category("Conectores Especiais")

## Conectores diagonais (planejados para o futuro). Não participam da geração nesta etapa.

@export var northeast_connector: ConnectorType = ConnectorType.NONE
@export var northwest_connector: ConnectorType = ConnectorType.NONE
@export var southeast_connector: ConnectorType = ConnectorType.NONE
@export var southwest_connector: ConnectorType = ConnectorType.NONE

@export_category("Geração")

## Atlas coord do tile de fundo liso (grama sem estrada) usado por esta Chunk.
## Fonte única de verdade para o scatter de natureza: só nasce vegetação sobre
## células cujo atlas coord no "Ground" seja este.
@export var background_atlas_coords: Vector2i = Vector2i(5, 0)

# Dados de geração pertencem ao WorldGenerator, não à Chunk.
# O comentário acima reserva a categoria no Inspector.


func _ready() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if enabled == Enabled.OFF:
		return

	# Fora do editor (jogo/depurador rodando), as guias de diagnóstico só são
	# desenhadas se o usuário as ligar explicitamente via show_in_game.
	if not Engine.is_editor_hint() and not show_in_game:
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
