extends CharacterBody2D

const MOVE_ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down"]

@export var walk_speed: float = 60.0
@export var sprint_speed: float = 100.0

# Tempo máximo entre dois toques para ativar a corrida.
@export var double_tap_time: float = 0.25

@onready var animated_sprite: AnimatedSprite2D = $MovimentSprite
@onready var no_hands_sprite: AnimatedSprite2D = $MovimentSpriteNoHands
@onready var weapon_holder: Node2D = $WeaponHolder

var last_direction := Vector2.DOWN
var is_attacking := false
var equipped_weapon: Weapon = null

# Controle do duplo toque
var last_move_action: String = ""
var last_move_time: float = -1.0
var double_tap_sprint_action: String = ""


func _ready() -> void:
	# Inicializa a visibilidade dos sprites
	update_sprite_visibility()
	update_animation(false)


func _physics_process(_delta: float) -> void:
	# Recarga (a lógica pertence à Weapon).
	if Input.is_action_just_pressed("reload") and equipped_weapon:
		equipped_weapon.reload()

	# Ataque: armas automáticas usam "is_action_pressed" (segurar dispara em
	# rajada, respeitando o cooldown); semiautomáticas exigem um clique por tiro.
	var wants_to_attack := (
		Input.is_action_pressed("attack")
		if equipped_weapon and equipped_weapon.is_automatic
		else Input.is_action_just_pressed("attack")
	)

	if wants_to_attack:
		start_attack()

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

	# Se a tecla do duplo toque foi solta, cancela a corrida por duplo toque
	if double_tap_sprint_action != "":
		if not Input.is_action_pressed(double_tap_sprint_action):
			double_tap_sprint_action = ""

	var is_sprinting := (
		Input.is_action_pressed("sprint")
		or double_tap_sprint_action != ""
	)

	velocity = calculate_movement_velocity(input_direction, is_sprinting)

	if input_direction != Vector2.ZERO:
		# Mantém corpo, empunhadura e cano alinhados durante a recarga.
		if not equipped_weapon or not equipped_weapon.is_reloading:
			last_direction = get_facing_direction(input_direction)
		update_animation(true)
	else:
		update_animation(false)

	move_and_slide()


func calculate_movement_velocity(input_direction: Vector2, sprinting: bool) -> Vector2:
	# Input.get_vector já limita a magnitude, preservando também entrada analógica.
	return input_direction * (sprint_speed if sprinting else walk_speed)


func _input(event: InputEvent) -> void:
	# Eventos contam cada toque uma vez, mesmo durante ataque/recarga.
	for action in MOVE_ACTIONS:
		if event.is_action_released(action):
			if double_tap_sprint_action == action:
				double_tap_sprint_action = ""
		elif event.is_action_pressed(action) and not event.is_echo():
			for other in MOVE_ACTIONS:
				if other != action and Input.is_action_pressed(other):
					# Uma combinação diagonal não é um novo duplo toque.
					last_move_action = ""
					return
			var current_time := Time.get_ticks_msec() / 1000.0
			if action == last_move_action and current_time - last_move_time <= double_tap_time:
				double_tap_sprint_action = action
			last_move_action = action
			last_move_time = current_time


func start_attack() -> void:
	var direction_name := get_direction_name(last_direction)

	# Arma equipada: o ataque é realizado pela Weapon. is_attacking só é ativado
	# se o disparo começou de verdade (evita bloqueios com recarga/sem munição).
	if equipped_weapon:
		if equipped_weapon.attack(direction_name):
			update_animation(false)
			# Sem frames de tiro, a arma pode terminar sincronamente.
			is_attacking = equipped_weapon.is_attacking
			velocity = Vector2.ZERO
		return

	# Sem arma: usa punch
	if is_attacking:
		return
	is_attacking = true
	velocity = Vector2.ZERO
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
	is_attacking = false
	update_animation(false)


func get_facing_direction(direction: Vector2) -> Vector2:
	if abs(direction.x) > abs(direction.y):
		return Vector2.LEFT if direction.x < 0.0 else Vector2.RIGHT

	return Vector2.UP if direction.y < 0.0 else Vector2.DOWN


func update_animation(is_moving: bool) -> void:
	if is_attacking:
		return

	var direction_name := get_direction_name(last_direction)
	var state := "run" if is_moving else "idle"

	# Se tiver arma, usar NoHands para o personagem e anima a arma
	if equipped_weapon:
		var no_hands_animation := state + "_" + direction_name
		if no_hands_sprite.sprite_frames.has_animation(no_hands_animation):
			if no_hands_sprite.animation != no_hands_animation or not no_hands_sprite.is_playing():
				no_hands_sprite.play(no_hands_animation)

		equipped_weapon.play_movement_animation(state, direction_name)
		update_weapon_holder()
		return

	# Sem arma: usa MovimentSprite normal
	var animation_name := state + "_" + direction_name

	if animated_sprite.animation != animation_name or not animated_sprite.is_playing():
		animated_sprite.play(animation_name)


func get_direction_name(direction: Vector2) -> String:
	if direction == Vector2.UP:
		return "up"

	if direction == Vector2.DOWN:
		return "down"

	if direction == Vector2.LEFT:
		return "left"

	return "right"


## Ajusta a ordem local e a posição da empunhadura.
## A posição do Weapon representa o ponto de empunhadura (mão).
## O sprite offset é aplicado internamente pela própria Weapon.
func update_weapon_holder() -> void:
	if not equipped_weapon:
		return

	var direction_name := get_direction_name(last_direction)

	# Mesma camada do corpo/props: apenas a ordem interna muda.
	# Assim a arma participa da composição do Player no Y-sort do mundo.
	var holder_index := 0 if direction_name == "up" else get_child_count() - 1
	if weapon_holder.get_index() != holder_index:
		move_child(weapon_holder, holder_index)

	# Sprites e holder ordenam nos pés (y=7), sem mudar a composição visual.
	# grip_offsets continuam relativos à origem lógica do Player.
	equipped_weapon.position = equipped_weapon.get_grip_offset(direction_name) - weapon_holder.position


# --- Sistema de armas ---

## Atualiza a visibilidade dos sprites com base na arma equipada.
func update_sprite_visibility() -> void:
	var has_weapon: bool = equipped_weapon != null

	animated_sprite.visible = not has_weapon
	no_hands_sprite.visible = has_weapon
	weapon_holder.visible = has_weapon


## Equipa uma arma e a coloca no WeaponHolder.
func equip_weapon(weapon: Weapon) -> void:
	if weapon == null or weapon == equipped_weapon:
		return
	unequip_weapon()

	equipped_weapon = weapon
	weapon_holder.add_child(weapon)
	weapon.position = Vector2.ZERO

	if not weapon.attack_finished.is_connected(_on_weapon_attack_finished):
		weapon.attack_finished.connect(_on_weapon_attack_finished)

	update_sprite_visibility()
	update_weapon_holder()
	update_animation(false)


## Remove a arma equipada do WeaponHolder.
func unequip_weapon() -> void:
	is_attacking = false
	if equipped_weapon:
		if equipped_weapon.attack_finished.is_connected(_on_weapon_attack_finished):
			equipped_weapon.attack_finished.disconnect(_on_weapon_attack_finished)

		weapon_holder.remove_child(equipped_weapon)
		equipped_weapon.queue_free()
		equipped_weapon = null

	update_sprite_visibility()
	update_animation(false)
