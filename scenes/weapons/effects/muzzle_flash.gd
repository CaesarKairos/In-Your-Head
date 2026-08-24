class_name MuzzleFlash
extends Node2D

## Efeito de fogo de boca (muzzle flash) reutilizável.
## É instanciado na cena (na posição da boca do cano), toca uma
## animação e se libera sozinho ao terminar.

@onready var fire_sprite: AnimatedSprite2D = $AnimatedSprite2D


## Define a posição local (a cena raiz de disparo costuma estar na origem).
func set_flash_position(pos: Vector2) -> void:
	position = pos


## Toca a animação de clarão correspondente à direção cardinal.
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