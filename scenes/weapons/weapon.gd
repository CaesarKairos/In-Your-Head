class_name Weapon
extends Node2D

@export var weapon_name: String = "Weapon"
@export var damage: int = 1
@export var attack_cooldown: float = 0.5


func attack() -> void:
	print("%s atacou com dano %d" % [weapon_name, damage])