extends Node2D

## Gera um mundo procedural de streaming infinito de Chunks.
##
## A Chunk inicial (crossroads_01) ocupa sempre a célula lógica (0,0) e sua
## posição mundial é definida por `start_position`. Daí, geram-se novas
## Chunks ao redor do Player conforme ele avança, descarregando-se as que
## ficam fora de um raio configurável (unload_radius_chunks) para não crescer em
## memória de forma infinita. Com o mesmo `world_seed`, uma mesma coordenada
## sempre produz a mesma Chunk (determinismo por world_seed + posição).

const ChunkScript: GDScript = preload("res://worlds/chunks/chunk.gd")

## Dimensões de uma Chunk — compartilhadas com chunk.gd.
const CHUNK_TILES: int = 33
const TILE_SIZE: int = 16
const CHUNK_SIZE: int = CHUNK_TILES * TILE_SIZE

## Pasta onde vivem as cenas de Chunk (escaneadas automaticamente).
const CHUNKS_DIRECTORY: String = "res://worlds/chunks/"
## Cena base/template. Nunca vira uma Chunk aleatória só por estar na pasta.
const BASE_CHUNK_SCENE: String = "res://worlds/chunks/chunk.tscn"

## Distância em px entre as origens de duas Chunks adjacentes.
## É a ÚNICA forma de converter uma coordenada de grid em posição de mundo.
const GRID_SPACING: int = CHUNK_SIZE

enum Direction {
	NORTH,
	EAST,
	SOUTH,
	WEST
}

const ALL_DIRECTIONS: Array[int] = [Direction.NORTH, Direction.EAST, Direction.SOUTH, Direction.WEST]

@export_category("Generación")

## Chunk obrigatória na célula (0,0). Nunca é escolhida como aleatória.
@export var start_chunk_scene: PackedScene = preload("res://worlds/chunks/crossroads_01.tscn")

## Posição mundial da origem (0,0) da grade.
@export var start_position: Vector2 = Vector2.ZERO

## Pool manual opcional. É somado ao escaneamento automático de res://worlds/chunks/.
@export var chunk_pool: Array[PackedScene] = []

## Cenas que nunca são escolhidas na geração (base, inicial, ou qualquer outra).
@export var excluded_chunks: Array[PackedScene] = []

## Raio de carga (em Chunks, distância de Chebyshev). Células dentro deste raio
## ao redor do Player ficam carregadas. Valores maiores = mais Chunks visíveis,
## reforçando a sensação de mundo "infinito".
@export var load_radius_chunks: int = 6

## Raio de descarga: células além desta distância são liberadas da memória.
@export var unload_radius_chunks: int = 8

## Semente determinística do mundo. Mesmo valor -> mesmas Chunks nas mesmas células.
@export var world_seed: int = 1337

## Se for verdadeiro, gera o mundo em _ready.
@export var regenerate_on_ready: bool = true

## Referência opcional ao Player a seguir. Se for null, procura o primeiro
## CharacterBody2D da cena (usado no test/mundo).
@export var player_to_follow: Node = null

## Nome (caminho de nó, ex.: "../Player") opcional do Player a seguir.
@export var player_follow_path: String = ""

## Contêiner das Chunks instanciadas.
@onready var chunks: Node2D = $Chunks

# Estado de stream.
var _loaded_chunks: Dictionary = {}         # key: Vector2i (célula) -> Node2D (instância)
var _player_last_cell: Vector2i = Vector2i(0, -1000000)  # sentinela impossível
var _chunk_meta_cache: Dictionary = {}      # path -> Dictionary (conectores)
var _generatable_cache: Array[PackedScene] = []
var _generatable_cache_dirty: bool = true
var _player_cached: Node2D = null


func _ready() -> void:
	_generatable_cache_dirty = true
	if regenerate_on_ready:
		generate_world()


