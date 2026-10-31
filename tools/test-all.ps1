<#
.SYNOPSIS
	Suite de tests complète et reproductible de MIMIC HUNTERS.

.DESCRIPTION
	Étapes (dans l'ordre) :
	  1. Lune   : vérification de syntaxe de tous les fichiers .luau   (CLI)
	  2. Lune   : tests unitaires et d'intégration de la logique pure  (CLI)
	  3. Selene : lint de src (std roblox) et de tests (std luau)      (CLI)
	  4. Luau   : analyse de types --!strict (luau-lsp)                (CLI)
	  5. StyLua : vérification du formatage                            (CLI)
	  6. Rojo   : construction de la place                             (CLI)
	  7. Studio : sessions Run / Play / Play mobile / Multijoueur      (Studio scripté, bureau caché)

	Produit build/test-reports/<horodatage>/report.md + report.json,
	et une copie build/test-reports/latest.md.

.EXAMPLE
	test.cmd                     (tout)
	test.cmd -SkipStudio         (uniquement la ligne de commande, ~5 s)
	test.cmd -Sessions server    (une seule session Studio)
	test.cmd -Visible            (Studio sur ton bureau, pour diagnostiquer)
#>
param(
	[switch]$SkipStudio,
	[string[]]$Sessions = @("server", "client", "mobile", "multiplayer"),
	[switch]$Visible,
	[switch]$Screenshots,
	[int]$StudioTimeoutSec = 900
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportDir = Join-Path $Root "build\test-reports\$stamp"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$suiteStart = Get-Date

function Invoke-Tool([string]$file, [string]$arguments, [string]$cwd) {
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $file
	$psi.Arguments = $arguments
	$psi.WorkingDirectory = $cwd
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
	$psi.StandardErrorEncoding = [Text.Encoding]::UTF8
	try {
		$p = [System.Diagnostics.Process]::Start($psi)
	} catch {
		return [pscustomobject]@{ ExitCode = -1; Output = "Impossible de lancer « $file » : $($_.Exception.Message)" }
	}
	$out = $p.StandardOutput.ReadToEndAsync()
	$err = $p.StandardError.ReadToEndAsync()
	$p.WaitForExit()
	return [pscustomobject]@{ ExitCode = $p.ExitCode; Output = ($out.Result + $err.Result) }
}

$steps = New-Object System.Collections.ArrayList
function Add-Step([string]$name, [string]$kind, [string]$file, [string]$arguments, [string]$cwd, [scriptblock]$summarize) {
	Write-Host ("▶ {0}…" -f $name)
	$t0 = Get-Date
	$r = Invoke-Tool $file $arguments $cwd
	$duration = ((Get-Date) - $t0).TotalSeconds
	$logName = ($name -replace "[^\w]+", "-").ToLower() + ".txt"
	[IO.File]::WriteAllText((Join-Path $ReportDir $logName), $r.Output, (New-Object Text.UTF8Encoding $false))
	$detail = if ($summarize) { & $summarize $r.Output } else { "" }
	$step = [pscustomobject]@{
		name = $name; kind = $kind; ok = ($r.ExitCode -eq 0); exitCode = $r.ExitCode
		durationSec = [math]::Round($duration, 1); detail = $detail; log = $logName
	}
	[void]$steps.Add($step)
	Write-Host ("  {0} ({1:N1} s) {2}" -f $(if ($step.ok) { "OK" } else { "ÉCHEC" }), $duration, $detail)
}

function Last-Line([string]$text, [string]$pattern) {
	$m = [regex]::Matches($text, $pattern)
	if ($m.Count -gt 0) { return $m[$m.Count - 1].Value.Trim() }
	return ""
}

# ── Étapes en ligne de commande ─────────────────────────────────────────
Add-Step "Lune : syntaxe" "CLI" "lune" "run tests/check" $Root { param($o) Last-Line $o "\d+ fichier\(s\) compilé\(s\), \d+ erreur\(s\)" }
Add-Step "Lune : tests logique pure" "CLI" "lune" "run tests/run" $Root { param($o) Last-Line $o "\d+ réussi\(s\), \d+ échoué\(s\), \d+ au total" }
Add-Step "Selene : src" "CLI" "selene" "src" $Root { param($o) (Last-Line $o "\d+ errors") + " / " + (Last-Line $o "\d+ warnings") }
Add-Step "Selene : tests" "CLI" "selene" "." (Join-Path $Root "tests") { param($o) (Last-Line $o "\d+ errors") + " / " + (Last-Line $o "\d+ warnings") }
Add-Step "Selene : suites Studio" "CLI" "selene" "tests/studio tests/datastore" $Root { param($o) (Last-Line $o "\d+ errors") + " / " + (Last-Line $o "\d+ warnings") }
Add-Step "Lune : syntaxe suites Studio" "CLI" "lune" "run tests/check tests/studio tests/datastore" $Root { param($o) Last-Line $o "\d+ fichier\(s\) compilé\(s\), \d+ erreur\(s\)" }
Add-Step "Luau : analyse de types" "CLI" "powershell" "-NoProfile -ExecutionPolicy Bypass -File tools/luau-analyze.ps1" $Root { param($o) Last-Line $o "\d+ erreur\(s\) de type" }
Add-Step "StyLua : formatage" "CLI" "stylua" "--check src tests" $Root { param($o) if ($o.Trim()) { "écarts de formatage" } else { "conforme" } }
Add-Step "Rojo : construction" "CLI" "rojo" "build default.project.json -o build/MimicHunters.rbxl" $Root { param($o) Last-Line $o "Built project to .*" }

# ── Étape Studio ────────────────────────────────────────────────────────
$studio = $null
if (-not $SkipStudio) {
	Write-Host "▶ Studio : sessions automatisées…"
	$t0 = Get-Date
	$studioArgs = @{ Sessions = $Sessions; ReportDir = $ReportDir; TimeoutSec = $StudioTimeoutSec }
	if ($Visible) { $studioArgs.Visible = $true }
	if ($Screenshots) { $studioArgs.Screenshots = $true }
	$studioOk = $true
	try {
		& (Join-Path $PSScriptRoot "studio-tests.ps1") @studioArgs | Tee-Object -FilePath (Join-Path $ReportDir "studio-console.txt") | Out-Host
		$studioOk = ($LASTEXITCODE -eq 0)
	} catch {
		$studioOk = $false
		"$_" | Out-File -Append -Encoding utf8 (Join-Path $ReportDir "studio-console.txt")
	}
	$resultsPath = Join-Path $ReportDir "studio-results.json"
	if (Test-Path $resultsPath) { $studio = Get-Content -Raw -Encoding UTF8 $resultsPath | ConvertFrom-Json }
	$detail = if ($studio) { "{0} réussi(s), {1} échoué(s), {2} ignoré(s)" -f $studio.passed, $studio.failed, $studio.skipped } else { "aucun résultat" }
	[void]$steps.Add([pscustomobject]@{
		name = "Studio : sessions automatisées"; kind = "Studio scripté"; ok = $studioOk; exitCode = $(if ($studioOk) { 0 } else { 1 })
		durationSec = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1); detail = $detail; log = "studio-console.txt"
	})
}

# ── Contexte ────────────────────────────────────────────────────────────
function Tool-Version([string]$tool) { (Invoke-Tool $tool "--version" $Root).Output.Trim() -split "`n" | Select-Object -First 1 }
$gitRun = Invoke-Tool "git" "rev-parse --short HEAD" $Root
if ($gitRun.ExitCode -eq 0) {
	$git = $gitRun.Output.Trim()
	$dirty = ((Invoke-Tool "git" "status --porcelain" $Root).Output.Trim().Length -gt 0)
} else {
	# Copie sans dépôt Git (VM de test) : l'hôte transmet le commit.
	$git = if ($env:MIMIC_COMMIT) { $env:MIMIC_COMMIT } else { "inconnu" }
	$dirty = $false
}
$context = [ordered]@{
	date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
	machine = $env:COMPUTERNAME
	os = (Get-CimInstance Win32_OperatingSystem).Caption
	gpu = ((Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ", ")
	commit = $git + $(if ($dirty) { " (modifications non commitées)" } else { "" })
	lune = Tool-Version "lune"; rojo = Tool-Version "rojo"; selene = Tool-Version "selene"; stylua = Tool-Version "stylua"; luauLsp = Tool-Version "luau-lsp"
	studioVersion = if ($studio) { $studio.studioVersion } else { "non exécuté" }
	studioExe = if ($studio) { $studio.studioExe } else { "" }
	screen = (Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution } | ForEach-Object { "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" }) -join ", "
}
$allOk = -not ($steps | Where-Object { -not $_.ok })
$totalSec = [math]::Round(((Get-Date) - $suiteStart).TotalSeconds, 1)

# ── Rapport Markdown ────────────────────────────────────────────────────
$md = New-Object System.Text.StringBuilder
function L([string]$s = "") { [void]$md.AppendLine($s) }
L "# Rapport de tests MIMIC HUNTERS — $($context.date)"
L ""
L ("**Résultat global : {0}** · durée totale {1} s" -f $(if ($allOk) { "✅ RÉUSSI" } else { "❌ ÉCHEC" }), $totalSec)
L ""
L "## Contexte"
L ""
L "| Élément | Valeur |"
L "|---|---|"
foreach ($k in $context.Keys) { L ("| {0} | {1} |" -f $k, ($context[$k] -replace "\|", "/")) }
L ""
L "## Étapes"
L ""
L "| Étape | Type | Statut | Durée | Détail | Journal |"
L "|---|---|---|---|---|---|"
foreach ($s in $steps) {
	L ("| {0} | {1} | {2} | {3} s | {4} | ``{5}`` |" -f $s.name, $s.kind, $(if ($s.ok) { "✅" } else { "❌" }), $s.durationSec, $s.detail, $s.log)
}
if ($studio) {
	L ""
	L "## Studio : isolation mesurée"
	L ""
	$iso = $studio.isolation
	# Dans la VM de test, le « bureau » mesuré est celui de la VM, pas celui de l'utilisateur.
	$inVm = (Get-CimInstance Win32_ComputerSystem).Model -match "VMware|Virtual"
	$desk = if ($inVm) { "le bureau de la VM" } else { "ton bureau" }
	if ($inVm) { L "Mesures prises **dans la machine virtuelle** : ton bureau n'est pas concerné."; L "" }
	L "| Mesure | Valeur |"
	L "|---|---|"
	L ("| Bureau Windows caché | {0} |" -f $iso.hiddenDesktop)
	L ("| Fenêtres Studio visibles sur {0} (max) | {1} |" -f $desk, $iso.studioWindowsOnUserDesktop)
	L ("| Une fenêtre Studio a pris le premier plan | {0} |" -f $iso.studioTookForeground)
	L ("| Le premier plan a changé pendant le test (toute cause, y compris toi) | {0} |" -f $iso.foregroundChangedDuringRun)
	L ("| Durée Studio / code de sortie / délai dépassé | {0} s / {1} / {2} |" -f $studio.durationSec, $studio.exitCode, $studio.timedOut)
	if ($studio.screenshots -gt 0) { L ("| Captures d'écran (dossier ``screenshots/``) | {0} |" -f $studio.screenshots) }
	L ""
	L "## Studio : tests"
	L ""
	L "| Session | Test | Statut | Durée | Message |"
	L "|---|---|---|---|---|"
	foreach ($t in $studio.tests) {
		$status = if ($t.skipped) { "⏭️ ignoré" } elseif ($t.ok) { "✅" } else { "❌" }
		$msg = if ($t.message) { ($t.message -replace "\|", "/" -replace "`r?`n", " ") } else { "" }
		L ("| {0} | {1} | {2} | {3} | {4} |" -f $t.session, $t.name, $status, $t.duration, $msg)
	}
	L ""
	L "### Sessions"
	L ""
	foreach ($s in $studio.sessions) {
		$extra = @()
		if ($s.deviceId) { $extra += "appareil simulé $($s.deviceId) ($($s.simulatedResolution), $($s.simulatedOrientation))" }
		if ($s.deviceError) { $extra += "simulation : $($s.deviceError)" }
		if ($s.report -and $s.report.clientEnv) {
			$e = $s.report.clientEnv
			$extra += "client : TouchEnabled=$($e.touchEnabled), KeyboardEnabled=$($e.keyboardEnabled), vue=$($e.viewport -join 'x'), HUD=$($e.screen -join 'x') disposition $($e.layout)"
		}
		L ("- **{0}** ({1}) : {2:N1} s, {3} tentative(s). {4}" -f $s.name, $s.mode, $s.duration, $s.attempts, ($extra -join " · "))
	}
	L ""
	L "## Erreurs et avertissements Studio"
	L ""
	if ($studio.anomalies -and $studio.anomalies.Count -gt 0) {
		foreach ($a in $studio.anomalies) { L ("- ``{0}``" -f ($a -replace "``", "'")) }
	} else {
		L "Aucune ligne d'erreur ou d'avertissement dans la sortie du script (bruit connu filtré : ContentId 203785492 de la Boîte à outils)."
	}
	L ""
	L "Journaux complets : ``studio-output.log`` (sortie du script et du jeu), ``roblox-logs/`` (journaux Studio de chaque processus)."
}
L ""
L "## Non couvert par l'automatisation (vérifications graphiques manuelles)"
L ""
L "Ces points demandent une session **visible** (ton bureau, une machine virtuelle ou un autre PC) — voir docs/TESTING.md :"
L ""
L "- Rendu visuel : couleurs, lumière, animations des 6 révélations, fuites, particules."
L "- Chevauchements entre éléments du HUD et avec l'interface Roblox (chat, barre du haut) : le test vérifie seulement que les boutons restent dans l'écran."
L "- Lisibilité et ergonomie tactile ; sons audibles."
L "- Performance (images/s, MicroProfiler) — la simulation mobile de Studio n'est jamais une mesure sur téléphone réel."
[IO.File]::WriteAllText((Join-Path $ReportDir "report.md"), $md.ToString(), (New-Object Text.UTF8Encoding $false))
Copy-Item (Join-Path $ReportDir "report.md") (Join-Path $Root "build\test-reports\latest.md") -Force

[pscustomobject]@{ ok = $allOk; durationSec = $totalSec; context = $context; steps = $steps; studio = $studio } |
	ConvertTo-Json -Depth 14 | Out-File -Encoding utf8 (Join-Path $ReportDir "report.json")

Write-Host ""
Write-Host ("{0} en {1} s — rapport : {2}" -f $(if ($allOk) { "TOUT RÉUSSI" } else { "ÉCHECS" }), $totalSec, (Join-Path $ReportDir "report.md"))
if ($allOk) { exit 0 } else { exit 1 }
