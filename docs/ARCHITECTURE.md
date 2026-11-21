# Архитектура (Phase 0)

Документ обновляется в конце каждой фазы.

## Обзор

Игра на **Godot 4.5.1** (GDScript), один проект = клиент + (в будущем) выделенный
сервер из headless-экспорта. Рендер Forward+ (десктоп). Физика — фиксированный шаг
120 Hz, логика в `_physics_process`; рендер не влияет на симуляцию.

Ключевой принцип master prompt, который мы сохраняем: **модель шин и кузова —
наша собственная**, тюнингуемая. Godot `VehicleBody3D` не используем — он чёрный
ящик. Коллизии отдаём встроенному PhysicsServer3D (в master prompt для этого
планировался Rapier; в Godot встроенный сервер решает ту же задачу).

## Поток данных трассы

```
tracks/*.json  →  track_format (парсер + валидация)  →  track_gen (меш + коллизии)
                →  сцена трассы (TrackRoot)  →  заезд (режим, тайминг)
```

## Поток гонки (Phase 2)

```
race_config.json ─┐
tracks/*.json ────┼→ RaceSession (грид, круги, позиции, DRS-правила, wake)
vehicle.json ─────┤        ↑ состояния машин каждый тик {pos, forward, speed}
                  │   main.gd (режим race; APEX_MODE=tt — Time Trial)
RacingLine ──→ SpeedProfile ──→ AiDriver (×7) ──→ car.external_input
                                игрок ──→ Input Map (+ DRS на E)
```

Трассы — данные, не код. Валидатор (`tracks/validate_tracks.gd`) гоняется в CI и
локально.

## Константы и данные

Все тюнингуемые константы физики — в data-файлах (`assets/data/*.json` начиная с
фазы 1), не в коде. Формулы и единицы — docs/PHYSICS.md.

## Структура каталогов

```
scenes/          сцены (main, car, track, ui)
scripts/         GDScript: track_format, track_gen, vehicle, ai, rules, hud,
                 camera_rig
assets/          процедурные материалы, data-файлы констант
tracks/          JSON-данные трасс + валидатор
tests/           headless-тесты (extends SceneTree, без сторонних плагинов)
docs/            PLAN, ARCHITECTURE, DECISIONS, PHYSICS, KNOWN_ISSUES
```

## Autoload

| Синглтон | Назначение |
|---|---|
| `Settings` | ассисты (тумблеры), качество графики (заготовка фазы 9) |

## Коллизии (Phase 2)

- Слой 1 — трасса (StaticBody3D: дорога — боксовые слэбы по сегментам,
  поребрики/барьеры — trimesh, трава — plane + skirt).
- Слой 2 — машины (RigidBody3D, бокс 1.4×0.5×4.3). Маска машины 1|2:
  трасса + другие машины. Лучи колёс маскируют только слой 1.
- Дорога — боксы, не trimesh: в trimesh находились субметровые щели между
  полосами треугольников (машина проваливалась наполовину).

## Тесты

Headless-скрипты, расширяющие `SceneTree`, запускаются так:

```
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tracks/validate_tracks.gd
```

Никаких сторонних тестовых плагинов — меньше зависимостей, детерминированный
выходной код для CI.

## CI (GitHub Actions)

Задача `lint`: gdformat --check + gdlint (gdtoolkit).
Задача `test`: headless-импорт, валидатор трасс, smoke-тесты на Godot 4.5.1
(linux).

## Что появится позже (не реализуем заранее)

- Фаза 2: `scripts/ai/` — гоночная линия, профили сложности.
- Фаза 3: `scripts/net/` — транспорт, снапшоты, предсказание; headless-сервер.
- Фаза 5: `scripts/damage/`, пит-лейн в данных трассы.
- Фаза 6: `scripts/weather/` — seeded-погода, влажность по сегментам.

Места под них архитектурой оставлены (данные трассы уже JSON, физика уже
data-driven), код не пишем до своих фаз.
