# Regenera todas las evidencias del laboratorio en el equipo actual (pensado para Windows 10/11).
# Uso, desde la raíz del proyecto:
#   powershell -ExecutionPolicy Bypass -File .\scripts\evidencias.ps1
# Compatible con Windows PowerShell 5.1 y PowerShell 7.
param(
    [string]$Salida = "reports/evidencias-windows",
    [int]$Puerto = 8080,
    [string]$ImagenPublicada = "ghcr.io/juanjosegl/lab243:1.0.0",
    [string]$Identidad = "https://github.com/juanjosegl/lab243/.github/workflows/secure-image.yml@refs/heads/main",
    [string]$Emisor = "https://token.actions.githubusercontent.com"
)
. "$PSScriptRoot\comun.ps1"

# Aquí algunos pasos deben fallar (lint del Dockerfile inseguro, docker exec, identidad falsa):
# se registran con su código de salida en vez de detener el script.
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$PS = (Get-Process -Id $PID).Path   # el mismo PowerShell que ejecuta este script
New-Item -ItemType Directory -Force -Path $Salida | Out-Null
$script:resumen = @()

function Registrar {
    param([string]$Archivo, [string]$Titulo, [string]$Esperado, [scriptblock]$Bloque)
    Write-Host ">>> $Titulo"
    $global:LASTEXITCODE = 0
    # Se quitan los códigos de color (ANSI) que PowerShell 7 añade a los mensajes de error.
    $lineas = & $Bloque 2>&1 | ForEach-Object { "$_" -replace "$([char]27)\[[0-9;]*m", "" }
    $codigo = $LASTEXITCODE
    @("### $Titulo", "") + $lineas + @("", "exit=$codigo") | Out-File -FilePath (Join-Path $Salida $Archivo) -Encoding utf8
    $ok = if ($Esperado -eq "0") { $codigo -eq 0 } else { $codigo -ne 0 }
    $script:resumen += [pscustomobject]@{
        Archivo = $Archivo; Codigo = $codigo; Esperado = $Esperado; Resultado = $(if ($ok) { "OK" } else { "REVISAR" })
    }
}

function Script-Hijo { param([string]$Ruta, [string[]]$Argumentos = @())
    & $PS -NoProfile -ExecutionPolicy Bypass -File $Ruta @Argumentos
}

Registrar "00_entorno.txt" "Entorno de ejecución" "0" {
    "> Sistema operativo"; [Environment]::OSVersion.VersionString
    "> PowerShell"; "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    "> docker --version"; docker --version
    "> docker info"; docker info --format 'Motor: {{.OperatingSystem}} | Kernel: {{.KernelVersion}} | {{.OSType}}/{{.Architecture}}'
    "> docker buildx version"; docker buildx version
    "> trivy --version"; trivy --version
    "> cosign version"; cosign version
}

Registrar "01_hadolint_insegura.txt" "hadolint sobre Dockerfile.insegura (se esperan hallazgos)" "≠0" {
    Script-Hijo "$PSScriptRoot\lint.ps1" @("-Dockerfile", "Dockerfile.insegura")
}
Registrar "02_hadolint_segura.txt" "hadolint sobre Dockerfile (sin hallazgos)" "0" {
    Script-Hijo "$PSScriptRoot\lint.ps1" @("-Dockerfile", "Dockerfile")
}
Registrar "03_build_segura.txt" "docker build -t lab243:1.0.0 ." "0" {
    docker build -t lab243:1.0.0 .
}
Registrar "04_build_insegura.txt" "docker build -f Dockerfile.insegura -t lab243:insegura ." "0" {
    docker build -f Dockerfile.insegura -t lab243:insegura .
}
Registrar "05_docker_images.txt" "docker images lab243" "0" {
    docker images lab243 --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.ID}}'
}

docker rm -f lab243-app 2>&1 | Out-Null
Registrar "06_docker_run.txt" "docker run -d --name lab243-app -p ${Puerto}:8080 lab243:1.0.0" "0" {
    docker run -d --name lab243-app -p "${Puerto}:8080" lab243:1.0.0
    Start-Sleep -Seconds 2
    "> docker ps --filter name=lab243-app"
    docker ps --filter name=lab243-app --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}
