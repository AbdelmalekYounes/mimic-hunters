<#
.SYNOPSIS
	Agent de tests à exécuter DANS la machine virtuelle MIMIC HUNTERS.

.DESCRIPTION
	Surveille le dossier d'échange partagé par l'hôte (dossier partagé VMware).
	Pour chaque demande « jobs/<id>/job.ready » :
	  1. copie le projet dans un dossier local de la VM ;
	  2. lance test.cmd -Visible -Screenshots (Studio s'affiche sur le bureau de la VM) ;
	  3. renvoie le rapport et les captures dans jobs/<id>/report, puis écrit jobs/<id>/done.json.

	L'agent n'agit que dans la VM. Il ne lit aucun mot de passe et ne contacte pas l'hôte,
	sauf via le dossier partagé.

.EXAMPLE
	powershell -ExecutionPolicy Bypass -File vm-agent.ps1
	powershell -ExecutionPolicy Bypass -File vm-agent.ps1 -Once -Exchange D:\echange -ExtraArgs "-SkipStudio"
#>
param(
	[string]$Exchange = "\\vmware-host\Shared Folders\mimic-exchange",
	[string]$WorkRoot = "C:\MimicTests\work",
	[int]$PollSec = 5,
	[switch]$Once,
	# Arguments supplémentaires pour test.cmd (ex. "-SkipStudio" pour tester l'agent sans Studio).
	[string]$ExtraArgs = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$jobsDir = Join-Path $Exchange "jobs"

function Write-Json($path, $object) {
	$tmp = "$path.tmp"
	$object | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 $tmp
	Move-Item -Force $tmp $path
}

function Invoke-Job([IO.DirectoryInfo]$jobDir) {
	$id = $jobDir.Name
	$job = Get-Content -Raw -Encoding UTF8 (Join-Path $jobDir.FullName "job.json") | ConvertFrom-Json
	New-Item -ItemType File -Force -Path (Join-Path $jobDir.FullName "claimed") | Out-Null
	$started = Get-Date
	Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] tâche $id : démarrage"

	$work = Join-Path $WorkRoot $id
	New-Item -ItemType Directory -Force -Path $work | Out-Null
	robocopy (Join-Path $jobDir.FullName "repo") $work /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

	$console = Join-Path $jobDir.FullName "console.txt"
	$env:MIMIC_COMMIT = $job.commit
	$arguments = @("-Visible", "-Screenshots")
	if ($job.sessions) { $arguments += @("-Sessions", ($job.sessions -join ",")) }
	if ($ExtraArgs) { $arguments += ($ExtraArgs -split " ") }

	$exitCode = -1
	Push-Location $work
	try {
		# Outils Rokit dans les versions du projet (téléchargés au premier passage).
		& rokit install 2>&1 | Out-File -Encoding utf8 $console
		& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work "tools\test-all.ps1") @arguments 2>&1 |
			Tee-Object -FilePath $console -Append | Out-Host
		$exitCode = $LASTEXITCODE
	} catch {
		"$_" | Out-File -Append -Encoding utf8 $console
	} finally { Pop-Location }

	$latest = Get-ChildItem (Join-Path $work "build\test-reports") -Directory -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime -Descending | Select-Object -First 1
	if ($latest) {
		robocopy $latest.FullName (Join-Path $jobDir.FullName "report") /E /NFL /NDL /NJH /NJS /NP | Out-Null
	}
	Write-Json (Join-Path $jobDir.FullName "done.json") ([pscustomobject]@{
		id = $id
		exitCode = $exitCode
		startedAt = $started.ToString("o")
		finishedAt = (Get-Date).ToString("o")
		durationSec = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
		guest = $env:COMPUTERNAME
		report = if ($latest) { "report/report.md" } else { $null }
	})
	Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] tâche $id : terminée (code $exitCode)"
	Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Write-Host "Agent MIMIC HUNTERS — échange : $Exchange"
while ($true) {
	if (Test-Path $Exchange) {
		New-Item -ItemType Directory -Force -Path $jobsDir | Out-Null
		Write-Json (Join-Path $Exchange "agent-heartbeat.json") ([pscustomobject]@{
			guest = $env:COMPUTERNAME; at = (Get-Date).ToString("o"); pid = $PID
		})
		$pending = Get-ChildItem $jobsDir -Directory | Where-Object {
			(Test-Path (Join-Path $_.FullName "job.ready")) -and
			-not (Test-Path (Join-Path $_.FullName "claimed")) -and
			-not (Test-Path (Join-Path $_.FullName "done.json"))
		} | Sort-Object Name
		foreach ($jobDir in $pending) {
			try { Invoke-Job $jobDir } catch {
				Write-Json (Join-Path $jobDir.FullName "done.json") ([pscustomobject]@{ id = $jobDir.Name; exitCode = -1; error = "$_" })
			}
		}
		# -Once : s'arrête après avoir traité au moins une tâche.
		if ($Once -and $pending) { break }
	} else {
		Write-Host "Dossier d'échange introuvable ($Exchange) : vérifier le dossier partagé VMware."
	}
	Start-Sleep -Seconds $PollSec
}
