class_name Handgun
extends Weapon

@export var fire_rate: float = 0.3


func _ready() -> void:
	weapon_name = "Handgun"
	damage = 10
	attack_cooldown = fire_rate


func attack() -> void:
	super.attack()
	print("Handgun disparou!")
