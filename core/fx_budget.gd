extends RefCounted
## Сколько одновременно может гореть ламп и лежать подпалин от взрывов и огня. В большом бою
## взрывов десятки в секунду; если каждому давать свою лампу и декаль, их набираются сотни и игра
## начинает тормозить. Сверх лимита эффект просто обходится без лампы или подпалины — на глаз
## разницы нет, они и так перекрывают друг друга.

const FxBudget := preload("res://core/fx_budget.gd")

const LIGHTS_MAX := 12
const DECALS_MAX := 36
## Взрывов в полную силу одновременно (дым столбом, кольцо песка, обломки). Остальные — облегчённые:
## вспышка и огненные клубы. В гуще боя их всё равно не различить, а дым от десятков взрывов
## слоями заливает экран и съедает видеокарту.
const EXPLOSIONS_FULL := 7

static var _lights := 0
static var _decals := 0
static var _explosions := 0
## Детальность частиц (дым, искры, следы ракет): 1 — полная, меньше — частиц меньше.
static var detail := 1.0
static var _lights_max := LIGHTS_MAX
static var _explosions_max := EXPLOSIONS_FULL
static var _decals_max := DECALS_MAX
static var _lite := -1


## Запасной рендер (OpenGL — старые и встроенные видеокарты без Vulkan/DirectX 12): там каждая
## система частиц дорога, а лампы рисуются отдельными проходами. Украшения из частиц (дым и песок
## взрывов, следы снарядов, гильзы, искры, щепки) не показываются; пламя, огонь и умения остаются.
static func lite() -> bool:
	if _lite < 0:
		_lite = 0 if RenderingServer.get_current_rendering_method() == "forward_plus" else 1
	return _lite == 1


## Украшение из частиц: на запасном рендере прячется (спрятанные частицы ничего не стоят).
static func cosmetic(p: GPUParticles3D) -> GPUParticles3D:
	if lite():
		p.visible = false
	return p


## Качество графики (settings.gd) и нижние ступени авто-качества: меньше частиц, ламп, взрывов.
static func set_detail(quality: int, bare: bool) -> void:
	detail = [0.3, 0.45, 0.75, 1.0][quality] * (0.6 if bare else 1.0)
	_lights_max = [0, 4, 8, LIGHTS_MAX][quality] / (2 if bare else 1)
	_explosions_max = maxi([2, 3, 5, EXPLOSIONS_FULL][quality] - (1 if bare else 0), 1)
	_decals_max = [12, 24, DECALS_MAX, DECALS_MAX][quality]
	if lite():
		_lights_max = mini(_lights_max, 2)


## Число частиц с учётом детальности (не меньше одной).
static func amount(n: int) -> int:
	return maxi(1, int(round(n * detail)))


static func take_explosion() -> bool:
	if _explosions >= _explosions_max:
		return false
	_explosions += 1
	return true


static func free_explosion() -> void:
	_explosions = maxi(_explosions - 1, 0)


static func take_light() -> bool:
	if _lights >= _lights_max:
		return false
	_lights += 1
	return true


static func free_light() -> void:
	_lights = maxi(_lights - 1, 0)


static func take_decal() -> bool:
	if _decals >= _decals_max:
		return false
	_decals += 1
	return true


static func free_decal() -> void:
	_decals = maxi(_decals - 1, 0)


## Новая сцена — счёт с нуля (эффекты прошлой сцены уже удалены).
static func reset() -> void:
	_lights = 0
	_decals = 0
	_explosions = 0
