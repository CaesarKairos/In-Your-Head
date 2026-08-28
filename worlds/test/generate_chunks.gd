extends SceneTree

## Gerador de chunks de terreno e estrada (execução única, ferramenta de dev):
##   godot --headless --script res://worlds/test/generate_chunks.gd
##
## Chunks geradas por IA para revisão visual manual posterior:
##  - 4 T-junctions: road_t_n/s/e/w_01 (crossroads com um braço fechado por tampa)
##  - 3 deadends: road_deadend_s/e/w_01 (faltavam no pool)
##  - 4 curvas extras: road_curve_{nw,ne,se,sw}_02 (variação de grama decorada)
##  - 10 chunks de terreno puro: terrain_* (conectores NONE)
##
## Convenção de sufixo direcional: indica a direção da conexão SINGULAR do
## formato (igual ao deadend_n existente): road_t_n = perna no norte
## (conexões N+E+W); road_deadend_e = única conexão a leste.

const TILE := 16
const GRASS := Vector2i(5, 0)
const CHUNK_TILES := 33

# Vocabulário de estrada (extraído das chunks existentes):
# Horizontal (linhas): (12,0) meio-fio N, (4,7) acostamento, (3,8) asfalto, (4,7), (12,2) meio-fio S
# Vertical (colunas):  (11,1) meio-fio W, (0,8) asfalto, (4,9)/(5,8) acostamento, (13,1) meio-fio E
const H_TOP := Vector2i(12, 0)
const H_SHOULDER := Vector2i(4, 7)
const H_ASPHALT := Vector2i(3, 8)
const H_BOTTOM := Vector2i(12, 2)
const V_LEFT := Vector2i(11, 1)
const V_ASPHALT := Vector2i(0, 8)
const V_SHOULDER_A := Vector2i(4, 9)
const V_SHOULDER_B := Vector2i(5, 8)
const V_RIGHT := Vector2i(13, 1)
# Tampa de pista (do road_deadend_n_01, linha y21).
const CAP_EDGE := Vector2i(13, 2)
const CAP_FILL := Vector2i(12, 2)

# Tiles de grama texturizada (desvio alto = grama com detalhe), full-opaque.
const GRASS_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3),
	Vector2i(0, 4), Vector2i(5, 4), Vector2i(10, 4), Vector2i(0, 5), Vector2i(1, 5),
	Vector2i(6, 5), Vector2i(7, 5), Vector2i(4, 12), Vector2i(6, 12),
]
# Tiles de terra (trilha) da linha y0 do atlas.
const DIRT_PATH: Array[Vector2i] = [
	Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(9, 0), Vector2i(10, 0),
]

var _img: Image
var _generated: Array[String] = []


func _initialize() -> void:
	var tex: Texture2D = load("res://assets/tilesets/Tiles/Background_Green_TileSet.png")
	_img = tex.get_image()
	_generate_ts()
	_generate_deadends()
	_generate_curve_variants()
	_generate_terrain()
	print("GERADAS %d chunks: %s" % [_generated.size(), ", ".join(_generated)])
	quit(0)


# ---------- helpers ----------

func _tile_full(coord: Vector2i) -> bool:
	if (coord.x + 1) * TILE > _img.get_width() or (coord.y + 1) * TILE > _img.get_height():
		return false
	for py in range(TILE):
		for px in range(TILE):
			if _img.get_pixel(coord.x * TILE + px, coord.y * TILE + py).a < 0.5:
				return false
	return true


func _safe(coord: Vector2i, fallback: Vector2i = GRASS) -> Vector2i:
	return coord if _tile_full(coord) else fallback


func _new_chunk(id: String) -> Node:
	var inst: Node = (load("res://worlds/chunks/chunk.tscn") as PackedScene).instantiate()
	inst.name = id
	inst.set("chunk_id", id)
	var ground: TileMapLayer = inst.get_node("Ground")
	ground.clear()
	for y in range(CHUNK_TILES):
		for x in range(CHUNK_TILES):
			ground.set_cell(Vector2i(x, y), 0, GRASS)
	return inst


func _connectors(inst: Node, n: int, s: int, e: int, w: int) -> void:
	inst.set("north_connector", n)
	inst.set("south_connector", s)
	inst.set("east_connector", e)
	inst.set("west_connector", w)


func _save(inst: Node) -> void:
	var id: String = inst.get("chunk_id")
	var path := "res://worlds/chunks/%s.tscn" % id
	var packed := PackedScene.new()
	var err := packed.pack(inst)
	if err != OK:
		push_error("Falha ao empacotar %s: %s" % [id, err])
		inst.free()
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("Falha ao salvar %s: %s" % [path, err])
	else:
		_generated.append(id)
	inst.free()


# Faixa horizontal de estrada: tile da linha `row` (14..18) para a coluna x.
func _h_road_cell(row: int) -> Vector2i:
	match row:
		14: return H_TOP
		15: return H_SHOULDER
		16: return H_ASPHALT
		17: return H_SHOULDER
		18: return H_BOTTOM
	return GRASS


