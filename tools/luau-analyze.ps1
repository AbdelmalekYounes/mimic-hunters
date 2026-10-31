<#
.SYNOPSIS
	Analyse de types Luau (--!strict) de src avec luau-lsp.

.DESCRIPTION
	1. Télécharge, si absentes, les définitions Roblox publiées avec la version de luau-lsp
	   épinglée dans rokit.toml (build/luau-lsp/globalTypes-<version>.d.luau).
	2. Génère la carte des fichiers Rojo (sourcemap) pour résoudre les require.
	3. Lance `luau-lsp analyze` sur src ; code de sortie 1 s'il reste des erreurs de type.

	Solveur de types par défaut de luau-lsp (l'ancien) : le nouveau solveur produit encore
	beaucoup de faux positifs sur ce code. Dernière ligne : « N erreur(s) de type ».
#>
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root "build\luau-lsp"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$pin = Select-String -Path (Join-Path $Root "rokit.toml") -Pattern 'luau-lsp\s*=\s*"JohnnyMorganz/luau-lsp@([\d.]+)"'
if (-not $pin) { throw "luau-lsp n'est pas épinglé dans rokit.toml" }
$version = $pin.Matches[0].Groups[1].Value
$defs = Join-Path $Out "globalTypes-$version.d.luau"
if (-not (Test-Path $defs)) {
	$url = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$version/scripts/globalTypes.d.luau"
	Write-Host "Téléchargement des définitions Roblox ($version)…"
	Invoke-WebRequest -UseBasicParsing $url -OutFile $defs
}

$sourcemap = Join-Path $Out "sourcemap.json"
& rojo sourcemap (Join-Path $Root "default.project.json") -o $sourcemap | Out-Null
if ($LASTEXITCODE -ne 0) { throw "rojo sourcemap a échoué" }

Push-Location $Root
# luau-lsp écrit ses messages [INFO] sur stderr : sous PowerShell 5.1 avec « Stop », ils
# deviendraient des erreurs bloquantes.
$ErrorActionPreference = "Continue"
try {
	$lines = & luau-lsp analyze "--definitions=$defs" "--sourcemap=$sourcemap" --no-strict-dm-types src 2>&1 |
		ForEach-Object { "$_" }
} finally {
	Pop-Location
}
# Un module requis depuis plusieurs scripts est signalé plusieurs fois : on dédoublonne.
$errors = @($lines | Where-Object { $_ -match "(TypeError|SyntaxError)" } | Sort-Object -Unique)
$errors | ForEach-Object { Write-Host $_ }
Write-Host ("{0} erreur(s) de type" -f $errors.Count)
if ($errors.Count -gt 0) { exit 1 }
exit 0