## Atualiza o streaming apenas quando o Player muda de célula.
func _physics_process(_delta: float) -> void:
	if not regenerate_on_ready:
		return
	var player := _get_player()
	if player == null:
		return
	var cell := _world_to_grid(player.global_position)
	if cell == _player_last_cell:
		return
	_player_last_cell = cell
	_stream_cells_around(cell)


## Limpa todas as Chunks e o estado interno.
func clear_world() -> void:
	if is_node_ready() and chunks:
		for child in chunks.get_children():
			chunks.remove_child(child)
			child.free()
	_loaded_chunks.clear()
	_player_last_cell = Vector2i(0, -1000000)
	_generatable_cache_dirty = true


## Gera (ou regenera) o mundo ao redor do Player ou do centro.
func generate_world() -> void:
	clear_world()
	if start_chunk_scene == null:
		push_error("[WorldGenerator] start_chunk_scene es nulo.")
		return

	var available := _get_generatable_chunks()
	if available.is_empty():
		push_warning(
			"[WorldGenerator] No hay cenas generables (revisa res://worlds/chunks/, chunk_pool y excluded_chunks)."
		)

	var player := _get_player()
	var center := (_world_to_grid(player.global_position) if player else Vector2i.ZERO)
	_player_last_cell = center
	_stream_cells_around(center)
## --- Streaming: carga/descarga ao redor de uma célula ---

func _stream_cells_around(player_cell: Vector2i) -> void:
	# 1) Descarrega as células fora do raio de descarga.
	var to_unload: Array[Vector2i] = []
	for key in _loaded_chunks:
		if _chebyshev(key, player_cell) > unload_radius_chunks:
			to_unload.append(key)
	for pos in to_unload:
		_unload_chunk(pos)

	# 2) Carrega todas as células dentro do raio de carga.
	for dy in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			var cell: Vector2i = player_cell + Vector2i(dx, dy)
			if not _loaded_chunks.has(cell):
				_load_chunk_at(cell)


func _load_chunk_at(grid_pos: Vector2i) -> void:
	if _loaded_chunks.has(grid_pos):
		return

	var scene := _choose_chunk_for_position(grid_pos)
	if scene == null:
		return

	var world_pos := _grid_to_world(grid_pos)
	var inst := _spawn_chunk(scene, world_pos)
	if inst == null:
		return

	chunks.add_child(inst)
	_loaded_chunks[grid_pos] = inst
	print(
		"[WorldGenerator] Chunk grid %s -> %s"
		% [grid_pos, scene.resource_path.get_file().get_basename()]
	)


func _unload_chunk(grid_pos: Vector2i) -> void:
	var inst: Node2D = _loaded_chunks.get(grid_pos, null)
	if inst != null and is_instance_valid(inst):
		chunks.remove_child(inst)
		inst.free()
	_loaded_chunks.erase(grid_pos)


## --- Seleção: inicial, determinismo e compatibilidade ---

func _choose_chunk_for_position(grid_pos: Vector2i) -> PackedScene:
	# A célula (0,0) sempre é a Chunk inicial definida.
	if grid_pos == Vector2i.ZERO and start_chunk_scene:
		return start_chunk_scene

	var valid := _get_valid_chunks_for_position(grid_pos)
	if valid.is_empty():
		_warn_no_valid_chunk(grid_pos)
		return null

	# Determinismo: mesma semente + mesma célula -> mesma candidata.
	var idx := _hash_cell(grid_pos) % valid.size()
	return valid[idx]


## Retorna apenas as cenas compatíveis com TODAS as vizinhas existentes.
func _get_valid_chunks_for_position(grid_pos: Vector2i) -> Array[PackedScene]:
	var valid: Array[PackedScene] = []
	for scene in _get_generatable_chunks():
		if _is_scene_compatible_with_neighbors(scene, grid_pos):
			valid.append(scene)
	return valid


