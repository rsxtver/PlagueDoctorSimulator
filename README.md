# Plague Doctor Simulator (Roblox)

## Установка в Roblox Studio (одна вставка)

1. Откройте место в Roblox Studio, включите **View → Command Bar**.
2. Скопируйте **весь** файл [`Install.luau`](Install.luau), вставьте в Command Bar, нажмите **Enter**.
3. Все папки, парты и скрипты появятся в Explorer. Отмена — `Ctrl+Z`.
4. Один раз: **Game Settings → Security → Enable Studio Access to API Services** (нужно для DataStore).

Повторный запуск безопасен: создаётся только недостающее, код скриптов обновляется до актуального.

## Для продвинутых: Rojo

```bash
rojo serve
```

Проект описан в `default.project.json`, код лежит в `src/`.

## Для разработки

`Install.luau` генерируется из `default.project.json` и `src/`:

```bash
python3 tools/build_installer.py
```
