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

	# Tâche « remote » (V0.3.2) : télécommande de l'interface de la VM (tools/vm-remote.ps1),
	# pour piloter Roblox Studio sans jamais utiliser la souris ni le clavier de l'hôte.
	if ($job.kind -eq "remote") {
		$exitCode = -1
		Push-Location $work
		try {
			$ErrorActionPreference = "Continue"
			& rokit install --no-trust-check 2>&1 | ForEach-Object { "$_" } | Out-File -Encoding utf8 $console
			& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work "tools\vm-remote.ps1") -Exchange $Exchange 2>&1 |
				ForEach-Object { $line = "$_"; $line | Out-File -Append -Encoding utf8 $console; $line } | Out-Host
			$exitCode = $LASTEXITCODE
		} catch {
			"$_" | Out-File -Append -Encoding utf8 $console
		} finally { Pop-Location }
		Write-Json (Join-Path $jobDir.FullName "done.json") ([pscustomobject]@{
			id = $id; kind = "remote"; exitCode = $exitCode; guest = $env:COMPUTERNAME
			startedAt = $started.ToString("o"); finishedAt = (Get-Date).ToString("o")
		})
		return
	}
	$arguments = @("-Visible", "-Screenshots")
	if ($job.sessions) { $arguments += @("-Sessions", ($job.sessions -join ",")) }
	if ($ExtraArgs) { $arguments += ($ExtraArgs -split " ") }

	$exitCode = -1
	Push-Location $work
	try {
		# Sous PowerShell 5.1, la sortie d'erreur d'un exécutable devient une erreur PowerShell :
		# avec « Stop », la moindre ligne sur stderr interromprait la tâche.
		$ErrorActionPreference = "Continue"
		# Outils Rokit épinglés dans rokit.toml du projet. La VM est une machine de test sans
		# personne pour répondre à la question de confiance de Rokit, d'où --no-trust-check.
		& rokit install --no-trust-check 2>&1 | ForEach-Object { "$_" } | Out-File -Encoding utf8 $console
		if ($LASTEXITCODE -ne 0) { throw "rokit install a échoué (code $LASTEXITCODE)" }
		& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work "tools\test-all.ps1") @arguments 2>&1 |
			ForEach-Object { $line = "$_"; $line | Out-File -Append -Encoding utf8 $console; $line } | Out-Host
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

$ownHash = (Get-FileHash $PSCommandPath).Hash.Substring(0, 12)
Write-Host "Agent MIMIC HUNTERS ($ownHash) — échange : $Exchange"
while ($true) {
	if (Test-Path $Exchange) {
		# Mise à jour automatique : avant chaque tâche, l'hôte publie la dernière version sous
		# setup\agent\vm-agent-<horodatage>-<empreinte>.ps1. On ne fait que lister le dossier
		# (lire un fichier partagé à chaque tour le garderait verrouillé côté hôte).
		$newest = Get-ChildItem (Join-Path $Exchange "setup\agent") -Filter "vm-agent-*.ps1" -ErrorAction SilentlyContinue |
			Sort-Object Name | Select-Object -Last 1
		$published = if ($newest) { $newest.FullName } else { $null }
		$changed = $false
		try {
			$changed = $newest -and $newest.BaseName -notlike "*-$ownHash"
			# Le fichier publié doit être lisible comme un script complet (pas une copie en cours).
			if ($changed) {
				$tokens = $null
				$parseErrors = $null
				[void][System.Management.Automation.Language.Parser]::ParseFile($published, [ref]$tokens, [ref]$parseErrors)
				if ($parseErrors) { $changed = $false }
			}
		} catch { $changed = $false } # fichier en cours d'écriture par l'hôte : on verra au tour suivant
		if ($changed) {
			Copy-Item $published $PSCommandPath -Force
			$relaunch = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
			foreach ($p in $PSBoundParameters.GetEnumerator()) {
				if ($p.Value -is [switch]) { if ($p.Value) { $relaunch += "-$($p.Key)" } }
				else { $relaunch += @("-$($p.Key)", "`"$($p.Value)`"") }
			}
			Write-Host "Nouvelle version de l'agent : redémarrage."
			Start-Process powershell.exe -ArgumentList $relaunch -WindowStyle Minimized
			exit 0
		}

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