# Faixa vertical de estrada: tile da coluna `col` (14..18) para a linha y.
func _v_road_cell(col: int) -> Vector2i:
	match col:
		14: return V_LEFT
		15: return V_ASPHALT
		16: return V_SHOULDER_A
		17: return V_SHOULDER_B
		18: return V_RIGHT
	return GRASS


func _draw_h_road(ground: TileMapLayer, x_from: int, x_to: int) -> void:
	for x in range(x_from, x_to + 1):
		for row in range(14, 19):
			ground.set_cell(Vector2i(x, row), 0, _h_road_cell(row))


func _draw_v_road(ground: TileMapLayer, y_from: int, y_to: int) -> void:
	for y in range(y_from, y_to + 1):
		for col in range(14, 19):
			ground.set_cell(Vector2i(col, y), 0, _v_road_cell(col))


# Tampa horizontal (fecha pista que corre verticalmente): linha única em y.
func _cap_h(ground: TileMapLayer, y: int) -> void:
	for x in range(14, 19):
		var coord := CAP_EDGE if (x == 14 or x == 18) else CAP_FILL
		ground.set_cell(Vector2i(x, y), 0, _safe(coord, H_BOTTOM))


# Tampa vertical (fecha pista que corre horizontalmente): coluna única em x.
func _cap_v(ground: TileMapLayer, x: int) -> void:
	for y in range(14, 19):
		var coord := CAP_EDGE if (y == 14 or y == 18) else CAP_FILL
		ground.set_cell(Vector2i(x, y), 0, _safe(coord, H_BOTTOM))


