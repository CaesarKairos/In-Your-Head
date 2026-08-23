extends SceneTree

## Script de validação do sistema de armas.
## Executa verificações básicas de carregamento e herança.

var _frame_count: int = 0
var _errors: Array[String] = []
var _tested: bool = false


func _process(_delta: float) -> bool:
	# Aguarda alguns frames para garantir que o root está pronto
	_frame_count += 1
	if _frame_count < 3:
		return false

	if _tested:
		return false

	_tested = true
	_run_tests()
	return false


func _run_tests() -> void:
	# 1. Verifica se a cena base Weapon carrega
	var weapon_scene: PackedScene = load("res://scenes/weapons/weapon.tscn")
	if weapon_scene == null:
		_errors.append("Falha ao carregar weapon.tscn")
	else:
		var weapon: Node = weapon_scene.instantiate()
		if weapon == null:
			_errors.append("Falha ao instanciar weapon.tscn")
		else:
			if not weapon is Weapon:
				_errors.append("weapon.tscn não é uma Weapon")
			if weapon.get_node_or_null("Sprite2D") == null:
				_errors.append("weapon.tscn não possui Sprite2D")
			if weapon.get_node_or_null("AttackPoint") == null:
				_errors.append("weapon.tscn não possui AttackPoint")
			weapon.free()

	# 2. Verifica se a Handgun carrega e herda de Weapon
	var handgun_scene: PackedScene = load("res://scenes/weapons/handgun/handgun.tscn")
	if handgun_scene == null:
		_errors.append("Falha ao carregar handgun.tscn")
	else:
		var handgun: Node = handgun_scene.instantiate()
		if handgun == null:
			_errors.append("Falha ao instanciar handgun.tscn")
		else:
			if not handgun is Weapon:
				_errors.append("handgun.tscn não herda de Weapon")
			if not handgun is Handgun:
				_errors.append("handgun.tscn não é uma Handgun")
			if handgun.get_node_or_null("Sprite2D") == null:
				_errors.append("handgun.tscn não possui Sprite2D")
			if handgun.get_node_or_null("AttackPoint") == null:
				_errors.append("handgun.tscn não possui AttackPoint")
			handgun.free()

	# 3. Valida os offsets calibrados da Handgun (nao podem ser alterados por
	#    "simetria" - sao derivados do pixel real de cada textura).
	var handgun_offsets: Node = null
	if handgun_scene == null:
		_errors.append("Falha ao carregar handgun.tscn (necessario para validar offsets)")
	else:
		handgun_offsets = handgun_scene.instantiate()
		# _ready() so roda apos entrar na arvore; os offsets sao populados nele.
		root.add_child(handgun_offsets)
	if handgun_offsets:
		# grip_offsets: validados contra a posicao real da mao no corpo.
		var expected_grip := {
			"down": Vector2(0, 4),
			"up": Vector2(0, 4),
			"left": Vector2(-2, 3),
			"right": Vector2(2, 3),
		}
		for dir_name in expected_grip:
			if handgun_offsets.get_grip_offset(dir_name) != expected_grip[dir_name]:
				_errors.append("grip_offset de '%s' divergiu (esperado %s)" % [dir_name, expected_grip[dir_name]])

		# sprite_offsets derivados das texturas (tools/analyze_hand_regions.py):
		# DOWN mão (pele) em linhas 4..9 -> +4.0; UP mãos em dois blocos -> -4.0.
		var expected_sprite := {
			"down": Vector2(0, 4),
			"up": Vector2(0, -4),
			"left": Vector2(0, 0),
			"right": Vector2(0, 0),
		}
		for dir_name in expected_sprite:
			if handgun_offsets.sprite_offsets[dir_name] != expected_sprite[dir_name]:
				_errors.append("sprite_offsets[%s] != %s" % [dir_name, expected_sprite[dir_name]])

		# sprite_offsets_by_state: frames de tiro NAO crescem simetricamente.
		# shoot_up precisa de -5.5 pois o recoil desce o conteudo no frame 0
		# e o usuario confirmou que -4.5 ainda mostrava a arma entre as pernas.
		var expected_state := {
			"shoot_down": Vector2(0, 4),
			"shoot_up": Vector2(0, -5.5),
			"shoot_left": Vector2(0, 0),
			"shoot_right": Vector2(0, 0),
		}
		for key in expected_state:
			if handgun_offsets.sprite_offsets_by_state[key] != expected_state[key]:
				_errors.append("sprite_offsets_by_state[%s] != %s" % [key, expected_state[key]])
		handgun_offsets.free()

	# 4. Verifica se o WeaponPickup carrega
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
				_errors.append("weapon_pickup.tscn não possui Sprite2D")
			if pickup.get_node_or_null("CollisionShape2D") == null:
				_errors.append("weapon_pickup.tscn não possui CollisionShape2D")
			pickup.free()

	# 4. Verifica se o Player carrega com o WeaponHolder
	var player_scene: PackedScene = load("res://scenes/characters/player/player.tscn")
	if player_scene == null:
		_errors.append("Falha ao carregar player.tscn")
	else:
		var player: Node = player_scene.instantiate()
		if player == null:
			_errors.append("Falha ao instanciar player.tscn")
		else:
			if player.get_node_or_null("WeaponHolder") == null:
				_errors.append("player.tscn não possui WeaponHolder")
			if player.get_node_or_null("MovimentSprite") == null:
				_errors.append("player.tscn não possui MovimentSprite")
			player.free()

	# 5. Verifica se o WeaponHolder está acessível via get_node
	var player_scene2: PackedScene = load("res://scenes/characters/player/player.tscn")
	if player_scene2:
		var player: Node = player_scene2.instantiate()
		root.add_child(player)
		var weapon_holder: Node = player.get_node_or_null("WeaponHolder")
		if weapon_holder == null:
			_errors.append("WeaponHolder não acessível via get_node")
		player.queue_free()

	if _errors.is_empty():
		print("=== TODOS OS TESTES PASSARAM ===")
		quit(0)
	else:
		print("=== ERROS ENCONTRADOS ===")
		for error in _errors:
			print(" - " + error)
		quit(1)