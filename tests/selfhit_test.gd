extends Node2D

## Teste do z-index dos projéteis e da auto-colisão.
##
## Verifica o comportamento desejado:
##   1. O projétil é criado.
##   2. O shooter (dono do disparo) continua sendo o Player correto.
##   3. O projétil NUNCA fica abaixo do Ground (z=0), nem mesmo ao mirar
##      para cima (caso que antes o colocava em z=-1, atrás do solo). Deve usar
##      a camada explícita de projétil (Weapon.Z_INDEX_PROJECTILE).
##   4. O muzzle flash também usa a camada fixa Z_INDEX_PROJECTILE (sempre acima
##      do Ground), independentemente da direção de mira.
##   5. Testa as quatro direções (up/down/left/right), com ênfase em "up".

var _failures: Array[String] = []
var _player: CharacterBody2D
var _holder: Node2D
var _ground: Node2D
var _pistol: Node

## Deve coincidir com Weapon.Z_INDEX_PROJECTILE (camada fixa do projétil e do flash).
const Z_INDEX_PROJECTILE: int = 100
const DIRECTIONS: Array[String] = ["up", "down", "left", "right"]


func _ready() -> void:
	_player = CharacterBody2D.new()
	_player.name = "PlayerTest"
	# Mesmas camadas do Player real (layer 2 = player, mask 1 = world),
	# para que a bala (layer 3, mask 1) nunca colida com ele.
	_player.collision_layer = 2
	_player.collision_mask = 1
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
	# Ground simulado com z_index 0 (como o TileMapLayer do mundo). Referência
	# de "solo" para comprovar que o projétil sempre é desenhado acima.
	_ground = Node2D.new()
	_ground.name = "Ground"
	_ground.z_index = 0
	add_child(_ground)
	await _wait(2)

	_pistol = load("res://scenes/weapons/pistol/pistol.tscn").instantiate()
	if _pistol == null:
		_failures.append("pistol não carregou")
		_finish()
		return
	_holder.add_child(_pistol)
	await _wait(2)

	for direction in DIRECTIONS:
		# Reproduz a lógica de Player.update_weapon_holder(): cima -> -1, resto -> 1.
		_holder.z_index = -1 if direction == "up" else 1
		_verify_projectile(direction)
		_verify_muzzle_flash(direction)

	await _wait(10)
	_finish()


func _verify_projectile(direction: String) -> void:
	_pistol.call("spawn_projectile", direction)
	var found := false
	for f in 20:
		await _wait(1)
		for child in get_children():
			if child is Bullet:
				var b := child as Bullet
				found = true
				# 2) Shooter correto (o Player que disparou).
				var shooter: Node = b.get("_shooter")
				if shooter != _player:
					_failures.append(
						"para " + direction + ": a bala não registrou o shooter correto"
					)
				# 3) Nunca abaixo do Ground (z=0).
				if b.z_index < _ground.z_index:
					_failures.append(
						"para " + direction
						+ ": a bala ficou abaixo do Ground (z=" + str(b.z_index) + ")"
					)
				elif b.z_index < 1:
					_failures.append(
						"para " + direction
						+ ": a bala ficou na mesma camada do Ground; deveria estar acima"
					)
				# 5) Usa a camada explícita de projétil, independente da arma.
				if b.z_index != Z_INDEX_PROJECTILE:
					_failures.append(
						"para " + direction
						+ ": a bala não usa a camada explícita de projétil (z="
						+ str(b.z_index) + ")"
					)
				child.free()
				break
		if found:
			break
	if not found:
		_failures.append("para " + direction + ": a bala não foi criada")
	# Limpa qualquer spawn residual deste disparo.
	for child in get_children():
		if child is Bullet:
			child.free()


func _verify_muzzle_flash(direction: String) -> void:
	# O flash usa a capa fixa Z_INDEX_PROJECTILE (a mesma da bala), sempre acima do
	# Ground, independente da direção de mira.
	var expected_z: int = Z_INDEX_PROJECTILE
	_pistol.call("spawn_muzzle_flash", direction)
	var found := false
	for f in 20:
		await _wait(1)
		for child in get_children():
			if child is MuzzleFlash:
				found = true
				# 4) O muzzle flash conserva a capa fixa do projetil.
				if child.z_index != expected_z:
					_failures.append(
						"para " + direction
						+ ": muzzle flash com z_index diferente da camada fixa (flash="
						+ str(child.z_index) + ", esperado=" + str(expected_z) + ")"
					)
				child.free()
				break
		if found:
			break
	if not found:
		_failures.append("para " + direction + ": o muzzle flash não foi criado")
	for child in get_children():
		if child is MuzzleFlash:
			child.free()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	if _failures.is_empty():
		print("=== SELF-HIT TEST OK: projétil e muzzle flash sempre acima do Ground ===")
	else:
		print("=== SELF-HIT TEST ERROS ===")
		for er in _failures:
			print(" - " + er)
	get_tree().quit(1 if _failures.size() > 0 else 0)