class_name Handgun
extends Weapon

@export var fire_rate: float = 0.3


func _ready() -> void:
	super._ready()

	weapon_name = "Handgun"
	damage = 10
	attack_cooldown = fire_rate


func attack(direction: String = "right") -> void:
	super.attack(direction)

	if is_attacking:
		print("Handgun disparou!")
