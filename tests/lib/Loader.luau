--[[
	Loader — charge les modules du jeu dans Lune, sans Roblox.

	Simule le strict nécessaire pour la logique pure :
	- `script` : une fausse Instance dont `.Parent` et les enfants
	  correspondent aux dossiers et fichiers .luau du projet ;
	- `require(instance)` : charge le fichier correspondant (avec cache) ;
	- `game:GetService("ReplicatedStorage").Shared` : pointe vers src/shared.

	Un module qui utilise une autre API Roblox échouera volontairement ici :
	c'est le signe qu'il n'est pas « pur » et qu'il doit être testé dans Studio.
	Les tests doivent être lancés depuis la racine du projet.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Loader = {}

-- Les fonctions de @lune/fs peuvent céder la main (yield), ce qui est interdit
-- dans un métaméthode __index : on indexe donc tout src/ une fois pour toutes.
local sources: { [string]: string } = {}
local folders: { [string]: boolean } = {}

local function indexTree(dir: string)
	folders[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			indexTree(path)
		elseif string.match(name, "%.luau$") then
			sources[string.gsub(path, "%.luau$", "")] = fs.readFile(path)
		end
	end
end
indexTree("src")

local nodeCache: { [string]: any } = {}
local moduleCache: { [string]: any } = {}
local loading: { [string]: boolean } = {}

local makeNode: (path: string, kind: string) -> any
local fakeGame: any
local loadModule: (node: any) -> any

local function childOf(path: string, name: string): any
	local childPath = path .. "/" .. name
	if sources[childPath] then
		return makeNode(childPath, "module")
	end
	if folders[childPath] then
		return makeNode(childPath, "folder")
	end
	return nil
end

local function finder(path: string, strict: boolean)
	return function(_self: any, name: string)
		local child = childOf(path, name)
		if child == nil and strict then
			error(string.format("Loader : WaitForChild('%s') introuvable dans %s", name, path), 2)
		end
		return child
	end
end

makeNode = function(path: string, kind: string): any
	local cached = nodeCache[path]
	if cached then
		return cached
	end
	local node = { __path = path, __kind = kind }
	setmetatable(node, {
		__index = function(_self, key)
			if key == "Parent" then
				local parent = string.match(path, "^(.*)/[^/]+$")
				return if parent then makeNode(parent, "folder") else nil
			elseif key == "Name" then
				return string.match(path, "([^/]+)$")
			elseif key == "WaitForChild" then
				return finder(path, true)
			elseif key == "FindFirstChild" then
				return finder(path, false)
			end
			local child = childOf(path, key)
			if child == nil then
				error(string.format("Loader : '%s' introuvable dans %s", tostring(key), path), 2)
			end
			return child
		end,
		__tostring = function()
			return path
		end,
	})
	nodeCache[path] = node
	return node
end

local function virtualService(children: { [string]: any }): any
	local service = {}
	setmetatable(service, {
		__index = function(_self, key)
			if key == "WaitForChild" or key == "FindFirstChild" then
				return function(_s, name)
					return children[name]
				end
			end
			local child = children[key]
			if child == nil then
				error("Loader : service simulé sans enfant " .. tostring(key), 2)
			end
			return child
		end,
	})
	return service
end

local services = {
	ReplicatedStorage = virtualService({ Shared = makeNode("src/shared", "folder") }),
}

fakeGame = {
	GetService = function(_self, name: string)
		local service = services[name]
		if service == nil then
			error("Loader : service Roblox non simulé : " .. name, 2)
		end
		return service
	end,
}

loadModule = function(node: any): any
	if type(node) ~= "table" or rawget(node, "__kind") ~= "module" then
		error("Loader : require() attend un ModuleScript simulé, reçu " .. tostring(node), 2)
	end
	local path = rawget(node, "__path")
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	if loading[path] then
		error("Loader : dépendance circulaire sur " .. path, 2)
	end
	loading[path] = true
	local source = assert(sources[path], "Loader : source introuvable " .. path)
	local chunk = luau.load(source, {
		debugName = path,
		environment = { script = node, require = loadModule, game = fakeGame },
	})
	local result = chunk()
	loading[path] = nil
	moduleCache[path] = result
	return result
end

function Loader.shared(relativePath: string): any
	return loadModule(makeNode("src/shared/" .. relativePath, "module"))
end

function Loader.server(relativePath: string): any
	return loadModule(makeNode("src/server/" .. relativePath, "module"))
end

-- Compile un fichier (vérification de syntaxe uniquement, sans l'exécuter).
function Loader.compile(path: string): (boolean, string?)
	local source = fs.readFile(path)
	local ok, err = pcall(luau.compile, source)
	return ok, if ok then nil else tostring(err)
end

return Loader
