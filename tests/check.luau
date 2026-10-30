--[[
	Vérification de syntaxe : compile (sans exécuter) chaque fichier .luau
	de src/, y compris les scripts qui dépendent de Roblox.

	Usage, depuis la racine du projet :  lune run tests/check
	Limite : ne vérifie ni les types (--!strict) ni l'API Roblox.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local checked, failed = 0, 0

local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.match(name, "%.luau$") then
			checked += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print("✗ " .. path .. "\n    " .. tostring(err))
			end
		end
	end
end

walk("src")
print(string.format("%d fichier(s) compilé(s), %d erreur(s)", checked, failed))
process.exit(if failed == 0 then 0 else 1)