func _clear(ground: TileMapLayer, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			ground.set_cell(Vector2i(x, y), 0, GRASS)



# ---------- geradores ----------

## T-junctions: crossroads com um braço removido + tampa de deadend.
func _generate_ts() -> void:
	var base: PackedScene = load("res://worlds/chunks/crossroads_01.tscn")

	# road_t_n: perna no norte (N+E+W), braço SUL fechado.
	var t_n: Node = base.instantiate()
	t_n.name = "road_t_n_01"
	t_n.set("chunk_id", "road_t_n_01")
	var g: TileMapLayer = t_n.get_node("Ground")
	_clear(g, Rect2i(14, 19, 5, 14))     # braço sul
	_cap_h(g, 19)
	_connectors(t_n, 1, 0, 1, 1)
	_save(t_n)

	# road_t_s: perna no sul (S+E+W), braço NORTE fechado.
	var t_s: Node = base.instantiate()
	t_s.name = "road_t_s_01"
	t_s.set("chunk_id", "road_t_s_01")
	g = t_s.get_node("Ground")
	_clear(g, Rect2i(14, 0, 5, 14))      # braço norte
	_cap_h(g, 13)
	_connectors(t_s, 0, 1, 1, 1)
	_save(t_s)

	# road_t_e: perna no leste (N+S+E), braço OESTE fechado.
	var t_e: Node = base.instantiate()
	t_e.name = "road_t_e_01"
	t_e.set("chunk_id", "road_t_e_01")
	g = t_e.get_node("Ground")
	_clear(g, Rect2i(0, 14, 14, 5))      # braço oeste
	_cap_v(g, 13)
	_connectors(t_e, 1, 1, 1, 0)
	_save(t_e)

	# road_t_w: perna no oeste (N+S+W), braço LESTE fechado.
	var t_w: Node = base.instantiate()
	t_w.name = "road_t_w_01"
	t_w.set("chunk_id", "road_t_w_01")
	g = t_w.get_node("Ground")
	_clear(g, Rect2i(19, 14, 14, 5))     # braço leste
	_cap_v(g, 19)
	_connectors(t_w, 1, 1, 0, 1)
	_save(t_w)


## Deadends restantes: south (espelho do _n), east e west (sintéticos).
func _generate_deadends() -> void:
	# road_deadend_s: espelho vertical do road_deadend_n_01.
	var dn: Node = (load("res://worlds/chunks/road_deadend_n_01.tscn") as PackedScene).instantiate()
	var src: TileMapLayer = dn.get_node("Ground")
	var d_s: Node = (load("res://worlds/chunks/chunk.tscn") as PackedScene).instantiate()
	d_s.name = "road_deadend_s_01"
	d_s.set("chunk_id", "road_deadend_s_01")
	var dst: TileMapLayer = d_s.get_node("Ground")
	dst.clear()
	for y in range(CHUNK_TILES):
		for x in range(CHUNK_TILES):
			var c := src.get_cell_atlas_coords(Vector2i(x, y))
			if c != Vector2i(-1, -1):
				dst.set_cell(Vector2i(x, 32 - y), 0, c)
	dn.free()
	_connectors(d_s, 0, 1, 0, 0)
	_save(d_s)

	# road_deadend_e: estrada horizontal da borda leste, tampa em x20.
	var d_e: Node = _new_chunk("road_deadend_e_01")
	var g: TileMapLayer = d_e.get_node("Ground")
	_draw_h_road(g, 20, 32)
	_cap_v(g, 20)
	_connectors(d_e, 0, 0, 1, 0)
	_save(d_e)

	# road_deadend_w: estrada horizontal da borda oeste, tampa em x12.
	var d_w: Node = _new_chunk("road_deadend_w_01")
	g = d_w.get_node("Ground")
	_draw_h_road(g, 0, 12)
	_cap_v(g, 12)
	_connectors(d_w, 0, 0, 0, 1)
	_save(d_w)


## Curvas extras (_02): layout idêntico às curvas originais, com patches de
## grama texturizada para quebrar a repetição visual.
func _generate_curve_variants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	for dir_name in ["nw", "ne", "se", "sw"]:
		var src: Node = (load("res://worlds/chunks/road_curve_%s_01.tscn" % dir_name) as PackedScene).instantiate()
		var id := "road_curve_%s_02" % dir_name
		var inst: Node = src.duplicate()
		inst.name = id
		inst.set("chunk_id", id)
		var g: TileMapLayer = inst.get_node("Ground")
		for i in range(48):
			var cell := Vector2i(rng.randi_range(0, 32), rng.randi_range(0, 32))
			if g.get_cell_atlas_coords(cell) == GRASS:
				g.set_cell(cell, 0, _safe(GRASS_VARIANTS[rng.randi_range(0, GRASS_VARIANTS.size() - 1)]))
		_connectors(inst,
			int(src.get("north_connector")), int(src.get("south_connector")),
			int(src.get("east_connector")), int(src.get("west_connector")))
		_save(inst)
		src.free()


## Terreno puro: 10 variações, todos conectores NONE.
func _generate_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1338
	var g: TileMapLayer

	# 1) Grama lisa (a "célula vazia" base do conjunto).
	var t := _new_chunk("terrain_grass_plain_01")
	_connectors(t, 0, 0, 0, 0)
	_save(t)

	# 2-4) Grama mesclada: manchas de grama texturizada (densidades diferentes).
	for v in range(3):
		var id := "terrain_grass_mixed_%02d" % (v + 1)
		t = _new_chunk(id)
		g = t.get_node("Ground")
		var density: float = [0.12, 0.22, 0.34][v]
		for y in range(CHUNK_TILES):
			for x in range(CHUNK_TILES):
				if rng.randf() < density:
					g.set_cell(Vector2i(x, y), 0, _safe(GRASS_VARIANTS[rng.randi_range(0, GRASS_VARIANTS.size() - 1)]))
		_connectors(t, 0, 0, 0, 0)
		_save(t)

	# 5-6) Touceiras em clusters (blocos 2x2 de grama texturizada).
	for v in range(2):
		var id := "terrain_grass_tufts_%02d" % (v + 1)
		t = _new_chunk(id)
		g = t.get_node("Ground")
		for i in range(26):
			var c := Vector2i(rng.randi_range(0, 31), rng.randi_range(0, 31))
			var tile := _safe(GRASS_VARIANTS[rng.randi_range(0, GRASS_VARIANTS.size() - 1)])
			for dy in range(2):
				for dx in range(2):
					g.set_cell(c + Vector2i(dx, dy), 0, tile)
		_connectors(t, 0, 0, 0, 0)
		_save(t)

	# 7-8) Trilha de terra horizontal (linha central com tiles de terra).
	for v in range(2):
		var id := "terrain_dirt_path_h_%02d" % (v + 1)
		t = _new_chunk(id)
		g = t.get_node("Ground")
		var row: int = [14, 18][v]
		for x in range(2, 31):
			g.set_cell(Vector2i(x, row), 0, _safe(DIRT_PATH[(x + v) % DIRT_PATH.size()]))
		_connectors(t, 0, 0, 0, 0)
		_save(t)

	# 9) Trilha de terra vertical.
	t = _new_chunk("terrain_dirt_path_v_01")
	g = t.get_node("Ground")
	for y in range(2, 31):
		g.set_cell(Vector2i(16, y), 0, _safe(DIRT_PATH[y % DIRT_PATH.size()]))
	_connectors(t, 0, 0, 0, 0)
	_save(t)

	# 10) Grama mesclada com padrão determinístico diferente.
	t = _new_chunk("terrain_grass_dark_01")
	g = t.get_node("Ground")
	for y in range(CHUNK_TILES):
		for x in range(CHUNK_TILES):
			if rng.randf() < 0.18:
				g.set_cell(Vector2i(x, y), 0, _safe(GRASS_VARIANTS[(x * 7 + y * 13) % GRASS_VARIANTS.size()]))
	_connectors(t, 0, 0, 0, 0)
	_save(t)
