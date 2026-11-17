#!/bin/bash
# ==============================================================================
# PROYECTO: Infraestructura de Red y Alta Disponibilidad - Grupo 5 (Reto 4)
# ARCHIVO:  auditoria_completa_g5.sh
# DESCRIPCIÓN: Script integral de comprobación de sistema, enrutamiento,
#              seguridad SSH, DNS Maestro/Esclavo, DHCP Failover y Web/Monitorix.
# AUTOR:    Grupo 5 (Cristina, Ibai, Alexandra, Enrique)
# FECHA:    Noviembre 2026
# USO:      chmod +x auditoria_completa_g5.sh && ./auditoria_completa_g5.sh
#           (Para ejecutar todo sin menú: ./auditoria_completa_g5.sh --all)
# ==============================================================================

# --- DEFINICIÓN DE COLORES PARA SALIDA LEGIBLE EN TERMINAL ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CIAN='\033[0;36m'
NEGRITA='\033[1m'
RESET='\033[0m'

# --- VARIABLES GLOBALES DE LA INFRAESTRUCTURA (GRUPO 5) ---
IP_GW_PFSENSE="192.168.5.1"
IP_WAN_PFSENSE="172.26.46.55"
IP_SERVER1="192.168.5.101"
IP_SERVER2="192.168.5.102"
IP_SERVER3="192.168.5.103"
IP_SERVER4="192.168.5.104"
DOMINIO="grupo5reto4.eus"
ZONA_INVERSA="5.168.192.in-addr.arpa"
HOSTNAME_ACTUAL=$(hostname)

# --- FUNCIONES DE FORMATO ---
cabecera() {
    echo -e "\n${AZUL}======================================================================${RESET}"
    echo -e "${NEGRITA}${CIAN}  $1${RESET}"
    echo -e "${AZUL}======================================================================${RESET}"
}

ok() {
    echo -e "  [${VERDE}OK${RESET}] $1"
}

error() {
    echo -e "  [${ROJO}FALLO${RESET}] $1"
}

aviso() {
    echo -e "  [${AMARILLO}INFO${RESET}] $1"
}

# ==============================================================================
# MÓDULO 1: IDENTIDAD DEL SISTEMA, SINCRONIZACIÓN NTP Y SEGURIDAD SSH
# ==============================================================================
comprobar_base_y_ssh() {
    cabecera "1. IDENTIDAD DEL SISTEMA, HORA NTP Y SEGURIDAD SSH ($HOSTNAME_ACTUAL)"

    # 1.1 Fecha y hora exacta (requisito de auditoría)
    echo -e "${NEGRITA}-> Fecha y hora del sistema:${RESET} $(date)"

    # 1.2 Verificación de sincronización NTP
    NTP_SYNC=$(timedatectl show -p NTPSynchronized --value)
    ZONA_HORARIA=$(timedatectl show -p Timezone --value)
    if [[ "$NTP_SYNC" == "yes" ]]; then
        ok "Reloj sincronizado vía NTP (Zona horaria: $ZONA_HORARIA)"
    else
        error "El reloj NO está sincronizado por NTP. Revisa systemd-timesyncd."
    fi

    # 1.3 Verificación de permisos en directorio .ssh y authorized_keys
    if [[ -d "$HOME/.ssh" ]]; then
        PERM_DIR=$(stat -c "%a" "$HOME/.ssh")
        if [[ "$PERM_DIR" == "700" ]]; then
            ok "Permisos de $HOME/.ssh correctos (700)"
        else
            error "Permisos inseguros en $HOME/.ssh ($PERM_DIR). Debe ser 700."
        fi
    else
        aviso "No existe el directorio $HOME/.ssh en este usuario."
    fi

    if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
        PERM_KEYS=$(stat -c "%a" "$HOME/.ssh/authorized_keys")
        TAM_KEYS=$(stat -c "%s" "$HOME/.ssh/authorized_keys")
        if [[ "$PERM_KEYS" == "600" ]]; then
            ok "Permisos de authorized_keys correctos (600) | Tamaño: ${TAM_KEYS} bytes"
        else
            error "Permisos inseguros en authorized_keys ($PERM_KEYS). Debe ser 600."
        fi
    else
        aviso "Fichero authorized_keys no encontrado."
    fi
}

