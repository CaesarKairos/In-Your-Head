class_name Weapon
extends Node2D

signal attack_finished

@export var weapon_name: String = "Weapon"
@export var damage: int = 1
@export var attack_cooldown: float = 0.5

@onready var animated_sprite: AnimatedSprite2D = $Sprite2D

var is_attacking: bool = false


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)


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


func attack(direction: String = "right") -> void:
	is_attacking = true

	var animation_name := "shoot_" + direction

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		finish_attack()
		return

	if animated_sprite.sprite_frames.get_frame_count(animation_name) == 0:
		finish_attack()
		return

	animated_sprite.play(animation_name)


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