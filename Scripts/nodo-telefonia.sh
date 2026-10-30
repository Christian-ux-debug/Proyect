#!/bin/bash
set -euo pipefail

#===================================#
#	Instalacion completa de telefonia	#
#					by Chris - Mesa 1				  #
#===================================#


if [[ $(whoami) != "root" ]]; then
	echo "lo siento, te recomiendo entrar en superusuario"
	exit 0
fi
apt update -y
apt install figlet lolcat -y
clear
figlet " Welcome" | lolcat -a
echo " ============================================="
echo " Script de instalacion y creacion de telefonia"
echo " ============================================="
sleep 3

echo ""
echo "  verificando si tienes asterisk..."
if dpkg -s asterisk &>/dev/null; then
	echo " asterisk ya esta instalado, continuando el script..."
else
	echo " Asterisk no esta instalado, instalando..."
	apt-get install asterisk -y &>/dev/null
	apt-get install asterisk-core-sounds-es asterisk-core-sounds-es-g722 asterisk-core-sounds-es-gsm asterisk-core-sounds-es-wav &>/dev/null
	service asterisk restart
fi

if ! asterisk -rx "core show version" >/dev/null 2>&1; then
    service asterisk start >/dev/null 2>&1
fi

if ! asterisk -rx "core show version" >/dev/null 2>&1; then
    echo " No se pudo iniciar Asterisk."
    exit 1
fi

asterisk -rx "module load chan_sip.so" >/dev/null 2>&1

if ! asterisk -rx "module show like chan_sip.so" 2>/dev/null | grep -Fq "chan_sip.so"; then
    echo " No se encuentra chan_sip.so."
    echo " Este script necesita ese modulo para funcionar."
    exit 1
fi

echo " Se reemplazaran los archivos de configuracion."
read -r -p " Quieres continuar? (s/n): " confirmar

if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
    echo " Configuracion cancelada."
    exit 0
fi

read -r -p " Cuantos telefonos quieres configurar?: " cantidad

case "$cantidad" in
    ''|*[!0-9]*)
        echo " Introduce un numero valido."
        exit 1
        ;;
esac

if [ "$cantidad" -lt 1 ]; then
    echo " Debes agregar al menos un telefono."
    exit 1
fi

for archivo in sip.conf extensions.conf musiconhold.conf queues.conf voicemail.conf confbridge.conf; do

    if [ -f "/etc/asterisk/$archivo" ] && [ ! -f "/etc/asterisk/$archivo.bak" ]; then
        if ! cp -p "/etc/asterisk/$archivo" "/etc/asterisk/$archivo.bak"; then
            echo " Error al crear la copia de seguridad de $archivo."
            exit 1
        fi
    fi

done

mkdir -p /var/lib/asterisk/moh/espera

cat > /etc/asterisk/sip.conf <<'EOF'
[general]
context=public
allowguest=no
udpbindaddr=0.0.0.0
tcpenable=no
transport=udp
disallow=all
allow=ulaw
allow=alaw
language=es

[telefonos](!)
type=friend
context=nodos
host=dynamic
secret=1234

EOF

cat > /etc/asterisk/musiconhold.conf <<'EOF'
[general]
cachertclasses=yes

[musica]
mode=files
directory=/var/lib/asterisk/moh/espera
sort=random
EOF

cat > /etc/asterisk/queues.conf <<'EOF'
[general]
autofill=yes
shared_lastcall=yes

[esperando]
musicclass=musica
strategy=ringall
timeout=10
retry=5
maxlen=0
EOF

cat > /etc/asterisk/voicemail.conf <<'EOF'
[general]
format=wav
maxsilence=10

[buzon]
EOF

cat > /etc/asterisk/confbridge.conf <<'EOF'
[admin]
type=user
pin=1751
marked=yes
admin=yes
music_on_hold_class=musica
music_on_hold_when_empty=yes
announce_user_count=yes

[usuarios]
type=user
pin=1234
wait_marked=yes
end_marked=yes
music_on_hold_class=musica
music_on_hold_when_empty=yes
announce_user_count=yes

[conferencia]
type=bridge
language=es
max_members=10
EOF

cat > /etc/asterisk/extensions.conf <<'EOF'
[nodos]
EOF

numero=1
extension=11

while [ "$numero" -le "$cantidad" ]; do

    while [ "$extension" -eq 20 ] || [ "$extension" -eq 60 ] || [ "$extension" -eq 70 ] || [ "$extension" -eq 71 ]; do
        extension=$((extension + 1))
    done

    echo
    echo " Telefono $numero de $cantidad"

    while true; do

        read -r -p " Nombre SIP: " nombre

        nombre=$(echo "$nombre" | tr 'A-Z' 'a-z' | tr -d ' ')

        case "$nombre" in
            ''|*[!a-z0-9_-]*)
                echo " Nombre no valido. Usa letras, numeros, guion o guion bajo."
                ;;
            *)
                if grep -Fq "[$nombre](telefonos)" /etc/asterisk/sip.conf; then
                    echo " Ese nombre ya existe."
                else
                    break
                fi
                ;;
        esac

    done

    read -r -p " CallerID (nombre que aparecera al llamar): " callerid

    if [ -z "$callerid" ]; then
        callerid="$nombre"
    fi

    # Evitar comillas en el CallerID
    callerid=$(printf '%s' "$callerid" | tr -d '"')

    echo " Usuario: $nombre"
    echo " CallerID: $callerid"
    echo " Extension: $extension"

    # Agregar usuario SIP
    cat >> /etc/asterisk/sip.conf <<EOF
[$nombre](telefonos)
callerid="$callerid" <$extension>

EOF

    # Agregar telefono a la cola
    echo "member => SIP/$nombre" >> /etc/asterisk/queues.conf

    # Crear buzon
    echo "$extension => 4321,$callerid" >> /etc/asterisk/voicemail.conf

    # Agregar llamada y buzon al plan de marcacion
    cat >> /etc/asterisk/extensions.conf <<EOF
exten => $extension,1,Answer()
same => n,Set(CHANNEL(musicclass)=musica)
same => n,Dial(SIP/$nombre,10)
same => n,VoiceMail($extension@buzon,s)
same => n,Hangup()

EOF

    numero=$((numero + 1))
    extension=$((extension + 1))

done

# Serivicos adicionales

cat >> /etc/asterisk/extensions.conf <<'EOF'
; Cola de llamadas
exten => 20,1,Answer()
same => n,Queue(esperando)
same => n,Hangup()

; Consultar buzon
exten => 60,1,Answer()
same => n,VoiceMailMain(@buzon)
same => n,Hangup()

; Conferencia administrador
exten => 70,1,Answer()
same => n,ConfBridge(1,conferencia,admin)
same => n,Hangup()

; Conferencia usuarios
exten => 71,1,Answer()
same => n,ConfBridge(1,conferencia,usuarios)
same => n,Hangup()
EOF

echo
echo " Reiniciando Asterisk..."

if service asterisk restart; then

    if asterisk -rx "core show version" >/dev/null 2>&1; then
        echo " Configuracion terminada correctamente."
    else
        echo " Asterisk no responde despues del reinicio."
        exit 1
    fi

else
    echo " Error al reiniciar Asterisk."
    exit 1
fi

echo
echo " Telefonos configurados: $cantidad"
echo " Cola: 20"
echo " Buzon: 60"
echo " Conferencia administrador: 70"
echo " Conferencia usuarios: 71"
echo
echo " Configuracion finalizada."
