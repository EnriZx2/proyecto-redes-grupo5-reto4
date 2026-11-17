# ==========================================================
# DESCARGA AUTOMATICA DE CONFIGURACIONES - GRUPO 5 RETO 4
# WINDOWS POWERSHELL
# ==========================================================

$IP = "172.26.46.55"
$USUARIO = "alumno"

# Carpeta donde se guardaran las configuraciones
$CARPETA = Join-Path $PSScriptRoot "config"

# Carpeta temporal en cada Ubuntu
$TEMPORAL = "/home/alumno/config-export"

# Contadores
$Correctos = 0
$Fallidos = 0

# ----------------------------------------------------------
# 1. COMPROBAR SSH Y SCP
# ----------------------------------------------------------

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: SSH no esta instalado." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: SCP no esta instalado." -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------
# 2. CREAR CARPETAS LOCALES
# ----------------------------------------------------------

Write-Host "`nCreando carpetas en Windows..." -ForegroundColor Cyan

$Servidores = @(
    "server1-g5",
    "server2-g5",
    "server3-g5",
    "server4-g5"
)

foreach ($Servidor in $Servidores) {
    $Destino = Join-Path $CARPETA $Servidor
    New-Item -ItemType Directory -Force -Path $Destino | Out-Null
}

# ----------------------------------------------------------
# 3. FUNCION PARA PREPARAR Y DESCARGAR
# ----------------------------------------------------------

function Descargar-Servidor {

    param (
        [int]$Puerto,
        [string]$Servidor,
        [string[]]$Copias
    )

    $Destino = Join-Path $CARPETA $Servidor

    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host " SERVIDOR: $Servidor"
    Write-Host " PUERTO NAT: $Puerto"
    Write-Host "==================================================" -ForegroundColor Cyan

    # Crear comandos para ejecutar en Ubuntu
    $Comandos = @(
        "rm -rf '$TEMPORAL'"
        "mkdir -p '$TEMPORAL'"
    )

    # Copiar archivos protegidos utilizando root sin detenerse si falta alguno
    foreach ($Copia in $Copias) {
        $Comandos += "cp -rL -- $Copia '$TEMPORAL/' 2>/dev/null || echo 'Aviso: No se encontro $Copia'"
    }

    # Dar permisos al usuario alumno
    $Comandos += "chown -R alumno:alumno '$TEMPORAL'"

    # Crear script remoto
    $ScriptRemoto = $Comandos -join "`n"

    # Codificar el script en Base64 para evitar problemas con comillas
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($ScriptRemoto)
    $Base64 = [Convert]::ToBase64String($Bytes)

    $ComandoRemoto = "echo $Base64 | base64 -d | sudo bash"

    Write-Host "`nPreparando archivos en Ubuntu..." -ForegroundColor Yellow

    # Conectar por SSH con terminal interactiva para sudo
    & ssh -t -p $Puerto "$USUARIO@$IP" $ComandoRemoto

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] No se pudieron preparar los archivos de $Servidor" -ForegroundColor Red
        $script:Fallidos++
        return
    }

    Write-Host "`nDescargando archivos a Windows..." -ForegroundColor Yellow

    # Descargar todo el contenido de la carpeta temporal
    & scp -r -P $Puerto "${USUARIO}@${IP}:${TEMPORAL}/." "$Destino/"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $Servidor descargado correctamente." -ForegroundColor Green
        $script:Correctos++
    }
    else {
        Write-Host "[ERROR] Fallo la descarga de $Servidor." -ForegroundColor Red
        $script:Fallidos++
    }
}

# ----------------------------------------------------------
# 4. SERVER1-G5 - PUERTO 2251
# ----------------------------------------------------------

Descargar-Servidor -Puerto 2251 -Servidor "server1-g5" -Copias @(
    "/etc/netplan/*.yaml"
    "/etc/dhcp/dhcpd.conf"
    "/etc/default/isc-dhcp-server"
    "/etc/bind/named.conf.local"
    "/etc/bind/named.conf.options"
    "/etc/bind/db.grupo5.local"
    "/etc/bind/db.192.168.5"
)

# ----------------------------------------------------------
# 5. SERVER2-G5 - PUERTO 2252
# ----------------------------------------------------------

Descargar-Servidor -Puerto 2252 -Servidor "server2-g5" -Copias @(
    "/etc/netplan/*.yaml"
    "/etc/dhcp/dhcpd.conf"
    "/etc/default/isc-dhcp-server"
    "/etc/bind/named.conf.local"
    "/etc/bind/named.conf.options"
)

# ----------------------------------------------------------
# 6. SERVER3-G5 - PUERTO 2253
# ----------------------------------------------------------

Descargar-Servidor -Puerto 2253 -Servidor "server3-g5" -Copias @(
    "/etc/netplan/*.yaml"
    "/etc/apache2/apache2.conf"
    "/etc/apache2/ports.conf"
    "/etc/apache2/sites-available/*.conf"
    "/etc/apache2/sites-enabled/*.conf"
    "/etc/monitorix/monitorix.conf"
)

# ----------------------------------------------------------
# 7. SERVER4-G5 - PUERTO 2254
# ----------------------------------------------------------

Descargar-Servidor -Puerto 2254 -Servidor "server4-g5" -Copias @(
    "/etc/netplan/*.yaml"
)

# ----------------------------------------------------------
# 8. RESUMEN FINAL
# ----------------------------------------------------------

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "              RESUMEN DE DESCARGAS"
Write-Host "==================================================" -ForegroundColor Cyan

Write-Host "Descargas correctas: $Correctos" -ForegroundColor Green
Write-Host "Descargas fallidas:  $Fallidos" -ForegroundColor Red

Write-Host "`nConfiguraciones guardadas en:"
Write-Host $CARPETA -ForegroundColor Yellow

Write-Host "`nEstructura de archivos:"
Get-ChildItem -Path $CARPETA -Recurse

Write-Host "`nProceso finalizado." -ForegroundColor Cyan

#Para descargar abre powershell como administrador, dirigete al directorio donde esta el script y ejecuta este comando se descargara las configuraciones de los servidores te pedira la contraseña que es: san luis
#.\descargar_configuraciones.ps1>> Set-ExecutionPolicy -Scope Process Bypass -Force
