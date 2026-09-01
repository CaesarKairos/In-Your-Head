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
const NatureScatter: GDScript = preload("res://worlds/chunks/nature_scatter.gd")

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

## Limite de instâncias ociosas guardadas no pool por tipo de chunk.
const POOL_LIMIT_PER_TYPE: int = 6

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

## Máximo de Chunks instanciadas (commit) por frame. Distribui o custo ao longo
## dos frames e evita travamento. Valor inicial conservador; aumente apenas se o
## carregamento parecer lento sem causar stutter.
@export var max_commits_per_frame: int = 3

## Imprime logs mínimos de streaming: coordenada carregada, descarregada e a
## prioridade da Chunk quando entra na fila. Fica atrás dessa flag para não
## poluir o console por padrão.
@export var debug_stream_logs: bool = false

## Semente determinística do mundo. Mesmo valor -> mesmas Chunks nas mesmas células.
@export var world_seed: int = 1337

## Pesos de sorteio por chunk (chave = nome do arquivo .tscn, valor = peso int).
## Chunks sem entrada usam as regras padrão de DEFAULT_WEIGHT_RULES; peso 1 se
## nenhuma regra casar. Valores maiores = chunk é sorteada mais vezes.
@export var chunk_weights: Dictionary = {}

## Regras padrão de peso por prefixo de nome de chunk (aplicadas na ordem).
## terrain_* é mais comum (terreno de fundo); estradas têm peso menor pra não
## inundar o mundo; cruzamentos são os mais raros.
const DEFAULT_WEIGHT_RULES: Array = [
	["terrain_", 4],
	["road_curve_", 2],
	["road_straight_", 2],
	["road_deadend_", 1],
	["road_t_", 1],
	["crossroads_", 1],
]

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
var _player_move_dir: Vector2i = Vector2i.ZERO            # última direção dominante (para prioridade leve à frente)
var _have_prev_cell: bool = false
var _chunk_meta_cache: Dictionary = {}      # path -> Dictionary (conectores)
var _generatable_cache: Array[PackedScene] = []
var _generatable_cache_dirty: bool = true
var _player_cached: Node2D = null
var _autoload_registered: bool = false

# --- Estado do streaming ASSÍNCRONO / pool (otimização de stutter) ---
var _desired_cells: Dictionary = {}         # cell -> true (dentro do load_radius)
var _pending: Dictionary = {}               # cell -> {path} (load em andamento)
var _prefetch_paths: Dictionary = {}        # path -> true (recursos já pré-buscados)
var _pool: Dictionary = {}                  # path -> Array[Node2D] instâncias ociosas
var _pool_root: Node2D = null


func _ready() -> void:
	_generatable_cache_dirty = true
	# Raiz oculta fora da área visível que guarda instâncias ociosas do pool.
	_pool_root = Node2D.new()
	_pool_root.name = "_Pool"
	_pool_root.visible = false
	add_child(_pool_root)
	_register_with_autoload(_get_player())
	if regenerate_on_ready:
		generate_world()


## Atualiza o streaming apenas quando o Player muda de célula.
## Detecta mudança de célula do Player (gatilho do streaming). O carregamento
## pesado (instanciação) NÃO acontece aqui: apenas detecta a fronteira e dispara
## o prefetch preditivo; o _process() faz o work (load + commit) distribuído ao
## longo dos frames seguintes.
func _physics_process(_delta: float) -> void:
	if not regenerate_on_ready:
		return
	var player := _get_player()
	if player == null:
		return
	_register_with_autoload(player)
	var cell := _world_to_grid(player.global_position)
	if cell == _player_last_cell:
		return
	var prev := _player_last_cell
	_player_last_cell = cell
	if _have_prev_cell:
		# Direção dominante do deslocamento (preferência leve à frente do Player).
		var move := cell - prev
		if absi(move.x) >= absi(move.y):
			_player_move_dir = Vector2i(signi(move.x), 0)
		else:
			_player_move_dir = Vector2i(0, signi(move.y))
	_have_prev_cell = true
	_prefetch_ahead(prev, cell, player)


## Loop por frame: poll dos loads assíncronos + commit de poucas chunks por frame.
func _process(_delta: float) -> void:
	if not regenerate_on_ready:
		return
	_tick_stream(_player_last_cell)


