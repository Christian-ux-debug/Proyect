#!/bin/bash

# ==============================================================================
# Script Maestro Automatizado - Nodo de Datos (MariaDB & Respaldos)
# Ejecutado en: Nodo Monitor (Usuario Normal)
# ==============================================================================

set -euo pipefail

echo "=== [1/3] Verificando dependencias base (Ansible / Yad) ==="
if ! command -v ansible &> /dev/null; then
    echo "[!] Ansible no está instalado. Instálalo ejecutando en tu terminal:"
    echo "    sudo apt update && sudo apt install -y ansible"
    exit 1
fi

if ! command -v yad &> /dev/null; then
    echo "[*] Yad no está instalado. Continuando en modo texto..."
fi

echo "=== [2/3] Captura de Configuración del Clúster de Datos ==="

USAR_YAD=true
if [ -z "${DISPLAY:-}" ]; then
    USAR_YAD=false
fi

IP_DATOS="192.168.3.24"
USER_DATOS="datos"
IP_SERVICIO="192.168.3.23"
DESEA_RESPALDOS="no"

if [ "$USAR_YAD" = true ] && command -v yad &>/dev/null; then
    FORM_RESULT=$(yad --form \
        --title="Configuración del Nodo de Datos" \
        --text="Configure los parámetros de conexión y respaldos:" \
        --field="IP del Nodo de Datos (Ej: 192.168.3.24):" "$IP_DATOS" \
        --field="Usuario SSH del Nodo de Datos (Ej: datos):" "$USER_DATOS" \
        --field="IP del Nodo Servicio (Ej: 192.168.3.23):" "$IP_SERVICIO" \
        --field="¿Activar respaldos automáticos diarios (Rsync/Cron)?:CHKS" FALSE \
        --button="Aceptar:0" \
        --button="Cancelar:1") || RET_FORM=$?

    if [ "${RET_FORM:-0}" -ne 0 ]; then
        echo "[!] Configuración cancelada por el usuario."
        exit 0
    fi

    IP_DATOS=$(echo "$FORM_RESULT" | awk -F'|' '{print $1}' | xargs)
    USER_DATOS=$(echo "$FORM_RESULT" | awk -F'|' '{print $2}' | xargs)
    IP_SERVICIO=$(echo "$FORM_RESULT" | awk -F'|' '{print $3}' | xargs)
    CHECK_RESP=$(echo "$FORM_RESULT" | awk -F'|' '{print $4}' | xargs)
    
    if [ "$CHECK_RESP" = "TRUE" ]; then
        DESEA_RESPALDOS="si"
    fi
else
    read -p "Ingrese la dirección IP del Nodo de Datos [$IP_DATOS]: " input_ip_d
    [ -n "$input_ip_d" ] && IP_DATOS="$input_ip_d"

    read -p "Ingrese el usuario SSH del Nodo de Datos [$USER_DATOS]: " input_user_d
    [ -n "$input_user_d" ] && USER_DATOS="$input_user_d"

    read -p "Ingrese la dirección IP del Nodo Servicio [$IP_SERVICIO]: " input_ip_s
    [ -n "$input_ip_s" ] && IP_SERVICIO="$input_ip_s"

    read -p "¿Desea activar respaldos automáticos diarios (s/n)?: " RESP_RESP
    if [[ "$RESP_RESP" =~ ^[Ss]$ ]]; then
        DESEA_RESPALDOS="si"
    fi
fi

if [ -z "$IP_DATOS" ] || [ -z "$USER_DATOS" ] || [ -z "$IP_SERVICIO" ]; then
    echo "[!] Los campos no pueden estar vacíos."
    exit 1
fi

echo "[*] Nodo de Datos: $IP_DATOS | Usuario: $USER_DATOS"
echo "[*] Nodo Servicio (Remoto permitido): $IP_SERVICIO"
echo "[*] Estado de respaldos automáticos: $DESEA_RESPALDOS"

echo "=== [3/3] Generando Playbooks y Ejecutando Ansible en Nodo de Datos ($IP_DATOS) ==="
ANSIBLE_DIR="$HOME/.ansible_master"
INVENTARIO_PATH="$ANSIBLE_DIR/inventory_datos.ini"
PLAYBOOK_DATOS="$ANSIBLE_DIR/deploy_nodo_datos.yml"
PLAYBOOK_BACKUPS="$ANSIBLE_DIR/configurar_respaldos.yml"

mkdir -p "$ANSIBLE_DIR"

