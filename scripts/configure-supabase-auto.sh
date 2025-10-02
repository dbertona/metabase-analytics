#!/bin/bash

# Script para configurar automáticamente la conexión a Supabase en Metabase
# Uso: ./scripts/configure-supabase-auto.sh

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

# Configurar la conexión a Supabase
echo "🗄️ Configurando conexión a Supabase..."

# Datos de conexión a Supabase
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

# Probar la conexión primero
echo "🔍 Probando conexión a Supabase..."
TEST_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$SUPABASE_CONFIG" \
  http://localhost:3000/api/database/test 2>/dev/null || echo "ERROR")

if echo "$TEST_RESPONSE" | grep -q '"valid":true'; then
    echo "✅ Conexión a Supabase verificada correctamente!"

    # Crear la conexión permanente
    echo "💾 Creando conexión permanente..."
    CREATE_RESPONSE=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -d "$SUPABASE_CONFIG" \
      http://localhost:3000/api/database 2>/dev/null || echo "ERROR")

    if echo "$CREATE_RESPONSE" | grep -q '"id"'; then
        echo "✅ ¡CONEXIÓN A SUPABASE CONFIGURADA EXITOSAMENTE!"
        echo ""
        echo "🌐 Accede a Metabase: http://192.168.88.68:3000"
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
elif echo "$TEST_RESPONSE" | grep -q '"valid":false'; then
    echo "❌ Contraseña incorrecta o problema de conectividad"
    echo "Respuesta: $TEST_RESPONSE"
else
    echo "⚠️ Error probando la conexión"
    echo "Respuesta: $TEST_RESPONSE"
fi





