#!/bin/bash

# ==============================================================================
# Script Maestro con Captura Dinámica de IP y Usuario para Ansible
# Ejecutado en: Nodo Monitor (Usuario Normal)
# ==============================================================================

set -euo pipefail

echo "=== [1/4] Verificando dependencias base (Ansible / Yad) ==="

if ! command -v ansible &> /dev/null; then
    echo "[!] Ansible no está instalado. Instálalo ejecutando en tu terminal:"
    echo "    sudo apt update && sudo apt install -y ansible"
    exit 1
fi

if ! command -v yad &> /dev/null; then
    echo "[*] Yad no está instalado. Si usas interfaz gráfica, puedes instalarlo con:"
    echo "    sudo apt update && sudo apt install -y yad"
    echo "[*] Continuando en modo texto..."
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

    if [ "$USAR_YAD" = true ] && command -v yad &>/dev/null; then
        FORM_RESULT=$(yad --form \
            --title="Gestión de Nodos del Clúster (Ansible)" \
            --text="Ingrese los datos del nodo a aprovisionar:\nNodos configurados: ${#NODOS_CONFIG[@]}" \
            --field="Dirección IP (Ej: 192.168.11.53):" "" \
            --field="Usuario SSH (Ej: pc3):" "" \
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
        read -p "Ingrese el usuario SSH para $IP_INPUT (Ej: pc3): " USER_INPUT
    fi

    if [ -z "$IP_INPUT" ] || [ -z "$USER_INPUT" ]; then
        echo "[!] La IP y el usuario no pueden estar vacíos."
        continue
    fi

    NODOS_CONFIG+=("$IP_INPUT|$USER_INPUT")
    echo "[*] Nodo agregado con éxito -> IP: $IP_INPUT | Usuario: $USER_INPUT"

    if [ "$USAR_YAD" = false ]; then
        read -p "¿Desea agregar otro nodo? (s/n): " RES_MAS
        if [[ ! "$RES_MAS" =~ ^[Ss]$ ]]; then
            break
        fi
    fi
done

echo "=== [3/4] Generando Inventario de Ansible de forma estructurada ==="
# Cambiado a la carpeta personal del usuario para evitar requerir sudo
ANSIBLE_DIR="$HOME/.ansible_master"
INVENTARIO_PATH="$ANSIBLE_DIR/inventory.ini"
mkdir -p "$ANSIBLE_DIR"

# Escribir la estructura correcta del inventario con variables globales
cat << EOF > "$INVENTARIO_PATH"
[nodos_cluster]
EOF

for nodo in "${NODOS_CONFIG[@]}"; do
    IP=$(echo "$nodo" | cut -d'|' -f1)
    USER=$(echo "$nodo" | cut -d'|' -f2)
    echo "$IP ansible_user=$USER" >> "$INVENTARIO_PATH"
done

cat << EOF >> "$INVENTARIO_PATH"

[all:vars]
ansible_ssh_private_key_file=$HOME/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3
EOF

echo "[*] Inventario generado exitosamente en $INVENTARIO_PATH"

PLAYBOOK_PATH="$ANSIBLE_DIR/deploy_datacenter.yml"

echo "=== [4/4] Generando Playbook de Aprovisionamiento Maestro ==="
cat << 'EOF' > "$PLAYBOOK_PATH"
---
- name: Aprovisionamiento y Configuración Idempotente - Nodos del Clúster
  hosts: nodos_cluster
  become: yes
  tasks:
    - name: Limpiar posibles bloqueos de dpkg previos
      raw: dpkg --configure -a && apt-get clean
      changed_when: false

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

    - name: Aplicar Hardening Global de SSH de forma segura
      copy:
        dest: /etc/ssh/sshd_config.d/99-hardening.conf
        content: |
          Port 22
          PermitRootLogin no
          PasswordAuthentication yes
          PubkeyAuthentication yes
          AuthorizedKeysFile .ssh/authorized_keys
          X11Forwarding no
          MaxAuthTries 3
          ClientAliveInterval 300
          ClientAliveCountMax 2
      notify: Reiniciar servicio SSH

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
            source: 192.168.11.52
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
    ansible-playbook -i "$INVENTARIO_PATH" "$PLAYBOOK_PATH"
else
    echo "[*] Despliegue cancelado por el usuario."
fi

