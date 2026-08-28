extends SceneTree

## Inventário do tileset + dos tiles usados pelas chunks existentes.
## Uso: godot --headless --script res://worlds/test/inventory_tileset.gd

const TILE := 16


func _initialize() -> void:
	_run()
	quit(0)


func _run() -> void:
	var tex: Texture2D = load("res://assets/tilesets/Tiles/Background_Green_TileSet.png")
	var img: Image = tex.get_image()
	var cols := img.get_width() / TILE
	var rows := int(ceil(img.get_height() / float(TILE)))
	print("ATLAS %dx%d tiles (%dx%d px)" % [cols, rows, img.get_width(), img.get_height()])
	for ty in range(rows):
		var line := ""
		for tx in range(cols):
			line += _classify(img, tx, ty) + " "
		print("y=%02d | %s" % [ty, line])

	# Tiles usados pelas chunks existentes.
	var dir := DirAccess.open("res://worlds/chunks")
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tscn") and entry != "chunk.tscn":
			var scene: PackedScene = load("res://worlds/chunks/" + entry)
			var inst := scene.instantiate()
			var ground: TileMapLayer = inst.get_node("Ground")
			var by_coord := {}
			for cell in ground.get_used_cells():
				var c := ground.get_cell_atlas_coords(cell)
				by_coord[c] = int(by_coord.get(c, 0)) + 1
			var pairs := []
			for c in by_coord:
				pairs.append("%s:%d" % [c, by_coord[c]])
			pairs.sort()
			print("CHUNK %s | conectores N%d S%d E%d W%d | %s" % [
				entry, inst.get("north_connector"), inst.get("south_connector"),
				inst.get("east_connector"), inst.get("west_connector"),
				", ".join(pairs)])
			inst.free()
		entry = dir.get_next()
	dir.list_dir_end()


func _classify(img: Image, tx: int, ty: int) -> String:
	if (tx + 1) * TILE > img.get_width() or (ty + 1) * TILE > img.get_height():
		return "...."
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for py in range(TILE):
		for px in range(TILE):
			var c := img.get_pixel(tx * TILE + px, ty * TILE + py)
			if c.a < 0.5:
				continue
			r += c.r
			g += c.g
			b += c.b
			n += 1
	if n < TILE * TILE / 2:
		return "...."  # vazio/translúcido
	r /= n
	g /= n
	b /= n
	if g > r and g > b:
		return "GRAS" if g > 0.4 else "gras"
	if r > g and r > b:
		return "DIRT" if r > 0.4 else "dirt"
	if absf(r - g) < 0.06 and absf(g - b) < 0.06:
		return "GRAY" if r > 0.4 else "gray"
	return "othr"
