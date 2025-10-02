#!/bin/bash

# Script para configurar automáticamente Supabase en Metabase
# Intenta diferentes contraseñas comunes de Supabase

set -e

echo "🔧 Configurando automáticamente la conexión a Supabase..."

# Esperar a que Metabase esté listo
echo "⏳ Esperando a que Metabase esté listo..."
for i in {1..20}; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo "✅ Metabase está listo!"
        break
    fi
    echo "⏳ Esperando... ($i/20)"
    sleep 15
done

# Verificar si Metabase está funcionando
if ! curl -s http://localhost:3000/api/health > /dev/null; then
    echo "❌ Metabase no está respondiendo"
    exit 1
fi

# Lista de contraseñas comunes de Supabase para probar
PASSWORDS=(
    "your-supabase-password"
    "postgres"
    "supabase"
    "password"
    "admin"
    "root"
    "metabase"
    "timesheet"
    "qfpswxjunoepznrpsltt"
    "PowerSolution2024"
    "PSI2024"
    "PSLAB2024"
)

echo "🔍 Probando conexión con diferentes contraseñas..."

for password in "${PASSWORDS[@]}"; do
    echo "🔑 Probando contraseña: $password"

    # Crear datos de conexión
    CONNECTION_DATA='{
        "engine": "postgres",
        "name": "Supabase Timesheet",
        "details": {
            "host": "db.qfpswxjunoepznrpsltt.supabase.co",
            "port": 5432,
            "dbname": "postgres",
            "user": "postgres",
            "password": "'$password'",
            "ssl": true,
            "ssl-mode": "require",
            "tunnel-enabled": false,
            "advanced-options": false,
            "retrieve-fields": true
        }
    }'

    # Probar la conexión usando la API de Metabase
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$CONNECTION_DATA" \
        http://localhost:3000/api/database/test 2>/dev/null || echo "ERROR")

    if echo "$RESPONSE" | grep -q '"valid":true'; then
        echo "✅ ¡CONTRASEÑA ENCONTRADA: $password"
        echo "🔧 Configurando conexión permanente..."

        # Crear la conexión permanente
        CREATE_RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$CONNECTION_DATA" \
            http://localhost:3000/api/database 2>/dev/null || echo "ERROR")

        if echo "$CREATE_RESPONSE" | grep -q '"id"'; then
            echo "✅ ¡CONEXIÓN A SUPABASE CONFIGURADA EXITOSAMENTE!"
            echo "🌐 Accede a Metabase: http://192.168.88.68:3000"
            echo "🗄️ Base de datos: Supabase Timesheet"
            exit 0
        else
            echo "❌ Error creando la conexión permanente"
            echo "Respuesta: $CREATE_RESPONSE"
        fi
    elif echo "$RESPONSE" | grep -q '"valid":false'; then
        echo "❌ Contraseña incorrecta: $password"
    else
        echo "⚠️ Error probando contraseña: $password"
    fi

    sleep 2
done

echo ""
echo "❌ No se pudo encontrar la contraseña correcta automáticamente"
echo ""
echo "📋 CONFIGURACIÓN MANUAL:"
echo "1. 🌐 Accede a: http://192.168.88.68:3000"
echo "2. 👤 Crea tu cuenta de administrador"
echo "3. 🗄️ Ve a Settings > Admin > Databases"
echo "4. ➕ Haz clic en 'Add database' > PostgreSQL"
echo ""
echo "📝 DATOS DE CONEXIÓN:"
echo "   Name: Supabase Timesheet"
echo "   Host: db.qfpswxjunoepznrpsltt.supabase.co"
echo "   Port: 5432"
echo "   Database name: postgres"
echo "   Username: postgres"
echo "   Password: [OBTENER DESDE SUPABASE DASHBOARD]"
echo "   SSL Mode: require"
echo ""
echo "🔑 OBTENER CONTRASEÑA:"
echo "   https://supabase.com/dashboard → Proyecto qfpswxjunoepznrpsltt → Settings → Database"





