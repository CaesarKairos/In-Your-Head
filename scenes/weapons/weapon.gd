class_name Weapon
extends Node2D

signal attack_finished
signal reload_finished

@export var weapon_name: String = "Weapon"
@export var damage: int = 1
@export var attack_cooldown: float = 0.5

## True: segurar o botão de ataque continua disparando (respeitando o cooldown).
## False: exige um clique por tiro (semiautomático).
@export var is_automatic: bool = false
## Ângulo total (em graus) de espalhamento dos projéteis. 0 = tiros perfeitamente
## retos. O desvio angular de cada projétil fica dentro de [-spread/2, +spread/2].
@export var spread_degrees: float = 0.0
## Quantidade de projéteis disparados por tiro (1 = comportamento padrão).
## A munição consumida é 1 por disparo, não uma por projétil.
@export var pellet_count: int = 1

## Capacidade do carregador (definida pela arma concreta).
@export var magazine_size: int = 6
## Munição atual dentro do carregador.
@export var current_ammo: int = 6
## Tempo configurável de recarga. A finalização visual está sincronizada
## com a animação reload_<direção> (não é usado um Timer separado).
@export var reload_time: float = 1.25

## Posicao da empunhadura da arma em relacao ao Player (preenchido pelo Player).
@export var grip_offset := Vector2.ZERO

## Posicao da empunhadura por direcao (up, down, left, right).
## A origem da Weapon representa o ponto onde a mao do personagem segura a arma.
@export var grip_offsets := {}

## Correcao visual do AnimatedSprite2D por direcao.
## O centro do sprite NAO e a origem da Weapon; este offset desloca o sprite
## para que o ponto real da empunhadura no desenho coincida com a origem.
@export var sprite_offsets := {}

## Correcao visual por estado + direcao (ex.: "shoot_down").
## Usado quando os sprites de ataque tem dimensoes diferentes dos de movimento.
@export var sprite_offsets_by_state := {}

## Posição da boca do cano (MuzzlePoint) por direção, em coordenadas locais.
@export var muzzle_offsets := {}

## Cenas reutilizáveis para o projétil e o clarão de boca.
@export var bullet_scene: PackedScene
@export var muzzle_flash_scene: PackedScene

## Textura do projétil criado por esta arma (Bullet não tem textura fixa).
@export var projectile_texture: Texture2D
## Alcance máximo do projétil desta arma (px). Pertence à arma, não ao Bullet.
@export var projectile_max_distance: float = 1400.0

@onready var animated_sprite: AnimatedSprite2D = $Sprite2D
@onready var muzzle_point: Marker2D = $MuzzlePoint

var is_attacking: bool = false
var is_reloading: bool = false
var current_direction := "right"

# Marca de tempo do último disparo (ms) para o cooldown.
var _last_shot_at: int = -1000000

## Camada explícita de renderização para os projéteis e clarões.
##
## A bala e o clarão são instanciados diretamente na cena atual (não dentro do WeaponHolder),
## por isso NÃO dependem do z_index do WeaponHolder (que varia com a direção de mira).
## Ao mirar para cima, o WeaponHolder fica em `z_index = -1` (atrás do corpo) e,
## se o projétil usasse essa mesma camada, ficaria atrás do Ground (que vive em
## z_index 0). Este valor é sempre superior a 0 (Ground) e ao intervalo da
## arma/corpo (-1..1), garantindo que o projétil nunca seja desenhado atrás do
## solo, independente da direção.
const Z_INDEX_PROJECTILE: int = 100


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Garante que a composição visível inicial está sincronizada.
	update_visual(get_direction_from_animation(animated_sprite.animation))
	update_muzzle(current_direction)


## Retorna o offset de empunhadura para uma direcao.
func get_grip_offset(direction: String) -> Vector2:
	if grip_offsets.has(direction):
		return grip_offsets[direction]
	return grip_offset


## Retorna a correcao visual do sprite para (estado, direcao).
func get_sprite_offset(direction: String, state: String = "") -> Vector2:
	if state != "" and sprite_offsets_by_state.has(state + "_" + direction):
		return sprite_offsets_by_state[state + "_" + direction]
	if sprite_offsets.has(direction):
		return sprite_offsets[direction]
	return Vector2.ZERO


## Atualiza a composicao visual do sprite da arma.
## Aplica o deslocamento visual do AnimatedSprite2D dentro da arma.
func update_visual(direction: String, state: String = "") -> void:
	animated_sprite.position = get_sprite_offset(direction, state)


## Atualiza a posição local do MuzzlePoint segundo a direção atual.
func update_muzzle(direction: String) -> void:
	current_direction = direction
	if muzzle_point:
		muzzle_point.position = muzzle_offsets.get(direction, Vector2.ZERO)


func play_movement_animation(state: String, direction: String) -> void:
	if is_attacking or is_reloading:
		return
	update_muzzle(direction)

	var animation_name := state + "_" + direction

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return

	if animated_sprite.sprite_frames.get_frame_count(animation_name) == 0:
		return

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)

	# Sincroniza a correção visual com o estado/direção atual.
	update_visual(direction, state)


