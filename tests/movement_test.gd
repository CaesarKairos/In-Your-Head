extends SceneTree

var failures: Array[String] = []
var player: CharacterBody2D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)

func send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	player = load("res://scenes/characters/player/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	for sprint in [false, true]:
		var expected: float = player.sprint_speed if sprint else player.walk_speed
		for actions in [["move_right"], ["move_left"], ["move_up"], ["move_down"],
				["move_right", "move_up"], ["move_left", "move_down"],
				["move_left", "move_up"], ["move_right", "move_down"]]:
			player.last_move_action = ""
			for action in actions:
				send(action, true)
			send("sprint", sprint)
			player._physics_process(1.0 / 60.0)
			var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			check(absf(input.length() - 1.0) < 0.0001, "Input magnitude " + str(actions))
			check(absf(player.velocity.length() - expected) < 0.0001, "Velocity " + str(actions))
			check(player.velocity.length() <= expected + 0.0001, "Speed limit " + str(actions))
			print("MOVEMENT ", actions, " sprint=", sprint, " velocity=", player.velocity.length())
			for action in actions:
				send(action, false)
			send("sprint", false)
	# Real event sequence: tap, release, tap, diagonal, release owner key.
	player.last_move_action = ""
	send("move_right", true)
	for i in 3:
		player._physics_process(1.0 / 60.0)
	check(player.double_tap_sprint_action == "", "One press across physics ticks is not two taps")
	send("move_right", false)
	send("move_right", true)
	check(player.double_tap_sprint_action == "move_right", "Double tap starts sprint")
	send("move_up", true)
	player._physics_process(1.0 / 60.0)
	check(is_equal_approx(player.velocity.length(), player.sprint_speed), "Double tap diagonal limit")
	send("move_right", false)
	player._physics_process(1.0 / 60.0)
	check(player.double_tap_sprint_action == "", "Owner release cancels sprint")
	check(is_equal_approx(player.velocity.length(), player.walk_speed), "Remaining direction walks")
	send("move_up", false)
	# Repeated diagonal chords must not become a double tap.
	player.last_move_action = ""
	for i in 2:
		send("move_right", true)
		send("move_up", true)
		check(player.double_tap_sprint_action == "", "Diagonal chord does not sprint")
		send("move_right", false)
		send("move_up", false)
	# Holding automatic attack with an empty magazine must still allow movement.
	var gun: Weapon = load("res://scenes/weapons/gun/gun.tscn").instantiate()
	player.equip_weapon(gun)
	gun.current_ammo = 0
	send("move_left", true)
	send("attack", true)
	player._physics_process(1.0 / 60.0)
	check(player.velocity.length() > 0.0, "Rejected shot does not freeze movement")
	send("move_left", false)
	send("attack", false)
	player.free()
	print("MOVEMENT TEST ", "OK" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
