# Ejecutar el laboratorio en Windows — Clase 243

**Regenerar las evidencias en Windows 10/11**
**Integrantes:** Juan José Gutiérrez Lasso · María Paula Andrade · Víctor Daniel Fernández · José Fernández · Alejandra Guzmán
**Repositorio:** [https://github.com/juanjosegl/lab243](https://github.com/juanjosegl/lab243)

---

## Qué vas a hacer

Vas a correr el laboratorio completo en un equipo con Windows para que las evidencias y capturas salgan de Windows. Un solo script, `scripts\evidencias.ps1`, ejecuta todos los pasos de la guía y guarda la salida de cada uno en `reports\evidencias-windows\`. Al final solo tienes que tomar unas capturas de pantalla y enviar la carpeta.

No necesitas tokens, contraseñas, `docker login` ni permisos sobre el repositorio. La imagen ya está publicada y firmada en GHCR de forma pública, y aquí solo se **verifica** su firma.

Tiempo estimado: 30–40 minutos la primera vez. La mayor parte se va en descargas: imagen de Go de unos 800 MB, Ubuntu y la base de datos de Trivy.

## 1. Requisitos

- Windows 10/11 con permisos de administrador.
- Unos 6 GB libres en disco.
- Conexión a internet.

## 2. Preparar Docker Desktop

Si no tienes Docker Desktop, instálalo desde [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/) con el backend **WSL 2** y reinicia si lo pide. Luego abre **PowerShell como administrador** y ejecuta:

```
wsl --update
wsl --set-default-version 2
```

Abre Docker Desktop y espera a que abajo a la izquierda diga **Engine running**. Comprueba:

```
docker --version
docker buildx version
```

## 3. Instalar Git, Trivy y cosign

En PowerShell (no hace falta que sea como administrador):

```
winget install Git.Git
winget install AquaSecurity.Trivy
winget install Sigstore.Cosign
```

**Cierra PowerShell y ábrelo de nuevo** para que se actualice el PATH. Comprueba:

```
git --version
trivy --version
cosign version
```

Opcional pero recomendado: PowerShell 7 (`winget install Microsoft.PowerShell`). Los scripts funcionan con el PowerShell que trae Windows (5.1), pero se validaron con PowerShell 7. Si algo falla con `powershell`, repite el comando cambiando `powershell` por `pwsh`.

## 4. Descargar el proyecto

```
mkdir C:\DevSecOps
cd C:\DevSecOps
git clone https://github.com/juanjosegl/lab243.git
cd lab243
```

## 5. Ejecutar el script de evidencias

Desde `C:\DevSecOps\lab243`:

```
powershell -ExecutionPolicy Bypass -File .\scripts\evidencias.ps1
```

Si el puerto 8080 está ocupado en tu equipo, usa otro:

```
powershell -ExecutionPolicy Bypass -File .\scripts\evidencias.ps1 -Puerto 8081
```

El script muestra `>>>` antes de cada paso y al final imprime una tabla como esta:

```
Archivo                              Codigo Esperado Resultado
-------                              ------ -------- ---------
00_entorno.txt                            0 0        OK
01_hadolint_insegura.txt                  1 ≠0       OK
...
17_cosign_verify_identidad_falsa.txt      1 ≠0       OK

Todas las evidencias quedaron como se esperaba. Carpeta: reports/evidencias-windows
```

**Todas las filas deben decir `OK`.** Algunos pasos deben fallar a propósito, y por eso su código esperado es `≠0`:
- el lint del Dockerfile inseguro;
- el `docker exec`, porque la imagen no tiene shell;
- la verificación con una identidad falsa.

Si alguna fila dice `REVISAR`, abre ese archivo y mira la sección 7.

## 6. Qué prueba cada archivo

| Archivo | Qué demuestra |
|---|---|
| `00_entorno.txt` | Windows, PowerShell, Docker, Trivy y cosign con sus versiones |
| `01_hadolint_insegura.txt` | hadolint encuentra 5 problemas en el Dockerfile inseguro |
| `02_hadolint_segura.txt` | El Dockerfile seguro no tiene hallazgos |
| `03_build_segura.txt`, `04_build_insegura.txt` | Construcción de ambas imágenes |
| `05_docker_images.txt` | Tamaños: ~1.09 GB la insegura, ~15 MB la segura |
| `06_docker_run.txt`, `07_invoke_webrequest.txt` | El contenedor corre y responde el JSON |
| `08_usuario_nonroot.txt` | Usuario `nonroot:nonroot`; `docker exec` falla por no haber shell |
| `09_scan_segura.txt` | Trivy: 0 vulnerabilidades HIGH/CRITICAL |
| `10_comparacion.txt` | Tabla insegura vs. segura: paquetes y CVE |
| `11_sbom.txt` | SBOM CycloneDX y sus componentes |
| `12_pipeline.txt` | `pipeline.ps1` completo en verde |
| `13_gate_bloquea.txt` | Con Go 1.22 el pipeline corregido se detiene; el script de la guía no |
| `14_imagen_publicada.txt` | La imagen de GHCR corre como `nonroot` |
| `15`, `16`, `17_cosign_verify_*.txt` | Firma válida con identidad exacta y con comodines; con identidad falsa, rechazada |
| `00_resumen.txt` | La tabla final con el resultado de cada paso |

## 7. Capturas de pantalla

Con las imágenes ya construidas por el script, cada comando tarda pocos segundos. Ejecuta cada bloque en PowerShell, dentro de `C:\DevSecOps\lab243`, y toma la captura de la ventana con **Win + Shift + S**. Guárdalas con el nombre indicado.

**w01_entorno.png**

```
docker --version; trivy --version; cosign version
```

**w02_hadolint.png**

```
Get-Content .\Dockerfile.insegura | docker run --rm -i hadolint/hadolint:v2.12.0 hadolint --no-color -
Get-Content .\Dockerfile | docker run --rm -i hadolint/hadolint:v2.12.0 hadolint --no-color -; "código: $LASTEXITCODE"
```

**w03_imagenes.png**

```
docker images lab243
```

**w04_ejecucion.png** (cambia 8080 por el puerto que usaste)

```
docker run -d --name lab243-app -p 8080:8080 lab243:1.0.0
Invoke-WebRequest http://localhost:8080 -UseBasicParsing
```

**w05_nonroot.png**

```
docker inspect lab243:1.0.0 --format '{{.Config.User}}'
docker exec lab243-app sh
docker rm -f lab243-app
```

**w06_trivy.png**

```
powershell -ExecutionPolicy Bypass -File .\scripts\scan.ps1
```

**w07_pipeline.png**

```
powershell -ExecutionPolicy Bypass -File .\scripts\pipeline.ps1
```

**w08_cosign_verify.png**

```
cosign verify ghcr.io/juanjosegl/lab243:1.0.0 `
  --certificate-identity "https://github.com/juanjosegl/lab243/.github/workflows/secure-image.yml@refs/heads/main" `
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## 8. Enviar los resultados

1. Comprime la carpeta `C:\DevSecOps\lab243\reports\evidencias-windows` junto con las 8 capturas en un ZIP llamado `evidencias-windows.zip`.
2. Envíaselo a Juan José para actualizar el informe con las salidas de Windows.

No hagas `git commit` ni `git push`: el repositorio no necesita cambios.

## 9. Problemas frecuentes

| Problema | Causa probable | Solución |
|---|---|---|
| "la ejecución de scripts está deshabilitada" | Política de ejecución de Windows | Ejecuta siempre con `powershell -ExecutionPolicy Bypass -File ...` |
| `docker: command not found` o `error during connect` | Docker Desktop no está abierto o WSL 2 falla | Abre Docker Desktop y espera **Engine running**; si persiste, `wsl --update` y reinicia Docker Desktop |
| `trivy` o `cosign` no se reconoce | PATH sin actualizar | Cierra y abre PowerShell; si sigue, reinicia sesión |
| `Bind for 0.0.0.0:8080 failed: port is already allocated` | El puerto 8080 está en uso | Usa `-Puerto 8081` |
| `07_invoke_webrequest.txt` dice "Sin respuesta" | El contenedor no arrancó o un firewall bloquea | Revisa `06_docker_run.txt`; prueba con otro puerto |
| Descargas lentas o que fallan (Docker Hub, Trivy DB, GHCR) | Red de la universidad o proxy | Reintenta con otra red; no desactives ningún control |
| `09` o `12` en REVISAR con vulnerabilidades nuevas | Se publicó una CVE nueva después del 24/10/2026 | Avísale a Juan José con el archivo; se actualiza la imagen base, no se desactiva el gate |
| Tildes raras en la consola | Codificación de Windows PowerShell 5.1 | No afecta los archivos generados; si molesta, usa `pwsh` |
