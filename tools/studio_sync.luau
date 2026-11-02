-- Синхронизация Studio с репозиторием без копипаста (для Claude через MCP execute_luau).
-- 1. В терминале: python3 tools/build_installer.py && python3 tools/studio_bridge.py . /tmp/studio_dump
-- 2. Выполнить этот код в Studio (Edit). HTTP включается только на время запроса.
local HttpService = game:GetService("HttpService")
local was = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local ok, body = pcall(function()
	return HttpService:GetAsync("http://127.0.0.1:34999/Install.luau?" .. os.clock())
end)
HttpService.HttpEnabled = was
assert(ok, body)
assert(loadstring(body))()
