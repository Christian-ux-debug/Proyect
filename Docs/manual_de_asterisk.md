## Manual General de Instalación y Configuración de Asterisk

### ¿Qué es Asterisk?
Asterisk es un framework de código abierto que convierte una computadora normal en un servidor de comunicaciones (PBX o central telefónica privada). Desarrollado inicialmente por Mark Spencer, permite gestionar llamadas telefónicas, interconectar redes de telefonía tradicional (PSTN) con redes de voz sobre IP (VoIP) y desplegar sistemas de comunicación avanzados sin necesidad de hardware propietario costoso.

### ¿Cómo se aplica Asterisk?
Se utiliza para construir desde pequeños sistemas telefónicos para oficinas corporativas hasta grandes centros de atención telefónica (Call Centers). Sus aplicaciones más comunes incluyen:
* **Conmutación de llamadas (PBX):** Conectar teléfonos internos entre sí y enrutarlos hacia el exterior.
* **Sistemas de Respuesta de Voz Interactiva (IVR):** Menús telefónicos automáticos ("Marque 1 para ventas, 2 para soporte").
* **Colas de atención:** Distribución de llamadas entrantes entre un grupo de agentes disponibles.
* **Servicios unificados:** Buzones de voz con envío a correo electrónico, grabación de llamadas y salas de audioconferencia.

---

### Proceso de Configuración Paso a Paso

Para desplegar un entorno de telefonía funcional, la configuración debe seguir un orden lógico desde la instalación de paquetes hasta el enrutamiento de las llamadas.

#### 1. Instalación del Sistema Base y Paquetes de Voz
El primer paso requiere acceso de superusuario (root) para instalar el motor principal y los archivos de audio en el idioma local.
* Actualizar los repositorios del sistema operativo.
* Instalar el paquete `asterisk`.
* Instalar los paquetes de audio (`asterisk-core-sounds`) en los códecs necesarios (wav, gsm, g722) para que las locuciones del sistema (como los mensajes del buzón de voz) se escuchen en español.

#### 2. Activación de Módulos de Comunicación
Asterisk funciona mediante módulos. Para conectar teléfonos IP estándar o softphones, es indispensable cargar el controlador SIP.
* Iniciar el servicio de Asterisk.
* Verificar y cargar el módulo `chan_sip.so` (o `pjsip` en implementaciones más modernas) para permitir el registro de dispositivos.

#### 3. Respaldo de Archivos Originales
Antes de personalizar la central, se deben crear copias de seguridad de los archivos de configuración predeterminados ubicados en `/etc/asterisk/`. Los archivos críticos a respaldar son:
* `sip.conf`
* `extensions.conf`
* `musiconhold.conf`
* `queues.conf`
* `voicemail.conf`
* `confbridge.conf`

#### 4. Configuración de Dispositivos (sip.conf)
Este archivo define quién puede conectarse a la central telefónica.
* **Configuración Global:** Se define el transporte (UDP), se rechazan las llamadas de invitados por seguridad (`allowguest=no`) y se especifican los códecs de audio permitidos (como `alaw` o `ulaw`).
* **Creación de Extensiones:** Se configuran los perfiles de los teléfonos (peers/friends), asignándoles un número de extensión, un nombre de usuario (CallerID), una contraseña (secret) y un contexto de red.

#### 5. Configuración de Servicios Auxiliares
Asterisk requiere que cada función especial tenga su propia parametrización en su archivo correspondiente:
* **Música en Espera (`musiconhold.conf`):** Se define un directorio (por ejemplo, `/var/lib/asterisk/moh/`) donde se alojarán los archivos de audio que escucharán los usuarios al ser puestos en espera.
* **Colas de Llamadas (`queues.conf`):** Se crean grupos de atención. Se define la estrategia de timbrado (por ejemplo, `ringall` para que suenen todos los agentes a la vez) y el tiempo máximo de espera.
* **Buzones de Voz (`voicemail.conf`):** Se establecen los buzones asignados a cada extensión, definiendo el formato de grabación y el PIN de seguridad de acceso.
* **Salas de Conferencia (`confbridge.conf`):** Se configuran perfiles de salas y de usuarios, diferenciando entre administradores (que controlan la sala) y usuarios regulares, así como los pines de acceso respectivos.

#### 6. Plan de Marcación (extensions.conf)
El "Dialplan" es el cerebro de Asterisk. Define qué sucede exactamente cuando un usuario marca un número.
* **Contextos:** Se agrupan las reglas bajo el mismo nombre asignado a los usuarios en el `sip.conf` (ej. `[nodos]`).
* **Reglas de Extensiones Físicas:** Se indica al servidor que, al marcar un número de extensión, debe hacer timbrar el dispositivo SIP correspondiente, y si no contesta en un tiempo determinado (ej. 10 segundos), derivar la llamada al buzón de voz.
* **Reglas de Servicios:** Se asignan números cortos para acceder a los servicios configurados. 
  * Un número para entrar a la cola de atención.
  * Un número para revisar el buzón de voz.
  * Números específicos para ingresar a las salas de conferencias (como administrador o como invitado).

#### 7. Aplicación de Cambios
Una vez que todos los archivos `.conf` están guardados, se debe reiniciar el servicio de Asterisk (`service asterisk restart` o recargar el núcleo desde la consola de Asterisk). Esto fuerza al sistema a leer la nueva configuración, habilitar los registros de los teléfonos e iniciar el enrutamiento de llamadas diseñado.