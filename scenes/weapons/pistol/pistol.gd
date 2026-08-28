class_name Pistol
extends Weapon

func _ready() -> void:
    super._ready()

    weapon_name = "Pistol"
    damage = 6
    magazine_size = 12
    current_ammo = magazine_size
    attack_cooldown = 0.15
    reload_time = 1.4

    # Pistol é semiautomática (um clique por tiro) e a mais precisa (menor spread).
    is_automatic = false
    spread_degrees = 2.0
    pellet_count = 1

    bullet_scene = load("res://scenes/weapons/projectiles/bullet.tscn") as PackedScene
    muzzle_flash_scene = load("res://scenes/weapons/effects/muzzle_flash.tscn") as PackedScene

    projectile_texture = load("res://assets/characters/player/Guns/Bullets/Pistol-bullet_Bullet.png") as Texture2D
    projectile_max_distance = 1100.0

    # Empunhadura = mão do personagem (mesma posição que a Gun).
    grip_offset = Vector2(0, 4)
    grip_offsets = {
        "down": Vector2(0, 4),
        "up": Vector2(0, 4),
        "left": Vector2(-2, 3),
        "right": Vector2(2, 3),
    }

    # Encaixe visual estimado da Pistol (arte menor que a Gun); ajustar no editor.
    sprite_offsets = {
        "down": Vector2(0, 2),
        "up": Vector2(0, -2),
        "left": Vector2(0, 0),
        "right": Vector2(0, 0),
    }

    sprite_offsets_by_state = {
        "shoot_down": Vector2(0, 2),
        "shoot_up": Vector2(0, -2),
        "shoot_left": Vector2(0, 0),
        "shoot_right": Vector2(0, 0),
    }

    # Boca do cano estimada da Pistol; ajustar visualmente no editor.
    muzzle_offsets = {
        "down": Vector2(0, 8),
        "up": Vector2(0, -10),
        "left": Vector2(-6, -2),
        "right": Vector2(6, -2),
    }

    update_visual(get_direction_from_animation(animated_sprite.animation))
    update_muzzle(current_direction)
