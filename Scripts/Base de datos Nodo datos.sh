#!/bin/bash

# ==============================================================================
# Script Idempotente de Configuración de Base de Datos y Tablas MariaDB
# Ejecutado en: Nodo de Datos (como usuario normal)
# ==============================================================================

set -euo pipefail

echo "======================================================"
echo "   CONFIGURACIÓN IDEMPOTENTE DE BASE DE DATOS Y TABLA"
echo "======================================================"

# 1. Captura de parámetros con valores por defecto
read -rp "Nombre de la Base de Datos [db_datacenter]: " DB_NAME
DB_NAME=${DB_NAME:-db_datacenter}

read -rp "Nombre del Usuario de la app [app_user]: " DB_USER
DB_USER=${DB_USER:-app_user}

read -rsp "Contraseña para el usuario '$DB_USER': " DB_PASS
echo ""
read -rsp "Confirme la contraseña: " DB_PASS_CONFIRM
echo ""

if [ "$DB_PASS" != "$DB_PASS_CONFIRM" ] || [ -z "$DB_PASS" ]; then
    echo "[!] Las contraseñas no coinciden o están vacías. Abortando."
    exit 1
fi

read -rp "IP del Nodo Servicio autorizada [192.168.3.23]: " IP_SERVICIO
IP_SERVICIO=${IP_SERVICIO:-192.168.3.23}

echo ""
echo "[*] Creando/Verificando Base de Datos y Usuarios..."

# 2. Archivo SQL temporal seguro
SQL_TMP=$(mktemp)
chmod 600 "$SQL_TMP"
trap 'rm -f "$SQL_TMP"' EXIT

# Generar sentencias SQL idempotentes
cat << EOF > "$SQL_TMP"
-- Crear Base de datos si no existe
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;

-- Crear o actualizar usuario para acceso remoto desde el Nodo Servicio
CREATE USER IF NOT EXISTS '$DB_USER'@'$IP_SERVICIO' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'$IP_SERVICIO' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$IP_SERVICIO';

-- Crear usuario para pruebas locales en el propio Nodo de Datos
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';

FLUSH PRIVILEGES;
EOF

# Se ejecuta con sudo solo la conexión interna a MySQL
sudo mysql -u root < "$SQL_TMP"
echo "[✓] Base de datos '$DB_NAME' y usuarios configurados con éxito."

# 3. Opción para crear Tabla de prueba
echo ""
read -rp "¿Deseas crear una tabla de prueba en '$DB_NAME'? (s/n): " CREAR_TABLA

if [[ "$CREAR_TABLA" =~ ^[sS]$ ]]; then
    read -rp "Nombre de la tabla [registros_servidor]: " TABLA_NAME
    TABLA_NAME=${TABLA_NAME:-registros_servidor}

    echo "[*] Verificando e insertando tabla de forma idempotente..."

    cat << EOF > "$SQL_TMP"
USE \`$DB_NAME\`;

CREATE TABLE IF NOT EXISTS \`$TABLA_NAME\` (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nodo_origen VARCHAR(50) NOT NULL,
    mensaje VARCHAR(255) NOT NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insertar un registro inicial de prueba solo si la tabla está vacía
INSERT INTO \`$TABLA_NAME\` (nodo_origen, mensaje)
SELECT 'Nodo Servicio', 'Prueba inicial de conexión exitosa'
WHERE NOT EXISTS (SELECT 1 FROM \`$TABLA_NAME\` LIMIT 1);
EOF

    sudo mysql -u root < "$SQL_TMP"
    echo "[✓] Tabla '$TABLA_NAME' verificada y lista en '$DB_NAME'."
else
    echo "[*] Se omitió la creación de la tabla."
fi

echo ""
echo "======================================================"
echo " ¡CONFIGURACIÓN COMPLETADA CON ÉXITO!"
echo "======================================================"
echo "Desde el Nodo Servicio ($IP_SERVICIO) puedes conectarte con:"
echo "  mysql -h <IP_NODO_DATOS> -u $DB_USER -p $DB_NAME"
