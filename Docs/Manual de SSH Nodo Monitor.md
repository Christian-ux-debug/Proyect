MANUAL DE GESTIÓN CENTRALIZADA DE SSH EN EL NODO MONITOR

Introducción

Las llaves criptográficas de administración se generan unicamente en el Nodo Monitor donde sera la principal de la infraestructura del DATA CENTER, donde llevara a cabo diferentes tipos de herramientas para el buen funcionamiento de la infraestructura, una de las herramientas que serán clave para la ejecución de procesos de automatización como playbooks a través de la herramienta SSH donde podremos comunicarnos y interactuar con la terminal de los diferentes nodos.

En este manual te enseñaremos a como lo adaptamos a nuestro entorno de infraestructura del datacenter:


Paso 1: Actualización de repositorios, instalación de la herramienta SSH y arranque del servidor:

# Ejecutamos estos comando en la terminal en el Nodo Monitor:

sudo apt update && sudo apt install -y openssh-server

sudo systemctl enable --now ssh


Paso 2: Generación de la clave Ed25519 en el Nodo Monitor:

ssh-keygen -t ed25519 -C "nodo@monitor" -f ~/.ssh/id_ed25519 -N ""


Paso 3: Copiamos la llave pública para los nodos de la infraestructura siempre en el nodo monitor, ejemplo:

ssh-copy-id -i ~/.ssh/id_ed25519.pub nododatos@192.168.11.55


Paso 4: Después de decirle que yes en la terminal y haberse conectado perfectamente, en el mismo apartado de la terminal sin salirse ejecutamos el siguiente comando para probar conexión sin contraseña:

ssh nododatos@192.168.11.55

# Para salirse de cada nodo dentro del ssh solo ejecutamos Exit en la terminal.

Nota: Después de haber hecho esto y todo salio bien sigue con los otros nodos restantes.
