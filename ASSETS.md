# Ассеты и лицензии

Правило master prompt: всё art/audio — процедурное, самодельное или CC0/перmissive.
Каждый внешний ассет обязан быть в этой таблице. Если ассета нет в таблице — его
нельзя коммитить.

| Ассет | Тип | Источник | Лицензия |
|---|---|---|---|
| `icon.svg` | иконка проекта | самодельный SVG | MIT (часть проекта) |
| материалы/небо в `main.tscn` | процедурные | ProceduralSkyMaterial Godot | MIT (часть проекта) |
| `assets/models/car/low_poly_f1.glb` | low-poly болид F1 (12.6k tris, 6 материалов, без текстур) | Sketchfab: «Low Poly-F1» by salasilma13 — https://sketchfab.com/3d-models/low-poly-f1-0ac02bfa81f64549be15acaa78f36f29 | CC-BY 4.0 — http://creativecommons.org/licenses/by/4.0/ |
| `assets/models/environment/endurance_run.glb` + `endurance_run_N.png` | low-poly сцена окружения (18.6k tris, 72 текстуры) | Sketchfab: «endurance run - road trip adventure» by amogusstrikesback2 — https://sketchfab.com/3d-models/endurance-run-road-trip-adventure-5e1a4b70baa241959b72ae12fec1253d | CC-BY 4.0 — http://creativecommons.org/licenses/by/4.0/ |
| `assets/ui/fonts/TitilliumWeb-*.ttf` | шрифт UI (меню/HUD; ближайший свободный аналог шрифта F1 Display) | Google Fonts: Titillium Web — https://fonts.google.com/specimen/Titillium+Web (исходники: github.com/google/fonts, ofl/titilliumweb) | SIL OFL 1.1 — `assets/ui/fonts/OFL.txt` |
| `assets/ui/controls/btn_*.png` | текстуры экранных кнопок (диск + белая иконка, normal/pressed — собрано скриптом) | базовые иконки: Kenney «Mobile Controls» (icon_pedal, icon_pedal_brake, icon_arrow, icon_pause) — https://kenney.nl/assets/mobile-controls | CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/ |
| `assets/ui/controls/btn_nitro*.png` | иконка нитро-баллона на кнопке | game-icons.net: «bottled bolt» by Lorc — https://game-icons.net/1x1/lorc/bottled-bolt.html | CC-BY 3.0 — http://creativecommons.org/licenses/by/3.0/ |
| `assets/audio/engine/engine_0..5.wav` | 6 бесшовных лупов двигателя по полосам RPM (кроссфейд в RaceAudio; обработка: шов-кроссфейд, 44.1 кГц, нормализация RMS) | OpenGameArt: «racing car engine sound loops» by domasx2 — https://opengameart.org/content/racing-car-engine-sound-loops | CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/ |
| `assets/audio/tires/skid_loop.wav` | луп визга шин (по слипу колёс; обработка: шов-кроссфейд, ресемплинг 44.1 кГц) | OpenGameArt: «Car tire squeal skid loop» by audible-edge (Tom Haigh) — https://opengameart.org/content/car-tire-squeal-skid-loop | CC-BY 3.0 — атрибуция в этой таблице обязательна при распространении |
| `assets/audio/nitro/nitro_loop.wav` | луп тяги нитро (thrusterFire_002, обработка: обрезка ровного куска 2.6 с + шов-кроссфейд) | Kenney «Sci-Fi Sounds» — https://kenney.nl/assets/sci-fi-sounds | CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/ |
| `assets/audio/crash/crash_1..2.ogg` | удары металла при контакте корпуса (impactMetal_heavy_001, impactPlate_heavy_000; пик −3 дБ) | Kenney «Impact Sounds» — https://kenney.nl/assets/impact-sounds | CC0 1.0 |
| `assets/audio/ui/*.ogg` | клик/назад/открыть/закрыть/тумблер/выбор + бипы старт-огней (click_002, back_002, open_001, close_001, switch_002, select_002, bong_001, confirmation_001) | Kenney «Interface Sounds» — https://kenney.nl/assets/interface-sounds | CC0 1.0 |
| `assets/audio/music/jingle_win.ogg` | финишный джингл (Hit jingles, HIT01; пик −3 дБ) | Kenney «Music Jingles» — https://kenney.nl/assets/music-jingles | CC0 1.0 |
| `assets/audio/music/menu_loop.ogg` | луп фоновой музыки главного меню (~154 с, синтовый грув; обработка: проверка швов лупа, громкость −6 дБ) | OpenGameArt: «Menu Music» by wipics — https://opengameart.org/content/menu-music-1 | CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/ |

Примечания:
- Кнопки управления (`btn_*.png`) — композиты: полупрозрачный тёмный диск + белая
  иконка; pressed-вариант — диск F1-красного цвета. Генерация:
  `scripts/gen_controls_textures.py` (вне репозитория, CairoSVG + Pillow).
- Kenney-пак CC0 — атрибуция не обязательна, но указана из уважения.
- CC-BY 3.0 (bottled bolt, Lorc; визг шин, audible-edge): атрибуция в этой
  таблице обязательна при распространении игры.
- Модели, которых нет в таблице, коммитить нельзя. Звуки — только CC0/CC-BY
  с источником в этой таблице (фаза 9 закрыта в 0.5.0).
