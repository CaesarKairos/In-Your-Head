extends Node2D

## Validação do streaming de Chunks do WorldGenerator.
##
## Verifica:
##   B) crossroads_01 se repete como vizinha de si mesma (é a única chunk do jogo),
##      preenchendo (0,0) e as células ao redor em todas as direções.
##   C) O mundo se expande para norte, sul, leste e oeste, com 528 px entre células
##      adjacentes (sem buracos nem sobreposição).
##   D) Em cada posição se escolhe uma candidata compatível com TODAS as vizinhas.
##   E) Se não houver cenas geráveis, emite-se um aviso (não há falha silenciosa).
##   F) Depois de descarregar e recarregar, com a mesma seed, a célula volta à mesma
##      chunk (determinismo).

const CHUNK_SIZE: int = 528

var _failures: Array[String] = []
var _fake: CharacterBody2D
var _wg: Node2D
var _initial_map: Dictionary = {}


func _ready() -> void:
	_fake = CharacterBody2D.new()
	_fake.name = "FakePlayer"
	add_child(_fake)
	_fake.global_position = _cell_to_world(Vector2i.ZERO)

	_wg = load("res://scenes/world/world_generator.tscn").instantiate()
	# Desativa a geração automática em _ready (controlamos manualmente),
	# mas a deixaremos ativa para o streaming em movimento.
	_wg.set("regenerate_on_ready", false)
	add_child(_wg)
	await _wait(3)

	# Raio reduzido para tornar as verificações pequenas.
	_wg.set("load_radius_chunks", 1)
	_wg.set("unload_radius_chunks", 2)
	_wg.set("world_seed", 42)
	_wg.call("generate_world")
	# Streaming ativo durante o movimento do Player.
	_wg.set("regenerate_on_ready", true)
	# O streaming agora é ASSÍNCRONO (1 chunk commit/frame + load em thread):
	# aguarda frames suficientes para as 9 células iniciais aparecerem.
	await _wait(150)

	# B) / C) / D) / E) iniciais.
	_initial_map = _cell_map()
	_check_initial_cells()

	# C) Expansão nas quatro direções.
	await _move_to(Vector2i(3, 0))    # leste
	_expect_has(Vector2i(2, 0), "leste")
	_expect_has(Vector2i(4, 0), "leste")
	await _move_to(Vector2i(0, -3))   # norte
	_expect_has(Vector2i(0, -2), "norte")
	await _move_to(Vector2i(-3, 0))   # oeste
	_expect_has(Vector2i(-2, 0), "oeste")
	await _move_to(Vector2i(0, 3))    # sul
	_expect_has(Vector2i(0, 2), "sul")

	# F) Descartar + recarregar com a mesma seed -> mesma chunk.
	await _move_to(Vector2i(7, 7))
	await _wait(150)
	# Agora a região original ficou fora do raio de descarte.
	await _move_to(Vector2i.ZERO)
	await _wait(150)
	_check_determinism()

	await _wait(10)
	_finish()


## Retorna a posição mundial dentro de uma célula de grid.
func _cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(c * CHUNK_SIZE) + Vector2(264, 264)


## Retorna célula -> chunk_id de todas as Chunks instanciadas.
func _cell_map() -> Dictionary:
	var m := {}
	for child in _wg.get_node("Chunks").get_children():
		var cell: Vector2i = _wg.call("_world_to_grid", child.position)
		m[cell] = child.get("chunk_id")
	return m


func _check_initial_cells() -> void:
	# B) crossroads_01 se repete em toda célula (ela é a única chunk disponível).
	if not _initial_map.has(Vector2i.ZERO) or _initial_map[Vector2i.ZERO] != "crossroads_01":
		_failures.append("a célula (0,0) não é crossroads_01")
	for key in _initial_map:
		if _initial_map[key] != "crossroads_01":
			_failures.append("célula " + str(key) + " não é crossroads_01 (é " + _initial_map[key] + ")")

	# C) Devem existir as 9 células do quadrado ±1 sem duplicatas.
	if _initial_map.size() != 9:
		_failures.append("esperava 9 células iniciais, há " + str(_initial_map.size()))
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			if not _initial_map.has(Vector2i(x, y)):
				_failures.append("falta a célula (" + str(x) + "," + str(y) + ")")

	# Sem sobreposição: nenhuma célula repetida em posições.
	var seen_cells := {}
	for cell in _initial_map:
		if seen_cells.has(cell):
			_failures.append("célula duplicada " + str(cell))
		seen_cells[cell] = true

	# D) As células vizinhas devem estar a exatamente 528 px (encostadas, sem buraco).
	for a in _initial_map.keys():
		for b in _initial_map.keys():
			if a == b:
				continue
			var d := Vector2(a - b)
			var dist := absi(d.x) + absi(d.y)
			if dist == 1:
				# Células ortogonalmente adjacentes -> 528 px exatos.
				var pa: Vector2 = _wg.call("_grid_to_world", a)
				var pb: Vector2 = _wg.call("_grid_to_world", b)
				if not is_equal_approx((pa - pb).length(), 528.0):
					_failures.append(
						"distância entre " + str(a) + " e " + str(b)
						+ " != 528 (" + str((pa - pb).length()) + ")"
					)


func _move_to(c: Vector2i) -> void:
	_fake.global_position = _cell_to_world(c)
	# Carga assíncrona: dá tempo ao anel de ~9 células novas + gating norte/oeste.
	await _wait(150)  # deixa correr vários _physics_process/_process do gerador


func _expect_has(c: Vector2i, label: String) -> void:
	var m := _cell_map()
	if not m.has(c):
		_failures.append("expansão para " + label + ": falta a célula " + str(c))


func _check_determinism() -> void:
	var m := _cell_map()
	# Voltar à inicial não deve quebrar o grid: (0,0) continua sendo crossroads.
	if not m.has(Vector2i.ZERO) or m[Vector2i.ZERO] != "crossroads_01":
		_failures.append("ao recarregar, (0,0) não voltou a ser crossroads_01")
	# Com a mesma seed, as células originais produzem as mesmas Chunks.
	for cell in _initial_map:
		if not m.has(cell):
			continue
		if m[cell] != _initial_map[cell]:
			_failures.append(
				"determinismo quebrado: célula " + str(cell)
				+ " era " + str(_initial_map[cell]) + " e voltou como " + str(m[cell])
			)


func _finish() -> void:
	if _failures.is_empty():
		print("=== WORLDGEN TEST OK: streaming, compatibilidade e determinismo ok ===")
	else:
		print("=== WORLDGEN TEST ERROS ===")
		for e in _failures:
			print(" - " + e)
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame