<#
.SYNOPSIS
	Lance les tests Studio VISIBLES dans la VM de test, sans rien afficher sur ton bureau.

.DESCRIPTION
	1. Démarre la VM VMware sans fenêtre (vmrun start <vmx> nogui) si elle ne tourne pas.
	2. Dépose une copie du projet (fichiers suivis + non ignorés) dans le dossier d'échange.
	3. Attend que l'agent de la VM écrive done.json, puis affiche le résultat.
	4. Met la VM en veille si c'est ce script qui l'a démarrée (sauf -KeepRunning).

	Aucun identifiant n'est utilisé : vmrun ne sert qu'à démarrer et suspendre la VM,
	la communication passe par le dossier partagé VMware « mimic-exchange ».

.EXAMPLE
	test-vm.cmd -Vmx "E:\VMs\MimicTests\MimicTests.vmx"    (première fois : mémorise le chemin)
	test-vm.cmd
	test-vm.cmd -Sessions client,mobile -KeepRunning
#>
param(
	[string]$Vmx,
	[string[]]$Sessions = @("server", "client", "mobile", "multiplayer"),
	[int]$TimeoutSec = 1200,
	[switch]$KeepRunning,
	# Débogage du protocole sans VM : ne pilote pas VMware (un agent doit tourner ailleurs).
	[switch]$NoVmControl
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
$Exchange = Join-Path $Root "build\vm-exchange"
$ConfigPath = Join-Path $Root "build\vm-config.json"
New-Item -ItemType Directory -Force -Path (Join-Path $Exchange "jobs") | Out-Null

# Le script d'installation de l'invité est mis à disposition dans le dossier d'échange.
$setupDir = Join-Path $Exchange "setup"
New-Item -ItemType Directory -Force -Path $setupDir | Out-Null
$setupScript = Join-Path $setupDir "vm-guest-setup.ps1"
if (-not (Test-Path $setupScript) -or (Get-FileHash (Join-Path $PSScriptRoot "vm-guest-setup.ps1")).Hash -ne (Get-FileHash $setupScript).Hash) {
	Copy-Item (Join-Path $PSScriptRoot "vm-guest-setup.ps1") $setupScript -Force
}
# Mise à jour automatique de l'agent. Un fichier que la VM lit régulièrement reste verrouillé
# côté hôte par VMware : chaque version est donc publiée sous un NOUVEAU nom
# (setup\agent\vm-agent-<horodatage>-<empreinte>.ps1), jamais réécrite. L'agent ne fait que
# lister ce dossier et compare l'empreinte du nom le plus récent à la sienne.
$agentDir = Join-Path $setupDir "agent"
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
$agentHash = (Get-FileHash (Join-Path $PSScriptRoot "vm-agent.ps1")).Hash.Substring(0, 12)
$newest = Get-ChildItem $agentDir -Filter "vm-agent-*.ps1" | Sort-Object Name | Select-Object -Last 1
if (-not $newest -or $newest.BaseName -notlike "*-$agentHash") {
	$published = Join-Path $agentDir ("vm-agent-{0}-{1}.ps1" -f (Get-Date -Format "yyyyMMddHHmmss"), $agentHash)
	Copy-Item (Join-Path $PSScriptRoot "vm-agent.ps1") $published
	Write-Host "Nouvelle version de l'agent publiée : $(Split-Path -Leaf $published)"
	# Anciennes versions : supprimées si possible (une version encore lue par la VM reste verrouillée).
	Get-ChildItem $agentDir -Filter "vm-agent-*.ps1" | Where-Object { $_.FullName -ne $published } |
		ForEach-Object { Remove-Item $_.FullName -ErrorAction SilentlyContinue }
}
# Ancien emplacement (agents d'avant les noms versionnés) : supprimé dès qu'il n'est plus lu.
Remove-Item (Join-Path $setupDir "vm-agent.ps1") -ErrorAction SilentlyContinue

function Find-Vmrun {
	$candidates = @(
		"${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe",
		"$env:ProgramFiles\VMware\VMware Workstation\vmrun.exe"
	)
	foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
	$cmd = Get-Command vmrun -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	return $null
}

$startedByUs = $false
$vmrun = $null
if (-not $NoVmControl) {
	$vmrun = Find-Vmrun
	if (-not $vmrun) { throw "vmrun.exe introuvable : installer VMware Workstation (voir docs/VM_SETUP.md)." }
	if ($Vmx) {
		[pscustomobject]@{ vmx = $Vmx } | ConvertTo-Json | Out-File -Encoding utf8 $ConfigPath
	} elseif (Test-Path $ConfigPath) {
		$Vmx = (Get-Content -Raw $ConfigPath | ConvertFrom-Json).vmx
	}
	if (-not $Vmx -or -not (Test-Path $Vmx)) { throw "Fichier .vmx de la VM introuvable : passer -Vmx `"<chemin>.vmx`" (mémorisé ensuite)." }

	$running = (& $vmrun -T ws list) -join "`n"
	if ($running -notmatch [regex]::Escape($Vmx)) {
		# Une VM chiffrée (TPM virtuel de Windows 11) ne démarre pas avec vmrun sans son mot de passe :
		# on ne le stocke pas, l'utilisateur la démarre dans Workstation (puis « Run in background »).
		if (Select-String -Path $Vmx -Pattern '^encryption\.keySafe' -Quiet) {
			throw "La VM est chiffrée (TPM virtuel) : vmrun ne peut pas la démarrer sans mot de passe. Démarre-la dans VMware Workstation (tu peux ensuite fermer Workstation avec « Run in Background »), puis relance test-vm.cmd."
		}
		Write-Host "Démarrage de la VM sans fenêtre…"
		& $vmrun -T ws start $Vmx nogui
		if ($LASTEXITCODE -ne 0) { throw "vmrun start a échoué (code $LASTEXITCODE)." }
		$startedByUs = $true
	} else {
		Write-Host "VM déjà démarrée."
	}
}

# Attente de l'agent (battement de cœur récent).
$heartbeat = Join-Path $Exchange "agent-heartbeat.json"
$deadline = (Get-Date).AddSeconds(240)
Write-Host "Attente de l'agent de la VM…"
while ($true) {
	if (Test-Path $heartbeat) {
		$age = ((Get-Date) - (Get-Item $heartbeat).LastWriteTime).TotalSeconds
		if ($age -lt 30) { break }
	}
	if ((Get-Date) -gt $deadline) { throw "L'agent ne répond pas (agent-heartbeat.json absent ou ancien). Dans la VM : session ouverte automatiquement ? Script de préparation lancé depuis CE compte (la tâche MimicHuntersAgent démarre pour l'utilisateur qui l'a enregistrée) ?" }
	Start-Sleep -Seconds 3
}

# Dépôt de la tâche.
$id = Get-Date -Format "yyyyMMdd-HHmmss"
$jobDir = Join-Path $Exchange "jobs\$id"
$repoDir = Join-Path $jobDir "repo"
New-Item -ItemType Directory -Force -Path $repoDir | Out-Null
Push-Location $Root
try {
	$files = & git ls-files -co --exclude-standard
	$commit = (& git rev-parse --short HEAD).Trim()
	if ((& git status --porcelain)) { $commit += " (modifications non commitées)" }
} finally { Pop-Location }
foreach ($f in $files) {
	$src = Join-Path $Root $f
	if (-not (Test-Path $src -PathType Leaf)) { continue }
	$dst = Join-Path $repoDir $f
	New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
	Copy-Item $src $dst
}
[pscustomobject]@{ id = $id; commit = $commit; sessions = $Sessions; createdAt = (Get-Date).ToString("o") } |
	ConvertTo-Json | Out-File -Encoding utf8 (Join-Path $jobDir "job.json")
New-Item -ItemType File -Path (Join-Path $jobDir "job.ready") | Out-Null
Write-Host "Tâche $id déposée ($($files.Count) fichiers, commit $commit)."

# Attente du résultat.
$done = Join-Path $jobDir "done.json"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$claimedShown = $false
while (-not (Test-Path $done)) {
	if (-not $claimedShown -and (Test-Path (Join-Path $jobDir "claimed"))) { Write-Host "Prise en charge par l'agent."; $claimedShown = $true }
	if ((Get-Date) -gt $deadline) { throw "Pas de résultat après $TimeoutSec s (voir $jobDir\console.txt dans l'échange)." }
	Start-Sleep -Seconds 5
}
$result = Get-Content -Raw -Encoding UTF8 $done | ConvertFrom-Json
$report = Join-Path $jobDir "report\report.md"
if (Test-Path $report) {
	Copy-Item $report (Join-Path $Root "build\test-reports\latest-vm.md") -Force
}
Remove-Item -Recurse -Force $repoDir -ErrorAction SilentlyContinue

if ($startedByUs -and -not $KeepRunning) {
	Write-Host "Mise en veille de la VM…"
	& $vmrun -T ws suspend $Vmx | Out-Null
}

$shots = @(Get-ChildItem (Join-Path $jobDir "report\screenshots\*.png") -ErrorAction SilentlyContinue).Count
Write-Host ("Résultat VM : code {0}, {1} s, invité {2}, {3} capture(s) d'écran" -f $result.exitCode, $result.durationSec, $result.guest, $shots)
Write-Host "Rapport : $report"
exit $(if ($result.exitCode -eq 0) { 0 } else { 1 })
