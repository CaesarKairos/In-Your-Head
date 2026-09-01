extends Node2D

## Teste da colisão "pés" do player contra props de natureza (Bug 1).
##
## A colisão do player deve ser uma cápsula pequena ancorada nos PÉS
## (offset y = +7), de modo que:
##   - vindo pelo NORTE (de trás), o player é bloqueado pelo tronco/base;
##   - passando LATERALMENTE já à frente do prop (pés abaixo da base), o
##     movimento NÃO é bloqueado (era o Bug 1);
##   - o player.tscn tem a CollisionShape2D deslocada para os pés e pequena.

const PropScript: GDScript = preload("res://worlds/chunks/nature_prop.gd")

var _failures: Array[String] = []
var _prop: Node2D


func _ready() -> void:
	await _check_player_scene_shape()
	await _check_physics()
	_finish()


## A shape física do player.tscn precisa estar ancorada nos pés.
func _check_player_scene_shape() -> void:
	var scene: PackedScene = load("res://scenes/characters/player/player.tscn")
	if scene == null:
		_failures.append("player.tscn não carregou")
		return
	var player: Node2D = scene.instantiate()
	var shape_node: Node2D = player.get_node("CollisionShape2D")
	var capsule: CapsuleShape2D = shape_node.shape as CapsuleShape2D
	if capsule == null:
		_failures.append("CollisionShape2D do player não é CapsuleShape2D")
	elif shape_node.position.y <= 0.0:
		_failures.append("CollisionShape2D do player não está deslocada para os pés (y="
				+ str(shape_node.position.y) + ")")
	elif capsule.height > 10.0 or capsule.radius > 5.0:
		_failures.append("cápsula do player grande demais: cobre o corpo inteiro "
				+ "(height=" + str(capsule.height) + ", radius=" + str(capsule.radius) + ")")
	# Não entra na árvore: o player.gd consulta Input em _physics_process.
	player.free()


## Simulação física mínima: CharacterBody2D "pé-ancorado" vs um NatureProp sólido.
func _check_physics() -> void:
	var tex: Texture2D = load("res://assets/props/Objects/Nature/Green/Tree_5_Big_Green.png")
	_prop = PropScript.new()
	_prop.set("texture", tex)
	_prop.set("solid", true)
	_prop.set("occludable", false)
	add_child(_prop)
	_prop.global_position = Vector2.ZERO
	_prop.set("scale", Vector2.ONE)

	# Caso A: vindo pelo norte (de trás), andando para baixo -> é bloqueado.
	var blocked_final := await _drive(Vector2(0, -40), Vector2(0, 80), 1.2)
	if blocked_final.y > -14.0:
		_failures.append("vindo pelo norte, o player atravessou a base do prop (y final="
				+ str(blocked_final.y) + ")")

	# Caso B: lateral, já VISIVELMENTE À FRENTE do prop (pés abaixo da base,
	# corpo ao sul) -> não deve ser bloqueado nem desviado.
	var lateral_final := await _drive(Vector2(-40, 14), Vector2(80, 0), 1.2)
	if lateral_final.x < 30.0:
		_failures.append("passando pela frente do prop o movimento foi bloqueado "
				+ "(x final=" + str(lateral_final.x) + ", esperado ~40)")

	# Caso C: lateral pelo NORTE do tronco (pés na mesma faixa da base) ->
	# deve haver algum bloqueio/desvio (a base continua sólida).
	await _drive(Vector2(-40, -6), Vector2(80, 0), 1.2)
	if _last_collision_count == 0:
		_failures.append("atravessando por trás da base, nenhuma colisão ocorreu "
				+ "(a base do prop deixou de ser sólida?)")


## Move um corpo com a MESMA configuração física do player (cápsula nos pés,
## layer 2 / mask 1). Retorna a posição final; o nº de frames com colisão fica
## em _last_collision_count.
func _drive(start: Vector2, vel: Vector2, seconds: float) -> Vector2:
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 3.0
	capsule.height = 6.0
	shape.shape = capsule
	shape.position = Vector2(0, 7)
	body.add_child(shape)
	add_child(body)
	body.global_position = start
	body.velocity = vel
	var collisions := 0
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		body.velocity = vel
		body.move_and_slide()
		if body.get_slide_collision_count() > 0:
			collisions += 1
		elapsed += 1.0 / 60.0
	var final := body.global_position
	body.queue_free()
	_last_collision_count = collisions
	return final


var _last_collision_count: int = 0


func _finish() -> void:
	if _failures.is_empty():
		print("=== PLAYER FEET COLLISION TEST OK ===")
	else:
		print("=== PLAYER FEET COLLISION TEST ERROS ===")
		for f in _failures:
			print(" - " + f)
	get_tree().quit(1 if _failures.size() > 0 else 0)
