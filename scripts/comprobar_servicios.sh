#!/bin/bash
# ==============================================================================
# Script de Auditoría Integral y Comprobación Total - Grupo 5 (Reto 4)
# Autor: Grupo 5 (Cristina, Ibai, Alexandra, Enrique)
# Descripción: Verifica sistema, NTP, seguridad SSH, red, enrutamiento, NAT,
#              DNS Maestro/Esclavo, DHCP Failover y Web Apache2/Monitorix.
# ==============================================================================

HOSTNAME=$(hostname)
DOMINIO="grupo5reto4.eus"
ZONA_INV="5.168.192.in-addr.arpa"
GW_PFSENSE="192.168.5.1"
WAN_PFSENSE="172.26.46.55"
IP_S1="192.168.5.101"
IP_S2="192.168.5.102"
IP_S3="192.168.5.103"
IP_S4="192.168.5.104"

echo "=========================================================================="
echo "   AUDITORÍA TOTAL DE INFRAESTRUCTURA - GRUPO 5 (RETO 4) - NODO: $HOSTNAME"
echo "=========================================================================="

echo -e "\n=== 1. IDENTIDAD, RECURSOS Y SINCRONIZACIÓN HORARIA (NTP) ==="
date
hostnamectl --static
uptime -p
free -h | awk '/^Mem:/ {print "Memoria RAM: Usada " $3 " / Total " $2}'
df -h / | awk 'NR==2 {print "Disco Raíz (/): Usado " $3 " de " $2 " (" $5 ")"}'
timedatectl | grep -E "Time zone|synchronized|NTP"

echo -e "\n=== 2. SEGURIDAD SSH Y PERMISOS DE CLAVE PÚBLICA ==="
systemctl is-active ssh
if [[ -d "$HOME/.ssh" ]]; then
    stat -c "Directorio %n -> Permisos: %a | Propietario: %U:%G" "$HOME/.ssh"
fi
if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
    stat -c "Fichero    %n -> Permisos: %a | Tamaño: %s bytes | Claves: " "$HOME/.ssh/authorized_keys" | tr -d '\n'
    wc -l < "$HOME/.ssh/authorized_keys"
else
    echo "AVISO: No existe $HOME/.ssh/authorized_keys"
fi

echo -e "\n=== 3. INTERFACES DE RED, NETPLAN Y ENRUTAMIENTO ==="
ip -4 -brief a
echo "--- Tabla de enrutamiento ---"
ip route show
echo "--- Servidores DNS configurados en el sistema ---"
resolvectl status 2>/dev/null | grep -E "DNS Servers|DNS Domain" || grep "nameserver" /etc/resolv.conf

echo -e "\n=== 4. CONECTIVIDAD ICMP (PING) ENTRE TODOS LOS NODOS Y PFSENSE ==="
for NODO in "$GW_PFSENSE:pfSense-LAN" "$WAN_PFSENSE:pfSense-WAN" "$IP_S1:server1-g5" "$IP_S2:server2-g5" "$IP_S3:server3-g5" "$IP_S4:server4-g5"; do
    IP="${NODO%%:*}"
    NOMBRE="${NODO##*:}"
    if ping -c 1 -W 1 "$IP" &>/dev/null; then
        echo "[OK]    Conectividad con $NOMBRE ($IP)"
    else
        echo "[FALLO] Sin respuesta de $NOMBRE ($IP)"
    fi
done

