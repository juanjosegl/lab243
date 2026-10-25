param([string]$Dockerfile = "Dockerfile")
. "$PSScriptRoot\comun.ps1"
New-Reports

$nombre = [IO.Path]::GetFileName($Dockerfile).ToLower()
$salida = "reports/hadolint-$nombre.txt"
$resultado = Get-Content $Dockerfile | docker run --rm -i $HADOLINT hadolint --no-color -
$codigo = $LASTEXITCODE
if ($codigo -eq 0) { $resultado = "hadolint: sin hallazgos en $Dockerfile (código 0)" }
else { $resultado = @($resultado) + "hadolint: $(@($resultado).Count) hallazgos en $Dockerfile (código $codigo)" }
$resultado | Tee-Object -FilePath $salida
exit $codigo
