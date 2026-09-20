class_name NatureProp
extends Node2D

## Prop sólido de natureza (árvore, arbusto, pedra) gerado pelo NatureScatter.
## Monta a si mesmo em _ready a partir de `texture` + flags:
##
##  - Sprite2D com a BASE ancorada na origem do nó (a posição é o "pezinho"
##    plantado no chão);
##  - StaticBody2D + CollisionShape2D PEQUENA (círculo, 3–8px de raio) centrada
##    exatamente no tronco/base — nunca um retângulo cobrindo o cluster;
##  - Oclusão translúcida POR PIXEL (não por tile, não por Area2D): cada prop
##    deriva a janela de oclusão do tamanho REAL do próprio sprite
##    (texture.get_size() * global_scale.abs()) e, a cada frame, compara com a posição em
##    pixels do Player (WorldCoordinates.pixel_position + offset dos pés).
##    Quando os PÉS do player estão atrás do prop (ao norte) e DENTRO da
##    silhueta desenhada (copa), o sprite fica translúcido (modulate.a ->
##    FADED_ALPHA). A ordem de desenho pertence ao Y-sort do mundo.

const FADED_ALPHA: float = 0.45
const OCCLUDE_MARGIN_PX: float = 2.0
const PLAYER_FOOT_OFFSET_PX: float = 7.0

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
var _wc: Node = null



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

	_wc = get_node_or_null("/root/WorldCoordinates")
	set_process(occludable and _wc != null)


## Janela derivada da textura real e da escala global, com base na origem.
func _update_occlusion(player_foot_px: Vector2) -> void:
	if not occludable:
		return
	var size: Vector2 = texture.get_size() * global_scale.abs()
	var half_w: float = size.x * 0.5 + OCCLUDE_MARGIN_PX
	var dx: float = absf(player_foot_px.x - global_position.x)
	var dy: float = global_position.y - player_foot_px.y
	# dy > 0: pés do player ao norte (acima) da base do prop; o pé deve estar
	# dentro da altura da copa para o prop cobri-lo visualmente.
	var occluded := dy > 0.0 and dy <= size.y + OCCLUDE_MARGIN_PX and dx <= half_w
	_set_occluded(occluded)


func _process(_delta: float) -> void:
	if _wc == null:
		return
	_update_occlusion(_wc.pixel_position + Vector2(0.0, PLAYER_FOOT_OFFSET_PX))


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
		_tween.tween_property(_sprite, "modulate:a", FADED_ALPHA, 0.12)
	else:
		_tween.tween_property(_sprite, "modulate:a", 1.0, 0.12)
