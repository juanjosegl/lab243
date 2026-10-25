# Lab 243: imágenes y contenedores seguros en el pipeline

Grupo: Juan José Gutiérrez Lasso, María Paula Andrade, Víctor Daniel Fernández, José Fernández y Alejandra Guzmán.

Servicio Go mínimo empaquetado en una imagen multi-stage sobre distroless, que corre como `nonroot`, se analiza con hadolint y Trivy, se publica en GHCR, se firma por digest con cosign y se entrega con su SBOM CycloneDX.

## Estructura

| Ruta | Contenido |
|---|---|
| `main.go`, `go.mod` | Servicio HTTP de ejemplo |
| `Dockerfile` | Imagen segura: multi-stage, distroless `static-debian12:nonroot`, binario estático |
| `Dockerfile.insegura` | Imagen inicial insegura, solo para comparar |
| `scripts/lint.ps1` | hadolint sobre un Dockerfile |
| `scripts/scan.ps1` | Trivy: reporte JSON y gate HIGH/CRITICAL |
| `scripts/sbom.ps1` | SBOM CycloneDX |
| `scripts/sign.ps1` | Publicar, firmar por digest y verificar con cosign |
| `scripts/pipeline.ps1` | Gate local completo |
| `.github/workflows/secure-image.yml` | Mismo flujo en CI, con publicación y firma keyless |
| `reports/` | Reportes y evidencias |

## Uso en Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\pipeline.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\scan.ps1
docker run -d --name lab243-app -p 8080:8080 lab243:1.0.0
Invoke-WebRequest http://localhost:8080
docker inspect lab243:1.0.0 --format '{{.Config.User}}'
```

Verificar la firma de la imagen publicada:

```powershell
cosign verify ghcr.io/juanjosegl/lab243:1.0.0 `
  --certificate-identity "https://github.com/juanjosegl/lab243/.github/workflows/secure-image.yml@refs/heads/main" `
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```