# ==============================================================================
# MÓDULO 2: ENRUTAMIENTO, INTERFACES DE RED Y CONECTIVIDAD PERIMETRAL
# ==============================================================================
comprobar_enrutamiento_y_red() {
    cabecera "2. CONFIGURACIÓN DE RED, ENRUTAMIENTO Y CONECTIVIDAD"

    # 2.1 Mostrar interfaces IPv4 activas
    echo -e "${NEGRITA}-> Interfaces de red activas:${RESET}"
    ip -4 -brief addr show | sed 's/^/     /'

    # 2.2 Mostrar tabla de enrutamiento del kernel
    echo -e "\n${NEGRITA}-> Tabla de enrutamiento IPv4:${RESET}"
    ip route show | sed 's/^/     /'

    # 2.3 Comprobar que la puerta de enlace predeterminada apunta a pfSense (192.168.5.1)
    GW_DETECTADO=$(ip route | awk '/default/ {print $3}')
    if [[ "$GW_DETECTADO" == "$IP_GW_PFSENSE" ]]; then
        ok "Puerta de enlace predeterminada correcta: $GW_DETECTADO (pfSense LAN)"
    else
        error "Puerta de enlace inesperada: '$GW_DETECTADO' (Esperada: $IP_GW_PFSENSE)"
    fi

    # 2.4 Comprobación de conectividad ICMP (Ping) hacia todos los nodos internos y WAN
    echo -e "\n${NEGRITA}-> Pruebas de conectividad ICMP (Ping):${RESET}"
    OBJETIVOS=("$IP_GW_PFSENSE:pfSense-LAN" "$IP_WAN_PFSENSE:pfSense-WAN" "$IP_SERVER1:server1-g5" "$IP_SERVER2:server2-g5" "$IP_SERVER3:server3-g5" "$IP_SERVER4:server4-g5")

    for ITEM in "${OBJETIVOS[@]}"; do
        IP="${ITEM%%:*}"
        NOMBRE="${ITEM##*:}"
        if ping -c 1 -W 1 "$IP" &>/dev/null; then
            ok "Conectividad exitosa con $NOMBRE ($IP)"
        else
            error "Sin respuesta de $NOMBRE ($IP)"
        fi
    done
}

# ==============================================================================
# MÓDULO 3: AUDITORÍA DE SERVICIO DNS REDUNDANTE (BIND9 MAESTRO / ESCLAVO)
# ==============================================================================
comprobar_dns() {
    cabecera "3. SERVICIO DNS REDUNDANTE (BIND9 MAESTRO / ESCLAVO)"

    # 3.1 Si estamos en server1 o server2, auditar el servicio local
    if [[ "$HOSTNAME_ACTUAL" == "server1-g5" || "$HOSTNAME_ACTUAL" == "server2-g5" ]]; then
        if systemctl is-active --quiet bind9; then
            ok "Servicio bind9 activo en $HOSTNAME_ACTUAL"
        else
            error "Servicio bind9 DETENIDO en $HOSTNAME_ACTUAL"
        fi

        # Validar sintaxis de configuración si existe named-checkconf
        if command -v named-checkconf &>/dev/null; then
            if sudo named-checkconf &>/dev/null; then
                ok "Sintaxis de configuración BIND9 (named-checkconf) válida"
            else
                error "Errores de sintaxis detectados en named.conf"
            fi
        fi

        # Comprobación específica según rol Maestro o Esclavo
        if [[ "$HOSTNAME_ACTUAL" == "server1-g5" ]]; then
            aviso "Rol detectado: DNS MAESTRO. Validando archivos de zona..."
            sudo named-checkzone "$DOMINIO" /etc/bind/db.grupo5.local | sed 's/^/     /'
            sudo named-checkzone "$ZONA_INVERSA" /etc/bind/db.192.168.5 | sed 's/^/     /'
        elif [[ "$HOSTNAME_ACTUAL" == "server2-g5" ]]; then
            aviso "Rol detectado: DNS ESCLAVO. Verificando zonas transferidas (AXFR) en /var/cache/bind/..."
            ls -lh /var/cache/bind/db.* 2>/dev/null | sed 's/^/     /'
        fi
    fi

    # 3.2 Pruebas de resolución directa, CNAME e inversa contra AMBOS servidores DNS
    echo -e "\n${NEGRITA}-> Pruebas de resolución cruzada contra Maestro ($IP_SERVER1) y Esclavo ($IP_SERVER2):${RESET}"
    for DNS_IP in "$IP_SERVER1" "$IP_SERVER2"; do
        echo -e "  ${CIAN}* Consultando servidor DNS $DNS_IP:${RESET}"
        
        # Registro A principal (www)
        RES_WWW=$(dig @"$DNS_IP" +short "www.$DOMINIO")
        [[ -n "$RES_WWW" ]] && ok "www.$DOMINIO -> $RES_WWW" || error "Fallo resolviendo www.$DOMINIO en $DNS_IP"

        # Alias CNAME (monitor -> server3-g5)
        RES_MON=$(dig @"$DNS_IP" +short "monitor.$DOMINIO" | tail -n 1)
        [[ -n "$RES_MON" ]] && ok "monitor.$DOMINIO (CNAME) -> $RES_MON" || error "Fallo resolviendo monitor.$DOMINIO en $DNS_IP"

        # Registro externo (reto)
        RES_RETO=$(dig @"$DNS_IP" +short "reto.$DOMINIO")
        [[ -n "$RES_RETO" ]] && ok "reto.$DOMINIO -> $RES_RETO" || error "Fallo resolviendo reto.$DOMINIO en $DNS_IP"

        # Resolución inversa PTR de server3-g5 (192.168.5.103)
        RES_PTR=$(dig @"$DNS_IP" +short -x "$IP_SERVER3")
        [[ -n "$RES_PTR" ]] && ok "Inversa PTR ($IP_SERVER3) -> $RES_PTR" || error "Fallo en resolución inversa PTR en $DNS_IP"
    done
}

