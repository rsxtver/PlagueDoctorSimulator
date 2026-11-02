-- Script: ServerScriptService -> MainServer
-- Точка входа сервера: запускает все сервисы по порядку.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))

DataService.Init()

print("[MainServer] Plague Doctor Simulator: сервер запущен")
