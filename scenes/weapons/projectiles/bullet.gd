class_name Bullet
extends CharacterBody2D

## Proyectil reutilizable e xenérico. Nace na boca do cano, viaxa en liña recta
## e libérase ao colidir ou superar a distancia máxima.
## É independiente do Player despois de crearse.
## A textura, o dano e a distancia máxima chegan da Weapon en setup().

@export var speed: float = 280.0

# Cargados pola Weapon en setup() (non son globais).
var damage: int = 0
var max_distance: float = 0.0

var direction := Vector2.RIGHT
var _traveled := 0.0
var _active := false

@onready var body_sprite: Sprite2D = $Sprite

# Corpo que disparou esta bala (excepción de colisión para non ferirse).
var _shooter: CharacterBody2D = null

## Prepara a bala cando a Weapon a instancia no MuzzlePoint.
## A textura, a distancia máxima e quen a disparou (corpo pai) proveñen da arma.
## shooter serve para engadir unha excepción de colisión: a bala non debe
## colidir co corpo que a creou (o Player), aínda que naza moi preto del.
func setup(initial_position: Vector2, aim_dir: Vector2, shot_damage: int, bullet_texture: Texture2D, proj_max_distance: float, shooter: CharacterBody2D = null) -> void:
    position = initial_position
    direction = aim_dir.normalized()
    damage = shot_damage
    max_distance = proj_max_distance
    if bullet_texture and body_sprite:
        body_sprite.texture = bullet_texture
    _traveled = 0.0
    if shooter:
        _shooter = shooter
        add_collision_exception_with(shooter)
    _active = true
    update_sprite_rotation()

func _physics_process(delta: float) -> void:
    if not _active:
        return

    _traveled += speed * delta
    if _traveled >= max_distance:
        queue_free()
        return

    # Detecta colision directa da bala (é un CharacterBody2D).
    var collision := move_and_collide(direction * speed * delta)
    if collision:
        var hit := collision.get_collider()
        print("Bala impacto contra: " + (hit.name if hit else "obstáculo"))
        queue_free()
        return

    update_sprite_rotation()

## Rota/voltea o sprite para que a bala apunte cara a onde vai.
func update_sprite_rotation() -> void:
    if not body_sprite:
        return
    if direction.y < 0:
        body_sprite.flip_h = false
        body_sprite.rotation = -PI / 2.0
    elif direction.y > 0:
        body_sprite.flip_h = false
        body_sprite.rotation = PI / 2.0
    else:
        body_sprite.flip_h = direction.x < 0
        body_sprite.rotation = 0

func _exit_tree() -> void:
    if _shooter:
        remove_collision_exception_with(_shooter)
        _shooter = null
