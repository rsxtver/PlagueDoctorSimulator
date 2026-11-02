-- ModuleScript: ServerScriptService -> Services -> Notify
-- Всплывающие сообщения игроку (показывает HUD на клиенте).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent

-- kind: "info" | "good" | "warn" — влияет на цвет сообщения
return function(player: Player, text: string, kind: string?)
	remote:FireClient(player, text, kind or "info")
end
