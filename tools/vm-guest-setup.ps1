<#
.SYNOPSIS
	Préparation unique de la VM de test MIMIC HUNTERS (à lancer DANS la VM, en administrateur).

.DESCRIPTION
	Ne modifie que la machine virtuelle :
	  - installe Git (winget) et Rokit (version officielle GitHub) s'ils manquent ;
	  - vérifie la présence de Roblox Studio (son installation et la connexion restent manuelles) ;
	  - désactive la mise en veille et l'extinction de l'écran de la VM (sinon le rendu s'arrête) ;
	  - copie l'agent dans C:\MimicTests\agent et l'enregistre au démarrage de session.

.EXAMPLE
	powershell -ExecutionPolicy Bypass -File "\\vmware-host\Shared Folders\mimic-exchange\setup\vm-guest-setup.ps1"
#>
param(
	[string]$Exchange = "\\vmware-host\Shared Folders\mimic-exchange"
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
	[Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "Lancer ce script en administrateur, dans la VM." }
if ((Get-CimInstance Win32_ComputerSystem).Model -notmatch "VMware") {
	throw "Ce script est prévu pour la VM VMware de test, pas pour une machine physique (modèle : $((Get-CimInstance Win32_ComputerSystem).Model))."
}

function Step($text) { Write-Host "`n▶ $text" }

Step "Git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
	winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
} else { Write-Host "déjà présent : $(git --version)" }

Step "Rokit"
$rokitBin = Join-Path $env:USERPROFILE ".rokit\bin"
if (-not (Test-Path (Join-Path $rokitBin "rokit.exe"))) {
	$release = Invoke-RestMethod "https://api.github.com/repos/rojo-rbx/rokit/releases/latest"
	$asset = $release.assets | Where-Object { $_.name -match "windows-x86_64\.zip$" } | Select-Object -First 1
	if (-not $asset) { throw "Archive Windows de Rokit introuvable dans la dernière version." }
	$zip = Join-Path $env:TEMP $asset.name
	Invoke-WebRequest $asset.browser_download_url -OutFile $zip
	$dir = Join-Path $env:TEMP "rokit-install"
	Expand-Archive $zip $dir -Force
	& (Join-Path $dir "rokit.exe") self-install
	Write-Host "Rokit installé : rouvrir la session pour mettre à jour le PATH."
} else { Write-Host "déjà présent" }

Step "Roblox Studio"
$studio = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions\*\RobloxStudioBeta.exe" -ErrorAction SilentlyContinue
if ($studio) {
	Write-Host "présent : $($studio[0].DirectoryName)"
} else {
	Write-Warning "Roblox Studio absent : l'installer depuis https://create.roblox.com (dans la VM), l'ouvrir une fois et se connecter."
}

Step "Alimentation de la VM (pas de veille, écran toujours actif)"
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

Step "Agent"
$agentDir = "C:\MimicTests\agent"
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot "vm-agent.ps1") $agentDir -Force
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument (
	"-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$agentDir\vm-agent.ps1`" -Exchange `"$Exchange`"")
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "MimicHuntersAgent" -Action $action -Trigger $trigger -Settings $settings `
	-Description "Agent de tests MIMIC HUNTERS (session interactive, pour que Studio puisse s'afficher)" -Force | Out-Null
Write-Host "Tâche planifiée « MimicHuntersAgent » enregistrée (démarre à l'ouverture de session de $env:USERNAME)."

Write-Host "`nÉtapes manuelles restantes dans la VM :"
Write-Host "  1. Ouverture de session automatique de ce compte (netplwiz ou Sysinternals Autologon)."
Write-Host "  2. Ouvrir Roblox Studio une fois et se connecter."
Write-Host "  3. Redémarrer la VM : l'agent démarre seul à l'ouverture de session."
