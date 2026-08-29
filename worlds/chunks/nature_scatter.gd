class_name NatureScatter
extends RefCounted

## Scatter procedural de natureza (decoração visual) para Chunks.
##
## Chamado UMA VEZ por chunk (diferido, na criação), logo após a chunk entrar na
## árvore (ver WorldGenerator._scatter_deferred). Lê o TileMapLayer "Ground" da
## própria chunk, considera elegíveis as células cujo atlas coord é
## `background_atlas_coords` (grama lisa) e instancia props dentro de um
## container "Nature" filho da chunk.
##
## Organicidade:
##  - Distribuição estilo Poisson-disc simplificada: distância mínima entre props
##    sólidos (18px) e entre árvores (30px), quebrando o padrão quadriculado e
##    evitando sobreposição de colisões;
##  - Jitter aleatório dentro da célula;
##  - Variação de escala (0.85–1.15) e flip horizontal;
##  - Mistura de tipos (sorteio ponderado por categoria) num mesmo cluster;
##  - Container "Nature" com y_sort_enabled: props mais abaixo na tela desenham
##    por cima de props mais acima, complementando a translucidez por oclusão.
##
## Determinismo: a semente é `world_seed` combinado com a posição de grid da
## chunk — os mesmos dois valores que definem QUAL chunk nasce na célula.
## Como o gerador faz streaming (descarrega/recarrega em pool), sem isso a
## vegetação mudaria a cada recarga da mesma célula.

const TILE_SIZE: int = 16
const CHUNK_TILES: int = 33
const PropScript: GDScript = preload("res://worlds/chunks/nature_prop.gd")

## Probabilidade por célula elegível de receber um prop (10%).
const DENSITY: float = 0.10

## Prop categorias consideradas sólidas (ganham StaticBody2D + colisão física).
const SOLID_KINDS: Array[String] = ["tree", "bush", "rock"]
## Prop que podem ocultar o jogador (copa alta) — ficam translúcidos por trás.
const OCCLUDABLE_KINDS: Array[String] = ["tree", "bush"]

## Distância mínima (px) entre props sólidos quaisquer.
const MIN_SOLID_DIST: float = 18.0
## Distância mínima (px) entre árvores (copas largas, mais espaçadas).
const MIN_TREE_DIST: float = 30.0
## Distância mínima (px) de um detalhe baixo a um prop sólido (evita invadir tronco).
const MIN_DETAIL_DIST: float = 6.0

## Diretório base dos props (paleta Green combina com o tileset das chunks).
const NATURE_DIR: String = "res://assets/props/Objects/Nature/"

## Categorias de props com pesos de sorteio. Grama/arbustos dominam; árvores
## são ocasionais; flores/cogumelos/pedras são raríssimos.
const PROP_CATEGORIES: Array[Dictionary] = [
	{
		"name": "grass",
		"weight": 42,
		"paths": [
			NATURE_DIR + "Green/Grass_1_Green.png",
			NATURE_DIR + "Green/Grass_2_Green.png",
			NATURE_DIR + "Green/Grass_3_Green.png",
			NATURE_DIR + "Green/Grass_4_Green.png",
			NATURE_DIR + "Green/Grass_5_Green.png",
		],
	},
	{
		"name": "bush",
		"weight": 24,
		"paths": [
			NATURE_DIR + "Green/Bush_1_Green.png",
			NATURE_DIR + "Green/Bush_2_Green.png",
		],
	},
	{
		"name": "tree",
		"weight": 13,
		"paths": [
			NATURE_DIR + "Green/Tree_1_Spruce_Green.png",
			NATURE_DIR + "Green/Tree_2_Spruce-Sparse_Green.png",
			NATURE_DIR + "Green/Tree_3_Normal_Green.png",
			NATURE_DIR + "Green/Tree_5_Big_Green.png",
			NATURE_DIR + "Green/Tree_6_Pine_Big_Green.png",
			NATURE_DIR + "Green/Tree_7_Birch_Green.png",
			NATURE_DIR + "Green/Tree_8_Birch_Green.png",
			NATURE_DIR + "Green/Tree_9_Small-oak_Green.png",
			NATURE_DIR + "Green/Tree_10_Small-oak_Green.png",
			NATURE_DIR + "Green/Tree-trunk_2_grass_Green.png",
		],
	},
	{
		"name": "rock",
		"weight": 8,
		"paths": [
			NATURE_DIR + "Green/Rocks/Rock-grass.png",
		],
	},
	{
		"name": "detail",
		"weight": 13,
		"paths": [
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Flowers_1_blue.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Flowers_2_purple.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Flowers_3_red.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Flowers_3_yellow.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Flower_1_red.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Flower_2_yellow.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Mushroom.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Mushrooms_1_Yellow.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Mushrooms_2_Red.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Stick.png",
			NATURE_DIR + "Flowers_Mashrooms_Other-nature-stuff/Stick_leaves.png",
		],
	},
]

## Cache de texturas carregadas (evita reload a cada chunk).
static var _texture_cache: Dictionary = {}


