class_name Handgun
extends Weapon

@export var fire_rate: float = 0.3


func _ready() -> void:
	super._ready()

	weapon_name = "Handgun"
	damage = 10
	attack_cooldown = fire_rate

	# =========================================================================
	# SISTEMA DE ENCAIXE - MAO DO PERSONAGEM COMO PONTO DE REFERENCIA
	# =========================================================================
	# A origem do no Weapon representa a EMPUNHADURA (mao do personagem).
	#
	# grip_offsets: desloca a origem da Weapon (= mao) no corpo do personagem.
	#   As maos ficam ~y=+4.5 abaixo do centro; LEFT mantem (-2, 3) ja aprovado
	#   e RIGHT e o espelho simetrico (2, 3).
	#
	# sprite_offsets: desloca o AnimatedSprite2D DENTRO da arma, alinhando o
	#   ponto real do cabo com a origem (mao).
	#   - DOWN (0, 4.0): a "mao" (pele) fica nas linhas 4..9 da textura 5x16;
	#     desloca a arma para BAIXO (mira para baixo, cano para frente).
	#   - UP (0, -4.0): a "mao" (pele) fica em dois blocos (linhas ~4..11) pois
	#     sao vistas de tras; desloca a arma para CIMA (mira para cima), de modo
	#     que a ponta traseira nao apareca abaixo das pernas.
	#     NAO e espelho simetrico de DOWN - a arte de up/down NAO e simetrica.
	#     (a ordem de desenho atras do corpo e controlada por WeaponHolder.z_index).
	#   - LEFT/RIGHT (0,0): frames horizontais ja centralizados na empunhadura.
	#
	# sprite_offsets_by_state: os sprites de tiro (5x17) NAO crescem simetricamente
	#   em relacao aos de idle/run (5x16): o recuo (recoil) desloca o conteudo
	#   visivel verticalmente ao longo dos 3 frames. Valores derivados das texturas
	#   de shoot (ver tools/analyze_hand_regions.py):
	#   - shoot_down (0, 4.0): mesmo deslocamento de down (cano para frente).
	#   - shoot_up (0, -5.5): o recoil desce o conteudo no frame 0, entao precisa
	#     de um deslocamento extra para cima para nao aparecer entre as pernas.
	# =========================================================================

	grip_offset = Vector2(0, 4)
	grip_offsets = {
		"down": Vector2(0, 4),
		"up": Vector2(0, 4),
		"left": Vector2(-2, 3),
		"right": Vector2(2, 3),
	}

	sprite_offsets = {
		"down": Vector2(0, 4),
		"up": Vector2(0, -4),
		"left": Vector2(0, 0),
		"right": Vector2(0, 0),
	}

	sprite_offsets_by_state = {
		"shoot_down": Vector2(0, 4),
		"shoot_up": Vector2(0, -5.5),
		"shoot_left": Vector2(0, 0),
		"shoot_right": Vector2(0, 0),
	}

	# Sincroniza a composicao visual inicial (dicionarios ja preenchidos).
	update_visual(get_direction_from_animation(animated_sprite.animation))


func attack(direction: String = "right") -> void:
	super.attack(direction)

	if is_attacking:
		print("Handgun disparou!")