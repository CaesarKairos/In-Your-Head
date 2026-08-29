extends Node
## WorldCoordinates (Autoload)
##
## Fonte única de verdade para o sistema de coordenadas do mundo.
## Define a origem do mundo em (0,0) — o ponto onde o WorldGenerator planta a
## chunk lógica (0,0) — e deriva, a partir da posição do Player, as coordenadas
## atuais em TILE (16px) e em CHUNK (33 tiles) relativas a essa origem.
##
## O cálculo é O(1) (divisão inteira), sem comparar distância contra todos os
## chunks. O sinal `coordinates_changed` só é emitido quando o TILE do jogador
## muda de verdade (a cada 16px de movimento), nunca a cada frame — assim os
## inscritos (props de natureza, HUD de debug) não têm overhead por frame.

signal coordinates_changed(tile_position: Vector2i, chunk_position: Vector2i)

const TILE_SIZE: int = 16
const CHUNK_TILES: int = 33
const CHUNK_SIZE: int = CHUNK_TILES * TILE_SIZE

## Origem do mundo em pixels. O WorldGenerator registra aqui o seu
## `start_position`, mantendo este autoload como fonte única de verdade.
var world_origin: Vector2 = Vector2.ZERO

## Posição do Player em tiles (relativa à origem).
var tile_position: Vector2i = Vector2i.ZERO
## Posição do Player em células de chunk (relativa à origem).
var chunk_position: Vector2i = Vector2i.ZERO
## Posição absoluta do Player no mundo (pixels), para leituras pontuais.
var pixel_position: Vector2 = Vector2.ZERO

var _player: Node2D = null
var _last_tile: Vector2i = Vector2i(0, -1000000)  # sentinela impossível


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return
	var pos: Vector2 = _player.global_position
	pixel_position = pos
	var local := pos - world_origin
	# O(1): posição em pixels -> tile -> chunk, por divisão inteira.
	var t := Vector2i(floori(local.x / float(TILE_SIZE)), floori(local.y / float(TILE_SIZE)))
	if t == _last_tile:
		return
	_last_tile = t
	tile_position = t
	chunk_position = Vector2i(floori(t.x / float(CHUNK_TILES)), floori(t.y / float(CHUNK_TILES)))
	coordinates_changed.emit(tile_position, chunk_position)


## Registra explicitamente o Player (chamado pelo WorldGenerator). Mais robusto
## (e determinístico) do que procurar na árvore a cada frame.
func register_player(p: Node2D) -> void:
	if p is CharacterBody2D:
		_player = p
		# Força uma recálculo imediato na próxima frame.
		_last_tile = Vector2i(0, -1000000)


## Alinha a origem do mundo com o start_position do WorldGenerator.
func set_origin(o: Vector2) -> void:
	world_origin = o
	_last_tile = Vector2i(0, -1000000)


## Localiza o primeiro CharacterBody2D da cena atual (fallback).
func _find_player() -> Node2D:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var stack: Array[Node] = [scene]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is CharacterBody2D:
			_player = node as Node2D
			return _player
		for child in node.get_children():
			stack.append(child)
	return null