## Verifica a compatibilidade com TODAS as vizinhas já carregadas (norte, sul, leste, oeste).
func _is_scene_compatible_with_neighbors(scene: PackedScene, grid_pos: Vector2i) -> bool:
	var meta := _get_chunk_meta(scene)
	if meta.is_empty():
		return false

	for direction in ALL_DIRECTIONS:
		var neighbor_pos: Vector2i = grid_pos + _grid_offset(direction)
		if not _loaded_chunks.has(neighbor_pos):
			continue
		var neighbor: Node2D = _loaded_chunks[neighbor_pos]

		var candidate_side: int
		var neighbor_side: int
		match direction:
			Direction.NORTH:
				candidate_side = meta["north"]
				neighbor_side = neighbor.get("south_connector")
			Direction.EAST:
				candidate_side = meta["east"]
				neighbor_side = neighbor.get("west_connector")
			Direction.SOUTH:
				candidate_side = meta["south"]
				neighbor_side = neighbor.get("north_connector")
			Direction.WEST:
				candidate_side = meta["west"]
				neighbor_side = neighbor.get("east_connector")

		if not _connector_compatible(candidate_side, neighbor_side):
			return false
	return true


## NONE = ausência de requisito (comportamento existente). Um conector não-NONE por
## parte da vizinha exige que a candidata ofereça o mesmo valor nesse lado.
func _connector_compatible(candidate_side: int, neighbor_side: int) -> bool:
	if neighbor_side == ChunkScript.ConnectorType.NONE:
		return true
	return candidate_side == neighbor_side


func _hash_cell(grid_pos: Vector2i) -> int:
	var h: int = world_seed
	h = h * 73856093 ^ (grid_pos.x * 19349663)
	h = h * 83492791 ^ (grid_pos.y * 63593373)
	return absi(h)


func _warn_no_valid_chunk(grid_pos: Vector2i) -> void:
	var base := "[WorldGenerator] Ninguna chunk compatible para %s" % grid_pos
	print(base)
	push_warning(base)
	for direction in ALL_DIRECTIONS:
		var neighbor_pos: Vector2i = grid_pos + _grid_offset(direction)
		if not _loaded_chunks.has(neighbor_pos):
			continue
		var neighbor: Node2D = _loaded_chunks[neighbor_pos]
		var value: int
		match direction:
			Direction.NORTH:
				value = neighbor.get("south_connector")
			Direction.EAST:
				value = neighbor.get("west_connector")
			Direction.SOUTH:
				value = neighbor.get("north_connector")
			Direction.WEST:
				value = neighbor.get("east_connector")
		print(
			"[WorldGenerator]   (vecino %s) exige conector %s"
			% [neighbor_pos, _connector_name(value)]
		)


func _connector_name(value: int) -> String:
	if value >= 0 and value < ChunkScript.ConnectorType.size():
		return ChunkScript.ConnectorType.keys()[value]
	return "?"
## --- Conjunto de Chunks disponibles (pool) ---

func _get_generatable_chunks() -> Array[PackedScene]:
	if not _generatable_cache_dirty:
		return _generatable_cache
	_generatable_cache = _build_candidate_chunks()
	_generatable_cache_dirty = false
	if _generatable_cache.is_empty():
		push_warning("[WorldGenerator] No hay cenas de chunk generable disponible.")
	return _generatable_cache


func _build_candidate_chunks() -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	var seen := {}
	for scene in _discover_chunk_scenes():
		if _scene_is_allowed(scene) and not seen.has(scene.resource_path):
			result.append(scene)
			seen[scene.resource_path] = true
	# Adiciona também o pool manual opcional (sem duplicados).
	for scene in chunk_pool:
		if scene == null:
			continue
		if _scene_is_allowed(scene) and not seen.has(scene.resource_path):
			result.append(scene)
			seen[scene.resource_path] = true
	return result


