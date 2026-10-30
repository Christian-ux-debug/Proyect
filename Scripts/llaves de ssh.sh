#!/bin/bash

# ==============================================================================
# Script de Gestión Criptográfica y Propagación SSH (Ed25519) - Versión Ajustada
# Ejecutado en: Nodo Monitor (192.168.3.10)
# ==============================================================================

# 1. Verificar e instalar 'yad' si no está presente
if ! command -v yad &> /dev/null; then
    echo "[*] La herramienta 'yad' no está instalada. Instalándola..."
    sudo apt update && sudo apt install -y yad
    if [ $? -ne 0 ]; then
        echo "[!] Error al instalar yad. Abortando."
        exit 1
    fi
fi

# 2. Asegurar que el servicio SSH esté activo en el monitor
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh

# 3. Generar llave Ed25519 central si no existe previamente
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "[*] Generando llave criptográfica Ed25519 en el Nodo Monitor..."
    ssh-keygen -t ed25519 -C "nodo@monitor" -f ~/.ssh/id_ed25519 -N ""
fi

# 4. Interfaz gráfica con Yad para captura dinámica de IPs
NODES=()

while true; do
    # Ventana para capturar la IP del nodo
    IP_INPUT=$(yad --entry \
        --title="Gestión de Nodos - Clúster" \
        --text="Ingrese la dirección IP del nodo destino:\n(Ejemplo: 192.168.3.20)\n\nNodos ingresados actualmente: ${#NODES[@]}" \
        --entry-text="" \
        --button="Agregar IP:0" \
        --button="Aceptar y Continuar:1" \
        --button="Cancelar:2")

    RET=$?

    # Botón Cancelar (2) o cierre de ventana
    if [ $RET -eq 2 ] || [ $RET -eq 255 ]; then
        yad --info --title="Cancelado" --text="El script ha sido cancelado por el usuario." --timeout=3
        exit 0
    fi

    # Botón Aceptar y Continuar (1)
    if [ $RET -eq 1 ]; then
        if [ ${#NODES[@]} -eq 0 ]; then
            yad --error --title="Error" --text="Debe ingresar al menos una dirección IP antes de continuar."
            continue
        fi
        break
    fi

    # Botón Agregar IP (0)
    IP_LIMPIA=$(echo "$IP_INPUT" | xargs) # Quitar espacios en blanco

    if [ -z "$IP_LIMPIA" ]; then
        yad --error --title="Error" --text="La IP no puede estar vacía."
        continue
    fi

    # Validar si la IP ya fue ingresada en el arreglo
    DUPLICADA=0
    for ip_existente in "${NODES[@]}"; do
        if [ "$ip_existente" == "$IP_LIMPIA" ]; then
            DUPLICADA=1
            break
        fi
    done

    if [ $DUPLICADA -eq 1 ]; then
        yad --warning --title="IP Duplicada" --text="La dirección IP [ $IP_LIMPIA ] ya ha sido ingresada previamente. Ingrese una diferente."
    else
        NODES+=("$IP_LIMPIA")
    fi
done

# 5. Proceso de Propagación Directa de Llaves hacia los nodos recopilados
RESULTADOS="Iniciando Propagación de Llaves SSH (Modo Hardened):\n\n"

for ip in "${NODES[@]}"; do
    echo "[$ip] Copiando llave pública directamente..."
    
    # Inyección directa de la llave pública saltando la restricción de contraseña
    cat ~/.ssh/id_ed25519.pub | ssh -o StrictHostKeyChecking=no fernando@$ip "mkdir -p ~/.ssh && grep -qxF \"$(cat ~/.ssh/id_ed25519.pub)\" ~/.ssh/authorized_keys || echo \"$(cat ~/.ssh/id_ed25519.pub)\" >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
    
    if [ $? -eq 0 ]; then
        RESULTADOS+="[ $ip ] -> OK: Llave instalada y permisos asegurados.\n"
    else
        RESULTADOS+="[ $ip ] -> ERROR: Fallo al instalar la llave.\n"
    fi
done

# Mostrar reporte final en pantalla con Yad
yad --text-info --title="Reporte de Propagación SSH" --text="$RESULTADOS" --width=500 --height=300 --button="Finalizar:0"
