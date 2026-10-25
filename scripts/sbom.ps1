param([string]$Imagen = "lab243:1.0.0")
. "$PSScriptRoot\comun.ps1"
New-Reports

Invoke-Paso "SBOM CycloneDX" {
    trivy image --format cyclonedx --output reports/sbom-lab243.json $Imagen
}
