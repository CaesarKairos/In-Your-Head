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
##    (texture.get_size() * scale) e, a cada frame, compara com a posição em
##    pixels do Player (WorldCoordinates.pixel_position + offset dos pés).
##    Quando os PÉS do player estão atrás do prop (ao norte) e DENTRO da
##    silhueta desenhada (copa), o sprite fica translúcido (modulate.a ->
##    FADED_ALPHA) e o z_index sobe para 1, desenhando o prop NA FRENTE do
##    jogador. Fora da silhueta (ao lado, na frente, ou acima do topo),
##    volta a 100% opaco e a z_index 0.
##
## Por que coordenada em vez de Area2D? A forma antiga usava um RectangleShape2D
## na "copa" (região superior, y<0) que nunca se sobrepunha ao corpo do Player
## (que fica na base), e o Area2D tinha collision_mask = 1 enquanto o Player está
## na layer 2 — então body_entered nunca disparava. A comparação por tile resolve
## "atrás vs na frente" de forma determinística e sem retângulos de debug.

const FADED_ALPHA: float = 0.45
const TILE_SIZE: int = 16

## Margem (px) adicionada à silhueta do sprite para a janela de oclusão.
## Pequena: só compensa a granularidade do movimento entre frames.
const OCCLUDE_MARGIN_PX: float = 2.0
## Offset (px) da "base dos pés" do Player em relação à origem do seu
## CharacterBody2D (a colisão do player é ancorada nos pés, ~7px abaixo).
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
## Sentinela explícita: `Vector2i.ZERO` é um tile legítimo do mundo, então não
## pode ser reaproveitado como "ainda não inicializado".
var _plant_tile_ready: bool = false
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

	# Tile de plantio: calculado diferido, após o prop estar posicionado na
	# árvore da cena (global_position confiável só então).
	call_deferred("_lazy_init")


## Calcula o tile de plantio após o nó estar devidamente posicionado na árvore
## (chunk já instanciada/posicionada). global_position reflete o nível do mundo.
func _lazy_init() -> void:
	if _plant_tile_ready:
		return
	_plant_tile_ready = true
	_plant_tile = Vector2i(
		floori(global_position.x / float(TILE_SIZE)),
		floori(global_position.y / float(TILE_SIZE))
	)


func _on_coords_changed(_tile_position: Vector2i, _chunk_position: Vector2i) -> void:
	# A checagem fina é feita por _process em pixels (o sinal só dispara a cada
	# 16px de movimento, granularidade demais para uma janela de ~20px).
	pass


## Decide se o prop fica translúcido dado o ponto dos "pés" do Player em pixels.
##
## A silhueta do sprite (com offset = (-w/2, -h), base em y=0, escalada pelo nó)
## cobre x em [-w/2, +w/2] e y em [-h, 0]. O Player só conta como "atrás" do
## prop quando o ponto dos pés dele está DENTRO dessa silhueta vindo pelo norte:
## assim, andar ao lado da copa (fora da largura desenhada) nunca translucida o
## prop — correção do Bug 2 (janela fixa de 2 tiles era maior que a copa para
## quase todos os sprites, e curta demais para as árvores grandes).
func _update_occlusion(player_foot_px: Vector2) -> void:
	if not occludable:
		return
	var size: Vector2 = texture.get_size() * scale
	var half_w: float = size.x * 0.5 + OCCLUDE_MARGIN_PX
	var dx: float = absf(player_foot_px.x - global_position.x)
	var dy: float = global_position.y - player_foot_px.y
	# dy > 0: pés do player ao norte (acima) da base do prop; o pé deve estar
	# dentro da altura da copa para o prop cobri-lo visualmente.
	var occluded := dy > 0.0 and dy <= size.y + OCCLUDE_MARGIN_PX and dx <= half_w
	_set_occluded(occluded)


func _process(_delta: float) -> void:
	if _wc == null or not _plant_tile_ready:
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
		z_index = 1
		_tween.tween_property(_sprite, "modulate:a", FADED_ALPHA, 0.12)
	else:
		z_index = 0
		_tween.tween_property(_sprite, "modulate:a", 1.0, 0.12)
