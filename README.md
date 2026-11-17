# Infraestructura de Red y Servicios Alta Disponibilidad - Grupo 5 (Reto 4)

Despliegue completo de una infraestructura de red segmentada con firewall perimetral **pfSense**, servicios redundantes **DNS (BIND9 Maestro/Esclavo)**, **DHCP Failover (ISC-DHCP)**, **Servidor Web (Apache2)** y **Monitorización (Monitorix)** sobre **Ubuntu 22.04.5 LTS**.

## Tabla de Direccionamiento IP

| Equipo / Nodo | Sistema Operativo | IP Interna (LAN) | IP Externa / Puertos NAT (WAN) | Servicios / Roles |
| :--- | :--- | :--- | :--- | :--- |
| **pfSense** | FreeBSD (pfSense CE) | `192.168.5.1/24` | `172.26.46.55` | Firewall, NAT, Unbound DNS Resolver |
| **server1-g5** | Ubuntu 22.04.5 LTS | `192.168.5.101` | `172.26.46.55:2251` (SSH)<br>`172.26.46.55:53` (DNS) | DNS Maestro (`grupo5reto4.eus`), DHCP Primary |
| **server2-g5** | Ubuntu 22.04.5 LTS | `192.168.5.102` | `172.26.46.55:2252` (SSH) | DNS Esclavo (AXFR), DHCP Secondary |
| **server3-g5** | Ubuntu 22.04.5 LTS | `192.168.5.103` | `172.26.46.55:8580` (HTTP)<br>`172.26.46.55:8581` (Mon)<br>`172.26.46.55:2253` (SSH) | Servidor Web Apache2, Monitorix |
| **server4-g5** | Ubuntu 22.04.5 LTS | `192.168.5.104` (DHCP) | `172.26.46.55:2254` (SSH) | Cliente de verificación DHCP/DNS |

## Mapa Lógico de la Red

```text
               [ RED EXTERNA / WAN: 172.26.44.0/24 ]
     PCs Aula: Cristina (.24), Ibai (.8), Alexandra (.25), Enrique (.23)
                                  |
                         IP WAN: 172.26.46.55
                      +-----------------------+
                      |   FIREWALL pfSense    |
                      +-----------------------+
                         IP LAN: 192.168.5.1
                                  |
     +----------------------------+----------------------------+
     |                            |                            |
[server1-g5]                 [server2-g5]                 [server3-g5]          [server4-g5]
192.168.5.101                192.168.5.102                192.168.5.103         192.168.5.104
DNS Master + DHCP Pri <----> DNS Slave + DHCP Sec         Apache2 + Monitorix   Cliente DHCP