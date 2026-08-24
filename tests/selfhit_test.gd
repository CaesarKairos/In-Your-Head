extends Node2D

## Teste: a bala e o muzzle flash não devem impactar o Player que a disparou
## e, ao mirar para cima, são desenhados na mesma camada (z_index) que a arma
## (atrás do corpo). Recria Player > WeaponHolder > Weapon.

var _failures: Array[String] = []
var _player: CharacterBody2D
var _holder: Node2D


func _ready() -> void:
    _player = CharacterBody2D.new()
    _player.name = "PlayerTest"
    _player.position = Vector2(300, 200)
    add_child(_player)
    var cs := CapsuleShape2D.new()
    cs.radius = 4.0
    cs.height = 14.0
    var csh := CollisionShape2D.new()
    csh.shape = cs
    _player.add_child(csh)
    _holder = Node2D.new()
    _holder.name = "WeaponHolder"
    _player.add_child(_holder)
    await _wait(2)

    var pistol: Node = load("res://scenes/weapons/pistol/pistol.tscn").instantiate()
    _holder.add_child(pistol)
    await _wait(2)

    _holder.z_index = -1
    var fired: bool = pistol.attack("up")
    print("Pistol up fired=" + str(fired))

    var found := false
    for f in 40:
        await _wait(1)
        if _check_spawns():
            found = true
            break
    if not found:
        _failures.append("não foi criada nem bala nem muzzle flash")

    await _wait(20)
    _finish()


func _check_spawns() -> bool:
    var any := false
    for child in get_children():
        if child is MuzzleFlash:
            any = true
            if child.z_index != _holder.z_index:
                _failures.append("muzzle flash z_index distinto da arma")
        if child is Bullet:
            var b := child as Bullet
            any = true
            var shooter: Node = b.get("_shooter")
            if shooter != _player:
                _failures.append("a bala não registrou o shooter correto")
            if b.z_index != _holder.z_index:
                _failures.append("bala z_index distinto da arma")
    return any


func _wait(n: int) -> void:
    for i in n:
        await get_tree().physics_frame


func _finish() -> void:
    if _failures.is_empty():
        print("=== SELF-HIT/ZINDEX TEST OK: bala e flash na capa da arma (detrás) ===")
    else:
        print("=== SELF-HIT TEST ERROS ===")
        for er in _failures:
            print(" - " + er)
    get_tree().quit(1 if _failures.size() > 0 else 0)