## Limpa todas as Chunks, o pool e os estados internos.
func clear_world() -> void:
	if is_node_ready() and chunks:
		for child in chunks.get_children():
			chunks.remove_child(child)
			child.free()
	if _pool_root != null and is_instance_valid(_pool_root):
		for path in _pool.keys():
			for inst in _pool[path]:
				if is_instance_valid(inst):
					inst.free()
	_pool.clear()
	_pending.clear()
	_desired_cells.clear()
	_loaded_chunks.clear()
	_player_last_cell = Vector2i(0, -1000000)
	_player_move_dir = Vector2i.ZERO
	_have_prev_cell = false
	_generatable_cache_dirty = true


## Gera (ou regenera) o mundo ao redor do Player ou do centro.
## O streaming em si é assíncrono: aqui só preparamos o terreno, pré-buscamos os
## recursos e marcamos para o _process() resolver.
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
	# Pré-busca (prefetch) dos recursos em background: deixa o disco aquecido para
	# que, ao cruzar uma fronteira, load_threaded_get() retorne instantaneamente.
	for scene in available:
		_prefetch(scene.resource_path)

	var player := _get_player()
	var center := (_world_to_grid(player.global_position) if player else Vector2i.ZERO)
	_player_last_cell = center
	_register_with_autoload(player)
	_prefetch_ahead(center, center, player)


## --- Streaming ASSÍNCRONO: previsão, pool, 1 commit/frame ---

## Orquestra o ciclo em cada frame. Usa a célula atual do jogador (que pode ser
## a sentinela inicial até o primeiro cruzamento).
func _tick_stream(player_cell: Vector2i) -> void:
	_update_desired(player_cell)
	_unload_out_of_range(player_cell)
	_request_pending_loads(player_cell)
	_commit_ready(player_cell)


## Conjunto desejado: todas as células dentro do load_radius ao redor do jogador.
func _update_desired(player_cell: Vector2i) -> void:
	_desired_cells.clear()
	for dy in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			_desired_cells[player_cell + Vector2i(dx, dy)] = true


## Move para o pool (em vez de free) as células que saíram do unload_radius.
func _unload_out_of_range(player_cell: Vector2i) -> void:
	var to_unload: Array[Vector2i] = []
	for key in _loaded_chunks:
		if _chebyshev(key, player_cell) > unload_radius_chunks:
			to_unload.append(key)
	for pos in to_unload:
		_unload_chunk(pos)


## Dispara cargas assíncronas (ResourceLoader.load_threaded_request) para as
## células prontas. "Pronta" = norte e oeste já carregados (mesma invariante do
## antigo scan linha-a-coluna), preservando a validação de conectores.
func _request_pending_loads(player_cell: Vector2i) -> void:
	# Célula inicial (0,0): imposta (start_chunk_scene), sem depender de vizinho.
	if _desired_cells.has(Vector2i.ZERO) \
			and not _loaded_chunks.has(Vector2i.ZERO) \
			and not _pending.has(Vector2i.ZERO) \
			and start_chunk_scene != null:
		_request_load(Vector2i.ZERO, start_chunk_scene)

	for dy in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			var cell: Vector2i = player_cell + Vector2i(dx, dy)
			if cell == Vector2i.ZERO:
				continue
			if _loaded_chunks.has(cell) or _pending.has(cell):
				continue
			if not _is_cell_ready(cell):
				continue
			var scene := _choose_chunk_for_position(cell)
			if scene == null:
				continue
			_request_load(cell, scene)


## Uma célula só é elegível para load quando seus vizinhos norte e oeste que
## estejam DENTRO do load_radius já estão carregados (validação de conectores).
func _is_cell_ready(cell: Vector2i) -> bool:
	var north := cell + Vector2i(0, -1)
	var west := cell + Vector2i(-1, 0)
	if _desired_cells.has(north) and not _loaded_chunks.has(north):
		return false
	if _desired_cells.has(west) and not _loaded_chunks.has(west):
		return false
	return true


## Inicia o carregamento de uma célula: apenas registra o path na fila de poll;
## a reutilização de pool e o commit são feitos em _commit_ready (dentro do
## limite de 1 por frame). O resource já é pré-buscado de antemão por _prefetch
## (load_threaded_request); o _commit_ready faz o load_threaded_get correspondente.
func _request_load(cell: Vector2i, scene: PackedScene) -> void:
	var path := scene.resource_path
	if not _prefetch_paths.has(path):
		_prefetch(path)
	_pending[cell] = {"path": path}


