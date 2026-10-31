-- Installe le contenu importé (dossier Workspace.MimicImport) dans les services du lieu ouvert
-- depuis Roblox, en remplaçant l'ancien contenu (V0.3.2, déploiement de l'expérience privée de
-- test). À coller dans la barre de commande de Studio, puis publier (Alt+P).
-- Le jeu ne contient que du code : la carte est générée au démarrage du serveur.
local import = workspace:FindFirstChild("MimicImport")
assert(import, "Workspace.MimicImport absent : importer d'abord le modèle")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local targets = {
	Shared = RS,
	Server = SSS,
	Client = SPS,
	DataStoreCheck = SSS,
}
-- Ancien contenu (y compris le contrôle DataStore s'il n'est pas réimporté).
for _, name in { "Shared", "Server", "Client", "DataStoreCheck" } do
	for _, parent in { RS, SSS, SPS } do
		local old = parent:FindFirstChild(name)
		if old and old.Parent ~= import then
			old:Destroy()
		end
	end
end
for _, child in import:GetChildren() do
	child.Parent = targets[child.Name] or error("élément inattendu : " .. child.Name)
end
import:Destroy()
-- Pas de Lighting.Technology ici : la barre de commande n'a pas le droit de l'écrire, et une
-- erreur fait annuler toute la commande par Studio (déjà réglé à Voxel à la création du lieu).
workspace.StreamingEnabled = false
print("INSTALLÉ", SSS:FindFirstChild("Server") ~= nil, RS:FindFirstChild("Shared") ~= nil, SPS:FindFirstChild("Client") ~= nil, "contrôle DataStore :", SSS:FindFirstChild("DataStoreCheck") ~= nil)
