extends CanvasLayer
## coords_hud
##
## Painel de debug fixo num canto da tela mostrando as coordenadas de TILE e
## CHUNK atuais do Player. Assina o sinal `coordinates_changed` do autoload
## WorldCoordinates e atualiza apenas quando o valor muda (sem overhead por
## frame).

@onready var label: Label = $Margin/Panel/VBox/LabelValue


func _ready() -> void:
	var wc: Variant = _world_coordinates()
	if wc == null:
		push_warning("[CoordsHUD] Autoload WorldCoordinates não encontrado.")
		return
	if not wc.coordinates_changed.is_connected(_refresh):
		wc.coordinates_changed.connect(_refresh)
	_refresh(wc.tile_position, wc.chunk_position)


func _refresh(tile_position: Vector2i, chunk_position: Vector2i) -> void:
	if label == null:
		return
	label.text = "Tile: (%d, %d) | Chunk: (%d, %d)" \
		% [tile_position.x, tile_position.y, chunk_position.x, chunk_position.y]


## Variant: acesso dinâmico ao autoload (sinal coordinates_changed).
func _world_coordinates() -> Variant:
	return get_node_or_null("/root/WorldCoordinates")