## Poll dos carregamentos e commit de POUCAS chunks por frame
## (max_commits_per_frame), distribuindo a instanciação ao longo dos frames.
## Recursos já em cache (a maioria: descobertos em generate_world) entram sem
## espera; os que nunca foram cached dependem do load_threaded_request do prefetch.
func _commit_ready(player_cell: Vector2i) -> void:
	var ready: Array[Vector2i] = []
	for cell in _pending.keys():
		if _is_loaded(_pending[cell]["path"]):
			ready.append(cell)
	if ready.is_empty():
		return
	# Ordem por PRIORIDADE: mais próximo do Player primeiro (distância ao quadrado);
	# desempates por direção de movimento e, por fim, determinístico por linha-coluna.
	ready.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_priority_less(a, b, player_cell))
	var n := mini(maxi(1, max_commits_per_frame), ready.size())
	for i in n:
		var cell := ready[i]
		if debug_stream_logs:
			print(
				"[WorldGenerator] Enfileirada grid %s (prioridade %d)"
				% [cell, _priority_order(cell, player_cell)]
			)
		# Se ficou longe demais enquanto carregava, descarta (não entra no mundo).
		if _chebyshev(cell, player_cell) > unload_radius_chunks:
			_pending.erase(cell)
			continue
		var path: String = _pending[cell]["path"]
		var scene: PackedScene = _get_scene(path)
		_pending.erase(cell)
		if scene == null:
			continue
		# Reutilização de pool dentro do limite por frame (zero instanciação).
		_finalize_chunk(cell, _pop_pool(scene), scene)


## Verdadeiro quando o resource do chunk já está disponível para instanciar:
## já cacheado (caminho normal) OU terminou o load em thread do prefetch.
func _is_loaded(path: String) -> bool:
	if ResourceLoader.has_cached(path):
		return true
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED


## Recupera o PackedScene do chunk: direto do cache (instantâneo, memória) se já
## carregado; senão, via load_threaded_get (troca a thread pelo recurso pronto).
func _get_scene(path: String) -> PackedScene:
	if ResourceLoader.has_cached(path):
		return load(path) as PackedScene
	return ResourceLoader.load_threaded_get(path) as PackedScene


## Conclui a entrada de uma chunk no mundo: posiciona, adiciona à árvore, marca
## como carregada e adia o scatter (setup de nós/corpos físicos) para não travar
## o frame. `reused_inst` é uma instância vinda do pool (zero instanciação).
func _finalize_chunk(cell: Vector2i, reused_inst: Node2D, scene: PackedScene) -> void:
	var world_pos := _grid_to_world(cell)
	var inst := reused_inst
	if inst != null:
		inst.position = world_pos
		inst.visible = true
		chunks.add_child(inst)
	else:
		inst = _spawn_chunk(scene, world_pos)
		if inst == null:
			_pending.erase(cell)
			return
		chunks.add_child(inst)
	_loaded_chunks[cell] = inst
	_pending.erase(cell)
	inst.set_meta("source_path", scene.resource_path)
	# Scatter pesado (dezenas de corpos físicos) vai para o fim da frame.
	call_deferred("_scatter_deferred", inst, cell)
	print(
		"[WorldGenerator] Chunk grid %s -> %s"
		% [cell, scene.resource_path.get_file().get_basename()]
	)


## Povoa a natureza de uma chunk de forma diferida (evita o pico de custo no
## frame da transição). Remove qualquer container "Nature" prévio (reuso do pool).
func _scatter_deferred(chunk: Node2D, cell: Vector2i) -> void:
	if not is_instance_valid(chunk):
		return
	var existing := chunk.get_node_or_null("Nature")
	if existing != null:
		chunk.remove_child(existing)
		existing.free()
	NatureScatter.scatter(chunk, cell, world_seed)


## Descarga: VAI PARA O POOL (quando o tipo tem vaga) em vez de free(), para
## reutilizar a instância se o jogador voltar à célula (evita reinstanciar).
func _unload_chunk(grid_pos: Vector2i) -> void:
	var inst: Node2D = _loaded_chunks.get(grid_pos, null)
	if inst != null and is_instance_valid(inst):
		chunks.remove_child(inst)
		_push_pool(inst)
	_loaded_chunks.erase(grid_pos)
	if debug_stream_logs:
		print("[WorldGenerator] Chunk descarregada grid %s" % grid_pos)


