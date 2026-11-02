#!/usr/bin/env python3
"""Generates Install.luau from default.project.json and src/.

Install.luau is pasted into the Roblox Studio Command Bar and creates (or updates)
every folder, part and script of the game. Run after changing anything in src/:

    python3 tools/build_installer.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "default.project.json"
OUTPUT = ROOT / "Install.luau"

SERVICES = {
    "ReplicatedStorage", "ServerScriptService", "ServerStorage", "Workspace",
    "StarterGui", "StarterPlayer", "StarterPack", "Lighting", "SoundService",
}


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    # A newline right after the opening bracket is dropped by Lua, so add one
    # to keep the first line of the source intact.
    return f"[{eq}[\n{text}]{eq}]"


def lua_value(name: str, value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list) and len(value) == 3:
        ctor = "Color3.new" if name == "Color" else "Vector3.new"
        return f"{ctor}({', '.join(repr(v) for v in value)})"
    if isinstance(value, str):
        if name == "Material":
            return f"Enum.Material.{value}"
        return json.dumps(value, ensure_ascii=False)
    raise ValueError(f"Unsupported property {name}={value!r}")


def script_class(path: Path) -> tuple[str, str]:
    name = path.name
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if name.endswith(suffix):
            return name[: -len(suffix)], cls
    raise ValueError(f"Unknown script type: {path}")


class Emitter:
    def __init__(self):
        self.lines: list[str] = []
        self.counter = 0

    def var(self) -> str:
        self.counter += 1
        return f"N[{self.counter}]"

    def emit_path(self, parent_var: str, name: str | None, path: Path):
        if path.is_dir():
            v = self.var()
            self.lines.append(f'{v} = ensure({parent_var}, "{name or path.name}", "Folder")')
            for child in sorted(path.iterdir()):
                self.emit_path(v, None, child)
        else:
            script_name, cls = script_class(path)
            v = self.var()
            source = path.read_text(encoding="utf-8")
            self.lines.append(f'{v} = ensure({parent_var}, "{name or script_name}", "{cls}")')
            self.lines.append(f"setSource({v}, {long_string(source)})")

    def emit_node(self, parent_var: str, name: str, node: dict):
        if "$path" in node:
            self.emit_path(parent_var, name, ROOT / node["$path"])
            return
        if parent_var == "game" and name in SERVICES:
            v = self.var()
            self.lines.append(f'{v} = game:GetService("{name}")')
        else:
            v = self.var()
            cls = node.get("$className", "Folder")
            props = node.get("$properties", {})
            if props:
                body = ", ".join(f"{k} = {lua_value(k, val)}" for k, val in props.items())
                self.lines.append(f'{v} = ensure({parent_var}, "{name}", "{cls}", {{ {body} }})')
            else:
                self.lines.append(f'{v} = ensure({parent_var}, "{name}", "{cls}")')
        for child_name, child in node.items():
            if not child_name.startswith("$"):
                self.emit_node(v, child_name, child)


HEADER = """-- =============================================================
-- Plague Doctor Simulator — АВТОУСТАНОВЩИК
-- Сгенерирован tools/build_installer.py, вручную не редактировать.
--
-- Как использовать:
--   1. Roblox Studio -> вкладка View -> Command Bar
--   2. Вставьте ВЕСЬ этот файл в Command Bar и нажмите Enter
--   3. Все папки, парты и скрипты появятся в Explorer
--
-- Повторный запуск безопасен: недостающее создаётся, код скриптов
-- обновляется до актуальной версии, ничего не дублируется.
-- Отменить установку: Ctrl+Z.
-- =============================================================

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local recording = ChangeHistoryService:TryBeginRecording("Install Plague Doctor Simulator")
local created, updated = 0, 0
local N = {} -- созданные объекты (таблица, а не locals: у Luau лимит 200 локальных)

local function ensure(parent: Instance, name: string, className: string, props: { [string]: any }?): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		warn(`[Installer] {existing:GetFullName()} имеет тип {existing.ClassName}, нужен {className}. Старый объект переименован в {name}_old`)
		existing.Name = name .. "_old"
	end
	local instance = Instance.new(className)
	instance.Name = name
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
	instance.Parent = parent
	created += 1
	return instance
end

local function setSource(script: Instance, source: string)
	local luaScript = script :: LuaSourceContainer
	if (luaScript :: any).Source == source then
		return
	end
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(luaScript, function()
			return source
		end)
	end)
	if not ok then
		(luaScript :: any).Source = source
	end
	updated += 1
end
"""

FOOTER = """
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(`[Installer] Готово! Создано объектов: {created}, обновлено скриптов: {updated}`)
print("[Installer] Не забудьте: Game Settings -> Security -> Enable Studio Access to API Services")
"""


def main():
    project = json.loads(PROJECT.read_text(encoding="utf-8"))
    emitter = Emitter()
    for name, node in project["tree"].items():
        if not name.startswith("$"):
            emitter.emit_node("game", name, node)
    OUTPUT.write_text(HEADER + "\n" + "\n".join(emitter.lines) + "\n" + FOOTER, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
