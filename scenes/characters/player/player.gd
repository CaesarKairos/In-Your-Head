extends CharacterBody2D

@export var walk_speed: float = 60.0
@export var sprint_speed: float = 100.0

@onready var animated_sprite: AnimatedSprite2D = $MovimentSprite

var last_direction := Vector2.DOWN
var is_attacking := false


func _physics_process(_delta: float) -> void:
	# Ataque
	if Input.is_action_just_pressed("attack") and not is_attacking:
		start_attack()
		return

	# Não permite movimento durante o ataque
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Movimento
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	var is_sprinting := Input.is_action_pressed("sprint")
	var current_speed := sprint_speed if is_sprinting else walk_speed

	velocity = input_direction * current_speed

	if input_direction != Vector2.ZERO:
		last_direction = get_facing_direction(input_direction)
		update_animation(true)
	else:
		update_animation(false)

	move_and_slide()


func start_attack() -> void:
	is_attacking = true
	velocity = Vector2.ZERO

	var direction_name := get_direction_name(last_direction)
	var animation_name := "punch_" + direction_name

	animated_sprite.play(animation_name)


func _on_moviment_sprite_animation_finished() -> void:
	if not is_attacking:
		return

	# Só considera animações de punch
	if not animated_sprite.animation.begins_with("punch_"):
		return

	is_attacking = false
	update_animation(false)


func get_facing_direction(direction: Vector2) -> Vector2:
	# Mantém apenas 4 direções para a animação.
	# O movimento continua podendo ser diagonal.
	if abs(direction.x) > abs(direction.y):
		return Vector2.LEFT if direction.x < 0.0 else Vector2.RIGHT

	return Vector2.UP if direction.y < 0.0 else Vector2.DOWN


func update_animation(is_moving: bool) -> void:
	if is_attacking:
		return

	var direction_name := get_direction_name(last_direction)
	var state := "run" if is_moving else "idle"

	var animation_name := state + "_" + direction_name

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)


func get_direction_name(direction: Vector2) -> String:
	if direction == Vector2.UP:
		return "up"

	if direction == Vector2.DOWN:
		return "down"

	if direction == Vector2.LEFT:
		return "left"

	return "right"