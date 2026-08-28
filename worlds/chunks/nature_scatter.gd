class_name NatureScatter
extends RefCounted

## Scatter procedural de natureza (decoração visual) para Chunks.
##
## Chamado UMA VEZ por chunk instanciada em tempo de jogo, logo após a chunk
## entrar na árvore (ver WorldGenerator._load_chunk_at). Lê o TileMapLayer
## "Ground" da própria chunk, considera elegíveis as células cujo atlas coord
## é `background_atlas_coords` (grama lisa) e instancia Sprite2D decorativas
## dentro de um container "Nature" filho da chunk.
##
## Determinismo: a semente é `world_seed` combinado com a posição de grid da
## chunk — os mesmos dois valores que definem QUAL chunk nasce na célula.
## Como o gerador faz streaming (descarrega/recarrega chunks), sem isso a
## vegetação mudaria a cada recarga da mesma célula.
##
## Profundidade: nesta etapa a natureza NÃO usa Y-sort. O container "Nature"
## é adicionado como último filho da chunk, com z_index 0 (relativo): desenha
## acima do Ground (que é opaco e viria por cima com z negativo) e abaixo do
## Player, que aparece depois do WorldGenerator na árvore de world.tscn.

const TILE_SIZE: int = 16
const PropScript: GDScript = preload("res://worlds/chunks/nature_prop.gd")

## Fração das células elegíveis que recebe um prop (8–15%).
const DENSITY: float = 0.12

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

	# Coleta células elegíveis: apenas tile de fundo liso (nunca estrada/borda).
	var eligible: Array[Vector2i] = []
	for cell in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) == background_coords:
			eligible.append(cell)
	if eligible.is_empty():
		return

	var nature := Node2D.new()
	nature.name = "Nature"
	nature.z_index = 0  # relativo; acima do Ground (ordem na árvore), abaixo do Player
	chunk.add_child(nature)

	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(world_seed, grid_pos)

	var count := int(round(eligible.size() * DENSITY))
	# Embaralha deterministicamente e toma os `count` primeiros.
	for i in range(eligible.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = tmp

	for k in range(mini(count, eligible.size())):
		var cell := eligible[k]
		var pick := _pick(rng)
		var texture: Texture2D = pick["texture"]
		if texture == null:
			continue
		nature.add_child(_make_prop(texture, String(pick["kind"]), cell, rng))



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


## Cria o nó do prop: NatureProp (colisão + oclusão) para árvores, arbustos,
## tocos e pedras; Sprite2D simples para decoração baixa (grama, flores etc.).
static func _make_prop(texture: Texture2D, kind: String, cell: Vector2i, rng: RandomNumberGenerator) -> Node2D:
	var solid_kinds := ["tree", "bush", "rock"]
	var occludable_kinds := ["tree", "bush"]
	var node: Node2D
	if kind in solid_kinds:
		var prop: Node2D = PropScript.new()
		prop.set("texture", texture)
		prop.set("solid", true)
		prop.set("occludable", kind in occludable_kinds)
		node = prop
	else:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.offset = Vector2(-texture.get_size().x / 2.0, -texture.get_size().y)
		node = sprite
	# Ancora a BASE do prop no centro da célula (com leve jitter), de modo que
	# árvores/arbustos "plantem" no chão e não flutuem sobre a célula.
	var jitter := float(TILE_SIZE) * 0.3
	node.position = Vector2(cell) * float(TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	node.position += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
	return node
