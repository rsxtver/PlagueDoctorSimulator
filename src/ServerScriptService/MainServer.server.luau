-- Script: ServerScriptService -> MainServer
-- Точка входа сервера: запускает все сервисы по порядку.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local InfectedService = require(Services:WaitForChild("InfectedService"))
local PharmacyService = require(Services:WaitForChild("PharmacyService"))

DataService.Init()
InfectedService.Init()
PharmacyService.Init()

print("[MainServer] Plague Doctor Simulator: сервер запущен")
