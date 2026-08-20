class_name WeaponPickup
extends Area2D

## Referência à cena da arma que este pickup representa.
@export var weapon_scene: PackedScene

## Nome exibido ao interagir (opcional).
@export var display_name: String = "Arma"


func _ready() -> void:
	# Configura o sprite com a textura da arma, se disponível.
	if weapon_scene:
		var weapon_instance: Node = weapon_scene.instantiate()
		var sprite: Sprite2D = weapon_instance.get_node_or_null("Sprite2D")
		if sprite and sprite.texture:
			var pickup_sprite: Sprite2D = $Sprite2D
			pickup_sprite.texture = sprite.texture
			pickup_sprite.region_enabled = sprite.region_enabled
			pickup_sprite.region_rect = sprite.region_rect
		weapon_instance.queue_free()


## Retorna uma nova instância da arma representada por este pickup.
func create_weapon() -> Weapon:
	if not weapon_scene:
		push_warning("WeaponPickup sem weapon_scene definida.")
		return null

	var weapon: Weapon = weapon_scene.instantiate() as Weapon
	return weapon