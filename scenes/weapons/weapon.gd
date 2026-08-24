class_name Weapon
extends Node2D

signal attack_finished
signal reload_finished

@export var weapon_name: String = "Weapon"
@export var damage: int = 1
@export var attack_cooldown: float = 0.5

## Capacidad del cargador (lo define el arma concreta).
@export var magazine_size: int = 6
## Municion actual dentro del cargador.
@export var current_ammo: int = 6
## Tiempo configurable de recarga. La finalizacion visual esta sincronizada
## con la animacion reload_<direccion> (no se usa un Timer aparte).
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

## Posicion de la boca del cano (MuzzlePoint) por direccion, en coords locales.
@export var muzzle_offsets := {}

## Escenas reutilizables para el proyectil y el destello de bocanada.
@export var bullet_scene: PackedScene
@export var muzzle_flash_scene: PackedScene

## Textura do proxectil creado por esta arma (Bullet non ten textura fixa).
@export var projectile_texture: Texture2D
## Alcance máximo do proxectil desta arma (px). Pertence á arma, non ao Bullet.
@export var projectile_max_distance: float = 1400.0

@onready var animated_sprite: AnimatedSprite2D = $Sprite2D
@onready var muzzle_point: Marker2D = $MuzzlePoint

var is_attacking: bool = false
var is_reloading: bool = false
var current_direction := "right"

# Marca de tiempo del ultimo disparo (ms) para el cooldown.
var _last_shot_at: int = -1000000


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Garante que a composicao visible inicial esta sincronizada.
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


## Actualiza la posicion local del MuzzlePoint segun la direccion actual.
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

	# Sincroniza a correcao visual com o estado/direcao atual.
	update_visual(direction, state)


func attack(direction: String = "right") -> bool:
	# Não disparar enquanto recarga.
	if is_reloading:
		return false
	# Não iniciar dois disparos ao mesmo tempo.
	if is_attacking:
		return false
	# Respetar o cooldown de disparo.
	if Time.get_ticks_msec() - _last_shot_at < int(attack_cooldown * 1000.0):
		return false
	# Sino municion: nao dispara, nao cria bala nem destello (so aviso).
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

	# A bala e o destello nacen na boca do cano ao inicio do disparo.
	spawn_projectile(direction)
	spawn_muzzle_flash(direction)
	return true


func finish_attack() -> void:
	if not is_attacking:
		return

	is_attacking = false
	attack_finished.emit()


## Crea a bala na posicion global do MuzzlePoint, independente do Player.
func spawn_projectile(direction: String) -> void:
	if not bullet_scene or not muzzle_point:
		return

	var bullet := bullet_scene.instantiate()
	if not bullet:
		return

	# Debuxase na mesma capa que a arma (detrás do corpo ao mirar cara arriba).
	bullet.z_index = _get_weapon_z_index()

	var scene := get_tree().current_scene
	if not scene:
		return

	# add_child.call_deferred evita erros se spawn_projectile for chamado em _ready.
	scene.call_deferred("add_child", bullet)
	bullet.position = muzzle_point.global_position
	bullet.call_deferred("setup", muzzle_point.global_position, direction_vector(direction), damage, projectile_texture, projectile_max_distance, _get_owner_body())


## Sube pola árbore até atopar o CharacterBody2D que empuña esta arma.
## A bala usa esta excepción para non colidir co corpo que a disparou (o Player).
func _get_owner_body() -> CharacterBody2D:
	var node := get_parent()
	while node:
		if node is CharacterBody2D:
			return node
		node = node.get_parent()
	return null

## Índice de orde de debuxo (z_index) da arma portadora actual.
## O muzzle flash e mais a bala deben debuxarse na mesma capa que a arma:
## ao mirar cara arriba a arma queda detrás do corpo, oracle que o flash tamén.
func _get_weapon_z_index() -> int:
	var holder := get_parent()
	if holder:
		return holder.z_index
	return 1

func spawn_muzzle_flash(direction: String) -> void:
	if not muzzle_flash_scene or not muzzle_point:
		return

	var flash := muzzle_flash_scene.instantiate()
	if not flash:
		return

	# O flash debe debuxarse na mesma capa que a da arma (atrás ao mirar arriba).
	flash.z_index = _get_weapon_z_index()

	var scene := get_tree().current_scene
	if not scene:
		return

	# add_child.call_deferred evita erros se spawn_muzzle_flash for chamado em _ready.
	scene.call_deferred("add_child", flash)
	flash.call_deferred("set_flash_position", muzzle_point.global_position)
	flash.call_deferred("flash", direction)


## Solicita a recarga. A lojica completa pertence a la Weapon, non ao Player.
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


## Prepara o cargador e emite o signal de recarga terminada.
func finish_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	current_ammo = magazine_size
	reload_finished.emit()
	print(weapon_name + ": recarregado! Munição: " + str(current_ammo) + "/" + str(magazine_size))
	play_movement_animation("idle", current_direction)


## Devolve o vector cardinal da direccion de disparo.
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


## Extrai a direcao (up/down/left/right) do nome de uma animacao.
func get_direction_from_animation(animation: String) -> String:
	if animation.ends_with("_up"):
		return "up"
	if animation.ends_with("_down"):
		return "down"
	if animation.ends_with("_left"):
		return "left"
	return "right"