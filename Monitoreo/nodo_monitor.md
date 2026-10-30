Manual de instalacion y configuracion del "nodo monitor" (Nginx, Prometheus, Grafana y Alertmanager)

----Instalacion de Ngnix------

1. Instalamos Ngnix en el nodo monitor:

sudo apt install -y nginx

2. Detenemos y deshabiitamos el puerto 80:

sudo systemctl stop apache2

sudo systemctl disable apache2

3. Configuramos el proxy inverso para el monitoreo:

server {
    listen 80;
    server_name monitor.altavista.local 192.168.11.52;

    # 1. Interfaz de Prometheus
    location /prometheus/ {
        proxy_pass http://127.0.0.1:9090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 2. Interfaz de Alertmanager
    location /alertmanager/ {
        proxy_pass http://127.0.0.1:9093/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # 3. Interfaz de Grafana (Servicio principal en la raíz)
    location / {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
    
4. Enlazamos el archivo de cnfiguracion, eliminamos la pagina por defecto y recargamos:

sudo ln -s /etc/nginx/sites-available/datacenter-monitor.conf /etc/nginx/sites-enabled/

sudo rm -f /etc/nginx/sites-enabled/default

----Instalacion de Prometheus------

1. Creacion el usuario del sistema:

sudo useradd --no-create-home --shell /bin/false prometheus

2. Descargamos los repositorios oficiales:

cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.51.2/prometheus-2.51.2.linux-amd64.tar.gz
tar -xvf prometheus-2.51.2.linux-amd64.tar.gz

3. Movemos los binarios y creamos las carpetas de configuracion

sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp prometheus-2.51.2.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.51.2.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chown prometheus:prometheus /usr/local/bin/promtool

sudo cp -r prometheus-2.51.2.linux-amd64/consoles /etc/prometheus/
sudo cp -r prometheus-2.51.2.linux-amd64/console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

4. Creamos el archivo de configuracion de pormetheus

global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter_datacenter'
    static_configs:
      - targets: 
        - '192.168.11.52:9100'  # Nodo Monitor
        - '192.168.11.53:9100'  # Nodo Servicio
        - '192.168.11.55:9100'  # Nodo Datos
        - '192.168.11.1:9100'   # Pasarela 1
        - '192.168.11.2:9100'   # Pasarela 2
        - '192.168.11.54:9100'  # Telefonia
        
5. Damos permisos al archivos:

con "sudo chmow"

6. Configuramos el demonio para qe se ejcute en segundo plano

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
    --web.external-url=http://192.168.11.52/prometheus \
    --web.route-prefix=/prometheus

[Install]
WantedBy=multi-user.target

7. Activamos e iniciamos el servicio

----Instalacion de Grafana------

1. Instalamos dpendecias y repositorios oficiales

sudo apt-get install -y apt-transport-https software-properties-common wget
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

2. Instalamos el servidor de grafana

sudo apt-get update
sudo apt-get install -y grafana

3. Iniciamos el servidor

----Instalacion de Alertmanager------

1. Descargamos y descomprimimos AlertManager
wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz

tar -xvf alertmanager-0.27.0.linux-amd64.tar.gz

2. Configuramos el servidor systemd para Alertmanager

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

*Reiniciamos el servidor*

3. Copiamos e archivo base y editamos lo siguiente

sudo cp alertmanager-0.27.0.linux-amd64/alertmanager.yml /etc/alertmanager/
sudo chown -R prometheus:prometheus /etc/alertmanager /var/lib/prometheus/alertmanager

4. Coniguramos el archivo con SMTP de Gmial

global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'proyectomesa1@gmail.com'
  smtp_auth_username: 'proyectomesa1@gmail.com'
  smtp_auth_password: 'zvkecqfrxdmkpgft'
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
      - to: 'proyectomesa1@gmail.com'
        send_resolved: true
        
*Reiniciamos Alertmanager*

5. Generamos una contraseña de 16 caracteres desde nuestra cuenta de google

6. Creamos el archivo de reglas en Prometheus

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
          
*Reiniciamos prometheus*