Registrar "07_invoke_webrequest.txt" "Invoke-WebRequest http://localhost:$Puerto" "0" {
    $r = $null
    foreach ($i in 1..10) {
        try { $r = Invoke-WebRequest "http://localhost:$Puerto" -UseBasicParsing; break } catch { Start-Sleep -Seconds 1 }
    }
    if ($r) {
        "StatusCode   : $($r.StatusCode)"
        "Content-Type : $($r.Headers['Content-Type'])"
        "Content      : $($r.Content.Trim())"
    } else { "Sin respuesta en el puerto $Puerto"; $global:LASTEXITCODE = 1 }
}
Registrar "08_usuario_nonroot.txt" "Usuario de ejecución y docker exec (debe fallar: sin shell)" "≠0" {
    "> docker inspect lab243:1.0.0 --format '{{.Config.User}}'"
    docker inspect lab243:1.0.0 --format '{{.Config.User}}'
    "> docker inspect lab243:insegura --format '{{.Config.User}}'   (vacío = root)"
    "[" + (docker inspect lab243:insegura --format '{{.Config.User}}') + "]"
    "> docker logs lab243-app"
    docker logs lab243-app
    "> docker exec lab243-app sh"
    docker exec lab243-app sh
}

Registrar "09_scan_segura.txt" "scripts/scan.ps1 (gate HIGH/CRITICAL)" "0" {
    Script-Hijo "$PSScriptRoot\scan.ps1"
}
Registrar "10_comparacion.txt" "Comparación lab243:insegura vs lab243:1.0.0" "0" {
    # Trivy cuenta con una plantilla: evita cargar en memoria el JSON de la imagen insegura (~14 MB).
    $plantilla = '{{range .}}{{if eq .Class "os-pkgs"}}BASE {{.Target}}{{"\n"}}{{end}}' +
        '{{range .Packages}}PKG{{"\n"}}{{end}}{{range .Vulnerabilities}}SEV {{.Severity}}{{"\n"}}{{end}}{{end}}'
    $filas = foreach ($tag in "insegura", "1.0.0") {
        $lineas = @(trivy image --quiet --list-all-pkgs --format template --template $plantilla "lab243:$tag")
        $usuario = docker inspect "lab243:$tag" --format '{{.Config.User}}'
        $base = ($lineas | Where-Object { $_ -like "BASE *" } | Select-Object -First 1) -replace '^BASE .*\((.*)\)$', '$1'
        [pscustomobject]@{
            Imagen   = "lab243:$tag"
            Tamano   = (docker images "lab243:$tag" --format '{{.Size}}')
            Usuario  = $(if ($usuario) { $usuario } else { "(root)" })
            Paquetes = @($lineas | Where-Object { $_ -eq "PKG" }).Count
            CRITICAL = @($lineas | Where-Object { $_ -eq "SEV CRITICAL" }).Count
            HIGH     = @($lineas | Where-Object { $_ -eq "SEV HIGH" }).Count
            MEDIUM   = @($lineas | Where-Object { $_ -eq "SEV MEDIUM" }).Count
            LOW      = @($lineas | Where-Object { $_ -eq "SEV LOW" }).Count
            Base     = $base
        }
    }
    $filas | Format-Table -AutoSize | Out-String -Width 200
    $global:LASTEXITCODE = 0
}
Registrar "11_sbom.txt" "scripts/sbom.ps1 (CycloneDX)" "0" {
    Script-Hijo "$PSScriptRoot\sbom.ps1"
    $codigo = $LASTEXITCODE
    $s = Get-Content reports/sbom-lab243.json -Raw | ConvertFrom-Json
    "bomFormat: $($s.bomFormat)  specVersion: $($s.specVersion)  componentes: $(@($s.components).Count)"
    $s.components | ForEach-Object { "  - $($_.type) $($_.name) $($_.version)" }
    $global:LASTEXITCODE = $codigo
}
Registrar "12_pipeline.txt" "scripts/pipeline.ps1 (gate completo)" "0" {
    Script-Hijo "$PSScriptRoot\pipeline.ps1"
}

