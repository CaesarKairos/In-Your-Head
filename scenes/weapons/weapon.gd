class_name Weapon
extends Node2D

signal attack_finished

@export var weapon_name: String = "Weapon"
@export var damage: int = 1
@export var attack_cooldown: float = 0.5

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

@onready var animated_sprite: AnimatedSprite2D = $Sprite2D

var is_attacking: bool = false


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Garante que a composicao visual inicial esta sincronizada.
	update_visual(get_direction_from_animation(animated_sprite.animation))


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


func play_movement_animation(state: String, direction: String) -> void:
	if is_attacking:
		return

	var animation_name := state + "_" + direction

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return

	if animated_sprite.sprite_frames.get_frame_count(animation_name) == 0:
		return

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)

	# Sincroniza a correcao visual com o estado/direcao atual.
	update_visual(direction, state)


func attack(direction: String = "right") -> void:
	is_attacking = true

	var animation_name := "shoot_" + direction

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		finish_attack()
		return

	if animated_sprite.sprite_frames.get_frame_count(animation_name) == 0:
		finish_attack()
		return

	# Aplica a correcao visual do tiro antes de tocar a animacao.
	animated_sprite.play(animation_name)
	update_visual(direction, "shoot")


func finish_attack() -> void:
	if not is_attacking:
		return

	is_attacking = false
	attack_finished.emit()


func _on_animation_finished() -> void:
	if not is_attacking:
		return

	if animated_sprite.animation.begins_with("shoot_"):
		finish_attack()


## Extrai a direcao (up/down/left/right) do nome de uma animacao.
func get_direction_from_animation(animation: String) -> String:
	if animation.ends_with("_up"):
		return "up"
	if animation.ends_with("_down"):
		return "down"
	if animation.ends_with("_left"):
		return "left"
	return "right"