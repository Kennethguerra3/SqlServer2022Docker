<#
.SYNOPSIS
    Crea un acceso directo en el Escritorio para encender SQL Server.
#>

$ScriptPath = Join-Path $PSScriptRoot "railway_control.ps1"
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$ShortcutFile = Join-Path $DesktopPath "Encender SQL Server.lnk"

$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutFile)

# El truco: Ejecutar PowerShell oculta la ventana luego de terminar
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -NoExit -File `"$ScriptPath`" -Action Start"
$Shortcut.Description = "Enciende el servidor SQL en Railway"
$Shortcut.IconLocation = "shell32.dll,13" # Icono de 'Mundo/Red'

$Shortcut.Save()

Write-Host "Acceso directo creado en: $ShortcutFile" -ForegroundColor Green
Write-Host "Ahora puedes hacer doble clic en ese icono para encender el servidor."
Read-Host "Presiona Enter para salir"
