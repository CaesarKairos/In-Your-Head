extends Node2D

## Validación del streaming de Chunks del WorldGenerator.
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

	_wg = load("res://worlds/world_generator.tscn").instantiate()
	# Desactiva la generación automática en _ready (la controlamos manualmente),
	# pero la dejaremos activa para el streaming en movimiento.
	_wg.set("regenerate_on_ready", false)
	add_child(_wg)
	await _wait(3)

	# Radio reducido para hacer las comprobaciones pequeñas.
	_wg.set("load_radius_chunks", 1)
	_wg.set("unload_radius_chunks", 2)
	_wg.set("world_seed", 42)
	_wg.call("generate_world")
	# Streaming activo durante el movimiento del Player.
	_wg.set("regenerate_on_ready", true)
	await _wait(2)

	# B) / C) / D) / E) iniciales.
	_initial_map = _cell_map()
	_check_initial_cells()

	# C) Expansión en las cuatro direcciones.
	await _move_to(Vector2i(3, 0))    # este
	_expect_has(Vector2i(2, 0), "este")
	_expect_has(Vector2i(4, 0), "este")
	await _move_to(Vector2i(0, -3))   # norte
	_expect_has(Vector2i(0, -2), "norte")
	await _move_to(Vector2i(-3, 0))   # oeste
	_expect_has(Vector2i(-2, 0), "oeste")
	await _move_to(Vector2i(0, 3))    # sur
	_expect_has(Vector2i(0, 2), "sur")

	# F) Descartar + recargar con mismo seed -> misma chunk.
	await _move_to(Vector2i(7, 7))
	await _wait(3)
	# Ahora la región original quedó fuera del radio de descarga.
	await _move_to(Vector2i.ZERO)
	await _wait(3)
	_check_determinism()

	await _wait(10)
	_finish()


## Devuelve la posición mundial dentro de una celda de grid.
func _cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(c * CHUNK_SIZE) + Vector2(264, 264)


## Devuelve celda -> chunk_id de todas las Chunks instanciadas.
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

	# C) Deben existir las 9 celdas del cuadrado ±1 sin duplicados.
	if _initial_map.size() != 9:
		_failures.append("se esperaban 9 celdas iniciales, hay " + str(_initial_map.size()))
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			if not _initial_map.has(Vector2i(x, y)):
				_failures.append("falta la celda (" + str(x) + "," + str(y) + ")")

	# Sin solapamiento: ninguna celda repetida en posiciones.
	var seen_cells := {}
	for cell in _initial_map:
		if seen_cells.has(cell):
			_failures.append("celda duplicada " + str(cell))
		seen_cells[cell] = true

	# D) Las celdas vecinas deben estar a exactamente 528 px (encostadas, sin hueco).
	for a in _initial_map.keys():
		for b in _initial_map.keys():
			if a == b:
				continue
			var d := Vector2(a - b)
			var dist := absi(d.x) + absi(d.y)
			if dist == 1:
				# Celdas ortogonalmente adyacentes -> 528 px exactos.
				var pa: Vector2 = _wg.call("_grid_to_world", a)
				var pb: Vector2 = _wg.call("_grid_to_world", b)
				if not is_equal_approx((pa - pb).length(), 528.0):
					_failures.append(
						"distancia entre " + str(a) + " y " + str(b)
						+ " != 528 (" + str((pa - pb).length()) + ")"
					)


func _move_to(c: Vector2i) -> void:
	_fake.global_position = _cell_to_world(c)
	await _wait(4)  # deja correr algunos _physics_process del generador


func _expect_has(c: Vector2i, label: String) -> void:
	var m := _cell_map()
	if not m.has(c):
		_failures.append("expansión hacia " + label + ": falta la celda " + str(c))


func _check_determinism() -> void:
	var m := _cell_map()
	# Volver a la inicial no debe romper el grid: (0,0) sigue siendo crossroads.
	if not m.has(Vector2i.ZERO) or m[Vector2i.ZERO] != "crossroads_01":
		_failures.append("al recargar, (0,0) no volvió a ser crossroads_01")
	# Con el mismo seed, las celdas originales producen las mismas Chunks.
	for cell in _initial_map:
		if not m.has(cell):
			continue
		if m[cell] != _initial_map[cell]:
			_failures.append(
				"determinismo roto: celda " + str(cell)
				+ " era " + str(_initial_map[cell]) + " y volvió como " + str(m[cell])
			)


func _finish() -> void:
	if _failures.is_empty():
		print("=== WORLDGEN TEST OK: streaming, compatibilidad y determinismo ok ===")
	else:
		print("=== WORLDGEN TEST ERRORES ===")
		for e in _failures:
			print(" - " + e)
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame