class_name Shotgun
extends Weapon

# Shotgun: por enquanto um único projétil para validar a arquitetura.
# Não implementa ainda máquina de recarga por cartuchos nem spread.

func _ready() -> void:
    super._ready()

    weapon_name = "Shotgun"
    damage = 14
    magazine_size = 4
    current_ammo = magazine_size
    attack_cooldown = 1.0
    reload_time = 1.6

    # Shotgun é semiautomática, com disparo em leque (vários pellets, 1 munição
    # por tiro) e o maior espalhamento das três armas.
    is_automatic = false
    spread_degrees = 18.0
    pellet_count = 6

    bullet_scene = load("res://scenes/weapons/projectiles/bullet.tscn") as PackedScene
    muzzle_flash_scene = load("res://scenes/weapons/effects/muzzle_flash.tscn") as PackedScene

    projectile_texture = load("res://assets/characters/player/Guns/Bullets/Shotgun-bullet.png") as Texture2D
    projectile_max_distance = 900.0

    grip_offset = Vector2(0, 4)
    grip_offsets = {
        "down": Vector2(0, 4),
        "up": Vector2(0, 4),
        "left": Vector2(-2, 3),
        "right": Vector2(2, 3),
    }

    sprite_offsets = {
        "down": Vector2(0, 3),
        "up": Vector2(0, -3),
        "left": Vector2(0, 0),
        "right": Vector2(0, 0),
    }

    sprite_offsets_by_state = {
        "shoot_down": Vector2(0, 3),
        "shoot_up": Vector2(0, -3),
        "shoot_left": Vector2(0, 0),
        "shoot_right": Vector2(0, 0),
    }

    muzzle_offsets = {
        "down": Vector2(0, 11),
        "up": Vector2(0, -13),
        "left": Vector2(-10, -2),
        "right": Vector2(10, -2),
    }

    update_visual(get_direction_from_animation(animated_sprite.animation))
    update_muzzle(current_direction)
