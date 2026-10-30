Manual tecnico de instalacion y configuracion: Nodo Monitor (Nginx, Prometheus, Grafana Y Alertmanager).


Modulo 1: Instalación y configuracion de Nginx


1. Instalación y configuración de Nginx

Instalamos Nginx en el Nodo Monitor y verificacion de que este corriengo:


sudo apt install -y nginx

sudo systemctl start nginx

sudo nginx -t

sudo systemctl status nginx


2. Gestión de conflictos con Apache si esta instalado.
Si el puerto 80 esttá ocupado por Apache, lo detendremos y lo deshabilitamos para eliminar conflictos:


sudo systemctl stop apache2

sudo systemctl disable apache2

sudo systemctl start nginx


3. Configuración del Proxy Inverso para el Monitoreo:
creamos y editamos el archivo de configuración virtual de Nginx.


sudo nano /etc/nginx/sites-available/datacenter-monitor.conf


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


4. Activación de la configuración:

Enlazamos el archivo de configuración, eliminamos la página por defecto y recargamos Nginx:


sudo ln -s /etc/nginx/sites-available/datacenter-monitor.conf /etc/nginx/sites-enabled/

sudo rm -f /etc/nginx/sites-enabled/default


Comprobamos que la sintaxis de Nginx no tenga errores:

sudo nginx -t

Recarga Nginx para aplicar los cambios:

sudo systemctl reload nginx



Modulo 2: Instalación y configuración de Prometheus.


1. Creación del Usuario del Sistema:

sudo useradd --no-create-home --shell /bin/false prometheus


2. Descarga de repositorios oficial:


cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.51.2/prometheus-2.51.2.linux-amd64.tar.gz
tar -xvf prometheus-2.51.2.linux-amd64.tar.gz


3. Instalación y Creación de directorios:


seguir en el mismo cd /tmp

3. Mover los binarios y crear carpetas de configuración

sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp prometheus-2.51.2.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.51.2.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chown prometheus:prometheus /usr/local/bin/promtool

sudo cp -r prometheus-2.51.2.linux-amd64/consoles /etc/prometheus/
sudo cp -r prometheus-2.51.2.linux-amd64/console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus


4. Crear el archivo de configuración de Prometheus

Crea el archivo principal de configuración:

sudo nano /etc/prometheus/prometheus.yml


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
        

Ajustamos los permisos del archivo:

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml


5. Creación del servicio Systemd
Configuramos el demonio de Systemd para mantener Prometheus ejecutándose en segundo plano:


sudo nano /etc/systemd/system/prometheus.service


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


6. Activación y inicio del Servicio

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
sudo systemctl status prometheus



Modulo 3: Instalación y Configuración de Grafana.


1. Instalación de Dependencia y Repositorio Oficial.


sudo apt-get install -y apt-transport-https software-properties-common wget
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list


2. Instalación del Servidor Grafana.

sudo apt-get update
sudo apt-get install -y grafana


3. Inicio y Activación del Servicio.


sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server
sudo systemctl status grafana-server


4. Configuración inicial en el Navegador:

# Estos son los enlace para entrar a grafana
http://192.168.11.52/login

# Enlace para prometheus

http://192.168.11.52/prometheus/


Credenciales por defecto: Usuario: admin | Contraseña: admin (te pedirá cambiarla en el primer ingreso; puedes definir por ejemplo 1751).

Agregar Fuente de Datos (Data Source):

Ve a Connections > Data sources > Add data source.

Selecciona Prometheus.

Ingresa la URL: http://127.0.0.1:9090/prometheus/.

Haz clic en Save & test.


Importar Dashboard de Node Exporter:

Ve a Dashboards > New > Import.

Introduce el ID oficial: 1860 (Node Exporter Full) y haz clic en Load.

Selecciona la fuente de datos Prometheus configurada previamente y haz clic en Import.



Modulo 4: Despligue del Agente Node-Exporter.


En cada una de nodos:

