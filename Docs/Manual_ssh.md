Manual de instalacion y configuracion de SSH en el "nodo monitor" (gestion centralizada de llaves)

----Instalacion de SSH------

1. Actualizamos los repositorios e instalamos el servidor SSH en el nodo monitor:

sudo apt update && sudo apt install -y openssh-server

2. Activamos e iniciamos el servicio:

sudo systemctl enable --now ssh

----Generacion de la llave------

1. Generamos la llave Ed25519 en el nodo monitor (solo se genera aqui):

ssh-keygen -t ed25519 -C "nodo@monitor" -f ~/.ssh/id_ed25519 -N ""

----Copia de la llave a los nodos------

1. Copiamos la llave publica a cada nodo de la infraestructura, siempre desde el nodo monitor. Ejemplo con el nodo de datos:

ssh-copy-id -i ~/.ssh/id_ed25519.pub nododatos@192.168.11.55

2. Escribimos "yes" cuando pregunte si queremos continuar conectando e ingresamos la contraseña del nodo.

3. Probamos la conexion sin contraseña, sin salirnos de la terminal:

ssh nododatos@192.168.11.55

4. Para salir del nodo ejecutamos:

exit

5. Repetimos los pasos 1 al 4 con los demas nodos (cambiando usuario e IP).
