MANUAL DE APROVISIONAMIENTO, HARDENING Y GESTIÓN CENTRALIZADA DE NODOS CON ANSIBLE


INTRODUCCIÓN

La administración de la infraestructura del Data Center se centraliza desde el Nodo Monitor, el cual tiene como rol de nodo de control principal, Desde esta maquina se ejecutaran las herramientas de automatización y despliegue masivo mediante playbooks de Ansible. Estableciendo una comunicación segura, cifrada e interactiva a través de la terminal hacia los diferentes nodos. Este manual detalla paso a paso.


Paso 1: Configuración del Nodo Monitor (instalación de Ansible):

sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

Para confirmar que la herramienta quedó instalada correctamente y validar su versión actual en el sistema, ejecutamos:

ansible --version


Paso 2: Creación del Archivo de inventario de Ansible:

El archivo de inventario es el componente donde se registran las direcciones IP de los nodos que conforman la infraestructura y se configuran las credenciales de acceso automatizado.

sudo mkdir -p /etc/ansible
sudo nano /etc/ansible/inventory.ini

En el siguiente contenido con los nodos de datos y servicio

[nodos_cluster]
192.168.11.53
192.168.11.55

[all:vars]
ansible_user=fernando
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3


Paso 3: Validación de Conectividad con el Clúster

#Los nodos deben esta encendidas
ansible nodos_cluster -i /etc/ansible/inventory.ini -m ping


Paso 4: Despliegue del Playbook de Automatización, Monitoreo y seguridad:

Este playbook se encarga de aprovisionar idempotentemente los nodos, aplicando:

* Limpieza de bloqueos del gestor de paquetes (dpkg / apt).

* Instalación del agente de métricas (prometheus-node-exporter), servidor web (nginx) y herramientas de seguridad (fail2ban, arpon).

* Hardening del servicio SSH (/etc/ssh/sshd_config.d/99-hardening.conf).

* Configuración de reglas estrictas de filtrado de tráfico mediante Iptables.

* Despliegue del sitio web de prueba en Nginx.


# Creamos el directorio:

sudo nano /etc/ansible/deploy_datacenter.yml

Nota: nodo servicio (192.168.11.53) y nodo monitor (192.168.11.52) debes de cambiarlo por la ip real que asignaremos.

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


Paso 5: Resolución de Bloqueos en Gestores de Paquetes (Mantenimiento Preventivo)

En caso de que puedan haber presentes bloqueos previos en el servicio de actualizaciones (APT), es necesario realizar una limpieza manual antes de lanzar el despliegue de automático:

#Entramos al nodo_datos
ssh nododatos@192.168.11.55

Ejecuta directamente estos comandos para limpiar los archivos de bloqueo y reconfigurar el gestor de paquetes:

sudo rm -f /var/lib/dpkg/lock-frontend
sudo rm -f /var/cache/apt/archives/lock
sudo rm -f /var/lib/dpkg/lock
sudo dpkg --configure -a
exit

# Hazlo en los 2 nodos.


Paso 6: Lanzar la Automatización

Una vez creado el playbook, ejecuta el comando de despliegue masivo hacia los 2 nodos:

# Esta es para ver el proceso de la instalación:
ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/deploy_datacenter.yml --ask-become-pass -vvv

# Esta es para manera silenciosa
ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/deploy_datacenter.yml --ask-become-pass


# Esta es solo para un nodo especifico, se tiene que hacer en ambos nodos
ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/deploy_datacenter.yml --ask-become-pass --limit 192.168.11.53