# ==============================================================================
# MÓDULO 4: AUDITORÍA DE SERVICIO DHCP EN ALTA DISPONIBILIDAD (FAILOVER)
# ==============================================================================
comprobar_dhcp() {
    cabecera "4. SERVICIO DHCP FAILOVER Y BALANCEO DE CARGA (ISC-DHCP-SERVER)"

    if [[ "$HOSTNAME_ACTUAL" == "server1-g5" || "$HOSTNAME_ACTUAL" == "server2-g5" ]]; then
        # 4.1 Verificar estado del demonio
        if systemctl is-active --quiet isc-dhcp-server; then
            ok "Demonio isc-dhcp-server activo en $HOSTNAME_ACTUAL"
        else
            error "Demonio isc-dhcp-server DETENIDO en $HOSTNAME_ACTUAL"
        fi

        # 4.2 Verificar escucha en puerto UDP 67 y puerto TCP 647 (Failover peer)
        if ss -ulnp | grep -q ":67 "; then
            ok "Servidor escuchando peticiones DHCP en puerto UDP 67"
        else
            error "No se detecta escucha en UDP 67"
        fi

        if ss -tlnp | grep -q ":647 "; then
            ok "Canal de sincronización Failover activo en puerto TCP 647"
        else
            aviso "Puerto TCP 647 (Failover) no está en escucha activa ahora mismo"
        fi

        # 4.3 Extraer último estado del par failover desde dhcpd.leases
        echo -e "\n${NEGRITA}-> Último estado registrado del par 'dhcp-failover' en /var/lib/dhcp/dhcpd.leases:${RESET}"
        if [[ -f /var/lib/dhcp/dhcpd.leases ]]; then
            awk '/failover peer "dhcp-failover"/,/\}/' /var/lib/dhcp/dhcpd.leases | tail -n 6 | sed 's/^/     /'
        else
            error "No se encuentra /var/lib/dhcp/dhcpd.leases"
        fi
    else
        # Si es cliente (ej. server4-g5), verificar concesión recibida
        aviso "Nodo cliente ($HOSTNAME_ACTUAL): Verificando concesión DHCP actual..."
        if [[ -f /var/lib/dhcp/dhclient.leases ]]; then
            grep -E "fixed-address|dhcp-server-identifier|expire" /var/lib/dhcp/dhclient.leases | tail -n 4 | sed 's/^/     /'
        else
            ip -4 addr show eth0 | grep "inet " | sed 's/^/     /'
        fi
    fi
}

