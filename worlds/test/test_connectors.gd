extends SceneTree

## Teste headless: gera o mundo e verifica que toda emenda entre chunks
## carregadas tem conectores estritamente iguais (ROAD↔ROAD / NONE↔NONE).

var _gen: Node = null
var _done: bool = false


func _initialize() -> void:
	var gen_script: GDScript = load("res://worlds/world_generator.gd")
	var gen: Node = gen_script.new()
	var chunks := Node2D.new()
	chunks.name = "Chunks"
	gen.add_child(chunks)
	root.add_child(gen)  # dispara _ready -> generate_world
	_gen = gen


func _process(_delta: float) -> bool:
	if _done or _gen == null or not _gen.is_node_ready():
		return false
	_done = true
	var gen: Node = _gen
	var loaded: Dictionary = gen.get("_loaded_chunks")
	print("Chunks carregadas: ", loaded.size())

	var errors := 0
	for pos in loaded:
		var chunk: Node = loaded[pos]
		var checks := {
			Vector2i(0, -1): ["north_connector", "south_connector"],
			Vector2i(0, 1): ["south_connector", "north_connector"],
			Vector2i(1, 0): ["east_connector", "west_connector"],
			Vector2i(-1, 0): ["west_connector", "east_connector"],
		}
		for offset in checks:
			var npos: Vector2i = pos + offset
			if not loaded.has(npos):
				continue
			var mine: int = chunk.get(checks[offset][0])
			var theirs: int = loaded[npos].get(checks[offset][1])
			if mine != theirs:
				errors += 1
				print("DESMATCH em %s <-> %s: %s vs %s" % [pos, npos, mine, theirs])

	# Natureza: cada chunk deve ter um container "Nature" com sprites,
	# e todos os props devem estar sobre células de grama lisa (5,0).
	var nature_total := 0
	var chunks_with_nature := 0
	for pos in loaded:
		var chunk_node: Node = loaded[pos]
		var nature_node: Node = chunk_node.get_node_or_null("Nature")
		if nature_node == null:
			print("SEM NATURE em ", pos)
			continue
		var ground: TileMapLayer = chunk_node.get_node("Ground")
		var bg: Vector2i = chunk_node.get("background_atlas_coords")
		var bad := 0
		for prop in nature_node.get_children():
			nature_total += 1
			var cell := Vector2i((prop as Node2D).position / 16.0)
			if ground.get_cell_atlas_coords(cell) != bg:
				bad += 1
		if bad > 0:
			print("PROPS FORA DA GRAMA em ", pos, ": ", bad)
		chunks_with_nature += 1
	print("Natureza: ", nature_total, " props em ", chunks_with_nature, " chunks")

	# Determinismo: segunda geração com a mesma seed deve produzir o mesmo mapa.
	var first_layout := {}
	for pos in loaded:
		first_layout[pos] = loaded[pos].get("chunk_id")
	gen.clear_world()
	gen.generate_world()
	var second_layout := {}
	for pos in loaded:
		second_layout[pos] = loaded[pos].get("chunk_id")
	var deterministic := first_layout == second_layout
	print("Determinístico: ", deterministic)

	if errors == 0 and deterministic and nature_total > 0 and chunks_with_nature == loaded.size():
		print("TESTE OK")
	else:
		print("TESTE FALHOU (erros de emenda: %d, natureza: %d/%d)" % [errors, chunks_with_nature, loaded.size()])
	var success := errors == 0 and deterministic and nature_total > 0 and chunks_with_nature == loaded.size()
	quit(0 if success else 1)
	return true
