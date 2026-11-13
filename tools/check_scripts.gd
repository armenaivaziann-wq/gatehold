extends SceneTree
## Проверка: все скрипты проекта компилируются (печатает ошибки разбора).
func _initialize() -> void:
	for path in ["res://weapons/blunderbuss.gd", "res://weapons/shell.gd", "res://effects/explosion.gd",
			"res://mobs/horde.gd", "res://core/main.gd", "res://hero/player.gd", "res://hero/fp_hands.gd", "res://core/waves.gd", "res://ui/hud.gd", "res://weapons/weapon.gd", "res://weapons/flamethrower.gd", "res://effects/fire_patch.gd", "res://ui/menu.gd", "res://core/settings.gd", "res://turrets/turrets.gd", "res://turrets/turret.gd", "res://turrets/turret_projectile.gd", "res://locations/base_builder.gd", "res://mobs/swarm_audio.gd", "res://locations/levels.gd", "res://core/progress.gd", "res://locations/map_builder.gd", "res://weapons/gravigun.gd", "res://effects/black_hole.gd", "res://core/upgrades.gd", "res://ui/upgrade_tree.gd", "res://core/mastery.gd", "res://weapons/minigun.gd", "res://core/fx_budget.gd", "res://audio/music/music.gd", "res://ui/tutorial.gd", "res://hero/hero_abilities.gd", "res://mobs/spears.gd", "res://weapons/launcher_model.gd", "res://turrets/turret_models.gd"]:
		var s: GDScript = load(path)
		print(path, " -> ", "ok" if s and s.can_instantiate() else "ОШИБКА")
	quit()
