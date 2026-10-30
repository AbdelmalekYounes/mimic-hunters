--[[
	Lanceur des tests unitaires (logique pure).

	Usage, depuis la racine du projet :
		lune run tests/run            -- tous les tests
		lune run tests/run capture    -- seulement les fichiers contenant « capture »
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local TestKit = require("./lib/TestKit")

local filter = process.args[1]

local files = fs.readDir("tests/specs")
table.sort(files)

local count = 0
for _, file in files do
	if string.match(file, "%.spec%.luau$") and (filter == nil or string.find(file, filter, 1, true)) then
		count += 1
		TestKit.setFile(file)
		local name = string.gsub(file, "%.luau$", "")
		require("./specs/" .. name)
	end
end

if count == 0 then
	print("Aucun fichier de test trouvé.")
	process.exit(1)
end

local ok = TestKit.run()
process.exit(if ok then 0 else 1)