## Ponto de entrada: povoa `chunk` com decoração de natureza determinística.
static func scatter(chunk: Node2D, grid_pos: Vector2i, world_seed: int) -> void:
	if chunk == null or Engine.is_editor_hint():
		return

	var ground := _find_ground_layer(chunk)
	if ground == null:
		return

	var bg_value = chunk.get("background_atlas_coords")
	var background_coords: Vector2i = bg_value if bg_value != null else Vector2i(5, 0)

	# Coleta células elegíveis: apenas tile de fundo liso (nunca estrada/borda),
	# pulando a margem de 1 tile para reduzir props cortados na emenda entre chunks.
	var eligible: Array[Vector2i] = []
	for cell in ground.get_used_cells():
		if cell.x <= 0 or cell.x >= CHUNK_TILES - 1 \
				or cell.y <= 0 or cell.y >= CHUNK_TILES - 1:
			continue
		if ground.get_cell_atlas_coords(cell) == background_coords:
			eligible.append(cell)
	if eligible.is_empty():
		return

	# Container da natureza com Y-sort ativo: props mais "baixos" na tela
	# desenham por cima dos mais "altos", dando profundidade ao cluster.
	var nature := Node2D.new()
	nature.name = "Nature"
	nature.z_index = 0
	nature.y_sort_enabled = true
	chunk.add_child(nature)

	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(world_seed, grid_pos)

	var placed_solids: Array[Vector2] = []
	var placed_trees: Array[Vector2] = []

	for cell in eligible:
		# Decisão por probabilidade (determinística na ordem das células).
		if rng.randf() > DENSITY:
			continue
		var pick := _pick(rng)
		var kind := String(pick["kind"])
		var texture := pick["texture"] as Texture2D
		if texture == null:
			continue
		var pos := _jittered_cell_pos(cell, rng)

		if kind in SOLID_KINDS:
			if not _min_distance_ok(pos, placed_solids, MIN_SOLID_DIST):
				continue
			if kind == "tree" and not _min_distance_ok(pos, placed_trees, MIN_TREE_DIST):
				continue
			placed_solids.append(pos)
			if kind == "tree":
				placed_trees.append(pos)
		else:
			# Detalhe baixo (grama/flor/cogumelo): só não invade o tronco de um sólido.
			if not _min_distance_ok(pos, placed_solids, MIN_DETAIL_DIST):
				continue

		nature.add_child(_make_prop(texture, kind, pos, rng))


## Centro da célula + jitter aleatório (quebra o padrão de grade).
static func _jittered_cell_pos(cell: Vector2i, rng: RandomNumberGenerator) -> Vector2:
	var base := Vector2(cell) * float(TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	var j := float(TILE_SIZE) * 0.4
	return base + Vector2(rng.randf_range(-j, j), rng.randf_range(-j, j))


## Verdadeiro se `pos` respeita `min_d` de TODOS os pontos de `list`.
static func _min_distance_ok(pos: Vector2, list: Array[Vector2], min_d: float) -> bool:
	for p in list:
		if pos.distance_to(p) < min_d:
			return false
	return true



## Semente estável: mesma world_seed + mesma célula -> mesma natureza sempre.
static func _cell_seed(world_seed: int, grid_pos: Vector2i) -> int:
	return hash("%d|%d|%d" % [world_seed, grid_pos.x, grid_pos.y])


static func _find_ground_layer(chunk: Node2D) -> TileMapLayer:
	var direct := chunk.get_node_or_null("Ground")
	if direct is TileMapLayer:
		return direct as TileMapLayer
	for child in chunk.get_children():
		if child is TileMapLayer:
			return child as TileMapLayer
	return null


static func _pick(rng: RandomNumberGenerator) -> Dictionary:
	var total_weight := 0
	for category in PROP_CATEGORIES:
		total_weight += int(category["weight"])
	var roll := rng.randi_range(1, total_weight)
	var chosen: Dictionary = PROP_CATEGORIES[0]
	for category in PROP_CATEGORIES:
		roll -= int(category["weight"])
		if roll <= 0:
			chosen = category
			break
	var paths: Array = chosen["paths"]
	var path: String = paths[rng.randi_range(0, paths.size() - 1)]
	return {"kind": String(chosen["name"]), "texture": _load_texture(path)}


static func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	if not ResourceLoader.exists(path):
		push_warning("[NatureScatter] Textura não encontrada: " + path)
		_texture_cache[path] = null
		return null
	var tex: Texture2D = load(path) as Texture2D
	_texture_cache[path] = tex
	return tex


## Cria o nó do prop: NatureProp (colisão + oclusão por coordenada) para árvores,
## arbustos, tocos e pedras; Sprite2D simples para decoração baixa (grama, flores).
## Aplica variação de escala e flip horizontal para quebrar a repetição visual.
static func _make_prop(texture: Texture2D, kind: String, pos: Vector2, rng: RandomNumberGenerator) -> Node2D:
	var flip := rng.randf() < 0.5
	var node: Node2D
	if kind in SOLID_KINDS:
		var prop: Node2D = PropScript.new()
		prop.set("texture", texture)
		prop.set("solid", true)
		prop.set("occludable", kind in OCCLUDABLE_KINDS)
		prop.set("flip_h", flip)
		node = prop
	else:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.flip_h = flip
		sprite.offset = Vector2(-texture.get_size().x / 2.0, -texture.get_size().y)
		node = sprite
	# A BASE do prop fica plantada na posição (o "pezinho" no chão).
	node.position = pos
	# Variação suave de escala (0.85–1.15), proporcional (sprite + colisão).
	var s := 0.85 + rng.randf() * 0.3
	node.scale = Vector2(s, s)
	return node