# Asegurar inventario dinámico estructurado en la carpeta del usuario
cat << EOF > "$INVENTARIO_PATH"
[nodos_datos]
$IP_DATOS ansible_user=$USER_DATOS

[all:vars]
ansible_ssh_private_key_file=$HOME/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3
EOF

# Crear Playbook Principal de MariaDB y Red
cat << EOF > "$PLAYBOOK_DATOS"
---
- name: Configuración Idempotente - Nodo de Datos (MariaDB & Red)
  hosts: nodos_datos
  become: yes
  tasks:
    - name: Actualizar repositorios APT de forma robusta
      shell: apt-get update -y

    - name: Instalar servidor MariaDB y cliente de forma idempotente
      apt:
        name:
          - mariadb-server
          - mariadb-client
          - curl
        state: present
        force_apt_get: yes

    - name: Asegurar que el servicio MariaDB esté iniciado y habilitado
      systemd:
        name: mariadb
        state: started
        enabled: yes

    - name: Permitir puerto MySQL (3306) con Iptables de forma exclusiva desde el Nodo Servicio
      iptables:
        chain: INPUT
        protocol: tcp
        source: "$IP_SERVICIO"
        destination_port: '3306'
        jump: ACCEPT

    - name: Modificar bind-address en MariaDB para aceptar conexiones remotas de forma segura
      lineinfile:
        path: /etc/mysql/mariadb.conf.d/50-server.cnf
        regexp: '^bind-address'
        line: 'bind-address = 0.0.0.0'
      notify: Reiniciar MariaDB

  handlers:
    - name: Reiniciar MariaDB
      systemd:
        name: mariadb
        state: restarted
EOF

echo "[*] Ejecutando aprovisionamiento del Nodo de Datos..."
ansible-playbook -i "$INVENTARIO_PATH" "$PLAYBOOK_DATOS" --ask-become-pass

# Si el usuario eligió activar los respaldos, generamos y ejecutamos su playbook
if [ "$DESEA_RESPALDOS" = "si" ]; then
    echo "[*] Generando Playbook de Respaldos Automáticos..."
    cat << 'EOF' > "$PLAYBOOK_BACKUPS"
---
- name: Configuración de Respaldos Automáticos con Rsync y Cron en Nodo Datos
  hosts: nodos_datos
  become: yes
  vars:
    backup_dir: "/var/backups/mariadb_backup"
  tasks:
    - name: Crear directorio seguro para los respaldos locales
      file:
        path: "{{ backup_dir }}"
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Instalar rsync y cron de forma idempotente
      apt:
        name:
          - rsync
          - cron
        state: present
        force_apt_get: yes

    - name: Crear script de respaldo automatizado
      copy:
        dest: "/usr/local/bin/ejecutar_respaldo.sh"
        owner: root
        group: root
        mode: '0755'
        content: |
          #!/bin/bash
          FECHA=$(date +%Y%m%d_%H%M%S)
          DESTINO="{{ backup_dir }}"
          mysqldump --all-databases --single-transaction --quick --lock-tables=false > "$DESTINO/db_backup_$FECHA.sql"
          gzip "$DESTINO/db_backup_$FECHA.sql"
          find "$DESTINO" -type f -name "*.sql.gz" -mtime +7 -delete

    - name: Asegurar que el servicio cron esté activo y habilitado
      systemd:
        name: cron
        state: started
        enabled: yes

    - name: Configurar tarea cron para automatizar el respaldo diario a las 2:00 AM
      cron:
        name: "Respaldo diario automatizado MariaDB"
        minute: "0"
        hour: "2"
        job: "/usr/local/bin/ejecutar_respaldo.sh"
        state: present
EOF

    echo "[*] Ejecutando configuración de respaldos automáticos..."
    ansible-playbook -i "$INVENTARIO_PATH" "$PLAYBOOK_BACKUPS" --ask-become-pass
else
    echo "[*] Omitiendo configuración de respaldos automáticos por elección del usuario."
fi

echo ""
echo "=== ¡Despliegue del Nodo de Datos Finalizado con Éxito! ==="
echo " Recuerda crear la base de datos y usuario en MariaDB con:"
echo "   sudo mysql -u root"
echo "   CREATE DATABASE db_datacenter;"
echo "   CREATE USER 'app_user'@'$IP_SERVICIO' IDENTIFIED BY 'TuContraseñaSegura';"
echo "   GRANT ALL PRIVILEGES ON db_datacenter.* TO 'app_user'@'$IP_SERVICIO';"
echo "   FLUSH PRIVILEGES;"