# Prueba del gate con una imagen vulnerable, en una copia temporal del proyecto.
Registrar "13_gate_bloquea.txt" "Gate con imagen vulnerable (Go 1.22): pipeline corregido vs. script de la guía" "0" {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "lab243-gate"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Copy-Item main.go, go.mod, Dockerfile, .dockerignore -Destination $tmp
    Copy-Item scripts -Destination $tmp -Recurse
    (Get-Content (Join-Path $tmp "Dockerfile")) -replace 'golang:1\.27', 'golang:1.22' | Set-Content (Join-Path $tmp "Dockerfile")
    $original = @'
$ErrorActionPreference = "Stop"
$IMAGE = "lab243:prueba-gate"
Write-Host "=== 1. Lint del Dockerfile ==="
Get-Content .\Dockerfile | docker run --rm -i hadolint/hadolint
Write-Host "=== 2. Build de la imagen ==="
docker build -t $IMAGE .
Write-Host "=== 3. Escaneo de vulnerabilidades ==="
trivy image --severity HIGH,CRITICAL --exit-code 1 $IMAGE
Write-Host "=== 4. Escaneo de secretos ==="
trivy fs --scanners secret --exit-code 1 .
Write-Host "=== 5. Generación de SBOM ==="
if (!(Test-Path "reports")) { New-Item -ItemType Directory -Path "reports" | Out-Null }
trivy image --format cyclonedx --output reports/sbom-lab243.json $IMAGE
Write-Host "=== Pipeline local completado con éxito ==="
'@
    Set-Content -Path (Join-Path $tmp "pipeline_original_guia.ps1") -Value $original -Encoding UTF8
    Push-Location $tmp
    "### A) scripts/pipeline.ps1 corregido (revisa `$LASTEXITCODE)"
    Script-Hijo ".\scripts\pipeline.ps1" @("-Imagen", "lab243:prueba-gate") 2>&1 | ForEach-Object { "$_" } |
        Select-String -Pattern '^===|Falló|^Total:|completado' | ForEach-Object { $_.Line }
    $a = $LASTEXITCODE
    "Código de salida del script: $a"
    ""
    "### B) Script original de la guía, sin cambios"
    Script-Hijo ".\pipeline_original_guia.ps1" 2>&1 | ForEach-Object { "$_" } |
        Select-String -Pattern '^===|^Total:|completado' | ForEach-Object { $_.Line }
    $b = $LASTEXITCODE
    "Código de salida del script: $b"
    Pop-Location
    docker rmi -f lab243:prueba-gate 2>&1 | Out-Null
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    # Lo esperado: el corregido falla (≠0) y el original termina en 0 pese al CRITICAL.
    $global:LASTEXITCODE = $(if ($a -ne 0 -and $b -eq 0) { 0 } else { 1 })
}

Registrar "14_imagen_publicada.txt" "docker pull $ImagenPublicada y docker inspect" "0" {
    docker pull -q $ImagenPublicada
    docker inspect $ImagenPublicada --format 'Usuario: {{.Config.User}} | RepoDigests: {{.RepoDigests}} | Arquitectura: {{.Architecture}}'
}
$digest = docker inspect --format '{{index .RepoDigests 0}}' $ImagenPublicada
Registrar "15_cosign_verify_identidad.txt" "cosign verify con identidad y emisor exactos" "0" {
    "> cosign verify $digest --certificate-identity $Identidad --certificate-oidc-issuer $Emisor"
    cosign verify $digest --certificate-identity $Identidad --certificate-oidc-issuer $Emisor
}
Registrar "16_cosign_verify_comodines.txt" "cosign verify con los comodines de la guía" "0" {
    "> cosign verify $digest --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*'"
    cosign verify $digest --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*'
}
Registrar "17_cosign_verify_identidad_falsa.txt" "cosign verify con una identidad ajena (debe fallar)" "≠0" {
    $falsa = $Identidad -replace 'github.com/[^/]+/', 'github.com/otro-usuario/'
    "> cosign verify $digest --certificate-identity $falsa --certificate-oidc-issuer $Emisor"
    cosign verify $digest --certificate-identity $falsa --certificate-oidc-issuer $Emisor
}

docker rm -f lab243-app 2>&1 | Out-Null
$tabla = $script:resumen | Format-Table -AutoSize | Out-String -Width 200
$tabla | Out-File -FilePath (Join-Path $Salida "00_resumen.txt") -Encoding utf8
Write-Host $tabla
$malos = @($script:resumen | Where-Object Resultado -ne "OK").Count
if ($malos -eq 0) { Write-Host "Todas las evidencias quedaron como se esperaba. Carpeta: $Salida" }
else { Write-Host "$malos paso(s) no dieron el resultado esperado; revisa los archivos marcados REVISAR." }
exit $malos