# ==============================================================================
# MÓDULO 5: AUDITORÍA DE SERVIDOR WEB (APACHE2) Y MONITORIZACIÓN (MONITORIX)
# ==============================================================================
comprobar_web_y_monitorix() {
    cabecera "5. SERVIDOR WEB APACHE2 Y MONITORIZACIÓN MONITORIX"

    # 5.1 Si estamos en server3-g5, comprobar servicios locales
    if [[ "$HOSTNAME_ACTUAL" == "server3-g5" ]]; then
        for SERV in apache2 monitorix; do
            if systemctl is-active --quiet "$SERV"; then
                ok "Servicio $SERV activo y en ejecución"
            else
                error "Servicio $SERV NO está activo"
            fi
        done

        # Verificar puertos locales 80 y 8581
        ss -tlnp | grep -q ":80 " && ok "Apache2 escuchando en puerto TCP 80" || error "Puerto 80 cerrado"
        ss -tlnp | grep -q ":8581 " && ok "Monitorix escuchando en puerto TCP 8581" || error "Puerto 8581 cerrado"
    fi

    # 5.2 Pruebas HTTP reales desde cualquier nodo de la red hacia server3-g5 y NAT pfSense
    echo -e "\n${NEGRITA}-> Pruebas de respuesta HTTP (Códigos de estado):${RESET}"
    
    # Prueba directa interna a Apache2
    CODE_APACHE_INT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://$IP_SERVER3:80")
    [[ "$CODE_APACHE_INT" == "200" ]] && ok "Acceso interno Web Apache2 (http://$IP_SERVER3:80) -> HTTP 200 OK" || error "Fallo acceso interno Web (Código: $CODE_APACHE_INT)"

    # Prueba externa vía NAT pfSense puerto 8580
    CODE_APACHE_EXT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://$IP_WAN_PFSENSE:8580")
    [[ "$CODE_APACHE_EXT" == "200" ]] && ok "Acceso externo NAT Web (http://$IP_WAN_PFSENSE:8580) -> HTTP 200 OK" || aviso "Acceso NAT 8580 devolvió código: $CODE_APACHE_EXT"

    # Prueba directa interna a Monitorix
    CODE_MON_INT=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://$IP_SERVER3:8581/monitorix/")
    [[ "$CODE_MON_INT" == "200" ]] && ok "Acceso interno Monitorix (http://$IP_SERVER3:8581/monitorix/) -> HTTP 200 OK" || error "Fallo acceso interno Monitorix (Código: $CODE_MON_INT)"
}

# ==============================================================================
# MENÚ INTERACTIVO O EJECUCIÓN COMPLETA (--all)
# ==============================================================================
ejecutar_todo() {
    comprobar_base_y_ssh
    comprobar_enrutamiento_y_red
    comprobar_dns
    comprobar_dhcp
    comprobar_web_y_monitorix
    echo -e "\n${VERDE}=== AUDITORÍA COMPLETA FINALIZADA ($(date)) ===${RESET}\n"
}

# Si se pasa el parámetro --all, ejecuta todas las pruebas de golpe
if [[ "$1" == "--all" ]]; then
    ejecutar_todo
    exit 0
fi

# Menú interactivo
while true; do
    echo -e "\n${NEGRITA}${AZUL}======================================================${RESET}"
    echo -e "${NEGRITA}   HERRAMIENTA DE AUDITORÍA Y ENRUTAMIENTO - GRUPO 5   ${RESET}"
    echo -e "${NEGRITA}${AZUL}======================================================${RESET}"
    echo "  1) Comprobar Identidad, Hora NTP y Seguridad SSH"
    echo "  2) Comprobar Enrutamiento, Tabla IP y Conectividad Red"
    echo "  3) Comprobar Servicio DNS Redundante (BIND9)"
    echo "  4) Comprobar Servicio DHCP Failover (ISC-DHCP)"
    echo "  5) Comprobar Servidor Web Apache2 y Monitorix"
    echo "  6) EJECUTAR AUDITORÍA COMPLETA (Todos los módulos)"
    echo "  0) Salir"
    echo -n "Selecciona una opción [0-6]: "
    read -r OPCION

    case $OPCION in
        1) comprobar_base_y_ssh ;;
        2) comprobar_enrutamiento_y_red ;;
        3) comprobar_dns ;;
        4) comprobar_dhcp ;;
        5) comprobar_web_y_monitorix ;;
        6) ejecutar_todo ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) error "Opción no válida. Inténtalo de nuevo." ;;
    esac
done