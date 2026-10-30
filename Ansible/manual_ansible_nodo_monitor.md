Manual de instalacion y configuracion de Ansible en el "nodo monitor" (gestion de nodos del cluster)

----Instalacion de Ansible------

1. Instalamos las dependencias y el repositorio oficial de Ansible en el nodo monitor:

sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible

2. Instalamos Ansible:

sudo apt install -y ansible

3. Verificamos que quedo instalado:

ansible --version

----Creacion del inventario------

1. Creamos la carpeta y el archivo de inventario:

sudo mkdir -p /etc/ansible
sudo nano /etc/ansible/inventory.ini

2. Agregamos las IP de los nodos y el usuario de conexion (cambiar por los datos reales):

[nodos_cluster]
192.168.11.53
192.168.11.55

[all:vars]
ansible_user=fernando
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3

3. Probamos la conexion con los nodos (deben estar encendidos):

ansible nodos_cluster -i /etc/ansible/inventory.ini -m ping

Si todo esta bien, cada nodo responde con "pong".

----Creacion del Playbook------

1. Creamos el archivo del playbook:

sudo nano /etc/ansible/deploy_datacenter.yml

2. Agregamos lo siguiente (instala nginx, node-exporter y fail2ban, activa los servicios y publica una pagina de prueba):

---
- name: Configuracion basica de los nodos
  hosts: nodos_cluster
  become: yes
  tasks:
    - name: Instalar paquetes
      apt:
        name:
          - nginx
          - prometheus-node-exporter
          - fail2ban
        state: present
        update_cache: yes

    - name: Activar y habilitar servicios
      systemd:
        name: "{{ item }}"
        state: started
        enabled: yes
      loop:
        - nginx
        - prometheus-node-exporter
        - fail2ban

    - name: Crear pagina web de prueba
      copy:
        dest: /var/www/html/index.html
        content: |
          <!DOCTYPE html>
          <html lang="es">
          <head>
              <meta charset="UTF-8">
              <title>Nodo Servicio</title>
          </head>
          <body>
              <h1>Servidor Nginx funcionando</h1>
              <p>Nodo integrado al cluster.</p>
          </body>
          </html>

----Ejecucion del Playbook------

1. Ejecutamos el playbook en todos los nodos:

ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/deploy_datacenter.yml --ask-become-pass

2. Si queremos ver el detalle del proceso, agregamos -vvv al final:

ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/deploy_datacenter.yml --ask-become-pass -vvv

3. Si queremos ejecutarlo en un solo nodo, usamos --limit:

ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/deploy_datacenter.yml --ask-become-pass --limit 192.168.11.53

4. Verificamos abriendo en el navegador la IP de cada nodo, por ejemplo http://192.168.11.53, y debe aparecer la pagina de prueba.
