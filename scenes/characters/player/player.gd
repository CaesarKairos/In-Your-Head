extends CharacterBody2D

@export var walk_speed: float = 60.0
@export var sprint_speed: float = 100.0

@onready var animated_sprite: AnimatedSprite2D = $MovimentSprite
@onready var no_hands_sprite: AnimatedSprite2D = $MovimentSpriteNoHands
@onready var weapon_holder: Node2D = $WeaponHolder

var last_direction := Vector2.DOWN
var is_attacking := false
var equipped_weapon: Weapon = null


func _ready() -> void:
	# Inicializa a visibilidade dos sprites
	update_sprite_visibility()


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

	# Se houver arma equipada, usa o ataque da arma (sem punch)
	if equipped_weapon:
		equipped_weapon.attack(direction_name)
		return

	# Sem arma: usa punch
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


func _on_weapon_attack_finished() -> void:
	# Chamado quando a arma termina a animação de ataque
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

	# Se tiver arma, usa NoHands para o personagem e anima a arma
	if equipped_weapon:
		var no_hands_animation := state + "_" + direction_name
		if no_hands_sprite.sprite_frames.has_animation(no_hands_animation):
			if no_hands_sprite.animation != no_hands_animation:
				no_hands_sprite.play(no_hands_animation)

		equipped_weapon.play_movement_animation(state, direction_name)
		return

	# Sem arma: usa MovimentSprite normal
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


# --- Sistema de armas ---

## Atualiza a visibilidade dos sprites com base na arma equipada.
func update_sprite_visibility() -> void:
	var has_weapon: bool = equipped_weapon != null

	animated_sprite.visible = not has_weapon
	no_hands_sprite.visible = has_weapon


## Equipa uma arma e a coloca no WeaponHolder.
func equip_weapon(weapon: Weapon) -> void:
	# Remove a arma atual, se houver
	unequip_weapon()

	equipped_weapon = weapon
	weapon_holder.add_child(weapon)
	weapon.position = Vector2.ZERO

	# Conecta o signal de ataque finalizado
	if not weapon.attack_finished.is_connected(_on_weapon_attack_finished):
		weapon.attack_finished.connect(_on_weapon_attack_finished)

	update_sprite_visibility()
	update_animation(false)


## Remove a arma equipada do WeaponHolder.
func unequip_weapon() -> void:
	if equipped_weapon:
		if equipped_weapon.attack_finished.is_connected(_on_weapon_attack_finished):
			equipped_weapon.attack_finished.disconnect(_on_weapon_attack_finished)

		weapon_holder.remove_child(equipped_weapon)
		equipped_weapon.queue_free()
		equipped_weapon = null

	update_sprite_visibility()
	update_animation(false)