## Guarda a instância no pool (oculta, longe da câmera) ou libera se o tipo
## já atingiu POOL_LIMIT_PER_TYPE.
func _push_pool(inst: Node2D) -> void:
	var path := ""
	if inst.has_meta("source_path"):
		path = str(inst.get_meta("source_path"))
	if path == "":
		inst.free()
		return
	# Remove a vegetação (corpos físicos) antes de ociosar: o pool guarda apenas o
	# TileMap, evitando dezenas de StaticBody2D ativos fora da câmera. Na reutilização
	# o _scatter_deferred recria a natureza.
	var nature := inst.get_node_or_null("Nature")
	if nature != null:
		inst.remove_child(nature)
		nature.free()
	var arr: Array = _pool.get(path, [])
	if arr.size() < POOL_LIMIT_PER_TYPE:
		_pool_root.add_child(inst)
		inst.position = Vector2(1e7, 1e7)
		inst.visible = false
		arr.append(inst)
		_pool[path] = arr
	else:
		inst.free()


## Retira uma instância ociosa do pool para o `scene` (mesma resource_path), se
## houver. Retorna null se o pool está vazio para aquele tipo.
func _pop_pool(scene: PackedScene) -> Node2D:
	var path := scene.resource_path
	var arr: Array = _pool.get(path, [])
	while arr.size() > 0:
		var inst: Node2D = arr.pop_back()
		if is_instance_valid(inst):
			_pool_root.remove_child(inst)
			return inst
	_pool.erase(path)
	return null


## Pré-busca (threaded) do recurso de um .tscn, sem esperar por ele. O guard
## `_prefetch_paths` evita repetir pedidos para recursos já aquecidos/cacheados.
func _prefetch(path: String) -> void:
	if _prefetch_paths.has(path) or ResourceLoader.has_cached(path):
		_prefetch_paths[path] = true
		return
	_prefetch_paths[path] = true
	ResourceLoader.load_threaded_request(path, "", true, ResourceLoader.CACHE_MODE_REUSE)


## Previsão de direção de movimento: pré-busca os recursos das células do anel
## imediatamente além do load_radius na direção do deslocamento. São apenas
## *recursos* aquecidos (nunca commit de células fora do raio), então quando o
## jogador cruzar a fronteira o load_threaded_get() já estará pronto.
func _prefetch_ahead(prev_cell: Vector2i, cell: Vector2i, player: Node2D) -> void:
	var dir := cell - prev_cell
	if dir == Vector2i.ZERO:
		dir = Vector2i(0, 1)
	# Normaliza para uma direção cardinal (caso o movimento seja diagonal).
	if absi(dir.x) >= absi(dir.y):
		dir = Vector2i(signi(dir.x), 0)
	else:
		dir = Vector2i(0, signi(dir.y))
	var look := load_radius_chunks + 1
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if absi(dx) == 1 and absi(dy) == 1:
				continue
			var ahead: Vector2i = cell + dir * look + Vector2i(dx, dy)
			var scene := _choose_chunk_for_position(ahead)
			if scene != null:
				_prefetch(scene.resource_path)


## Registra origem e player no autoload WorldCoordinates (fonte única de verdade).
func _register_with_autoload(player: Node2D) -> void:
	if _autoload_registered:
		return
	# Variant: acesso dinâmico ao autoload (set_origin/register_player).
	var wc: Variant = get_node_or_null("/root/WorldCoordinates")
	if wc == null:
		_autoload_registered = true  # autoload ausente (ex.: rodando isolado)
		return
	if wc.has_method("set_origin"):
		wc.set_origin(start_position)
	if player != null and wc.has_method("register_player"):
		wc.register_player(player)
	_autoload_registered = true


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
	# Sorteio PONDERADO (roleta) com pesos por chunk (_weight_for_scene).
	var total := 0
	var weights: Array[int] = []
	for scene in valid:
		var w := _weight_for_scene(scene)
		weights.append(w)
		total += w
	if total <= 0:
		return valid[_hash_cell(grid_pos) % valid.size()]
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash_cell(grid_pos)
	var roll := rng.randi_range(1, total)
	for i in range(valid.size()):
		roll -= weights[i]
		if roll <= 0:
			return valid[i]
	return valid[valid.size() - 1]


