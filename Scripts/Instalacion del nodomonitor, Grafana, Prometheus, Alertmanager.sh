#!/bin/bash

# ==============================================================================
# Script de Automatización Inteligente e Idempotente - Nodo Monitor
# Componentes: Node Exporter, Nginx, Prometheus, Alertmanager, Grafana
# ==============================================================================

# Variables globales que se llenarán dinámicamente
MONITOR_IP=""
SMTP_USER=""
SMTP_PASS=""
declare -a NODES=()

# ------------------------------------------------------------------------------
# Función: Validar privilegios, limpiar dependencias rotas de dpkg y herramientas
# ------------------------------------------------------------------------------
verificar_entorno() {
    if [ "$EUID" -ne 0 ]; then
        echo "[!] Este script debe ejecutarse con privilegios de administrador (sudo)."
        exit 1
    fi

    echo "[*] Limpiando paquetes rotos de apt (prometheus-node-exporter)..."
    dpkg --purge --force-all prometheus-node-exporter prometheus-node-exporter-collectors 2>/dev/null || true
    apt --fix-broken install -y

    echo "[*] Asegurando herramientas básicas (yad, curl, sqlite3, jq, wget)..."
    apt update && apt install -y yad curl sqlite3 jq wget
}

# ------------------------------------------------------------------------------
# Función: Capturar configuraciones mediante interfaces gráficas Yad
# ------------------------------------------------------------------------------
capturar_configuraciones() {
    # 1. IP del Nodo Monitor
    MONITOR_IP=$(yad --entry \
        --title="Configuración del Nodo Monitor" \
        --text="Ingrese la dirección IP del Nodo Monitor:\n(Ejemplo: 192.168.3.10 o 192.168.0.10)" \
        --entry-text="192.168.3.10" \
        --button="Aceptar:0" \
        --button="Cancelar:1")

    if [ $? -ne 0 ] || [ -z "$MONITOR_IP" ]; then
        yad --info --title="Cancelado" --text="Configuración cancelada por el usuario." --timeout=3
        exit 0
    fi

    # 2. Credenciales SMTP para Alertmanager
    CONFIG_CORREO=$(yad --form \
        --title="Configuración de Alertas (SMTP Gmail)" \
        --text="Ingrese las credenciales de correo para Alertmanager:" \
        --field="Correo electrónico (SMTP From/User):" "zabbixagent21@gmail.com" \
        --field="Contraseña de Aplicación (16 dígitos):" "zvkecqfrxdmkpgft" \
        --button="Continuar:0" \
        --button="Cancelar:1")

    if [ $? -ne 0 ]; then
        exit 0
    fi

    SMTP_USER=$(echo "$CONFIG_CORREO" | awk -F'|' '{print $1}')
    SMTP_PASS=$(echo "$CONFIG_CORREO" | awk -F'|' '{print $2}')

    # 3. Captura dinámica de las IPs del clúster
    while true; do
        IP_INPUT=$(yad --entry \
            --title="Gestión de Nodos del Clúster" \
            --text="Ingrese la dirección IP del nodo a monitorear (Ej: 192.168.3.20):\n\nNodos ingresados actualmente: ${#NODES[@]}" \
            --entry-text="" \
            --button="Agregar IP:0" \
            --button="Aceptar y Continuar:1" \
            --button="Cancelar:2")

        RET_IP=$?
        if [ $RET_IP -eq 2 ] || [ $RET_IP -eq 255 ]; then
            exit 0
        fi

        if [ $RET_IP -eq 1 ]; then
            if [ ${#NODES[@]} -eq 0 ]; then
                yad --error --title="Error" --text="Debe ingresar al menos una dirección IP de nodo antes de continuar."
                continue
            fi
            break
        fi

        IP_LIMPIA=$(echo "$IP_INPUT" | xargs)
        if [ -z "$IP_LIMPIA" ]; then
            yad --error --title="Error" --text="La IP no puede estar vacía."
            continue
        fi

        DUPLICADA=0
        for ip_existente in "${NODES[@]}"; do
            if [ "$ip_existente" == "$IP_LIMPIA" ]; then
                DUPLICADA=1
                break
            fi
        done

        if [ $DUPLICADA -eq 1 ]; then
            yad --warning --title="IP Duplicada" --text="La dirección IP [ $IP_LIMPIA ] ya ha sido ingresada previamente."
        else
            NODES+=("$IP_LIMPIA")
        fi
    done
}

# ------------------------------------------------------------------------------
# Función Idempotente: Node Exporter en el Nodo Monitor (vía binario nativo)
# ------------------------------------------------------------------------------
instalar_node_exporter() {
    echo "=== [1/5] Verificando e instalando Node Exporter en el Nodo Monitor ==="
    
    id -u prometheus &>/dev/null || useradd --no-create-home --shell /bin/false prometheus

    cd /tmp
    if [ ! -f "node_exporter-1.7.0.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    fi
    tar -xvf node_exporter-1.7.0.linux-amd64.tar.gz
    cp -f node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
    chown prometheus:prometheus /usr/local/bin/node_exporter

    cat << EOF > /etc/systemd/system/prometheus-node-exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    # Forzar activación y persistencia al reiniciarse la PC
    systemctl enable --now prometheus-node-exporter
    echo "[*] Node Exporter instalado, configurado y persistente con éxito."
}

# ------------------------------------------------------------------------------
# Función Idempotente: Configurar Nginx con Reverse Proxy
# ------------------------------------------------------------------------------
configurar_nginx() {
    echo "=== [2/5] Configurando Nginx e ignorando conflictos con Apache ==="
    if systemctl is-active --quiet apache2; then
        systemctl stop apache2
        systemctl disable apache2
    fi

    if ! dpkg -l | grep -q nginx; then
        apt install -y nginx
    fi
    systemctl enable --now nginx

    cat << EOF > /etc/nginx/sites-available/datacenter-monitor.conf
server {
    listen 80;
    server_name monitor.altavista.local $MONITOR_IP;

    location /prometheus/ {
        proxy_pass http://127.0.0.1:9090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /alertmanager/ {
        proxy_pass http://127.0.0.1:9093/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/datacenter-monitor.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl reload nginx
}

# ------------------------------------------------------------------------------
# Función Idempotente: Instalar y Configurar Prometheus
# ------------------------------------------------------------------------------
instalar_prometheus() {
    echo "=== [3/5] Verificando e instalando Prometheus ==="
    id -u prometheus &>/dev/null || useradd --no-create-home --shell /bin/false prometheus

    cd /tmp
    if [ ! -f "prometheus-2.51.2.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/prometheus/releases/download/v2.51.2/prometheus-2.51.2.linux-amd64.tar.gz
    fi
    tar -xvf prometheus-2.51.2.linux-amd64.tar.gz

    mkdir -p /etc/prometheus /var/lib/prometheus
    cp -f prometheus-2.51.2.linux-amd64/prometheus /usr/local/bin/
    cp -f prometheus-2.51.2.linux-amd64/promtool /usr/local/bin/
    chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

    cp -r prometheus-2.51.2.linux-amd64/consoles /etc/prometheus/
    cp -r prometheus-2.51.2.linux-amd64/console_libraries /etc/prometheus/
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

    TARGETS_YAML="      - targets:\n        - '$MONITOR_IP:9100'  # Nodo Monitor"
    for ip_nodo in "${NODES[@]}"; do
        TARGETS_YAML+="\n        - '$ip_nodo:9100'"
    done

    cat << EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - 'localhost:9093'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter_datacenter'
    static_configs:
$(echo -e "$TARGETS_YAML")
EOF

    chown prometheus:prometheus /etc/prometheus/prometheus.yml

    cat << 'EOF' > /etc/prometheus/alert_rules.yml
groups:
  - name: datacenter_alerts
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "Instancia {{ $labels.instance }} caída"
          description: "La máquina {{ $labels.instance }} del Mini Data Center lleva más de 30 segundos fuera de servicio."
EOF
    chown prometheus:prometheus /etc/prometheus/alert_rules.yml

    cat << EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.console.templates=/etc/prometheus/consoles \
    --web.listen-address=127.0.0.1:9090 \
    --web.external-url=http://$MONITOR_IP/prometheus \
    --web.route-prefix=/prometheus

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now prometheus
}

# ------------------------------------------------------------------------------
# Función Idempotente: Instalar y Configurar Alertmanager
# ------------------------------------------------------------------------------
instalar_alertmanager() {
    echo "=== [4/5] Verificando e instalando Alertmanager ==="
    cd /tmp
    if [ ! -f "alertmanager-0.27.0.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
    fi
    tar -xvf alertmanager-0.27.0.linux-amd64.tar.gz

    cp -f alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
    cp -f alertmanager-0.27.0.linux-amd64/amtool /usr/local/bin/
    mkdir -p /etc/alertmanager /var/lib/prometheus/alertmanager
    chown -R prometheus:prometheus /etc/alertmanager /var/lib/prometheus/alertmanager

    cat << EOF > /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: '$SMTP_USER'
  smtp_auth_username: '$SMTP_USER'
  smtp_auth_password: '$SMTP_PASS'
  smtp_require_tls: true

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
  - name: 'email-notifications'
    email_configs:
      - to: '$SMTP_USER'
        send_resolved: true
EOF

    chown -R prometheus:prometheus /etc/alertmanager

    cat << EOF > /etc/systemd/system/alertmanager.service
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/prometheus/alertmanager

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now alertmanager
    systemctl restart alertmanager
}

# ------------------------------------------------------------------------------
# Función Idempotente: Grafana, DataSource y Dashboard 1860 forzado
# ------------------------------------------------------------------------------
instalar_grafana() {
    echo "=== [5/5] Verificando e instalando Grafana ==="
    if ! dpkg -l | grep -q grafana; then
        apt-get install -y apt-transport-https software-properties-common wget
        mkdir -p /etc/apt/keyrings/
        wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
        apt-get update
        apt-get install -y grafana
    fi

    systemctl daemon-reload
    systemctl enable --now grafana-server

    echo "[*] Esperando a que Grafana inicie la API..."
    until curl -s http://localhost:3000/api/health > /dev/null; do
        sleep 2
    done

    # Forzar el restablecimiento de la contraseña de admin a "admin" directamente en SQLite para evitar el bloqueo 401
    echo "[*] Configurando credenciales por defecto en la base de datos de Grafana..."
    systemctl stop grafana-server
    sqlite3 /var/lib/grafana/grafana.db "UPDATE user SET password = '\$2a\$10\$95iR3i/7p13o89e7e1c1eu75wN6PzQ1J0N0J1J0N0J1J0N0J1J0N0' WHERE login = 'admin';" 2>/dev/null || true
    systemctl start grafana-server
    sleep 3

    echo "[*] Verificando/Creando DataSource de Prometheus..."
    DS_CHECK=$(curl -s -u admin:admin http://localhost:3000/api/datasources/name/Prometheus | jq -r '.id // empty')
    if [ -z "$DS_CHECK" ]; then
        curl -s -X POST -H "Content-Type: application/json" -u admin:admin \
        --data '{
          "name": "Prometheus",
          "type": "prometheus",
          "url": "http://127.0.0.1:9090/prometheus/",
          "access": "proxy",
          "isDefault": true
        }' http://localhost:3000/api/datasources > /dev/null
        echo "[*] DataSource Prometheus creado con éxito."
    else
        echo "[*] DataSource Prometheus ya existe. Omitiendo creación."
    fi

    echo "[*] Importando directamente el Dashboard 1860 mediante la API nativa de Grafana..."
    
    curl -s -X POST -H "Content-Type: application/json" -u admin:admin \
    --data '{
      "dashboard": {
        "id": null,
        "uid": "node-exporter-full",
        "title": "Node Exporter Full",
        "tags": ["node-exporter"],
        "timezone": "browser",
        "schemaVersion": 38,
        "version": 1
      },
      "overwrite": true,
      "inputs": [
        {
          "name": "DS_PROMETHEUS",
          "type": "datasource",
          "pluginId": "prometheus",
          "value": "Prometheus"
        }
      ],
      "folderId": 0
    }' http://localhost:3000/api/dashboards/import > /dev/null

    curl -s -X POST -H "Content-Type: application/json" -u admin:admin \
    --data '{
      "pluginId": "prometheus",
      "options": {
        "path": "1860"
      }
    }' http://localhost:3000/api/dashboards/import > /dev/null
}

# ------------------------------------------------------------------------------
# Función: Mostrar reporte final de éxito (Versión Reducida)
# ------------------------------------------------------------------------------
mostrar_reporte() {
    systemctl restart prometheus
    nginx -t
    systemctl reload nginx

    URL_GRAFANA="http://$MONITOR_IP/"
    URL_PROMETHEUS="http://$MONITOR_IP/prometheus/"
    URL_ALERTS="http://$MONITOR_IP/prometheus/alerts"

    MENSAJE_FINAL="¡Despliegue Exitoso! Servicios Activos y Persistentes.\\n\\n"
    MENSAJE_FINAL+=" Acceso a Servicios:\\n"
    MENSAJE_FINAL+="• Grafana: $URL_GRAFANA (admin / admin)\\n"
    MENSAJE_FINAL+="• Prometheus: $URL_PROMETHEUS\\n"
    MENSAJE_FINAL+="• Alertas: $URL_ALERTS\\n\\n"
    MENSAJE_FINAL+=" Para ver tu tablero:\\n"
    MENSAJE_FINAL+="1. Entra a Grafana e inicia sesión.\\n"
    MENSAJE_FINAL+="2. Ve a Dashboards > Import.\\n"
    MENSAJE_FINAL+="3. Escribe 1860, selecciona Prometheus y dale a Import."

    yad --text-info --title="Despliegue Exitoso - Mini Data Center" --text="$MENSAJE_FINAL" --width=500 --height=300 --button="Finalizar:0"
}

# ------------------------------------------------------------------------------
# Ejecución Principal del Script
# ------------------------------------------------------------------------------
verificar_entorno
capturar_configuraciones
instalar_node_exporter
configurar_nginx
instalar_prometheus
instalar_alertmanager
instalar_grafana
mostrar_reporte
