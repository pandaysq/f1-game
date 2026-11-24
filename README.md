# Apex GP

Open-wheel racing game for friend leagues (working title). Fictional teams,
drivers and tracks only — no real-world brands.

**Engine:** Godot 4.5.1 · **Target:** mobile (Android/iOS, Mobile renderer) ·
**License:** MIT · **Roadmap:** [docs/PLAN.md](docs/PLAN.md)

[![CI](https://github.com/pandaysq/f1-game/actions/workflows/ci.yml/badge.svg)](https://github.com/pandaysq/f1-game/actions/workflows/ci.yml)

## Что это

Гонка с открытыми колёсами для дружеских лиг. Сейчас (Phase 0) — каркас проекта;
далее по роадмапу: одиночный Time Trial → гонки против AI → онлайн-лиги →
зрители/комментатор → шины/пит-стопы/повреждения → погода → правила/стюарды →
сетапы/бюджеты → полировка.

## Быстрый старт

1. Скачай Godot 4.5.1: https://godotengine.org/download
2. Открой папку проекта в Godot (файл `project.godot`)
3. Нажми F5

Управление (раскладка Phase 0, всё через Input Map и ремапится):

| Действие | Клавиши |
|---|---|
| Газ | W / ↑ |
| Тормоз | S / ↓ |
| Руль | A D / ← → |
| Нитро | Shift |
| Переключение передач | Q / E |
| Сброс машины | R |
| Камера (кокпит/chase) | V |
| Пауза | Esc / P |
| Дебаг-оверлей | F3 (скрыт по умолчанию) |

## Интерфейс и управление (0.4.0)

Игра стартует в F1-стиле меню: PLAY / TIME TRIAL / SETTINGS + заглушки
будущих режимов (онлайн, чемпионат, гараж). В настройках — ассисты и пресеты
качества (low/medium/high: MSAA + разрешение 3D), всё сохраняется в
`user://settings.cfg`. На телефоне поверх кнопок — экранные: стрелки руления
слева, педали газа/тормоза и нитро справа, пауза сверху. Метод рендера задан
явно (`mobile`), лимитов FPS в коде нет.

## Разработка

Структуру, поток данных и планы расширения — [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Все решения — [docs/DECISIONS.md](docs/DECISIONS.md). Физика —
[docs/PHYSICS.md](docs/PHYSICS.md). Известные проблемы —
[docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

Тесты и проверки headless (нужен Godot 4.5.1 в PATH или замените путь):

```sh
godot --headless --path . --script res://tests/run_tests.gd          # smoke-тесты
godot --headless --path . --script res://tracks/validate_tracks.gd   # валидатор трасс
```

Форматирование GDScript (gdtoolkit):

```sh
pip install gdtoolkit==4.*
gdformat -i scripts tests tracks
gdlint scripts tests tracks
```

CI прогоняет всё это на каждый push (GitHub Actions).

## Лицензия

Код — MIT (см. LICENSE). Ассеты — процедурные/самодельные, реестр — ASSETS.md.