echo -e "\n=== 5. COMPROBACIÓN DE SERVICIOS ESPECÍFICOS SEGÚN ROL DEL NODO ==="
if [[ "$HOSTNAME" == "server1-g5" || "$HOSTNAME" == "server2-g5" ]]; then
    echo "--- [DNS] Estado BIND9 y Sincronización de Zonas ---"
    systemctl is-active bind9
    sudo rndc status | grep -E "version|number of zones|server is"
    
    if [[ "$HOSTNAME" == "server1-g5" ]]; then
        echo "Validando sintaxis y zonas en DNS MAESTRO:"
        sudo named-checkconf && echo "[OK] named-checkconf sin errores"
        sudo named-checkzone "$DOMINIO" /etc/bind/db.grupo5.local
        sudo named-checkzone "$ZONA_INV" /etc/bind/db.192.168.5
    else
        echo "Verificando archivos replicados (AXFR) en DNS ESCLAVO:"
        ls -lh /var/cache/bind/db.* 2>/dev/null || echo "AVISO: No se encontraron archivos en /var/cache/bind/"
    fi

    echo -e "\n--- [DHCP] Estado ISC-DHCP-SERVER y Clúster Failover ---"
    systemctl is-active isc-dhcp-server
    ss -tulpn | grep -E ':67|:647'
    echo "Último estado del par failover en dhcpd.leases:"
    awk '/failover peer "dhcp-failover"/,/\}/' /var/lib/dhcp/dhcpd.leases | tail -n 6
    echo "Concesiones activas registradas:"
    grep -E "lease 192.168.5.|binding state active" /var/lib/dhcp/dhcpd.leases | tail -n 6

elif [[ "$HOSTNAME" == "server3-g5" ]]; then
    echo "--- [WEB & MONITORIX] Estado de Servicios y Puertos ---"
    systemctl is-active apache2 monitorix
    ss -tulpn | grep -E ':80|:8581'
    echo "Contenido de /var/www/html/:"
    ls -lh /var/www/html/

else
    echo "--- [CLIENTE DHCP] Estado de Concesión IP en $HOSTNAME ---"
    ip -4 addr show eth0 | grep "inet "
    if [[ -f /var/lib/dhcp/dhclient.leases ]]; then
        grep -E "fixed-address|dhcp-server-identifier|expire" /var/lib/dhcp/dhclient.leases | tail -n 4
    fi
fi

echo -e "\n=== 6. RESOLUCIÓN DNS CRUZADA (MAESTRO .101 Y ESCLAVO .102) ==="
for DNS in "$IP_S1" "$IP_S2"; do
    echo "--- Consultando servidor DNS $DNS ---"
    echo -n "  www.$DOMINIO (A):       " && dig @"$DNS" +short "www.$DOMINIO" | tr '\n' ' ' && echo ""
    echo -n "  monitor.$DOMINIO (CNAME): " && dig @"$DNS" +short "monitor.$DOMINIO" | tr '\n' ' ' && echo ""
    echo -n "  reto.$DOMINIO (A):      " && dig @"$DNS" +short "reto.$DOMINIO" | tr '\n' ' ' && echo ""
    echo -n "  Inversa PTR ($IP_S3): " && dig @"$DNS" +short -x "$IP_S3" | tr '\n' ' ' && echo ""
done

echo -e "\n=== 7. COMPROBACIÓN DE SERVICIOS WEB Y PUERTOS NAT PFSENSE ==="
echo -n "  Web interna Apache2 (http://$IP_S3:80):         HTTP "
curl -s -o /dev/null -w "%{http_code}\n" --connect-timeout 2 "http://$IP_S3:80"

echo -n "  Web externa NAT     (http://$WAN_PFSENSE:8580): HTTP "
curl -s -o /dev/null -w "%{http_code}\n" --connect-timeout 2 "http://$WAN_PFSENSE:8580"

echo -n "  Monitorix interno   (http://$IP_S3:8581):       HTTP "
curl -s -o /dev/null -w "%{http_code}\n" --connect-timeout 2 "http://$IP_S3:8581/monitorix/"

echo "  Estado de puertos SSH/Web/Monitorix publicados en pfSense ($WAN_PFSENSE):"
for PUERTO in 2251 2252 2253 2254 8580 8581; do
    if nc -z -w 1 "$WAN_PFSENSE" "$PUERTO" 2>/dev/null; then
        echo "    [ABIERTO] $WAN_PFSENSE:$PUERTO"
    else
        echo "    [CERRADO] $WAN_PFSENSE:$PUERTO"
    fi
done

echo -e "\n=========================================================================="
echo "   FIN DE LA AUDITORÍA - $(date)"
echo "=========================================================================="