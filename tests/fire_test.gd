extends Node2D

## Test determinista do sistema de armas.
## 1) Cada arma exporta a súa propia textura de proxectil e alcance.
## 2) Bullet.setup() aplica textura, dano e alcance que recibe da Weapon.

var _failures: Array[String] = []


func _ready() -> void:
    _check_weapon_now("res://scenes/weapons/gun/gun.tscn", "Gun", "res://assets/characters/player/Guns/Bullets/Gun-bullet_Bullet.png", 1400.0, 10)
    _check_weapon_now("res://scenes/weapons/pistol/pistol.tscn", "Pistol", "res://assets/characters/player/Guns/Bullets/Pistol-bullet_Bullet.png", 1100.0, 6)
    _check_weapon_now("res://scenes/weapons/shotgun/shotgun.tscn", "Shotgun", "res://assets/characters/player/Guns/Bullets/Shotgun-bullet.png", 900.0, 14)
    _check_bullet_setup()
    await get_tree().create_timer(0.1).timeout
    _finish()


func _check_weapon_now(path: String, nm: String, tex_path: String, dist: float, dmg: int) -> void:
    var scene: PackedScene = load(path)
    if scene == null:
        _failures.append(nm + " non cargou")
        return
    var w: Node = scene.instantiate()
    add_child(w)
    await get_tree().process_frame
    var tex: Texture2D = w.get("projectile_texture")
    var rp: String = tex.resource_path if tex else "NULL"
    if rp != tex_path:
        _failures.append(nm + ": projectile_texture incorrecto (" + rp + ")")
    var dist_val: float = w.get("projectile_max_distance")
    if absf(dist_val - dist) > 0.01:
        _failures.append(nm + ": projectile_max_distance incorrecto (" + str(dist_val) + ")")
    var dmg_val: int = w.get("damage")
    if dmg_val != dmg:
        _failures.append(nm + ": damage incorrecto (" + str(dmg_val) + ")")
    w.free()


func _check_bullet_setup() -> void:
    var scene: PackedScene = load("res://scenes/weapons/projectiles/bullet.tscn")
    if scene == null:
        _failures.append("non se puido cargar bullet.tscn")
        return
    var b: Bullet = scene.instantiate()
    add_child(b)
    await get_tree().process_frame
    var tex: Texture2D = load("res://assets/characters/player/Guns/Bullets/Pistol-bullet_Bullet.png")
    b.setup(Vector2.ZERO, Vector2.RIGHT, 7, tex, 1234.5)
    await get_tree().process_frame
    if absf(b.max_distance - 1234.5) > 0.01:
        _failures.append("Bullet.max_distance non aplicado polo setup")
    if b.damage != 7:
        _failures.append("Bullet.damage non aplicado polo setup")
    var sprite: Sprite2D = null
    for cc in b.get_children():
        if cc is Sprite2D:
            sprite = cc as Sprite2D
    if sprite and sprite.texture:
        if sprite.texture.resource_path != "res://assets/characters/player/Guns/Bullets/Pistol-bullet_Bullet.png":
            _failures.append("Bullet.texture non aplicado polo setup")
    else:
        _failures.append("Bullet sen sprite ou textura tras setup")
    b.free()


func _finish() -> void:
    if _failures.is_empty():
        print("=== FIRE/CONFIG TEST OK ===")
    else:
        print("=== TEST ERROS ===")
        for f in _failures:
            print(" - " + f)
    get_tree().quit(1 if _failures.size() > 0 else 0)