## Peso de sorteio de uma chunk: override explícito em chunk_weights
## (chave = nome do arquivo), senão regra por prefixo, senão 1.
func _weight_for_scene(scene: PackedScene) -> int:
	var file := scene.resource_path.get_file()
	if chunk_weights.has(file):
		return maxi(int(chunk_weights[file]), 1)
	for rule in DEFAULT_WEIGHT_RULES:
		if file.begins_with(rule[0]):
			return maxi(int(rule[1]), 1)
	return 1


## Retorna apenas as cenas compatíveis com TODAS as vizinhas existentes.
## Regra anti-repetição: candidatos "terreno puro" (4 conectores NONE) que
## repetiriam o mesmo chunk_id de um vizinho imediato já carregado são
## descartados — exceto se isso esvaziar a lista (aí mantemos todos).
func _get_valid_chunks_for_position(grid_pos: Vector2i) -> Array[PackedScene]:
	var valid: Array[PackedScene] = []
	for scene in _get_generatable_chunks():
		if _is_scene_compatible_with_neighbors(scene, grid_pos):
			valid.append(scene)

	var non_repeating: Array[PackedScene] = []
	for scene in valid:
		if not _would_repeat_neighbor_terrain(scene, grid_pos):
			non_repeating.append(scene)
	return non_repeating if not non_repeating.is_empty() else valid


## Verdadeiro se `scene` é terreno puro (N/S/E/W = NONE) e tem o mesmo
## chunk_id de alguma vizinha já carregada.
func _would_repeat_neighbor_terrain(scene: PackedScene, grid_pos: Vector2i) -> bool:
	var meta := _get_chunk_meta(scene)
	if int(meta["north"]) != ChunkScript.ConnectorType.NONE \
			or int(meta["south"]) != ChunkScript.ConnectorType.NONE \
			or int(meta["east"]) != ChunkScript.ConnectorType.NONE \
			or int(meta["west"]) != ChunkScript.ConnectorType.NONE:
		return false
	var my_id := scene.resource_path.get_file().get_basename()
	for direction in ALL_DIRECTIONS:
		var neighbor_pos: Vector2i = grid_pos + _grid_offset(direction)
		if not _loaded_chunks.has(neighbor_pos):
			continue
		var neighbor: Node2D = _loaded_chunks[neighbor_pos]
		if str(neighbor.get("chunk_id")) == my_id:
			return true
	return false


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


## Compatibilidade ESTRITAMENTE simétrica: os dois lados que se tocam precisam
## declarar exatamente o mesmo tipo de conector (ROAD↔ROAD, NONE↔NONE etc.).
## Aceitar qualquer valor quando a vizinha é NONE permitia estradas "nascerem"
## coladas em grama pura (chunks desconectadas).
func _connector_compatible(candidate_side: int, neighbor_side: int) -> bool:
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


## Regra de ordem usada na fila de carregamento: o que está mais perto do Player
## (distância ao quadrado) entra/commita primeiro. Empates são quebrados por
## direção de movimento (leve preferência à frente) e, por fim, de forma
## determinística por linha-coluna. Usa distância de GRID (Vector2i), nunca pixels.
func _chunk_priority_less(a: Vector2i, b: Vector2i, player_cell: Vector2i) -> bool:
	var da := a - player_cell
	var db := b - player_cell
	var dist_a := da.x * da.x + da.y * da.y
	var dist_b := db.x * db.x + db.y * db.y
	if dist_a != dist_b:
		return dist_a < dist_b
	var ba := _movement_priority_bonus(a, player_cell)
	var bb := _movement_priority_bonus(b, player_cell)
	if ba != bb:
		return ba < bb
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Bônus leve (menor valor = mais prioridade) para células à frente do Player,
## na direção dominante do último deslocamento. Não muda a ordem por distância;
## apenas desempata células a uma mesma distância.
func _movement_priority_bonus(cell: Vector2i, player_cell: Vector2i) -> int:
	if _player_move_dir == Vector2i.ZERO:
		return 0
	var d := cell - player_cell
	var bonus := 0
	if _player_move_dir.x != 0 and signi(d.x) == _player_move_dir.x:
		bonus -= 1
	if _player_move_dir.y != 0 and signi(d.y) == _player_move_dir.y:
		bonus -= 1
	return bonus


## Chave numérica de prioridade para logs de debug (menor = carregado antes).
func _priority_order(cell: Vector2i, player_cell: Vector2i) -> int:
	var d := cell - player_cell
	return d.x * d.x + d.y * d.y + _movement_priority_bonus(cell, player_cell)


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
