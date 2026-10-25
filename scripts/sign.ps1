# Publica la imagen, la firma por digest con cosign (keyless) y verifica la firma.
# Requiere: docker login ghcr.io con un token que tenga write:packages.
param(
    [string]$Imagen = "lab243:1.0.0",
    [string]$Repositorio = "ghcr.io/juanjosegl/lab243",
    [string]$Tag = "1.0.0",
    # En producción: identidad y emisor OIDC exactos, no comodines.
    [string]$Identidad = ".*",
    [string]$Emisor = ".*"
)
. "$PSScriptRoot\comun.ps1"

$remota = "${Repositorio}:${Tag}"
Invoke-Paso "Etiquetar" { docker tag $Imagen $remota }
Invoke-Paso "Publicar" { docker push $remota }
$DIGEST = docker inspect --format='{{index .RepoDigests 0}}' $remota
if ($LASTEXITCODE -ne 0 -or -not $DIGEST) { throw "No se pudo obtener el digest de $remota" }
Write-Host "Digest: $DIGEST"

# Siempre se firma el digest: la etiqueta puede moverse, el digest no.
Invoke-Paso "Firmar" { cosign sign --yes $DIGEST }
Invoke-Paso "Verificar" {
    cosign verify $DIGEST `
        --certificate-identity-regexp $Identidad `
        --certificate-oidc-issuer-regexp $Emisor
}
