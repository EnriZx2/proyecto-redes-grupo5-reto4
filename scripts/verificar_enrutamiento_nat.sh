#!/bin/bash
# ==============================================================================
# PROYECTO: Infraestructura de Red - Grupo 5 (Reto 4)
# ARCHIVO:  verificar_enrutamiento_nat.sh
# DESCRIPCIÓN: Verifica la salida a través del gateway pfSense, el enrutamiento
#              entre subredes (LAN -> WAN) y el mapeo de puertos NAT externos.
# ==============================================================================

GW_LAN="192.168.5.1"
IP_WAN="172.26.46.55"
IP_EXTERNA_RETO="172.16.250.105"

echo "=== AUDITORÍA DE ENRUTAMIENTO Y PUERTOS NAT ($(date)) ==="

# 1. Comprobar que el reenvío de paquetes y ruta por defecto existen
echo -e "\n[1] Ruta por defecto configurada:"
ip route | grep default || echo "ERROR: No hay ruta por defecto"

# 2. Trazado de ruta hacia la red externa (WAN / Aula)
echo -e "\n[2] Trazado de saltos hacia el servidor externo ($IP_EXTERNA_RETO):"
if command -v traceroute &>/dev/null; then
    traceroute -n -m 5 "$IP_EXTERNA_RETO"
else
    tracepath -n -m 5 "$IP_EXTERNA_RETO"
fi

# 3. Verificación de puertos publicados mediante NAT en pfSense (172.26.46.55)
echo -e "\n[3] Comprobando disponibilidad de puertos NAT en pfSense ($IP_WAN):"
PUERTOS_NAT=(
    "2251:SSH-server1-g5"
    "2252:SSH-server2-g5"
    "2253:SSH-server3-g5"
    "2254:SSH-server4-g5"
    "8580:HTTP-Apache2-server3"
    "8581:Monitorix-server3"
)

for ENTRADA in "${PUERTOS_NAT[@]}"; do
    PUERTO="${ENTRADA%%:*}"
    SERVICIO="${ENTRADA##*:}"
    # Comprueba mediante netcat (nc) si el puerto TCP responde a través del NAT
    if nc -z -w 2 "$IP_WAN" "$PUERTO" 2>/dev/null; then
        echo "  [ABIERTO] Puerto $PUERTO ($SERVICIO) accesible en $IP_WAN"
    else
        echo "  [CERRADO] Puerto $PUERTO ($SERVICIO) no responde en $IP_WAN"
    fi
done