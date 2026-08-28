class_name NatureProp
extends Node2D

## Prop sólido de natureza (árvore, arbusto, pedra, toco) gerado pelo
## NatureScatter. Monta a si mesmo em _ready a partir de `texture` + flags:
##
##  - Sprite2D com a BASE ancorada na origem do nó (a posição é o "pezinho"
##    plantado no chão);
##  - StaticBody2D + CollisionShape2D pequena na base (colisão física real —
##    o jogador não atravessa o tronco). NÃO é atacável: StaticBody2D puro,
##    sem HP e sem marcação em grupo de dano (o projeto não tem grupos de
##    damageable; este nó deliberadamente não entra em grupo nenhum);
##  - Area2D de oclusão cobrindo a copa/região superior (o que fica "acima"
##    do jogador na tela): quando um CharacterBody2D (jogador) entra nela,
##    o sprite fica translúcido (modulate.a -> FADED_ALPHA) e o z_index sobe
##    para 1, desenhando o prop NA FRENTE do jogador com transparência — o
##    padrão "canopy occlusion / see-through foliage". Ao sair, volta a 100%
##    opaco e a z_index 0 (atrás do jogador). Isso reproduz o efeito de
##    Y-sort sem reestruturar a árvore de cena do mundo em streaming.
##
## NOTA IA: valores de fade/área são aproximados — revisar visualmente.

const FADED_ALPHA: float = 0.45

@export var texture: Texture2D
## Colisão física na base (tronco/pedra). Arbustos grandes também são sólidos.
@export var solid: bool = true
## Zona de oclusão (copa). Falso para pedras/tocos (baixos, nunca cobrem o player).
@export var occludable: bool = true

var _sprite: Sprite2D
var _tween: Tween


func _ready() -> void:
	if texture == null:
		push_warning("[NatureProp] Sem texture; prop ignorado.")
		return
	var size := texture.get_size()

	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.offset = Vector2(-size.x / 2.0, -size.y)
	add_child(_sprite)

	if solid:
		var body := StaticBody2D.new()
		body.name = "Body"
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = clampf(minf(size.x, size.y) * 0.18, 3.0, 8.0)
		shape.shape = circle
		shape.position = Vector2(0.0, -circle.radius)
		body.add_child(shape)
		add_child(body)

	if occludable:
		var area := Area2D.new()
		area.name = "OcclusionArea"
		var area_shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		# Cobre a região superior do sprite (copa): é a área que o jogador
		# "invade" quando passa por trás do prop.
		rect.size = Vector2(size.x * 0.85, size.y * 0.55)
		area_shape.shape = rect
		area_shape.position = Vector2(0.0, -size.y + rect.size.y / 2.0)
		area.add_child(area_shape)
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
		add_child(area)


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_set_occluded(true)


func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_set_occluded(false)


func _set_occluded(occluded: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_LINEAR)
	if occluded:
		z_index = 1
		_tween.tween_property(_sprite, "modulate:a", FADED_ALPHA, 0.1)
	else:
		z_index = 0
		_tween.tween_property(_sprite, "modulate:a", 1.0, 0.1)
