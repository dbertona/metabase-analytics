#!/bin/bash

# Script completo para configurar Metabase y conectar a Supabase
# Uso: ./scripts/setup-complete.sh

set -e

echo "🚀 Configurando Metabase completo con conexión a Supabase..."

# Esperar a que Metabase esté listo
echo "⏳ Esperando a que Metabase esté listo..."
for i in {1..30}; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo "✅ Metabase está listo!"
        break
    fi
    echo "⏳ Esperando... ($i/30)"
    sleep 10
done

# Verificar si Metabase está funcionando
if ! curl -s http://localhost:3000/api/health > /dev/null; then
    echo "❌ Metabase no está respondiendo después de 5 minutos"
    exit 1
fi

# Verificar si ya está configurado
echo "🔍 Verificando si Metabase ya está configurado..."
if curl -s http://localhost:3000/api/session/properties | grep -q "setup-token"; then
    echo "✅ Metabase ya está configurado"
else
    echo "🔧 Metabase necesita configuración inicial"
    echo ""
    echo "📋 CONFIGURACIÓN MANUAL REQUERIDA:"
    echo ""
    echo "1. 🌐 Accede a: http://192.168.88.68:3000"
    echo "2. 👤 Crea tu cuenta de administrador"
    echo "3. 🏢 Configura tu organización"
    echo "4. ⏭️ Salta la configuración de base de datos por ahora"
    echo ""
    echo "5. 🗄️ Ve a Settings > Admin > Databases"
    echo "6. ➕ Haz clic en 'Add database'"
    echo "7. 🐘 Selecciona 'PostgreSQL'"
    echo ""
    echo "📝 DATOS DE CONEXIÓN A SUPABASE:"
    echo "   Name: Supabase Timesheet"
    echo "   Host: db.qfpswxjunoepznrpsltt.supabase.co"
    echo "   Port: 5432"
    echo "   Database name: postgres"
    echo "   Username: postgres"
    echo "   Password: e3u2zDnt4mGMJFWA"
    echo "   SSL Mode: require"
    echo ""
    echo "✅ Una vez configurado, tendrás acceso a todas las tablas de tu aplicación timesheet"
    exit 0
fi

# Si ya está configurado, intentar configurar la conexión automáticamente
echo "🔧 Intentando configurar conexión automáticamente..."

# Crear usuario administrador si no existe
echo "👤 Configurando usuario administrador..."
ADMIN_DATA='{
  "first_name": "Admin",
  "last_name": "User",
  "email": "admin@metabase.local",
  "password": "admin123",
  "password_confirm": "admin123"
}'

# Intentar crear el usuario administrador
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$ADMIN_DATA" \
  http://localhost:3000/api/setup > /dev/null || echo "Usuario ya existe o error en creación"

# Obtener token de sesión
echo "🔐 Iniciando sesión..."
LOGIN_DATA='{
  "username": "admin@metabase.local",
  "password": "admin123"
}'

SESSION_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$LOGIN_DATA" \
  http://localhost:3000/api/session)

# Extraer el token de la respuesta
TOKEN=$(echo "$SESSION_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "❌ No se pudo obtener el token de sesión"
    echo "Respuesta: $SESSION_RESPONSE"
    echo ""
    echo "📋 CONFIGURACIÓN MANUAL:"
    echo "1. 🌐 Accede a: http://192.168.88.68:3000"
    echo "2. 👤 Inicia sesión con tu cuenta"
    echo "3. 🗄️ Ve a Settings > Admin > Databases"
    echo "4. ➕ Add database > PostgreSQL"
    echo "5. 📝 Usa los datos de conexión proporcionados arriba"
    exit 1
fi

echo "✅ Token obtenido: ${TOKEN:0:20}..."

# Configurar la conexión a Supabase
echo "🗄️ Configurando conexión a Supabase..."

SUPABASE_CONFIG='{
  "engine": "postgres",
  "name": "Supabase Timesheet",
  "details": {
    "host": "db.qfpswxjunoepznrpsltt.supabase.co",
    "port": 5432,
    "dbname": "postgres",
    "user": "postgres",
    "password": "e3u2zDnt4mGMJFWA",
    "ssl": true,
    "ssl-mode": "require",
    "tunnel-enabled": false,
    "advanced-options": false,
    "retrieve-fields": true
  }
}'

# Probar la conexión
echo "🔍 Probando conexión a Supabase..."
TEST_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-Metabase-Session: $TOKEN" \
  -d "$SUPABASE_CONFIG" \
  http://localhost:3000/api/database/test 2>/dev/null || echo "ERROR")

if echo "$TEST_RESPONSE" | grep -q '"valid":true'; then
    echo "✅ Conexión a Supabase verificada correctamente!"

    # Crear la conexión permanente
    echo "💾 Creando conexión permanente..."
    CREATE_RESPONSE=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "X-Metabase-Session: $TOKEN" \
      -d "$SUPABASE_CONFIG" \
      http://localhost:3000/api/database 2>/dev/null || echo "ERROR")

    if echo "$CREATE_RESPONSE" | grep -q '"id"'; then
        echo "✅ ¡CONEXIÓN A SUPABASE CONFIGURADA EXITOSAMENTE!"
        echo ""
        echo "🌐 Accede a Metabase: http://192.168.88.68:3000"
        echo "👤 Usuario: admin@metabase.local"
        echo "🔑 Contraseña: admin123"
        echo "🗄️ Base de datos: Supabase Timesheet"
        echo ""
        echo "📊 Tablas disponibles:"
        echo "   - job (Proyectos)"
        echo "   - job_task (Tareas)"
        echo "   - timesheet (Líneas de timesheet)"
        echo "   - resource (Recursos/Empleados)"
        echo "   - calendar_period_days (Calendario)"
        echo "   - resource_timesheet_header (Cabeceras)"
        echo ""
        echo "🎉 ¡Ya puedes crear dashboards y consultas con tus datos!"
    else
        echo "❌ Error creando la conexión permanente"
        echo "Respuesta: $CREATE_RESPONSE"
    fi
else
    echo "❌ Error en la conexión a Supabase"
    echo "Respuesta: $TEST_RESPONSE"
fi





