<#
.SYNOPSIS
	Télécommande de la VM (V0.3.2) : exécute DANS la VM des actions d'interface (clic, saisie,
	raccourci, capture d'écran, lancement d'un programme) envoyées par l'hôte.

.DESCRIPTION
	Lancée par vm-agent.ps1 pour une tâche de type « remote ». Lit les commandes
	<Exchange>\remote\cmd-<n>.json, les exécute dans la session de la VM (souris et clavier
	VIRTUELS de la VM : rien n'atteint le bureau de l'hôte), puis écrit res-<n>.json et une
	capture shot-<n>.png. S'arrête sur l'action « exit » ou après IdleExitSec sans commande.

	Sert à piloter Roblox Studio dans la VM (publication privée de test) sans jamais utiliser
	la souris ni le clavier de l'utilisateur. Ne lit aucun mot de passe, aucun cookie, aucun
	jeton : seules les actions demandées sont faites.

	Actions (champ « type ») :
	  click     { x, y, button = "left" | "right", double = false }  coordonnées de la capture
	  move      { x, y }
	  scroll    { x, y, delta }                                     delta > 0 : vers le haut
	  type      { text }                                            saisie littérale
	  keys      { keys }                                            syntaxe SendKeys ("^s", "%+p", "{ENTER}")
	  wait      { sec }
	  run       { file, args, cwd, wait = false }                   lance un programme
	  focus     { title }                                           met au premier plan la fenêtre dont le titre contient « title »
	  windows   { }                                                 liste les fenêtres visibles
	  screenshot{ }                                                 (une capture est de toute façon prise après chaque commande)
	  exit      { }
#>
param(
	[Parameter(Mandatory = $true)][string]$Exchange,
	[int]$IdleExitSec = 2400
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class VmInput {
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
	[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, int data, UIntPtr extra);
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
}
"@
[void][VmInput]::SetProcessDPIAware()

$remoteDir = Join-Path $Exchange "remote"
New-Item -ItemType Directory -Force -Path $remoteDir | Out-Null

function Save-Shot([string]$path) {
	$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
	$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
	$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
	$g.Dispose(); $bmp.Dispose()
	return @{ width = $bounds.Width; height = $bounds.Height }
}

function Invoke-Click($a) {
	[void][VmInput]::SetCursorPos([int]$a.x, [int]$a.y)
	Start-Sleep -Milliseconds 80
	$down, $up = if ($a.button -eq "right") { 0x0008, 0x0010 } else { 0x0002, 0x0004 }
	$times = if ($a.double) { 2 } else { 1 }
	for ($i = 0; $i -lt $times; $i++) {
		[VmInput]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
		Start-Sleep -Milliseconds 40
		[VmInput]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
		Start-Sleep -Milliseconds 90
	}
}

# Saisie littérale : les caractères spéciaux de SendKeys sont échappés.
function Send-Text([string]$text) {
	$escaped = ($text.ToCharArray() | ForEach-Object {
		if ("+^%~(){}[]".Contains([string]$_)) { "{$_}" } else { [string]$_ }
	}) -join ""
	[System.Windows.Forms.SendKeys]::SendWait($escaped)
}

function Get-VisibleWindows {
	Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
		ForEach-Object { [pscustomobject]@{ process = $_.ProcessName; pid = $_.Id; title = $_.MainWindowTitle } }
}

Write-Host "Télécommande de la VM prête (dossier : $remoteDir)."
$lastCommand = Get-Date
$running = $true
while ($running) {
	$next = Get-ChildItem $remoteDir -Filter "cmd-*.json" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
	if (-not $next) {
		if (((Get-Date) - $lastCommand).TotalSeconds -gt $IdleExitSec) { break }
		Start-Sleep -Milliseconds 400
		continue
	}
	$lastCommand = Get-Date
	$id = $next.BaseName.Substring(4)
	$output = @()
	$ok = $true
	$errorText = $null
	try {
		$command = Get-Content -Raw -Encoding UTF8 $next.FullName | ConvertFrom-Json
		Remove-Item $next.FullName -Force
		foreach ($a in @($command.actions)) {
			switch ($a.type) {
				"click" { Invoke-Click $a }
				"move" { [void][VmInput]::SetCursorPos([int]$a.x, [int]$a.y) }
				"scroll" {
					[void][VmInput]::SetCursorPos([int]$a.x, [int]$a.y)
					[VmInput]::mouse_event(0x0800, 0, 0, [int]$a.delta, [UIntPtr]::Zero)
				}
				"type" { Send-Text ([string]$a.text) }
				"keys" { [System.Windows.Forms.SendKeys]::SendWait([string]$a.keys) }
				"wait" { Start-Sleep -Milliseconds ([int]([double]$a.sec * 1000)) }
				"run" {
					$params = @{ FilePath = $a.file; PassThru = $true }
					if ($a.args) { $params.ArgumentList = $a.args }
					if ($a.cwd) { $params.WorkingDirectory = $a.cwd }
					if ($a.wait) { $params.Wait = $true; $params.NoNewWindow = $true }
					$p = Start-Process @params
					$output += "lancé : $($a.file) (pid $($p.Id))"
					if ($a.wait) { $output += "code de sortie : $($p.ExitCode)" }
				}
				"focus" {
					$w = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$($a.title)*" } | Select-Object -First 1
					if ($w) {
						[void][VmInput]::ShowWindow($w.MainWindowHandle, 3)
						[void][VmInput]::SetForegroundWindow($w.MainWindowHandle)
						$output += "premier plan : $($w.MainWindowTitle)"
					} else { $output += "fenêtre introuvable : $($a.title)" }
				}
				"windows" { $output += (Get-VisibleWindows | ForEach-Object { "$($_.process) [$($_.pid)] $($_.title)" }) }
				"screenshot" { }
				"exit" { $running = $false }
				default { throw "action inconnue : $($a.type)" }
			}
		}
	} catch {
		$ok = $false
		$errorText = "$_"
	}
	Start-Sleep -Milliseconds 300
	$shot = Join-Path $remoteDir "shot-$id.png"
	$size = Save-Shot $shot
	[pscustomobject]@{ id = $id; ok = $ok; error = $errorText; output = $output; screen = $size; at = (Get-Date).ToString("o") } |
		ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 (Join-Path $remoteDir "res-$id.json.tmp")
	Move-Item -Force (Join-Path $remoteDir "res-$id.json.tmp") (Join-Path $remoteDir "res-$id.json")
}
Write-Host "Télécommande arrêtée."
