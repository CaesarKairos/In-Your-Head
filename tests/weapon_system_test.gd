extends SceneTree

## Script de validação do sistema de armas.
## Executa verificações de carga e herança para Gun, Pistol e Shotgun.

var _frame_count: int = 0
var _errors: Array[String] = []
var _tested: bool = false


func _process(_delta: float) -> bool:
    # Aguarda alguns frames para que o root esteja pronto.
    _frame_count += 1
    if _frame_count < 3:
        return false
    if _tested:
        return false
    _tested = true
    _run_tests()
    return false


func _check_weapon_load(path: String, label: String) -> void:
    var scene: PackedScene = load(path)
    if scene == null:
        _errors.append("Falha ao carregar " + path)
        return
    var instance: Node = scene.instantiate()
    if instance == null:
        _errors.append("Falha ao instanciar " + path)
        return
    if not instance is Weapon:
        _errors.append(label + " não herda de Weapon")
    if instance.get_node_or_null("Sprite2D") == null:
        _errors.append(label + " não tem Sprite2D")
    if instance.get_node_or_null("MuzzlePoint") == null:
        _errors.append(label + " não tem MuzzlePoint")
    instance.free()


func _run_tests() -> void:
    # 1. Cena base Weapon
    _check_weapon_load("res://scenes/weapons/weapon.tscn", "weapon")
    # 2. Gun
    _check_weapon_load("res://scenes/weapons/gun/gun.tscn", "gun")
    # 3. Pistol
    _check_weapon_load("res://scenes/weapons/pistol/pistol.tscn", "pistol")
    # 4. Shotgun
    _check_weapon_load("res://scenes/weapons/shotgun/shotgun.tscn", "shotgun")

    # 5. Classes e dados por arma (requer estar na árvore para _ready).
    var gun_scene: PackedScene = load("res://scenes/weapons/gun/gun.tscn")
    if gun_scene:
        var gun: Node = gun_scene.instantiate()
        if not gun is Gun:
            _errors.append("gun.tscn não é uma Gun")
        root.add_child(gun)
        if gun.get("weapon_name") != "Gun":
            _errors.append("Gun weapon_name incorreto")
        if gun.get("damage") != 10:
            _errors.append("Gun damage incorreto")
        if gun.get("projectile_max_distance") != 1400.0:
            _errors.append("Gun projectile_max_distance incorreto")
        gun.queue_free()

    var pistol_scene: PackedScene = load("res://scenes/weapons/pistol/pistol.tscn")
    if pistol_scene:
        var pistol: Node = pistol_scene.instantiate()
        if not pistol is Pistol:
            _errors.append("pistol.tscn não é uma Pistol")
        root.add_child(pistol)
        if pistol.get("weapon_name") != "Pistol":
            _errors.append("Pistol weapon_name incorreto")
        if pistol.get("damage") != 6:
            _errors.append("Pistol damage incorreto")
        if pistol.get("projectile_max_distance") != 1100.0:
            _errors.append("Pistol projectile_max_distance incorreto")
        pistol.queue_free()

    var shot_scene: PackedScene = load("res://scenes/weapons/shotgun/shotgun.tscn")
    if shot_scene:
        var shotgun: Node = shot_scene.instantiate()
        if not shotgun is Shotgun:
            _errors.append("shotgun.tscn não é uma Shotgun")
        root.add_child(shotgun)
        if shotgun.get("weapon_name") != "Shotgun":
            _errors.append("Shotgun weapon_name incorreto")
        if shotgun.get("damage") != 14:
            _errors.append("Shotgun damage incorreto")
        if shotgun.get("projectile_max_distance") != 900.0:
            _errors.append("Shotgun projectile_max_distance incorreto")
        shotgun.queue_free()

    # 6. WeaponPickup
    var pickup_scene: PackedScene = load("res://scenes/weapons/weapon_pickup.tscn")
    if pickup_scene == null:
        _errors.append("Falha ao carregar weapon_pickup.tscn")
    else:
        var pickup: Node = pickup_scene.instantiate()
        if pickup == null:
            _errors.append("Falha ao instanciar weapon_pickup.tscn")
        else:
            if not pickup is WeaponPickup:
                _errors.append("weapon_pickup.tscn não é um WeaponPickup")
            if pickup.get_node_or_null("Sprite2D") == null:
                _errors.append("weapon_pickup.tscn não tem Sprite2D")
            if pickup.get_node_or_null("CollisionShape2D") == null:
                _errors.append("weapon_pickup.tscn não tem CollisionShape2D")
            pickup.free()

    # 7. Player e WeaponHolder
    var player_scene: PackedScene = load("res://scenes/characters/player/player.tscn")
    if player_scene == null:
        _errors.append("Falha ao carregar player.tscn")
    else:
        var player: Node = player_scene.instantiate()
        if player == null:
            _errors.append("Falha ao instanciar player.tscn")
        else:
            if player.get_node_or_null("WeaponHolder") == null:
                _errors.append("player.tscn não tem WeaponHolder")
            if player.get_node_or_null("MovimentSprite") == null:
                _errors.append("player.tscn não tem MovimentSprite")
            player.free()

    if _errors.is_empty():
        print("=== TODOS OS TESTES PASSARAM ===")
        quit(0)
    else:
        print("=== ERROS ENCONTRADOS ===")
        for error in _errors:
            print(" - " + error)
        quit(1)
