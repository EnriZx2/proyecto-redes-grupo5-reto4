# Informe Técnico Integral de Infraestructura y Servicios — Grupo 5 (Reto 4)

## Índice

1. [Introducción y arquitectura general del sistema](#1-introducción-y-arquitectura-general-del-sistema)
2. [Acceso remoto seguro mediante clave pública SSH](#2-acceso-remoto-seguro-mediante-clave-pública-ssh)
3. [Fase 1: preparación base de servidores, red (Netplan) y sincronización NTP](#3-fase-1-preparación-base-de-servidores-red-netplan-y-sincronización-ntp)
4. [Fase 2: firewall perimetral, NAT y DNS Resolver (pfSense)](#4-fase-2-firewall-perimetral-nat-y-dns-resolver-pfsense)
5. [Fase 3: servicio DHCP en alta disponibilidad (Failover y balanceo)](#5-fase-3-servicio-dhcp-en-alta-disponibilidad-failover-y-balanceo)
6. [Fase 4: servicio DNS redundante (BIND9 maestro / esclavo)](#6-fase-4-servicio-dns-redundante-bind9-maestro--esclavo)
7. [Fase 5: servidor web (Apache2) y monitorización (Monitorix)](#7-fase-5-servidor-web-apache2-y-monitorización-monitorix)
8. [Conclusiones y líneas de mejora futura](#8-conclusiones-y-líneas-de-mejora-futura)
9. [Anexo I. Evidencias gráficas de configuración y pruebas](#anexo-i-evidencias-gráficas-de-configuración-y-pruebas)

---

## 1. Introducción y arquitectura general del sistema

El presente informe técnico documenta el diseño, despliegue, configuración, seguridad y validación de la infraestructura de red y servicios de alta disponibilidad desarrollada por el **Grupo 5** para el **Reto 4** (*Gran Premio de Euskadi - Bilbao 2026*).

El objetivo principal del proyecto es implementar una arquitectura empresarial segmentada, segura y tolerante a fallos capaz de suministrar servicios críticos (direccionamiento dinámico DHCP, resolución de nombres DNS autoritativa, alojamiento web y monitorización de recursos) eliminando puntos únicos de fallo (SPOF).

### 1.1. Diseño topológico y segmentación de red

La infraestructura se estructura en dos segmentos aislados mediante un cortafuegos perimetral **pfSense**:

* **Red Externa / Aula (WAN — `172.26.44.0/24`):** Representa el entorno externo desde donde operan los puestos de administración del equipo (Cristina `.24`, Ibai `.8`, Alexandra `.25`, Enrique `.23`) y los clientes que acceden a los servicios publicados. La interfaz WAN del firewall recibe la dirección IP **`172.26.46.55`**.
* **Red Interna / Servidores (LAN — `192.168.5.0/24`):** Subred privada aislada tras el firewall (`192.168.5.1` como puerta de enlace predeterminada), donde operan cuatro máquinas virtuales **Ubuntu 22.04.5 LTS** virtualizadas sobre **KVM/QEMU**.

```text
====================================================================================================
                             RED EXTERNA / AULA (WAN: 172.26.44.0/24)
   Puestos Grupo 5: Cristina (.24), Ibai (.8), Alexandra (.25), Enrique (.23)
   Servidor externo de referencia: reto.grupo5reto4.eus -> 172.16.250.105
====================================================================================================
                                                |
                                                | IP WAN: 172.26.46.55
                                  +---------------------------+
                                  |     FIREWALL pfSense      |
                                  |  - NAT / Port Forwarding  |
                                  |  - DNS Resolver (Unbound) |
                                  |  - DHCP LAN Desactivado   |
                                  +---------------------------+
                                                | IP LAN: 192.168.5.1 (Gateway)
                                                |
------------------------------------------------+---------------------------------------------------
                                   RED INTERNA (LAN: 192.168.5.0/24)
----------------------------------------------------------------------------------------------------
          |                              |                              |                         |
+-------------------+          +-------------------+          +-------------------+     +-------------------+
|    server1-g5     |          |    server2-g5     |          |    server3-g5     |     |    server4-g5     |
| IP: 192.168.5.101 |          | IP: 192.168.5.102 |          | IP: 192.168.5.103 |     | IP: 192.168.5.104 |
+-------------------+          +-------------------+          +-------------------+     +-------------------+
| - DNS Maestro     |  AXFR    | - DNS Esclavo     |          | - Web Apache2     |     | - Cliente Linux   |
|   (BIND9)         |=========>|   (BIND9)         |          |   (Puerto 80)     |     |   (Pruebas DHCP)  |
| - DHCP Primary    | Failover | - DHCP Secondary  |          | - Monitorix       |     | - SSH (Pto 2254)  |
|   (isc-dhcp)      |<========>|   (isc-dhcp)      |          |   (Puerto 8581)   |     |                   |
| - SSH (Pto 2251)  |          | - SSH (Pto 2252)  |          | - SSH (Pto 2253)  |     |                   |
+-------------------+          +-------------------+          +-------------------+     +-------------------+
```

### 1.2. Tabla resumen de nodos y direccionamiento IP

| Nodo / equipo | Sistema operativo | IP interna (LAN) | IP externa / puertos NAT (WAN) | Roles y servicios principales |
| :--- | :--- | :--- | :--- | :--- |
| **pfSense** | FreeBSD (pfSense CE) | `192.168.5.1/24` | `172.26.46.55` | Firewall perimetral, NAT Port Forward y DNS Resolver (Unbound). |
| **`server1-g5`** | Ubuntu 22.04.5 LTS | `192.168.5.101` | `172.26.46.55:2251` (SSH)<br>`172.26.46.55:53` (DNS) | DNS maestro (BIND9) y DHCP primario (ISC-DHCP). |
| **`server2-g5`** | Ubuntu 22.04.5 LTS | `192.168.5.102` | `172.26.46.55:2252` (SSH) | DNS esclavo mediante AXFR y DHCP secundario. |
| **`server3-g5`** | Ubuntu 22.04.5 LTS | `192.168.5.103` | `172.26.46.55:8580` (HTTP)<br>`172.26.46.55:8581` (Monitorix)<br>`172.26.46.55:2253` (SSH) | Servidor web Apache2 y monitorización Monitorix. |
| **`server4-g5`** | Ubuntu 22.04.5 LTS | `192.168.5.104` (dinámica) | `172.26.46.55:2254` (SSH) | Cliente Linux para pruebas DHCP y DNS. |

---

## 2. Acceso remoto seguro mediante clave pública SSH

### 2.1. Metodología y despliegue de autenticación asimétrica

Para administrar los cuatro servidores de forma segura desde los equipos del aula sin transmitir contraseñas por la red ni exponerse a ataques de fuerza bruta, se implementó autenticación SSH basada en criptografía de clave pública (par de claves Ed25519).

* **Paso 1: Generación del par de claves en el equipo cliente (PC Administrador)**
  En cada puesto de trabajo se generó un par de claves (clave privada guardada localmente en `~/.ssh/id_ed25519` y clave pública en `~/.ssh/id_ed25519.pub`):

```bash
ssh-keygen -t ed25519 -C "admin@grupo5reto4.eus"
```

* **Paso 2: Preparación del directorio y permisos estrictos en los servidores (`server1-g5` a `server4-g5`)**
  El demonio OpenSSH (`sshd`) exige por seguridad que ni el directorio `.ssh` ni el archivo `authorized_keys` puedan ser leídos o modificados por otros usuarios del sistema. En cada servidor se ejecutó:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

* **Paso 3: Instalación de la clave pública en los servidores**
  Se transfirió el contenido de la clave pública del cliente dentro de `/home/alumno/.ssh/authorized_keys` (de ahí su tamaño de 381 bytes verificado en `server1-g5` y `server2-g5`):

```bash
# Copia automática usando los puertos NAT configurados en pfSense:
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2251 alumno@172.26.46.55
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2252 alumno@172.26.46.55
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2253 alumno@172.26.46.55
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2254 alumno@172.26.46.55
```

* **Paso 4: Comandos de conexión directa desde el exterior (vía NAT pfSense)**
  Gracias a las reglas *Port Forward* de pfSense (`172.26.46.55`), la administración remota sin contraseña de cada servidor interno se realiza mediante los siguientes comandos:

| Servidor destino | IP interna | Puerto externo NAT | Comando de conexión con clave pública |
| :--- | :--- | :--- | :--- |
| **`server1-g5`** | `192.168.5.101` | `2251` | `ssh -i ~/.ssh/id_ed25519 -p 2251 alumno@172.26.46.55` |
| **`server2-g5`** | `192.168.5.102` | `2252` | `ssh -i ~/.ssh/id_ed25519 -p 2252 alumno@172.26.46.55` |
| **`server3-g5`** | `192.168.5.103` | `2253` | `ssh -i ~/.ssh/id_ed25519 -p 2253 alumno@172.26.46.55` |
| **`server4-g5`** | `192.168.5.104` | `2254` | `ssh -i ~/.ssh/id_ed25519 -p 2254 alumno@172.26.46.55` |

---

## 3. Fase 1: preparación base de servidores, red (Netplan) y sincronización NTP

### 3.1. Desarrollo y comandos de configuración base

Antes de desplegar los servicios de red, se estandarizó el entorno base en los cuatro nodos **Ubuntu 22.04.5 LTS**:

* **Identidad del sistema y sincronización NTP:** Se configuraron los nombres estáticos (`server1-g5` a `server4-g5`) y la zona horaria `Europe/Madrid` con sincronización NTP activa, requisito indispensable para evitar desfases en los números de serie SOA de DNS y los tiempos de concesión (`mclt`) del clúster DHCP Failover.
* **Configuración de red con Netplan (`/etc/netplan/00-installer-config.yaml`):**
  * `server1-g5` (`.101`), `server2-g5` (`.102`) y `server3-g5` (`.103`) se configuraron con IPv4 estática, puerta de enlace `192.168.5.1` y servidores DNS internos `192.168.5.101` y `192.168.5.102`.
  * `server4-g5` se configuró como cliente dinámico (`dhcp4: true`).

```bash
# Comandos ejecutados en cada nodo (sustituyendo X por 1, 2, 3 o 4):
sudo hostnamectl set-hostname serverX-g5
sudo timedatectl set-timezone Europe/Madrid
sudo timedatectl set-ntp true

# Configuración Netplan estática en server1-g5, server2-g5 y server3-g5:
cat << 'EOF' | sudo tee /etc/netplan/00-installer-config.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses: [192.168.5.10X/24]
      routes:
        - to: default
          via: 192.168.5.1
      nameservers:
        addresses: [192.168.5.101, 192.168.5.102]
        search: [grupo5reto4.eus]
EOF
sudo netplan apply
```

*(Ver evidencias gráficas en el [Anexo I — Sección 1](#1-preparación-base-ntp-y-acceso-ssh)).*

---

## 4. Fase 2: firewall perimetral, NAT y DNS Resolver (pfSense)

### 4.1. Desarrollo y configuración realizada

El cortafuegos **pfSense** (`172.26.46.55` en WAN / `192.168.5.1` en LAN) aísla la red interna y publica únicamente los servicios necesarios hacia el exterior:

1. **Desactivación del servidor DHCP en pfSense:** Se desmarcó la casilla *Enable DHCP server on LAN interface* en *Services > DHCP Server > LAN* para evitar colisiones con el clúster ISC-DHCP dedicado de `server1-g5` y `server2-g5`.
2. **Reglas NAT (*Port Forward*):** Se tradujeron puertos externos de la IP WAN `172.26.46.55` hacia los hosts internos de `192.168.5.0/24`:
   * `53 TCP/UDP` $\rightarrow$ `192.168.5.101:53` (DNS).
   * `2251`, `2252`, `2253`, `2254` $\rightarrow$ Puerto `22` de `.101`, `.102`, `.103` y `.104` (SSH).
   * `8580` $\rightarrow$ `192.168.5.103:80` (Portal web Apache2).
   * `8581` $\rightarrow$ `192.168.5.103:8581` (Panel Monitorix).
3. **Reglas de Filtrado WAN:** Se autorizó el acceso DNS (`53`) a las IPs de los cuatro integrantes del grupo (Cristina `.24`, Ibai `.8`, Alexandra `.25`, Enrique `.23`), la administración web de pfSense (`80/443`) y el tráfico vinculado a las reglas NAT.
4. **DNS Resolver (*Unbound Host Overrides*):** Se configuraron registros estáticos para resolver `www.grupo5reto4.eus` y `monitor.grupo5reto4.eus` hacia `172.26.46.55`, y `reto.grupo5reto4.eus` hacia `172.16.250.105`.

*(Ver evidencias gráficas en el [Anexo I — Sección 2](#2-firewall-perimetral-nat-y-dns-resolver-pfsense)).*

---

## 5. Fase 3: servicio DHCP en alta disponibilidad (Failover y balanceo)

### 5.1. Desarrollo y comandos de configuración

Se desplegó el servicio `isc-dhcp-server` en modo **Failover activo-activo** con balanceo de carga (`split 128`, reparto 50/50) entre `server1-g5` (*Primary*) y `server2-g5` (*Secondary*) sobre un pool de 50 direcciones IP (`192.168.5.104` a `192.168.5.153`), comunicándose ambos nodos por el puerto TCP `647` con un tiempo `mclt` de `1800` segundos.

```bash
# Instalación y fijación de interfaz eth0 (en server1-g5 y server2-g5):
sudo apt update && sudo apt install -y isc-dhcp-server
sudo sed -i 's/INTERFACESv4=""/INTERFACESv4="eth0"/' /etc/default/isc-dhcp-server

# Configuración /etc/dhcp/dhcpd.conf en server1-g5 (Primary):
cat << 'EOF' | sudo tee /etc/dhcp/dhcpd.conf
authoritative;
default-lease-time 43200;
max-lease-time 86400;

failover peer "dhcp-failover" {
  primary;
  address 192.168.5.101;
  port 647;
  peer address 192.168.5.102;
  peer port 647;
  max-response-delay 60;
  max-unacked-updates 10;
  load balance max seconds 3;
  mclt 1800;
  split 128;
}

subnet 192.168.5.0 netmask 255.255.255.0 {
  option routers 192.168.5.1;
  option subnet-mask 255.255.255.0;
  option domain-name "grupo5reto4.eus";
  option domain-name-servers 192.168.5.101, 192.168.5.102;

  pool {
    failover peer "dhcp-failover";
    range 192.168.5.104 192.168.5.153;
  }
}
EOF
sudo systemctl restart isc-dhcp-server
```

*(Nota: En `server2-g5` se aplicó la misma estructura declarando el rol `secondary;`, intercambiando `address 192.168.5.102` y `peer address 192.168.5.101`, y omitiendo `mclt` y `split` propios del nodo primario).*

*(Ver evidencias gráficas en el [Anexo I — Sección 3](#3-servicio-dhcp-en-alta-disponibilidad-failover)).*

---

## 6. Fase 4: servicio DNS redundante (BIND9 maestro / esclavo)

### 6.1. Desarrollo y comandos de configuración

Se implementó un sistema DNS autoritativo redundante con **BIND9** para la zona directa `grupo5reto4.eus` y su zona inversa `5.168.192.in-addr.arpa`:

```bash
# Instalación en server1-g5 y server2-g5:
sudo apt update && sudo apt install -y bind9 bind9utils bind9-doc

# 1. Configuración de zonas en server1-g5 (Maestro - /etc/bind/named.conf.local):
cat << 'EOF' | sudo tee /etc/bind/named.conf.local
zone "grupo5reto4.eus" {
    type master;
    file "/etc/bind/db.grupo5.local";
    allow-transfer { 192.168.5.102; };
    also-notify { 192.168.5.102; };
};

zone "5.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192.168.5";
    allow-transfer { 192.168.5.102; };
    also-notify { 192.168.5.102; };
};
EOF

# 2. Zona directa (/etc/bind/db.grupo5.local):
cat << 'EOF' | sudo tee /etc/bind/db.grupo5.local
$TTL 86400
@   IN  SOA server1-g5.grupo5reto4.eus. admin.grupo5reto4.eus. (
            2026110607 ; Serial
            3600       ; Refresh
            1800       ; Retry
            604800     ; Expire
            86400 )    ; Negative Cache TTL
;
@           IN  NS      server1-g5.grupo5reto4.eus.
@           IN  NS      server2-g5.grupo5reto4.eus.
server1-g5  IN  A       192.168.5.101
server2-g5  IN  A       192.168.5.102
server3-g5  IN  A       192.168.5.103
server4-g5  IN  A       192.168.5.104
www         IN  A       172.26.46.55
reto        IN  A       172.16.250.105
monitor     IN  CNAME   server3-g5.grupo5reto4.eus.
EOF

# 3. Zona inversa (/etc/bind/db.192.168.5):
cat << 'EOF' | sudo tee /etc/bind/db.192.168.5
$TTL 86400
@   IN  SOA server1-g5.grupo5reto4.eus. admin.grupo5reto4.eus. (
            2026110501 ; Serial
            3600       ; Refresh
            1800       ; Retry
            604800     ; Expire
            86400 )    ; Negative Cache TTL
;
@       IN  NS  server1-g5.grupo5reto4.eus.
@       IN  NS  server2-g5.grupo5reto4.eus.
101     IN  PTR server1-g5.grupo5.local.
102     IN  PTR server2-g5.grupo5.local.
103     IN  PTR server3-g5.grupo5.local.
104     IN  PTR server4-g5.grupo5.local.
EOF
sudo systemctl restart bind9

# 4. Configuración de zonas en server2-g5 (Esclavo - /etc/bind/named.conf.local):
cat << 'EOF' | sudo tee /etc/bind/named.conf.local
zone "grupo5reto4.eus" {
    type slave;
    file "/var/cache/bind/db.grupo5reto4.eus";
    masters { 192.168.5.101; };
};

zone "5.168.192.in-addr.arpa" {
    type slave;
    file "/var/cache/bind/db.192.168.5.s";
    masters { 192.168.5.101; };
};
EOF
sudo systemctl restart bind9
```

*(Ver evidencias gráficas en el [Anexo I — Sección 4](#4-servicio-dns-redundante-bind9-maestro--esclavo)).*

---

## 7. Fase 5: servidor web (Apache2) y monitorización (Monitorix)

### 7.1. Desarrollo y comandos de configuración

En `server3-g5` (`192.168.5.103`) se desplegó el servidor web **Apache2** (puerto `80`) alojando el portal *Gran Premio de Euskadi - Bilbao 2026* en `/var/www/html/` y la herramienta de monitorización **Monitorix** escuchando en el puerto `8581`.

```bash
# Instalación de Apache2 y Monitorix en server3-g5:
sudo apt update && sudo apt install -y apache2 monitorix

# Configuración de permisos del portal web en /var/www/html/:
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/

# Habilitación de servicios:
sudo systemctl enable --now apache2 monitorix
```

*(Ver evidencias gráficas en el [Anexo I — Sección 5](#5-servidor-web-apache2-y-monitorización-monitorix)).*

---

## 8. Conclusiones y líneas de mejora futura

### 8.1. Conclusiones

El despliegue realizado por el **Grupo 5** para el **Reto 4** (*Gran Premio de Euskadi - Bilbao 2026*) cumple satisfactoriamente con todos los objetivos técnicos planteados, logrando construir una infraestructura empresarial segmentada, segura y de alta disponibilidad mediante la eliminación de puntos únicos de fallo (SPOF).

A lo largo de las cinco fases del proyecto se ha validado el correcto funcionamiento e integración de todos los componentes críticos:

* **Segmentación y seguridad perimetral:** La arquitectura aislada detrás de **pfSense** (`192.168.5.0/24`), junto con las reglas estrictas de filtrado WAN, el mapeo controlado de puertos NAT y la administración remota mediante claves asimétricas **SSH (Ed25519)**, garantiza que únicamente los servicios autorizados sean accesibles desde el exterior sin comprometer la integridad interna de los servidores.
* **Tolerancia a fallos en servicios esenciales (DHCP y DNS):** Las pruebas de simulación de caída (*failover*) realizadas deteniendo los servicios en `server1-g5` confirmaron la continuidad operativa sin interrupción de servicio. El clúster **ISC-DHCP** en modo activo-activo (balanceo 50/50) y la replicación **BIND9 Maestro-Esclavo** mediante transferencias AXFR permitieron que `server2-g5` asumiera de forma transparente tanto la concesión de direcciones dinámicas como la resolución directa e inversa de nombres.
* **Publicación web y observabilidad:** El despliegue del portal oficial en **Apache2** sobre `server3-g5`, respaldado por el panel de métricas en tiempo real **Monitorix**, asegura la disponibilidad del servicio de cara al usuario final y proporciona visibilidad constante sobre el rendimiento y estado de los recursos del sistema.

En definitiva, la solución implementada demuestra la viabilidad y solidez de combinar software libre sobre entornos virtualizados (KVM/QEMU y Ubuntu Server) con políticas de red robustas para ofrecer servicios críticos resilientes y escalables en producción.

### 8.2. Líneas de mejora futura

De cara a una evolución hacia un entorno productivo de mayor envergadura, se proponen las siguientes mejoras:

* **Cifrado de extremo a extremo (HTTPS interno):** Implementar certificados SSL/TLS en Apache2 (mediante una CA interna o Let's Encrypt) para cifrar también el tráfico web en el tramo LAN entre pfSense y `server3-g5`.
* **Endurecimiento adicional de SSH (*Hardening*):** Deshabilitar explícitamente el inicio de sesión mediante contraseña (`PasswordAuthentication no`) y el acceso directo como superusuario (`PermitRootLogin no`) en `/etc/ssh/sshd_config`.
* **Centralización de registros (*Logging*):** Desplegar un servidor `rsyslog` centralizado o una pila ELK/Grafana Loki para auditar de forma unificada los eventos de seguridad de pfSense, las concesiones DHCP y las peticiones DNS/HTTP.

---

## Anexo I. Evidencias gráficas de configuración y pruebas

### 1. Preparación Base, NTP y Acceso SSH

#### Captura 1: Verificación base en `server1-g5`
![Verificación server1](capturas/Captura2.PNG)

* **Qué se prueba:** Identidad del servidor (`hostnamectl`), sincronización horaria NTP (`timedatectl`) y permisos del archivo `~/.ssh/authorized_keys`.
* **Resultado obtenido:** Sistema Ubuntu 22.04.5 LTS activo, reloj sincronizado en zona `Europe/Madrid` y fichero `authorized_keys` con permisos `600` (`-rw-------`) y 381 bytes.
* **Autor de la captura:** Ibai.

#### Captura 2: Verificación base en `server2-g5`
![Verificación server2](capturas/Captura.PNG)

* **Qué se prueba:** Identidad, sincronización NTP y configuración de claves SSH en el servidor secundario.
* **Resultado obtenido:** Hostname `server2-g5`, NTP activo y clave pública SSH instalada correctamente (381 bytes).
* **Autor de la captura:** Alexandra.

#### Captura 3: Verificación base en `server3-g5`
![Verificación server3](capturas/Captura3.PNG)

* **Qué se prueba:** Identidad, sincronización NTP y existencia del directorio `.ssh` en el servidor web/monitorización.
* **Resultado obtenido:** Hostname `server3-g5`, reloj sincronizado y fichero `authorized_keys` preparado con permisos seguros `600`.
* **Autor de la captura:** Enrique.

#### Captura 4: Verificación base en `server4-g5`
![Verificación server4](capturas/Captura4.PNG)

* **Qué se prueba:** Identidad y sincronización horaria en el nodo cliente.
* **Resultado obtenido:** Hostname `server4-g5` verificado con NTP activo.
* **Autor de la captura:** Cristina.

#### Captura Extra 1: Configuración de Red / Netplan en los servidores
* **Comando ejecutado:** `date && cat /etc/netplan/*.yaml && ip -4 a`
* **Qué se prueba:** Configuración de interfaces de red en `/etc/netplan/` y direcciones IPv4 activas asignadas en `eth0`.
* **Resultado obtenido:** Configuración de IPs estáticas (`192.168.5.101`, `.102`, `.103`) y dinámica (`server4-g5`), puerta de enlace (`192.168.5.1`) y servidores DNS (`192.168.5.101`, `192.168.5.102`).
* **Autor de la captura:** Enrique.

---

### 2. Firewall Perimetral, NAT y DNS Resolver (pfSense)

#### Captura 5: Desactivación del servidor DHCP en pfSense
![DHCP pfSense desactivado](capturas/Capturadhcp.PNG)

* **Qué se prueba:** Configuración de *Services > DHCP Server > LAN* (`192.168.5.0/24`) en pfSense.
* **Resultado obtenido:** La opción *Enable DHCP server on LAN interface* está desmarcada para delegar la asignación de IPs exclusivamente al clúster DHCP de `server1-g5` y `server2-g5`.
* **Autor de la captura:** Cristina.

#### Captura 6: Reglas de Redirección de Puertos (NAT Port Forward)
![NAT pfSense](capturas/firre.PNG)

* **Qué se prueba:** Mapeo de puertos externos desde la WAN (`172.26.46.55`) hacia los servidores de la LAN (`192.168.5.0/24`).
* **Resultado obtenido:** Puertos configurados: `53 TCP/UDP` hacia `.101` (DNS), `2251-2254` hacia puerto `22` de `.101-.104` (SSH), `8580` hacia `.103:80` (Web) y `8581` hacia `.103:8581` (Monitorix).
* **Autor de la captura:** Cristina.

#### Captura 7: Reglas de Filtrado en Interfaz WAN
![Reglas WAN pfSense](capturas/fd1.PNG)

* **Qué se prueba:** Permisos de tráfico entrante en la interfaz WAN de pfSense.
* **Resultado obtenido:** Se permite tráfico DNS (`53`) a los equipos de los integrantes (`.24`, `.8`, `.25`, `.23`), gestión web de pfSense (`80/443`) y el tráfico asociado a las reglas NAT.
* **Autor de la captura:** Cristina.

#### Captura 8: Configuración de Host Overrides en DNS Resolver (Unbound)
![Host Overrides pfSense](capturas/hostOverrides.PNG)

* **Qué se prueba:** Resolución interna de nombres de dominio en pfSense para `grupo5reto4.eus`.
* **Resultado obtenido:** `www.grupo5reto4.eus` y `monitor.grupo5reto4.eus` apuntan a `172.26.46.55`, mientras que `reto.grupo5reto4.eus` apunta a `172.16.250.105`.
* **Autor de la captura:** Cristina.

---

### 3. Servicio DHCP en Alta Disponibilidad (Failover)

#### Captura Extra 2: Configuración DHCP Failover en `server1-g5` y `server2-g5`
* **Comando ejecutado:** `date && grep -vE '^\s*#|^\s*$' /etc/dhcp/dhcpd.conf`
* **Qué se prueba:** Declaración activa de parámetros en `/etc/dhcp/dhcpd.conf` sin comentarios ni líneas en blanco.
* **Resultado obtenido:** Declaración del bloque `failover peer "dhcp-failover"`, rango de 50 IPs y opciones de subred entregadas (gateway, máscara, dominio y servidores DNS).
* **Autor de la captura:** Ibai.

#### Captura 9: Estado del Servidor DHCP Primario (`server1-g5`)
![Estado DHCP server1](capturas/Comprobaciondedhcpserver1.PNG)

* **Qué se prueba:** Estado del demonio `isc-dhcp-server` y estado de sincronización del pool en `/var/lib/dhcp/dhcpd.leases`.
* **Resultado obtenido:** Servicio `active (running)`, pool de 50 direcciones balanceado (25 libres / 25 backup) y estado del par failover en `normal`.
* **Autor de la captura:** Ibai.

#### Captura 10: Estado del Servidor DHCP Secundario (`server2-g5`)
![Estado DHCP server2](capturas/Comprobaciondeserverdhcp2.PNG)

* **Qué se prueba:** Estado del demonio `isc-dhcp-server` secundario y sincronización con `server1-g5`.
* **Resultado obtenido:** Servicio `active (running)` y bloque `failover peer "dhcp-failover"` con `my state normal` y `partner state normal` (`mclt 1800`).
* **Autor de la captura:** Ibai.

#### Captura 11: Prueba de Caída - Parada del DHCP Primario (`server1-g5`)
![Parada DHCP server1](capturas/pruebadhcpserver1.PNG)

* **Qué se prueba:** Simulación de fallo crítico deteniendo `isc-dhcp-server` en `server1-g5`.
* **Resultado obtenido:** El servicio primario queda detenido a las `13:04:23 CET`.
* **Autor de la captura:** Ibai.

#### Captura 12: Prueba de Failover - Renovación de IP en Cliente (`server4-g5`)
![Renovación DHCP server4](capturas/pruebadhcpserver4.PNG)

* **Qué se prueba:** Liberación (`dhclient -r`) y nueva solicitud de concesión (`dhclient -v`) desde `server4-g5` con `server1-g5` caído.
* **Resultado obtenido:** `server2-g5` (`192.168.5.102`) responde con `DHCPOFFER` y `DHCPACK`, asignando la IP `192.168.5.104/24` en `eth0` sin pérdida de servicio.
* **Autor de la captura:** Ibai.

---

### 4. Servicio DNS Redundante (BIND9 Maestro / Esclavo)

#### Captura Extra 3: Configuración DNS BIND9 en `server1-g5`
* **Comando ejecutado:** `date && cat /etc/bind/named.conf.local /etc/bind/db.grupo5.local /etc/bind/db.192.168.5`
* **Qué se prueba:** Declaración de zonas y registros autoritativos en el servidor DNS maestro.
* **Resultado obtenido:** Registros SOA, NS, A, CNAME y PTR correctamente definidos, además de la directiva `allow-transfer` restringida hacia `192.168.5.102`.
* **Autor de la captura:** Alexandra.

#### Captura 13: Validación de Sintaxis y Zonas en el Maestro (`server1-g5`)
![Validación zonas DNS](capturas/dns-redundante.PNG)

* **Qué se prueba:** Comprobación sintáctica de configuración (`named-checkconf`) y de integridad de las zonas directa e inversa (`named-checkzone`).
* **Resultado obtenido:** Zona directa `grupo5reto4.eus` (serial `2026110607`) y zona inversa `5.168.192.in-addr.arpa` (serial `2026110501`) cargadas con estado `OK`.
* **Autor de la captura:** Alexandra.

#### Captura 14: Sincronización de Zonas en el Esclavo (`server2-g5`)
![Sincronización esclavo DNS](capturas/sincronizacion%20esclavo.PNG)

* **Qué se prueba:** Transferencia de zona (AXFR) en `/var/cache/bind/` y estado del servicio mediante `rndc status`.
* **Resultado obtenido:** Archivos replicados presentes (`db.grupo5reto4.eus`, `db.inverso`, `db.192.168.5.s`) y servidor operativo (`server is up and running`).
* **Autor de la captura:** Alexandra.

#### Captura 15: Prueba de Caída - Parada del DNS Maestro (`server1-g5`)
![Parada BIND9 server1](capturas/captura_08_dns_failover_resolucion_apagarserver1.PNG)

* **Qué se prueba:** Simulación de caída del servidor DNS maestro deteniendo `bind9` en `server1-g5`.
* **Resultado obtenido:** Servicio detenido a las `13:09:52 CET`.
* **Autor de la captura:** Alexandra.

#### Captura 16: Resolución Directa, Alias e Inversa contra el Esclavo (`server2-g5`)
![Failover DNS resolución](capturas/captura_08_dns_failover_resolucion.PNG)

* **Qué se prueba:** Consultas `nslookup` apuntando directamente al servidor esclavo (`192.168.5.102`) mientras el maestro está apagado.
* **Resultado obtenido:** El esclavo resuelve con éxito `www.grupo5reto4.eus` (`172.26.46.55`), el CNAME `monitor.grupo5reto4.eus` (`192.168.5.103`), `reto.grupo5reto4.eus` (`172.16.250.105`) y la resolución inversa PTR de `192.168.5.103` (`server3-g5.grupo5.local`).
* **Autor de la captura:** Alexandra.

---

### 5. Servidor Web (Apache2) y Monitorización (Monitorix)

#### Captura Extra 4: Configuración VirtualHost Apache2 y Archivos Web en `server3-g5`
* **Comando ejecutado:** `date && grep -vE '^\s*#|^\s*$' /etc/apache2/sites-enabled/*.conf && ls -la /var/www/html/`
* **Qué se prueba:** Configuración del sitio web activo en Apache2 y ubicación de los archivos desplegados en `/var/www/html/`.
* **Resultado obtenido:** Configuración del VirtualHost en el puerto `80`, apuntando a `/var/www/html/`, y presencia de los archivos del portal *Gran Premio de Euskadi - Bilbao 2026*.
* **Autor de la captura:** Enrique.

#### Captura 17: Verificación de Servicios y Puertos en `server3-g5`
![Estado Apache y Monitorix](capturas/captura_09_apache_monitorix_terminal.PNG)

* **Qué se prueba:** Estado de `apache2` y `monitorix` mediante `systemctl status` y puertos en escucha con `ss -tulpn`.
* **Resultado obtenido:** Ambos demonios `active (running)`; Apache escuchando en puerto `80` y Monitorix en puerto `8581`.
* **Autor de la captura:** Enrique.

#### Captura 18: Acceso Web al Portal *GP Euskadi - Bilbao 2026* (Vía NAT 8580)
![Web navegador puerto 8580](capturas/captura_10_web_navegador_servidor103.jpg)

* **Qué se prueba:** Acceso externo al servidor web Apache2 a través de `http://grupo5reto4.eus:8580`.
* **Resultado obtenido:** Carga completa de la web con cuenta atrás, galería fotográfica y descarga de normativa FIA con hash SHA-256.
* **Autor de la captura:** Enrique.

#### Captura 19: Acceso Web HTTPS al Portal Oficial
![Web navegador HTTPS](capturas/captura_10_web_navegador.jpg)

* **Qué se prueba:** Resolución y carga del portal desde `https://reto.grupo5reto4.eus/index.html`.
* **Resultado obtenido:** Visualización correcta del sitio web corporativo del evento.
* **Autor de la captura:** Enrique.

#### Captura 20: Panel de Monitorización en Tiempo Real (Monitorix)
![Panel Monitorix](capturas/captura_10_web_navegador_monitorix.PNG)

* **Qué se prueba:** Acceso externo al panel de métricas del sistema a través del puerto NAT `8581` (`http://grupo5reto4.eus:8581/monitorix-cgi/monitorix.cgi...`).
* **Resultado obtenido:** Visualización de gráficas de carga de CPU (*System load*), memoria RAM (957 MB), procesos activos (54) y *Uptime* (7 días) de `server3-g5`.
* **Autor de la captura:** Enrique.