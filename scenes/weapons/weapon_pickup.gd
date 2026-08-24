class_name WeaponPickup
extends Area2D

@export var weapon_scene: PackedScene
@export var display_name: String = "Arma"

var player_in_range: Node = null


func _ready() -> void:
	update_pickup_visual()


func update_pickup_visual() -> void:
	if not weapon_scene:
		return

	var weapon_instance := weapon_scene.instantiate()
	var weapon_sprite := weapon_instance.get_node_or_null("Sprite2D") as AnimatedSprite2D
	var pickup_sprite := $Sprite2D as AnimatedSprite2D

	if weapon_sprite and pickup_sprite:
		if weapon_sprite.sprite_frames:
			pickup_sprite.sprite_frames = weapon_sprite.sprite_frames

		if pickup_sprite.sprite_frames.has_animation("idle_down"):
			pickup_sprite.play("idle_down")

	weapon_instance.queue_free()


func create_weapon() -> Weapon:
	if not weapon_scene:
		push_warning("WeaponPickup sem weapon_scene definida.")
		return null

	return weapon_scene.instantiate() as Weapon


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return

	if not player_in_range:
		return

	if not player_in_range.has_method("equip_weapon"):
		return

	var weapon := create_weapon()

	if not weapon:
		return

	player_in_range.equip_weapon(weapon)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("equip_weapon"):
		player_in_range = body


func _on_body_exited(body: Node2D) -> void:
	if body == player_in_range:
		player_in_range = null