### Archivo `gestion.md` (Raíz)
```markdown
# Gestión del Proyecto y Reparto de Tareas - Grupo 5

| Miembro del Equipo | Rol / Responsabilidad Principal | Tareas Realizadas |
| :--- | :--- | :--- |
| **Cristina** (`172.26.44.24`) | Seguridad Perimetral y Firewall | Configuración de pfSense, reglas WAN/LAN, Port Forwarding (NAT), Host Overrides en Unbound y desactivación de DHCP en pfSense. |
| **Ibai** (`172.26.44.8`) | Servicios DHCP y Alta Disponibilidad | Instalación y configuración de `isc-dhcp-server` en modo Failover/Balanceo entre `server1-g5` y `server2-g5`, pruebas de caída y concesión en `server4-g5`. |
| **Alexandra** (`172.26.44.25`) | Resolución de Nombres (DNS) | Despliegue de BIND9 Maestro (`server1-g5`) y Esclavo (`server2-g5`), zonas directa e inversa de `grupo5reto4.eus`, transferencia AXFR y pruebas de failover. |
| **Enrique** (`172.26.44.23`) | Servicios Web y Monitorización | Despliegue de Apache2 y web *GP Euskadi - Bilbao 2026* en `server3-g5`, configuración de Monitorix (puerto 8581), scripting y documentación técnica. |