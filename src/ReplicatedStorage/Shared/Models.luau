-- ModuleScript: ReplicatedStorage -> Shared -> Models
-- Выдаёт копии 3D-моделей (питомцы, яйцо) из папки ReplicatedStorage.Models.
-- Модели сгенерированы в Studio (generate_procedural_model) и хранятся в репозитории
-- как assets/Models.rbxm. Если папки нет (её не вставили), Build вернёт nil и код
-- покажет простую запасную фигуру.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = {}

local function getFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("Models")
end

-- Копия модели. Все детали заякорены и без коллизий, PrimaryPart — невидимый Root в центре,
-- «перед» модели смотрит в -Z (как у персонажа). nil, если такой модели нет.
function Models.Build(name: string): Model?
	local folder = getFolder()
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	return template:Clone()
end

function Models.Has(name: string): boolean
	local folder = getFolder()
	return folder ~= nil and folder:FindFirstChild(name) ~= nil
end

return Models
