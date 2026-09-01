extends Node2D

## Teste da oclusão dos props de natureza (Bug 2).
##
## A janela de oclusão deve derivar do tamanho REAL de cada sprite (largura/altura
## em px, escalados), e não de constantes fixas em tiles. Regras travadas aqui:
##   - Player ao norte, DENTRO da largura da copa  -> prop translúcido (occluded).
##   - Player ao norte, FORA da largura da copa    -> prop opaco (era o Bug 2:
##     a janela antiga de ±32px translucida props com copa de 15–39px).
##   - Player ao sul (na frente) do prop           -> sempre opaco.
##   - Player ao norte, acima do topo da copa      -> opaco.
##   - Prop não-occludable                          -> nunca fica translúcido.

const PropScript: GDScript = preload("res://worlds/chunks/nature_prop.gd")
const MARGIN: float = 2.0  # OCCLUDE_MARGIN_PX em nature_prop.gd

var _failures: Array[String] = []


func _ready() -> void:
	# Tree_5_Big_Green: 34x52 px -> copa x em [-17, +17], y em [-52, 0].
	await _run_cases("res://assets/props/Objects/Nature/Green/Tree_5_Big_Green.png", 34.0, 52.0)
	# Bush_1_Green: 15x13 px -> arbusto BAIXO: quase nada deveria translucir.
	await _run_cases("res://assets/props/Objects/Nature/Green/Bush_1_Green.png", 15.0, 13.0)
	_finish()


func _run_cases(tex_path: String, w: float, h: float) -> void:
	var tex: Texture2D = load(tex_path)
	if tex == null:
		_failures.append("textura não carregou: " + tex_path)
		return
	var half_w: float = w * 0.5 + MARGIN

	var prop: Node2D = PropScript.new()
	prop.set("texture", tex)
	prop.set("solid", false)
	prop.set("occludable", true)
	add_child(prop)
	prop.global_position = Vector2(1000, 1000)
	prop.set("scale", Vector2.ONE)
	await get_tree().process_frame
	await get_tree().process_frame

	# Dentro da copa, atrás (norte) -> translúcido.
	var dy_in := minf(20.0, h * 0.5)
	_check(prop, Vector2(1000, 1000 - dy_in), true, tex_path + ": dentro da copa ao norte")
	# Fora da largura da copa, atrás -> OPACO (regressão do Bug 2).
	_check(prop, Vector2(1000 + half_w + 6.0, 1000 - dy_in), false,
			tex_path + ": ao lado, fora da copa")
	# Na frente (sul) -> opaco.
	_check(prop, Vector2(1000, 1000 + 10), false, tex_path + ": na frente (sul)")
	# Muito ao norte, acima do topo da copa -> opaco.
	_check(prop, Vector2(1000, 1000 - h - 10.0), false, tex_path + ": acima do topo da copa")
	# Limite exato da largura (dentro da silhueta) -> translúcido.
	_check(prop, Vector2(1000 + w * 0.5, 1000 - h * 0.5), true,
			tex_path + ": na borda da copa ao norte")

	prop.queue_free()
	await get_tree().process_frame

	# Prop não-occludable nunca transluz.
	var plain: Node2D = PropScript.new()
	plain.set("texture", tex)
	plain.set("solid", true)
	plain.set("occludable", false)
	add_child(plain)
	plain.global_position = Vector2(2000, 2000)
	await get_tree().process_frame
	_check(plain, Vector2(2000, 2000 - 20), false, "occludable=false: nunca transluz")
	plain.queue_free()
	await get_tree().process_frame


func _check(prop: Node, player_foot: Vector2, expected: bool, label: String) -> void:
	prop.call("_update_occlusion", player_foot)
	var occluded: bool = prop.get("_occluded")
	if occluded != expected:
		_failures.append(label + " -> esperado occluded=" + str(expected)
				+ ", obtido " + str(occluded)
				+ " (pés do player em " + str(player_foot) + ")")


func _finish() -> void:
	if _failures.is_empty():
		print("=== NATURE PROP OCCLUSION TEST OK ===")
	else:
		print("=== NATURE PROP OCCLUSION TEST ERROS ===")
		for f in _failures:
			print(" - " + f)
	get_tree().quit(1 if _failures.size() > 0 else 0)
