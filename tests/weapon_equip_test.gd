extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	world.position = Vector2(120, 90)
	var player = load("res://scenes/characters/player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	for kind in ["gun", "pistol", "shotgun"]:
		var weapon: Weapon = load("res://scenes/weapons/%s/%s.tscn" % [kind, kind]).instantiate()
		player.equip_weapon(weapon)
		check(player.equipped_weapon == weapon, kind + " equipped")
		check(weapon.get_parent() == player.weapon_holder, kind + " holder")
		check(not player.animated_sprite.visible and player.no_hands_sprite.visible, kind + " no hands")
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			player.last_direction = direction
			var label: String = player.get_direction_name(direction)
			for moving in [false, true]:
				player.update_animation(moving)
				var sprite := weapon.animated_sprite
				var animation: String = ("run_" if moving else "idle_") + label
				check(sprite.animation == animation and sprite.is_playing(), kind + animation)
				check(sprite.sprite_frames.get_frame_count(animation) > 0, kind + " frames")
				check(sprite.is_visible_in_tree(), kind + " visible")
				check(sprite.global_position.distance_to(player.global_position) < 24.0, kind + " composition")
				check(player.weapon_holder.z_index == 0, kind + " same actor layer")
				check((player.weapon_holder.get_index() < player.no_hands_sprite.get_index()) == (direction == Vector2.UP), kind + " internal draw order")
				var frame := sprite.frame
				player.update_animation(moving)
				check(sprite.frame == frame, "Movement does not restart")
			weapon._last_shot_at = -1000000
			var ammo := weapon.current_ammo
			player.start_attack()
			check(player.is_attacking and weapon.is_attacking, kind + " shooting")
			check(weapon.current_ammo == ammo - 1, kind + " ammo per shot")
			check(not weapon.attack(label), kind + " cooldown")
			var muzzle := weapon.muzzle_point.global_position
			await process_frame
			var pellets := 0
			var flashes := 0
			for child in world.get_children():
				if child is Bullet:
					pellets += 1
					check(child._shooter == player, "Shooter")
					var origin: Vector2 = child.global_position - child.direction * child._traveled
					check(origin.distance_to(muzzle) < 0.01, kind + label + " muzzle " + str(origin) + " expected " + str(muzzle))
					check(absf(child.direction.angle_to(direction)) <= deg_to_rad(weapon.spread_degrees / 2.0) + 0.001, "Spread")
					child.queue_free()
				elif child is MuzzleFlash:
					flashes += 1
					check(child.global_position.is_equal_approx(muzzle), "Flash world position")
					child.queue_free()
			check(pellets == weapon.pellet_count and flashes == 1, kind + " projectiles and flash")
			await create_timer(0.5).timeout
			check(not player.is_attacking and not weapon.is_attacking, kind + " attack finishes")
			check(weapon.animated_sprite.animation == "idle_" + label, kind + " returns idle")
			weapon.reload()
			check(weapon.is_reloading, kind + " reload starts")
			check(not weapon.attack(label), kind + " no fire during reload")
			var turn_action := "move_right" if direction == Vector2.LEFT else "move_left"
			Input.action_press(turn_action)
			player._physics_process(1.0 / 60.0)
			check(player.last_direction == direction and weapon.current_direction == label, kind + " reload facing lock")
			check(weapon.animated_sprite.animation == "reload_" + label, kind + " movement preserves reload")
			Input.action_release(turn_action)
			await create_timer(2.2).timeout
			check(not weapon.is_reloading and weapon.current_ammo == weapon.magazine_size, kind + " reload finishes")
		# Switching during attack cannot leave the body locked or old signals connected.
		weapon._last_shot_at = -1000000
		player.start_attack()
		player.unequip_weapon()
		check(not player.is_attacking and player.animated_sprite.visible, "Unequip resets attack")
		check(not weapon.attack_finished.is_connected(player._on_weapon_attack_finished), "Disconnect old weapon")
		await process_frame
		for child in world.get_children():
			if child is Bullet or child is MuzzleFlash:
				child.queue_free()
		await process_frame
	player.start_attack()
	await create_timer(1.0).timeout
	check(not player.is_attacking and player.animated_sprite.animation.begins_with("idle_"), "Punch returns idle")
	var empty: Weapon = load("res://scenes/weapons/weapon.tscn").instantiate()
	player.equip_weapon(empty)
	player.start_attack()
	check(not player.is_attacking, "Synchronous attack completion does not lock Player")
	world.queue_free()
	await process_frame
	print("WEAPON EQUIP TEST ", "OK" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
