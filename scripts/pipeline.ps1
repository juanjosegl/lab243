# Gate de seguridad local: cualquier paso que falle detiene el pipeline.
param([string]$Imagen = "lab243:1.0.0")
. "$PSScriptRoot\comun.ps1"
New-Reports

Invoke-Paso "1. Lint del Dockerfile" {
    Get-Content .\Dockerfile | docker run --rm -i $HADOLINT hadolint --no-color -
}
Invoke-Paso "2. Build de la imagen" { docker build -t $Imagen . }
Invoke-Paso "3. Escaneo de vulnerabilidades" {
    trivy image --severity HIGH,CRITICAL --exit-code 1 $Imagen
}
Invoke-Paso "4. Escaneo de secretos" {
    trivy fs --scanners secret --exit-code 1 --skip-dirs reports .
}
Invoke-Paso "5. Usuario no root" {
    $usuario = docker inspect $Imagen --format '{{.Config.User}}'
    Write-Host "Usuario: $usuario"
    if ($usuario -notmatch '^nonroot') { throw "La imagen no corre como nonroot (usuario: '$usuario')" }
}
Invoke-Paso "6. Generación de SBOM" {
    trivy image --format cyclonedx --output reports/sbom-lab243.json $Imagen
}
Write-Host "=== Pipeline local completado con éxito ==="
