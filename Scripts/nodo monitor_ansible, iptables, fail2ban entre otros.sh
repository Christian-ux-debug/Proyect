#!/bin/bash

# ==============================================================================
# Script Maestro con Captura Dinámica de IP y Usuario para Ansible
# Ejecutado en: Nodo Monitor, instala prometheus-node-exporter, fail2ban, arpon
# ngnix, mariadb-client, Ansible, iptables.
# ==============================================================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[!] Este script debe ejecutarse con privilegios de administrador (sudo)."
    exit 1
fi

echo "=== [1/4] Verificando e instalando dependencias base (Ansible, Yad) ==="
if ! command -v ansible &> /dev/null; then
    apt update && apt install -y software-properties-common ppa:ansible/ansible ansible
else
    echo "[*] Ansible ya se encuentra instalado."
fi

if ! command -v yad &> /dev/null; then
    apt update && apt install -y yad || true
else
    echo "[*] Yad ya se encuentra instalado."
fi

echo "=== [2/4] Captura dinámica de Nodos y Usuarios del Clúster ==="
declare -a NODOS_CONFIG=()

USAR_YAD=true
if [ -z "${DISPLAY:-}" ]; then
    USAR_YAD=false
fi

while true; do
    IP_INPUT=""
    USER_INPUT=""
    RET_IP=0

    if [ "$USAR_YAD" = true ] && yad --version &>/dev/null; then
        # Ventana Yad para pedir IP y Usuario juntos
        FORM_RESULT=$(yad --form \
            --title="Gestión de Nodos del Clúster (Ansible)" \
            --text="Ingrese los datos del nodo a aprovisionar:\nNodos configurados: ${#NODOS_CONFIG[@]}" \
            --field="Dirección IP (Ej: 192.168.3.20):" "" \
            --field="Usuario SSH (Ej: nodo_servicio):" "" \
            --button="Agregar Nodo:0" \
            --button="Aceptar y Continuar:1" \
            --button="Cancelar:2") || RET_IP=$?

        if [ $RET_IP -eq 2 ] || [ $RET_IP -eq 255 ]; then
            echo "[!] Configuración cancelada."
            exit 0
        elif [ $RET_IP -eq 1 ]; then
            if [ ${#NODOS_CONFIG[@]} -eq 0 ]; then
                yad --error --title="Error" --text="Debe ingresar al menos un nodo."
                continue
            fi
            break
        fi

        IP_INPUT=$(echo "$FORM_RESULT" | awk -F'|' '{print $1}' | xargs)
        USER_INPUT=$(echo "$FORM_RESULT" | awk -F'|' '{print $2}' | xargs)
    else
        # Modo Consola de Texto si no hay entorno gráfico
        echo ""
        echo "--------------------------------------------------------"
        echo " Nodos ingresados actualmente: ${#NODOS_CONFIG[@]}"
        echo "--------------------------------------------------------"
        read -p "Ingrese la dirección IP del nodo (o Enter vacío para terminar): " IP_INPUT
        if [ -z "$IP_INPUT" ]; then
            if [ ${#NODOS_CONFIG[@]} -eq 0 ]; then
                echo "[!] Debe ingresar al menos un nodo."
                continue
            fi
            break
        fi
        read -p "Ingrese el usuario SSH para $IP_INPUT (Ej: nodo_servicio): " USER_INPUT
    fi

    if [ -z "$IP_INPUT" ] || [ -z "$USER_INPUT" ]; then
        echo "[!] La IP y el usuario no pueden estar vacíos."
        continue
    fi

    # Guardar en formato IP|USER
    NODOS_CONFIG+=("$IP_INPUT|$USER_INPUT")
    echo "[*] Nodo agregado con éxito -> IP: $IP_INPUT | Usuario: $USER_INPUT"

    if [ "$USAR_YAD" = false ]; then
        read -p "¿Desea agregar otro nodo? (s/n): " RES_MAS
        if [[ ! "$RES_MAS" =~ ^[Ss]$ ]]; then
            break
        fi
    fi
done

echo "=== [3/4] Generando Inventario de Ansible con IP y Usuario ==="
INVENTARIO_PATH="/etc/ansible/inventory.ini"

PLAYBOOK_PATH="/etc/ansible/deploy_datacenter.yml"

cat << 'EOF' > "$PLAYBOOK_PATH"
---
- name: Aprovisionamiento y Configuración Idempotente - Nodos del Clúster
  hosts: nodos_cluster
  become: yes
  tasks:
    - name: Actualizar repositorios APT de forma robusta
      shell: apt-get update -y

    - name: Instalar paquetes esenciales de forma idempotente
      apt:
        name:
          - prometheus-node-exporter
          - fail2ban
          - arpon
          - nginx
          - mariadb-client
          - curl
          - htop
        state: present
        force_apt_get: yes

    - name: Aplicar Hardening Global de SSH solo si es necesario
      copy:
        dest: /etc/ssh/sshd_config.d/99-hardening.conf
        content: |
          Port 22
          PermitRootLogin no
          PasswordAuthentication no
          PubkeyAuthentication yes
          AuthorizedKeysFile .ssh/authorized_keys
          X11Forwarding no
          MaxAuthTries 3
          ClientAliveInterval 300
          ClientAliveCountMax 2
      notify: Reiniciar servicio SSH

    - name: Configurar ArpON para interfaz local (ens160)
      copy:
        dest: /etc/default/arpon
        content: |
          RUN="yes"
          INTERFACE="{{ ansible_default_ipv4.interface }}"
          DAEMON="-D"

    - name: Asegurar que los servicios clave estén activos y habilitados
      systemd:
        name: "{{ item }}"
        state: started
        enabled: yes
      loop:
        - arpon
        - prometheus-node-exporter
        - fail2ban
        - nginx

    - name: Configurar reglas estrictas de cortafuegos con Iptables de forma idempotente
      block:
        - name: Permitir tráfico establecido y relacionado (conexiones activas)
          iptables:
            chain: INPUT
            ctstate: ESTABLISHED,RELATED
            jump: ACCEPT

        - name: Permitir tráfico en la interfaz de loopback (localhost)
          iptables:
            chain: INPUT
            in_interface: lo
            jump: ACCEPT

        - name: Permitir puertos esenciales (SSH 22, HTTP 80, HTTPS 443)
          iptables:
            chain: INPUT
            protocol: tcp
            destination_port: "{{ item }}"
            jump: ACCEPT
          loop:
            - '22'
            - '80'
            - '443'

        - name: Permitir acceso exclusivo al puerto de métricas (9100) desde el Nodo Monitor
          iptables:
            chain: INPUT
            protocol: tcp
            source: 192.168.3.10
            destination_port: '9100'
            jump: ACCEPT

        - name: Establecer política por defecto en DROP para el tráfico entrante
          iptables:
            chain: INPUT
            policy: DROP

    - name: Desplegar página web de prueba personalizada en Nginx
      copy:
        dest: /var/www/html/index.html
        content: |
          <!DOCTYPE html>
          <html lang="es">
          <head>
              <meta charset="UTF-8">
              <title>Nodo Servicio - Altavista Data Center</title>
              <style>
                  body { font-family: Arial, sans-serif; background-color: #f4f6f9; text-align: center; padding: 50px; }
                  .card { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); display: inline-block; }
                  h1 { color: #2c3e50; }
                  p { color: #7f8c8d; }
                  .status { color: #27ae60; font-weight: bold; }
              </style>
          </head>
          <body>
              <div class="card">
                  <h1>Servidor Web Nginx de Producción</h1>
                  <p>Nodo Integrado al Clúster</p>
                  <p>Estado: <span class="status">ONLINE / FUNCIONAL</span></p>
              </div>
          </body>
          </html>

  handlers:
    - name: Reiniciar servicio SSH
      systemd:
        name: ssh
        state: restarted
EOF




echo "[*] Inventario y Playbook generados correctamente."
echo "=== [5/4] Probando conectividad con Ansible ==="
ansible nodos_cluster -i "$INVENTARIO_PATH" -m ping || echo "[!] Advertencia de conectividad."

echo ""
read -p "¿Deseas lanzar el despliegue masivo idempotente ahora mismo? [S/N]: " RESPUESTA

if [[ "$RESPUESTA" =~ ^[Ss]$ ]]; then
    ansible-playbook -i "$INVENTARIO_PATH" "$PLAYBOOK_PATH" --ask-become-pass
else
    echo "[*] Puedes ejecutarlo manualmente con:"
    echo "ansible-playbook -i $INVENTARIO_PATH $PLAYBOOK_PATH --ask-become-pass"
fi