## Escaneia automaticamente a pasta res://worlds/chunks/.
func _discover_chunk_scenes() -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	var dir := DirAccess.open(CHUNKS_DIRECTORY)
	if dir == null:
		push_warning("[WorldGenerator] No fue posible abrir %s" % CHUNKS_DIRECTORY)
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tscn"):
			var scene: PackedScene = load(CHUNKS_DIRECTORY + entry)
			if scene:
				result.append(scene)
		entry = dir.get_next()
	dir.list_dir_end()
	return result


## Uma cena NÃO é gerável se for a base (template) ou estiver em excluded_chunks.
## A cena inicial (start_chunk_scene) NÃO é excluída: quando ela é a única chunk do
## jogo, precisa poder se repetir como vizinha de si mesma (ex.: crossroads_01).
func _scene_is_allowed(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var path: String = scene.resource_path
	if path == BASE_CHUNK_SCENE:
		return false
	for exc in excluded_chunks:
		if exc != null and exc.resource_path == path:
			return false
	return true


## Lê (e cacheia) os conectores de uma cena de Chunk sem colocá-la no mundo.
func _get_chunk_meta(scene: PackedScene) -> Dictionary:
	var path: String = scene.resource_path
	if _chunk_meta_cache.has(path):
		return _chunk_meta_cache[path]

	var meta := {}
	var root := scene.instantiate()
	if root != null:
		meta["north"] = int(root.get("north_connector"))
		meta["south"] = int(root.get("south_connector"))
		meta["east"] = int(root.get("east_connector"))
		meta["west"] = int(root.get("west_connector"))
		root.free()
	_chunk_meta_cache[path] = meta
	return meta
## --- Instanciação e posicionamento ---

func _spawn_chunk(scene: PackedScene, world_pos: Vector2) -> Node2D:
	var chunk := scene.instantiate() as Node2D
	if chunk == null:
		push_error("[WorldGenerator] Fallo al instanciar cena de Chunk.")
		return null
	chunk.position = world_pos
	# Identidade: usa o nome da cena como chunk_id (facilita depuração e registros).
	chunk.set("chunk_id", scene.resource_path.get_file().get_basename())
	return chunk


## Única função para converter coordenada de grid em posição mundial.
## Células vizinhas ficam exatamente a uma distância de GRID_SPACING (528 px).
func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	return start_position + Vector2(grid_pos) * GRID_SPACING


## Única função para converter uma posição mundial em célula de grid.
func _world_to_grid(world_pos: Vector2) -> Vector2i:
	var rel := world_pos - start_position
	return Vector2i(
		floori(rel.x / float(GRID_SPACING)),
		floori(rel.y / float(GRID_SPACING))
	)


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(absi(a.x - b.x), absi(a.y - b.y))


## --- Helpers ---

func _grid_offset(direction: int) -> Vector2i:
	match direction:
		Direction.NORTH:
			return Vector2i(0, -1)
		Direction.EAST:
			return Vector2i(1, 0)
		Direction.SOUTH:
			return Vector2i(0, 1)
		Direction.WEST:
			return Vector2i(-1, 0)
		_:
			return Vector2i.ZERO


func _get_player() -> Node2D:
	if _player_cached != null and is_instance_valid(_player_cached):
		return _player_cached
	if player_to_follow != null and is_instance_valid(player_to_follow):
		_player_cached = player_to_follow as Node2D
		return _player_cached
	if player_follow_path != "":
		var np: Node = get_node(player_follow_path)
		if np is Node2D:
			_player_cached = np as Node2D
			return _player_cached
	# Busca o primeiro CharacterBody2D da cena (fallback).
	var scene: Node = get_tree().current_scene
	if scene:
		var stack: Array[Node] = [scene]
		while stack.size() > 0:
			var node: Node = stack.pop_back()
			if node is CharacterBody2D:
				_player_cached = node as CharacterBody2D
				return _player_cached
			for c in node.get_children():
				stack.append(c)
	return null
