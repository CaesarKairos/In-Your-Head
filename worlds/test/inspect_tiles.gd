extends SceneTree

## Inspeciona chunks de estrada existentes (mapa célula->tile) e mede a
## "textura" (desvio-padrão) de tiles candidatos a grama lisa/variante.

const TILE := 16


func _initialize() -> void:
	_run()
	quit(0)


func _dump(scene_path: String) -> void:
	var inst: Node = (load(scene_path) as PackedScene).instantiate()
	var ground: TileMapLayer = inst.get_node("Ground")
	print("== ", scene_path.get_file())
	for y in range(33):
		var row := {}
		var all_grass := true
		for x in range(33):
			var c := ground.get_cell_atlas_coords(Vector2i(x, y))
			if c != Vector2i(-1, -1):
				row[x] = c
				if c != Vector2i(5, 0):
					all_grass = false
		if all_grass:
			continue
		var runs: Array[String] = []
		var prev := Vector2i(-9, -9)
		var start := -1
		for x in range(34):
			var c: Vector2i = row.get(x, Vector2i(-9, -9))
			if c != prev:
				if start >= 0 and prev != Vector2i(-9, -9):
					runs.append("x%d-%d:%s" % [start, x - 1, prev])
				prev = c
				start = x
		print("  y%02d: %s" % [y, " | ".join(runs)])
	inst.free()


func _texture_stats(img: Image, coord: Vector2i) -> void:
	var sum := 0.0
	var sum2 := 0.0
	var n := 0
	for py in range(TILE):
		for px in range(TILE):
			var c := img.get_pixel(coord.x * TILE + px, coord.y * TILE + py)
			if c.a < 0.5:
				continue
			var lum := c.get_luminance()
			sum += lum
			sum2 += lum * lum
			n += 1
	if n == 0:
		print("  %s: VAZIO" % coord)
		return
	var mean := sum / n
	var sd := sqrt(maxf(sum2 / n - mean * mean, 0.0))
	print("  %s: luminancia média %.3f, desvio %.4f" % [coord, mean, sd])


func _run() -> void:
	_dump("res://worlds/chunks/crossroads_01.tscn")

	var tex: Texture2D = load("res://assets/tilesets/Tiles/Background_Green_TileSet.png")
	var img: Image = tex.get_image()
	print("== estatísticas de tiles de grama (candidatos a fundo/decoração)")
	for coord in [
		Vector2i(5, 0), Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
		Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3),
		Vector2i(0, 4), Vector2i(5, 4), Vector2i(10, 4),
		Vector2i(0, 5), Vector2i(1, 5), Vector2i(6, 5), Vector2i(7, 5),
		Vector2i(4, 12), Vector2i(6, 12),
		Vector2i(4, 7), Vector2i(4, 9), Vector2i(5, 8),
	]:
		_texture_stats(img, coord)
