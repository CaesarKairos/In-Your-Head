extends Node2D

## Teste del z-index de los proyectiles y de la auto-colisión.
##
## Verifica el comportamiento deseado:
##   1. El proyectil es creado.
##   2. El shooter (dueño del disparo) sigue siendo el Player correcto.
##   3. El proyectil NUNCA queda por debajo del Ground (z=0), ni siquiera al mirar
##      hacia arriba (caso que antes lo ponía en z=-1, detrás del suelo). Debe usar
##      la capa explícita de proyectil (Weapon.Z_INDEX_PROJECTILE).
##   4. El muzzle flash también usa la capa fija Z_INDEX_PROJECTILE (siempre encima
##      del Ground), independientemente de la dirección de mira.
##   5. Prueba las cuatro direcciones (up/down/left/right), con énfasis en "up".

var _failures: Array[String] = []
var _player: CharacterBody2D
var _holder: Node2D
var _ground: Node2D
var _pistol: Node

## Debe coincidir con Weapon.Z_INDEX_PROJECTILE (capa fija del proyectil y del flash).
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
	# Ground simulado con z_index 0 (como el TileMapLayer del mundo). Referencia
	# de "suelo" para comprobar que el proyectil siempre se dibuja encima.
	_ground = Node2D.new()
	_ground.name = "Ground"
	_ground.z_index = 0
	add_child(_ground)
	await _wait(2)

	_pistol = load("res://scenes/weapons/pistol/pistol.tscn").instantiate()
	if _pistol == null:
		_failures.append("pistol no cargó")
		_finish()
		return
	_holder.add_child(_pistol)
	await _wait(2)

	for direction in DIRECTIONS:
		# Reproduce la lógica de Player.update_weapon_holder(): arriba -> -1, resto -> 1.
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
				# 2) Shooter correcto (el Player que disparó).
				var shooter: Node = b.get("_shooter")
				if shooter != _player:
					_failures.append(
						"hacia " + direction + ": la bala no registró al shooter correcto"
					)
				# 3) Nunca por debajo del Ground (z=0).
				if b.z_index < _ground.z_index:
					_failures.append(
						"hacia " + direction
						+ ": la bala quedó por debajo del Ground (z=" + str(b.z_index) + ")"
					)
				elif b.z_index < 1:
					_failures.append(
						"hacia " + direction
						+ ": la bala quedó en la misma capa del Ground; debería estar encima"
					)
				# 5) Usa la capa explícita de proyectil, independiente del arma.
				if b.z_index != Z_INDEX_PROJECTILE:
					_failures.append(
						"hacia " + direction
						+ ": la bala no usa la capa explícita de proyectil (z="
						+ str(b.z_index) + ")"
					)
				child.free()
				break
		if found:
			break
	if not found:
		_failures.append("hacia " + direction + ": la bala no fue creada")
	# Limpia cualquier spawn residual de este disparo.
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
						"hacia " + direction
						+ ": muzzle flash z_index distinto da capa fixa (flash="
						+ str(child.z_index) + ", esperado=" + str(expected_z) + ")"
					)
				child.free()
				break
		if found:
			break
	if not found:
		_failures.append("hacia " + direction + ": el muzzle flash no fue creado")
	for child in get_children():
		if child is MuzzleFlash:
			child.free()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	if _failures.is_empty():
		print("=== SELF-HIT TEST OK: proyectil y muzzle flash siempre encima del Ground ===")
	else:
		print("=== SELF-HIT TEST ERRORES ===")
		for er in _failures:
			print(" - " + er)
	get_tree().quit(1 if _failures.size() > 0 else 0)