# 1. Conectarse a un nodo.

ssh nododatos@192.168.11.55


# 2. Instalar el paquete oficial de node exporter.

sudo apt install -y prometheus-node-exporter


# 3. Habilitar y verificar el servicio.

sudo systemctl enable --now prometheus-node-exporter

sudo systemctl status prometheus-node-exporter


# 4 Salir del Nodo.

exit


Reiniciamos Prometheus en el Nodo Monitor para refrescar:

sudo systemctl restart prometheus

(Verificamos en Prometheus ingresando a Status > Targets desde http://192.168.11.52/prometheus/).



Modulo 5: Configuracion de AlertManaer y Reglas de Alerta.


1. Descargar y descomprimir Alertmanager:

wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz

tar -xvf alertmanager-0.27.0.linux-amd64.tar.gz

Mover los binarios a su ruta oficial y crear directorios:

sudo cp alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
sudo cp alertmanager-0.27.0.linux-amd64/amtool /usr/local/bin/
sudo mkdir -p /etc/alertmanager /var/lib/prometheus/alertmanager
sudo chown -R prometheus:prometheus /etc/alertmanager /var/lib/prometheus/alertmanager


2. Configuración del Servicio Systemd para Alertmanager:

sudo nano /etc/systemd/system/alertmanager.service


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


Reiniciar e iniciar el servicio:


sudo systemctl daemon-reload
sudo systemctl enable --now alertmanager


3. Configuración de Alertas por correo (Gmail SMTP).

Copia el archivo de configuración base y editamos:


sudo cp alertmanager-0.27.0.linux-amd64/alertmanager.yml /etc/alertmanager/
sudo chown -R prometheus:prometheus /etc/alertmanager /var/lib/prometheus/alertmanager


Utilizamos la siguiente estructura con la contraseña de aplicacion de Gmail.


4. Configurar el archivo con SMTP de Gmail

sudo nano /etc/alertmanager/alertmanager.yml

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
        

Reiniciamos Alertmanager:

sudo systemctl restart alertmanager
sudo systemctl status alertmanager


4. Para que Alertmanager pueda enviar correos a través de Gmail sin problemas, necesitas generar una Contraseña de Aplicación (App Password) de 16 caracteres desde tu cuenta de Google:

* Entra a tu cuenta de Google (proyectomesa1@gmail.com).

* Ve a la sección de Seguridad de tu cuenta Google.

* Asegúrate de tener la Verificación en dos pasos activada (es un requisito indispensable de Google para crear contraseñas de aplicación).

* Busca la opción llamada Contraseñas de aplicaciones (App Passwords).

* Crea una nueva (puedes nombrarla por ejemplo "Alertmanager Mini Data Center"). Te dará una clave de 16 letras agrupadas.




* seguridad y inicio de sesión)! Como esa opción a veces está oculta para que no se presione por accidente, tienes dos formas muy rápidas de encontrarla en esa misma pantalla:Método más rápido (Usando el buscador):

* Dirígete a la barra de búsqueda superior de la página de Google (donde dice "Search Google Account" arriba a la izquierda).   

* Escribe Contraseñas de aplicaciones o App passwords y presiona Enter. Te llevará directo a la opción de inmediato.Desplazándote hacia abajo:

* Busca la sección de acceso y encontrarás la opción de Contraseñas de aplicaciones (App Passwords).    


Contraseña que me genero: zvkecqfrxdmkpgft 


4. Creación de Reglas de Monitoreo de caida.

Creamos el archivo de relgas en Prometheus:

sudo nano /etc/prometheus/prometheus.yml

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


Reiniciamos Prometheus para aplciar los cambios de reglas:

sudo systemctl restart prometheus


Panel de alertas: http://192.168.11.52/prometheus/alerts


Si quieres refrescar configuracions o corregir parametros de red:


sudo systemctl daemon-reload
sudo systemctl restart prometheus
sudo systemctl restart alertmanager
sudo nginx -t
sudo systemctl reload nginx

