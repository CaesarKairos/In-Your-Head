extends SceneTree

## Executar com renderer real (sem --headless). Compara pixels na emenda.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var world := Node2D.new()
	world.y_sort_enabled = true
	world.position = Vector2(-450, 0)
	viewport.add_child(world)
	var scene: PackedScene = load("res://worlds/chunks/crossroads_01.tscn")
	var left: Node2D = scene.instantiate()
	world.add_child(left)
	var nature := Node2D.new()
	nature.y_sort_enabled = true
	left.add_child(nature)
	var tree := NatureProp.new()
	tree.texture = load("res://assets/props/Objects/Nature/Green/Tree_5_Big_Green.png")
	tree.solid = false
	tree.occludable = false
	tree.position = Vector2(524, 100)
	nature.add_child(tree)
	await process_frame
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image()
	var right: Node2D = scene.instantiate()
	right.position = Vector2(528, 0)
	world.add_child(right)
	await process_frame
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image()
	var texture := tree.texture.get_image()
	var checked := 0
	for y in texture.get_height():
		for x in texture.get_width():
			# Tree rect starts at x=507, y=48; neighbor starts at x=528.
			var pixel := Vector2i(57 + x, 48 + y)
			if pixel.x < 78 or texture.get_pixel(x, y).a < 0.99:
				continue
			checked += 1
			if before.get_pixelv(pixel) != after.get_pixelv(pixel):
				failures.append("Neighbor ground covered tree at " + str(pixel))
	if checked == 0:
		failures.append("No tree pixels tested beyond chunk boundary")
	# Compara Y-sort natural com ordem explicitamente forçada, usando os pés.
	var actor = load("res://scenes/characters/player/player.tscn").instantiate()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.get_node("Camera2D").enabled = false
	actor.animated_sprite.pause()
	for behind in [false, true]:
		# Centro ainda ao norte, mas pés ao sul: precisa desenhar à frente.
		actor.position = Vector2(524, 88 if behind else 96)
		await process_frame
		await RenderingServer.frame_post_draw
		var natural := viewport.get_texture().get_image()
		if behind:
			tree.z_index = 1
		else:
			actor.z_index = 1
		await process_frame
		await RenderingServer.frame_post_draw
		var forced := viewport.get_texture().get_image()
		if natural.get_data() != forced.get_data():
			failures.append("Incorrect feet Y-sort, behind=" + str(behind))
		tree.z_index = 0
		actor.z_index = 0
	actor.queue_free()
	await process_frame
	# Contact sheet using real Player and weapons, all directions.
	var players: Array[Node2D] = []
	for row in 3:
		var kind: String = ["gun", "pistol", "shotgun"][row]
		for column in 4:
			var player = load("res://scenes/characters/player/player.tscn").instantiate()
			player.position = Vector2(650 + column * 60, 70 + row * 75)
			world.add_child(player)
			player.set_physics_process(false)
			player.get_node("Camera2D").enabled = false
			player.last_direction = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP][column]
			player.equip_weapon(load("res://scenes/weapons/%s/%s.tscn" % [kind, kind]).instantiate())
			player.no_hands_sprite.pause()
			player.no_hands_sprite.frame = 0
			player.equipped_weapon.animated_sprite.pause()
			player.equipped_weapon.animated_sprite.frame = 0
			players.append(player)
	await process_frame
	await RenderingServer.frame_post_draw
	var equipped := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/review"))
	if equipped.save_png("res://.godot/review/composition.png") != OK:
		failures.append("Could not save composition.png")
	for player in players:
		player.weapon_holder.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden := viewport.get_texture().get_image()
	for player in players:
		var center := Vector2i(player.global_position)
		var changed := 0
		for y in range(center.y - 24, center.y + 24):
			for x in range(center.x - 24, center.x + 24):
				if equipped.get_pixel(x, y) != hidden.get_pixel(x, y):
					changed += 1
		print(player.equipped_weapon.weapon_name, " ", player.last_direction, " weapon pixels=", changed)
		if changed == 0:
			failures.append("Weapon fully hidden: " + player.equipped_weapon.weapon_name + str(player.last_direction))
	print("RENDERING TEST ", "OK" if failures.is_empty() else failures, " edge pixels=", checked)
	viewport.queue_free()
	await process_frame
	Input.set_custom_mouse_cursor(null)
	call_deferred("quit", 0 if failures.is_empty() else 1)
