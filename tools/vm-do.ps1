<#
.SYNOPSIS
	Hôte : envoie une commande à la télécommande de la VM (tools/vm-remote.ps1) et attend la
	réponse (V0.3.2). La capture d'écran renvoyée est aussi convertie en JPEG réduit.

.EXAMPLE
	tools\vm-do.ps1 -Json '{"actions":[{"type":"windows"}]}'
	tools\vm-do.ps1 -Json '{"actions":[{"type":"click","x":640,"y":400}]}' -Scale 0.5
#>
param(
	[Parameter(Mandatory = $true)][string]$Json,
	[int]$TimeoutSec = 90,
	[double]$Scale = 0.5,
	[string]$OutDir
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
$remote = Join-Path $Root "build\vm-exchange\remote"
New-Item -ItemType Directory -Force -Path $remote | Out-Null
if (-not $OutDir) { $OutDir = Join-Path $Root "build\vm-remote" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$id = Get-Date -Format "yyyyMMddHHmmssfff"
[void]($Json | ConvertFrom-Json) # validation
$tmp = Join-Path $remote "cmd-$id.json.tmp"
[IO.File]::WriteAllText($tmp, $Json, (New-Object Text.UTF8Encoding $false))
Move-Item $tmp (Join-Path $remote "cmd-$id.json")

$res = Join-Path $remote "res-$id.json"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while (-not (Test-Path $res)) {
	if ((Get-Date) -gt $deadline) { throw "Pas de réponse de la VM en $TimeoutSec s (télécommande lancée ?)" }
	Start-Sleep -Milliseconds 300
}
Start-Sleep -Milliseconds 200
$result = Get-Content -Raw -Encoding UTF8 $res | ConvertFrom-Json
$png = Join-Path $remote "shot-$id.png"
$jpg = Join-Path $OutDir "shot-$id.jpg"
if (Test-Path $png) {
	Add-Type -AssemblyName System.Drawing
	$img = [System.Drawing.Image]::FromFile($png)
	$w = [int]($img.Width * $Scale); $h = [int]($img.Height * $Scale)
	$bmp = New-Object System.Drawing.Bitmap $img, $w, $h
	$img.Dispose()
	$bmp.Save($jpg, [System.Drawing.Imaging.ImageFormat]::Jpeg)
	$bmp.Dispose()
	Copy-Item $png (Join-Path $OutDir "shot-$id.png") -Force
	Remove-Item $png -Force -ErrorAction SilentlyContinue
}
Remove-Item $res -Force -ErrorAction SilentlyContinue
Write-Host ("ok={0} écran={1}x{2} erreur={3}" -f $result.ok, $result.screen.width, $result.screen.height, $result.error)
foreach ($line in @($result.output)) { if ($line) { Write-Host "  $line" } }
Write-Host "capture : $jpg (échelle $Scale ; coordonnées VM = pixels / $Scale)"
