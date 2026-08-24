class_name Gun
extends Weapon

@export var fire_rate: float = 0.3

func _ready() -> void:
    super._ready()

    weapon_name = "Gun"
    damage = 10
    magazine_size = 6
    current_ammo = magazine_size
    attack_cooldown = fire_rate
    reload_time = 1.25

    # Cenas reutilizáveis de projétil e clarão de boca.
    bullet_scene = load("res://scenes/weapons/projectiles/bullet.tscn") as PackedScene
    muzzle_flash_scene = load("res://scenes/weapons/effects/muzzle_flash.tscn") as PackedScene

    # Projétil (textura) e alcance máximo desta arma.
    projectile_texture = load("res://assets/characters/player/Guns/Bullets/Gun-bullet_Bullet.png") as Texture2D
    projectile_max_distance = 1400.0

    # SISTEMA DE ENCAIXE E OFFSETS (calibrado para a arte Gun desta arma).
    grip_offset = Vector2(0, 4)
    grip_offsets = {
        "down": Vector2(0, 4),
        "up": Vector2(0, 4),
        "left": Vector2(-2, 3),
        "right": Vector2(2, 3),
    }

    sprite_offsets = {
        "down": Vector2(0, 4),
        "up": Vector2(0, -4),
        "left": Vector2(0, 0),
        "right": Vector2(0, 0),
    }

    sprite_offsets_by_state = {
        "shoot_down": Vector2(0, 4),
        "shoot_up": Vector2(0, -5.5),
        "shoot_left": Vector2(0, 0),
        "shoot_right": Vector2(0, 0),
    }

    # Boca do cano por direção. Nos laterais corrige-se o ~1-2 px abaixo
    # (y=-2 empurra para cima).
    muzzle_offsets = {
        "down": Vector2(0, 12),
        "up": Vector2(0, -14),
        "left": Vector2(-9, -2),
        "right": Vector2(8, -2),
    }

    # Sincroniza a composição visual inicial.
    update_visual(get_direction_from_animation(animated_sprite.animation))
    update_muzzle(current_direction)

func attack(direction: String = "right") -> bool:
    var fired := super.attack(direction)
    if fired:
        print("Gun disparou!")
    return fired
