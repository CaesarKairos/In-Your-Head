class_name NatureProp
extends Node2D

## Prop sólido de natureza (árvore, arbusto, pedra) gerado pelo NatureScatter.
## Monta a si mesmo em _ready a partir de `texture` + flags:
##
##  - Sprite2D com a BASE ancorada na origem do nó (a posição é o "pezinho"
##    plantado no chão);
##  - StaticBody2D + CollisionShape2D PEQUENA (círculo, 3–8px de raio) centrada
##    exatamente no tronco/base — nunca um retângulo cobrindo o cluster;
##  - Oclusão translúcida baseada em COORDENADA (não em Area2D): cada prop sabe
##    o tile do mundo onde está plantado e, via o autoload WorldCoordinates,
##    compara com o tile atual do Player. Quando o Player está atrás do prop
##    (mais ao norte / acima na tela) e dentro de uma janela lateral, o sprite
##    fica translúcido (modulate.a -> FADED_ALPHA) e o z_index sobe para 1,
##    desenhando o prop NA FRENTE do jogador com transparência. Ao sair dessa
##    faixa, volta a 100% opaco e a z_index 0.
##
## Por que coordenada em vez de Area2D? A forma antiga usava um RectangleShape2D
## na "copa" (região superior, y<0) que nunca se sobrepunha ao corpo do Player
## (que fica na base), e o Area2D tinha collision_mask = 1 enquanto o Player está
## na layer 2 — então body_entered nunca disparava. A comparação por tile resolve
## "atrás vs na frente" de forma determinística e sem retângulos de debug.

const FADED_ALPHA: float = 0.45
const TILE_SIZE: int = 16

## Quantos tiles de altura (ao norte) o Player ainda conta como "atrás" do prop.
const OCCLUDE_Y_SPAN: int = 2
## Meia-largura em tiles da janela lateral de oclusão (evita desvanecer árvores
## longe na mesma fileira).
const OCCLUDE_X_SPAN: int = 2

@export var texture: Texture2D
## Colisão física na base (tronco/pedra). Arbustos grandes também são sólidos.
@export var solid: bool = true
## Zona de oclusão (copa). Falso para pedras/tocos (baixos, nunca cobrem o player).
@export var occludable: bool = true
## Espelha o sprite horizontalmente (variação visual pedida na Parte 3).
@export var flip_h: bool = false

var _sprite: Sprite2D
var _tween: Tween
var _occluded: bool = false
var _plant_tile: Vector2i = Vector2i.ZERO
var _wc = null  # Variant: autoload WorldCoordinates (acesso dinâmico ao sinal)


func _ready() -> void:
	if texture == null:
		push_warning("[NatureProp] Sem texture; prop ignorado.")
		return
	var size := texture.get_size()

	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.flip_h = flip_h
	_sprite.offset = Vector2(-size.x / 2.0, -size.y)
	add_child(_sprite)

	if solid:
		var body := StaticBody2D.new()
		body.name = "Body"
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		# Círculo pequeno na base, centrado/tocado ao tronco, proporcional ao sprite.
		circle.radius = clampf(minf(size.x, size.y) * 0.16, 3.0, 8.0)
		shape.shape = circle
		shape.position = Vector2(0.0, -circle.radius * 0.5)
		body.add_child(shape)
		add_child(body)

	# Oclusão por coordenada via autoload (mais confiável que Area2D).
	_wc = get_node_or_null("/root/WorldCoordinates")
	if _wc != null:
		if not _wc.coordinates_changed.is_connected(_on_coords_changed):
			_wc.coordinates_changed.connect(_on_coords_changed)

	if _plant_tile == Vector2i.ZERO:
		call_deferred("_lazy_init")

	if not occludable:
		return
	# Estado inicial (caso a origem coincida com (0,0), força reavaliação).
	if _wc != null:
		_on_coords_changed(_wc.tile_position, _wc.chunk_position)


## Calcula o tile de plantio após o nó estar devidamente posicionado na árvore
## (chunk já instanciada/posicionada). global_position reflete o nível do mundo.
func _lazy_init() -> void:
	if _plant_tile == Vector2i.ZERO:
		_plant_tile = Vector2i(
			floori(global_position.x / float(TILE_SIZE)),
			floori(global_position.y / float(TILE_SIZE))
		)
		if _wc != null:
			_on_coords_changed(_wc.tile_position, _wc.chunk_position)


func _on_coords_changed(tile_position: Vector2i, _chunk_position: Vector2i) -> void:
	if _plant_tile == Vector2i.ZERO:
		return
	# "Atrás" = o Player está ao NORTE (acima na tela) do prop: p.y < plant.y.
	# dy > 0 => player ao norte; dy <= 0 => na mesma linha ou ao sul (na frente).
	var dy: int = _plant_tile.y - tile_position.y
	var dx: int = absi(tile_position.x - _plant_tile.x)
	var occluded := dy > 0 and dy <= OCCLUDE_Y_SPAN and dx <= OCCLUDE_X_SPAN
	_set_occluded(occluded)


func _set_occluded(occluded: bool) -> void:
	if occluded == _occluded:
		return
	_occluded = occluded
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)
	if occluded:
		z_index = 1
		_tween.tween_property(_sprite, "modulate:a", FADED_ALPHA, 0.12)
	else:
		z_index = 0
		_tween.tween_property(_sprite, "modulate:a", 1.0, 0.12)
