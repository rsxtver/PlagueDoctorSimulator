-- Script: ServerScriptService -> MainServer
-- Точка входа сервера: запускает все сервисы по порядку.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local InfectedService = require(Services:WaitForChild("InfectedService"))
local PharmacyService = require(Services:WaitForChild("PharmacyService"))
local UpgradeService = require(Services:WaitForChild("UpgradeService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local PetService = require(Services:WaitForChild("PetService"))
local AuraService = require(Services:WaitForChild("AuraService"))
local DoctorService = require(Services:WaitForChild("DoctorService"))

DataService.Init()
InfectedService.Init()
PharmacyService.Init()
UpgradeService.Init()
RebirthService.Init()
PetService.Init()
AuraService.Init()
DoctorService.Init()

print("[MainServer] Plague Doctor Simulator: сервер запущен")
