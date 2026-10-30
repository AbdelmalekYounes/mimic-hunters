<#
.SYNOPSIS
	Tests automatisés de MIMIC HUNTERS dans Roblox Studio, sans souris ni clavier.

.DESCRIPTION
	1. Construit la place avec Rojo.
	2. Génère le pilote (tests/studio/Driver.template.luau + suites).
	3. Lance Studio : --task RunScript --localPlaceFile --runScriptFile --outputFile --quitAfterExecution,
	   par défaut sur un bureau Windows secondaire invisible (tools/HiddenDesktopRunner.cs).
	4. Lit les lignes « @@MH@@ » de la sortie, copie les journaux Studio, écrit studio-results.json.

	Aucune entrée clavier/souris n'est simulée. Seuls les processus Studio lancés
	par ce script peuvent être arrêtés (délai dépassé).

.EXAMPLE
	powershell -ExecutionPolicy Bypass -File tools\studio-tests.ps1
	powershell -ExecutionPolicy Bypass -File tools\studio-tests.ps1 -Sessions server,client
	powershell -ExecutionPolicy Bypass -File tools\studio-tests.ps1 -Visible
#>
param(
	[string[]]$Sessions = @("server", "client", "mobile", "multiplayer"),
	[string]$ReportDir,
	[int]$TimeoutSec = 420,
	[switch]$Visible,
	[string]$StudioExe,
	[string]$MobileDevice = "iphone_13"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
if (-not $ReportDir) {
	$ReportDir = Join-Path $Root ("build\test-reports\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

function Find-Studio {
	if ($StudioExe) { return $StudioExe }
	$candidates = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions\*\RobloxStudioBeta.exe" -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime -Descending
	if (-not $candidates) { throw "Roblox Studio introuvable dans $env:LOCALAPPDATA\Roblox\Versions" }
	return $candidates[0].FullName
}

$sessionCatalog = @{
	server      = @{ name = "server"; mode = "Run"; args = @{ suite = "server" } }
	client      = @{ name = "client-pc"; mode = "Play"; args = @{ suite = "client"; device = "pc" } }
	mobile      = @{ name = "client-mobile"; mode = "Play"; device = $MobileDevice; args = @{ suite = "client"; device = "mobile" } }
	multiplayer = @{ name = "multiplayer"; mode = "Multiplayer"; players = 2; args = @{ suite = "multiplayer" } }
}
$selected = @()
foreach ($s in $Sessions) {
	foreach ($part in ($s -split ",")) {
		$key = $part.Trim()
		if (-not $sessionCatalog.ContainsKey($key)) { throw "Session inconnue : $key (server, client, mobile, multiplayer)" }
		$selected += $sessionCatalog[$key]
	}
}

# 1. Construction de la place
$place = Join-Path $Root "build\MimicHunters.rbxl"
Push-Location $Root
try {
	& rojo build default.project.json -o $place 2>&1 | Out-File -Encoding utf8 (Join-Path $ReportDir "rojo-build.txt")
	if ($LASTEXITCODE -ne 0) { throw "rojo build a échoué (voir rojo-build.txt)" }
} finally { Pop-Location }

# 2. Génération du pilote
$template = Get-Content -Raw -Encoding UTF8 (Join-Path $Root "tests\studio\Driver.template.luau")
$serverSuite = Get-Content -Raw -Encoding UTF8 (Join-Path $Root "tests\studio\ServerSuite.server.luau")
$clientSuite = Get-Content -Raw -Encoding UTF8 (Join-Path $Root "tests\studio\ClientSuite.client.luau")
foreach ($src in @($serverSuite, $clientSuite)) {
	if ($src.Contains("]==]")) { throw "Une suite contient « ]==] », incompatible avec l'injection." }
}
$sessionsJson = ConvertTo-Json -InputObject @($selected) -Depth 6 -Compress
$driver = $template.Replace("__SERVER_SUITE__", $serverSuite).Replace("__CLIENT_SUITE__", $clientSuite).Replace("__SESSIONS__", $sessionsJson)
$driverPath = Join-Path $ReportDir "driver.luau"
[IO.File]::WriteAllText($driverPath, $driver, (New-Object Text.UTF8Encoding $false))

# 3. Lancement de Studio
$exe = Find-Studio
$outputLog = Join-Path $ReportDir "studio-output.log"   # Studio exige l'extension .log
Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot "HiddenDesktopRunner.cs"))
$cmd = "`"$exe`" --task RunScript --localPlaceFile `"$place`" --runScriptFile `"$driverPath`" --outputFile `"$outputLog`" --quitAfterExecution"
$launchTime = Get-Date
Write-Host ("Studio : {0} ({1})" -f $exe, $(if ($Visible) { "bureau de l'utilisateur" } else { "bureau caché" }))
Write-Host ("Sessions : {0}" -f (($selected | ForEach-Object { $_.name }) -join ", "))
$run = [HiddenDesktopRunner]::Run($cmd, $TimeoutSec * 1000, -not $Visible, "MimicHuntersTests", "RobloxStudioBeta")
if ($run.Error) { throw "Lancement impossible : $($run.Error)" }

# Nettoyage : uniquement les processus Studio enfants de NOTRE lancement (clients multijoueur).
$children = Get-CimInstance Win32_Process -Filter "Name = 'RobloxStudioBeta.exe'" -ErrorAction SilentlyContinue |
	Where-Object { $_.ParentProcessId -eq $run.ProcessId }
foreach ($child in $children) { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue }

# 4. Journaux et résultats
$logDir = Join-Path $ReportDir "roblox-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Get-ChildItem "$env:LOCALAPPDATA\Roblox\logs\*Studio*.log" -ErrorAction SilentlyContinue |
	Where-Object { $_.LastWriteTime -ge $launchTime.AddSeconds(-2) } |
	ForEach-Object { Copy-Item $_.FullName $logDir }

$events = @()
$anomalies = @()
$knownNoise = @("rbxassetid://203785492")   # Boîte à outils de Studio, sans lien avec le jeu
if (Test-Path $outputLog) {
	foreach ($line in (Get-Content -Encoding UTF8 $outputLog)) {
		if ($line.StartsWith("@@MH@@ ")) {
			$events += ($line.Substring(7) | ConvertFrom-Json)
		} elseif ($line -match "(?i)error|exception|failed|stack|infinite yield|warn") {
			$noise = $false
			foreach ($n in $knownNoise) { if ($line.Contains($n)) { $noise = $true } }
			if (-not $noise -and $line -notmatch "^\s*(--|local |if |end|expect|error\(|check\(|\t)") { $anomalies += $line.Trim() }
		}
	}
}

$sessionsOut = @($events | Where-Object { $_.kind -eq "session" } | ForEach-Object { $_.data })
$start = $events | Where-Object { $_.kind -eq "start" } | Select-Object -First 1
$devices = $events | Where-Object { $_.kind -eq "devices" } | Select-Object -First 1
$done = [bool]($events | Where-Object { $_.kind -eq "done" })

$tests = @()
foreach ($s in $sessionsOut) {
	if ($s.ok -and $s.report) {
		foreach ($r in $s.report.results) {
			$tests += [pscustomobject]@{ session = $s.name; name = $r.name; ok = [bool]$r.ok; skipped = [bool]$r.skipped; message = $r.message; duration = $r.duration }
		}
	} else {
		$tests += [pscustomobject]@{ session = $s.name; name = "session.execution"; ok = $false; message = $(if ($s.error) { $s.error } else { "aucun rapport (EndTest non reçu)" }); duration = $s.duration }
	}
}
foreach ($wanted in $selected) {
	if (-not ($sessionsOut | Where-Object { $_.name -eq $wanted.name })) {
		$tests += [pscustomobject]@{ session = $wanted.name; name = "session.absente"; ok = $false; message = "session non exécutée (Studio arrêté, délai ou plantage)"; duration = 0 }
	}
}

$result = [pscustomobject]@{
	studioExe = $exe
	studioVersion = if ($start) { $start.data.studioVersion } else { $null }
	launchedAt = $launchTime.ToString("o")
	durationSec = $run.DurationSec
	exitCode = $run.ExitCode
	timedOut = $run.TimedOut
	driverFinished = $done
	isolation = [pscustomobject]@{
		hiddenDesktop = $run.HiddenDesktop
		studioWindowsOnUserDesktop = $run.MaxProcessWindowsOnUserDesktop
		studioTookForeground = $run.ProcessWindowInForeground
		foregroundChangedDuringRun = $run.ForegroundChanged
	}
	devices = if ($devices) { $devices.data } else { $null }
	sessions = $sessionsOut
	tests = $tests
	anomalies = $anomalies
	passed = @($tests | Where-Object { $_.ok -and -not $_.skipped }).Count
	skipped = @($tests | Where-Object { $_.skipped }).Count
	failed = @($tests | Where-Object { -not $_.ok }).Count
}
$result | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 (Join-Path $ReportDir "studio-results.json")

foreach ($t in $tests) {
	$mark = if ($t.skipped) { "IGNORE" } elseif ($t.ok) { "OK  " } else { "ECHEC" }
	$msg = if ($t.message) { " — $($t.message)" } else { "" }
	Write-Host ("[{0}] {1} › {2}{3}" -f $mark, $t.session, $t.name, $msg)
}
Write-Host ("Studio : {0} réussi(s), {1} échoué(s), {2} ignoré(s), {3:N1} s, isolation : fenêtres sur ton bureau = {4}, premier plan pris = {5}" -f `
	$result.passed, $result.failed, $result.skipped, $run.DurationSec, $run.MaxProcessWindowsOnUserDesktop, $run.ProcessWindowInForeground)
Write-Host "Rapport : $ReportDir"
if ($result.failed -gt 0 -or $run.TimedOut -or -not $done) { exit 1 }
exit 0