func attack(direction: String = "right") -> bool:
	# Não disparar enquanto recarga.
	if is_reloading:
		return false
	# A arma automática pode encadear tiros enquanto o botão estiver pressionado
	# (a cadência é controlada pelo cooldown); a semiautomática bloqueia novo
	# disparo enquanto a animação do tiro estiver em andamento.
	if is_attacking and not is_automatic:
		return false
	# Respetar o cooldown de disparo.
	if Time.get_ticks_msec() - _last_shot_at < int(attack_cooldown * 1000.0):
		return false
	# Sem munição: não dispara, não cria bala nem clarão (só aviso).
	if current_ammo <= 0:
		print(weapon_name + ": sem munição. Pressione R para recarregar.")
		return false

	is_attacking = true
	current_ammo -= 1
	_last_shot_at = Time.get_ticks_msec()
	update_muzzle(direction)

	var animation_name := "shoot_" + direction

	if not animated_sprite.sprite_frames.has_animation(animation_name) \
			or animated_sprite.sprite_frames.get_frame_count(animation_name) == 0:
		spawn_projectile(direction)
		spawn_muzzle_flash(direction)
		finish_attack()
		return true

	# Aplica a correcao visual do tiro antes de tocar a animacao.
	animated_sprite.play(animation_name)
	update_visual(direction, "shoot")

	# A bala e o clarão nascem na boca do cano no início do disparo.
	spawn_projectile(direction)
	spawn_muzzle_flash(direction)
	return true


func finish_attack() -> void:
	if not is_attacking:
		return

	is_attacking = false
	attack_finished.emit()


## Cria os projéteis na posição global do MuzzlePoint, independente do Player.
## Dispara `pellet_count` balas (comportamento padrão = 1), cada uma com seu
## próprio desvio angular dentro de [-spread_degrees/2, +spread_degrees/2].
func spawn_projectile(direction: String) -> void:
	if not bullet_scene or not muzzle_point:
		return

	var scene := get_tree().current_scene
	if not scene:
		return

	# Direção base do disparo (cardinal) antes do espalhamento.
	var base_direction := direction_vector(direction)
	# Cada bala nasce num mesmo ponto; a munição é consumida 1x por disparo em
	# attack(), não uma por pellet.
	var shot_count := maxi(pellet_count, 1)

	for i in shot_count:
		var bullet := bullet_scene.instantiate()
		if not bullet:
			continue

		# Camada fixa, sempre acima do Ground (z=0) e da arma/corpo (-1..1).
		# Não depende da camada do WeaponHolder, que varia com a direção de mira.
		# z_as_relative = false torna o z_index ABSOLUTO: imune a qualquer z_index
		# de ancestral (garante que a bala nunca fique atrás das chunks/ground).
		bullet.z_as_relative = false
		bullet.z_index = Z_INDEX_PROJECTILE

		# Aplica o desvio angular aleatório (em radianos) dentro do spread.
		var shot_direction := base_direction
		if spread_degrees > 0.0:
			var spread_rad := deg_to_rad(spread_degrees) * randf_range(-0.5, 0.5)
			shot_direction = shot_direction.rotated(spread_rad)

		# add_child.call_deferred evita erros se spawn_projectile for chamado em _ready.
		scene.call_deferred("add_child", bullet)
		bullet.position = muzzle_point.global_position
		bullet.call_deferred("setup", muzzle_point.global_position, shot_direction, damage, projectile_texture, projectile_max_distance, _get_owner_body())


## Sobe pela árvore até encontrar o CharacterBody2D que empunha esta arma.
## A bala usa esta exceção para não colidir com o corpo que a disparou (o Player).
func _get_owner_body() -> CharacterBody2D:
	var node := get_parent()
	while node:
		if node is CharacterBody2D:
			return node
		node = node.get_parent()
	return null

func spawn_muzzle_flash(direction: String) -> void:
	if not muzzle_flash_scene or not muzzle_point:
		return

	var flash := muzzle_flash_scene.instantiate()
	if not flash:
		return

	# Camada fixa (a mesma da bala), sempre acima do Ground (z=0) e da arma/corpo,
	# independente da direção de mira — não depende do z_index do WeaponHolder.
	# z_as_relative = false torna o z_index absoluto (imune a ancestrais).
	flash.z_as_relative = false
	flash.z_index = Z_INDEX_PROJECTILE

	var scene := get_tree().current_scene
	if not scene:
		return

	# add_child.call_deferred evita erros se spawn_muzzle_flash for chamado em _ready.
	scene.call_deferred("add_child", flash)
	flash.call_deferred("set_flash_position", muzzle_point.global_position)
	flash.call_deferred("flash", direction)


## Solicita a recarga. A lógica completa pertence à Weapon, não ao Player.
func reload() -> void:
	if is_reloading:
		return
	if is_attacking:
		return
	if current_ammo >= magazine_size:
		return
	start_reload(current_direction)


func start_reload(direction: String) -> void:
	is_reloading = true
	update_muzzle(direction)

	var animation_name := "reload_" + direction
	if not animated_sprite.sprite_frames.has_animation(animation_name) \
			or animated_sprite.sprite_frames.get_frame_count(animation_name) == 0:
		finish_reload()
		return

	animated_sprite.play(animation_name)
	print(weapon_name + ": recarregando...")


## Prepara o carregador e emite o signal de recarga terminada.
func finish_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	current_ammo = magazine_size
	reload_finished.emit()
	print(weapon_name + ": recarregado! Munição: " + str(current_ammo) + "/" + str(magazine_size))
	play_movement_animation("idle", current_direction)


## Devolve o vetor cardinal da direção de disparo.
func direction_vector(direction: String) -> Vector2:
	match direction:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		_:
			return Vector2.RIGHT


func _on_animation_finished() -> void:
	if is_attacking and animated_sprite.animation.begins_with("shoot_"):
		finish_attack()
	elif is_reloading and animated_sprite.animation.begins_with("reload_"):
		finish_reload()


## Extrai a direção (up/down/left/right) do nome de uma animação.
func get_direction_from_animation(animation: String) -> String:
	if animation.ends_with("_up"):
		return "up"
	if animation.ends_with("_down"):
		return "down"
	if animation.ends_with("_left"):
		return "left"
	return "right"