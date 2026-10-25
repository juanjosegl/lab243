param([string]$Imagen = "lab243:1.0.0")
. "$PSScriptRoot\comun.ps1"
New-Reports
$REPORT = "reports/trivy-lab243.json"

# Primero el informe JSON (se conserva aunque el gate falle) y luego el gate.
Invoke-Paso "Informe JSON de Trivy" {
    trivy image --severity HIGH,CRITICAL --format json --output $REPORT $Imagen
}
Invoke-Paso "Gate de vulnerabilidades HIGH/CRITICAL" {
    trivy image --severity HIGH,CRITICAL --exit-code 1 --format table $Imagen
}
