# Update $defaultExecutable to match your Godot CLI path before running.
param(
	[string]$GodotExecutable = ""
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$defaultExecutable = "E:\Godot\v4.5.1\Godot_v4.5.1-stable_mono_win64.exe"

if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
	$GodotExecutable = $defaultExecutable
}

if (-not (Test-Path -Path $GodotExecutable -PathType Leaf)) {
	Write-Error "Godot executable not found: $GodotExecutable"
	exit 1
}

$arguments = @(
	"--headless",
	"--path", $repoRoot,
	"--script", "addons/gut/gut_cmdln.gd",
	"-gdir=res://addons/simpleassetplacer/tests",
	"-ginclude_subdirs",
	"-gexit"
)

Write-Host "Running GUT tests using $GodotExecutable" -ForegroundColor Cyan

& $GodotExecutable @arguments
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
	Write-Error "GUT tests failed with exit code $exitCode"
	exit $exitCode
}

Write-Host "GUT tests completed successfully." -ForegroundColor Green
