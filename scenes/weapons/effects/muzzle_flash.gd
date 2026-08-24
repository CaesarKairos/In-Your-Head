class_name MuzzleFlash
extends Node2D

## Efecto fuego de boca (muzzle flash) reutilizable.
## Se instancia en la scene (a la posicion de la boca del cano), toca una
## animacion y se libera a si mismo al terminar.

@onready var fire_sprite: AnimatedSprite2D = $AnimatedSprite2D


## Fija la posicion local (la escena raiz de disparo suele estar en el origen).
func set_flash_position(pos: Vector2) -> void:
	position = pos


## Toca a animacion de destello correspondente á dirección cardinal.
func flash(direction: String) -> void:
	fire_sprite.visible = true
	if fire_sprite.sprite_frames.has_animation(direction):
		fire_sprite.play(direction)
	else:
		var names := fire_sprite.sprite_frames.get_animation_names()
		if names.size() > 0:
			fire_sprite.play(names[0])
	fire_sprite.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	queue_free()