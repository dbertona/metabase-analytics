#!/bin/bash

# Script para configurar automáticamente la conexión a Supabase en Metabase
# Uso: ./scripts/configure-supabase.sh

set -e

echo "🔧 Configurando conexión a Supabase en Metabase..."

# Esperar a que Metabase esté completamente iniciado
echo "⏳ Esperando a que Metabase esté listo..."
sleep 30

# Verificar que Metabase esté funcionando
echo "🔍 Verificando estado de Metabase..."
if ! curl -s http://localhost:3000/api/health > /dev/null; then
    echo "❌ Metabase no está respondiendo. Esperando más tiempo..."
    sleep 30
fi

# Obtener el token de sesión (esto requiere que Metabase esté configurado)
echo "🔑 Obteniendo token de sesión..."

# Crear usuario administrador si no existe
echo "👤 Creando usuario administrador..."
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
    exit 1
fi

echo "✅ Token obtenido: ${TOKEN:0:20}..."

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
    "password": "your-supabase-password-here",
    "ssl": true,
    "ssl-mode": "require",
    "tunnel-enabled": false,
    "advanced-options": false,
    "retrieve-fields": true
  }
}'

# Crear la conexión a la base de datos
echo "📡 Enviando configuración a Metabase..."
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-Metabase-Session: $TOKEN" \
  -d "$SUPABASE_CONFIG" \
  http://localhost:3000/api/database)

echo "📋 Respuesta de Metabase:"
echo "$RESPONSE"

# Verificar si la conexión fue exitosa
if echo "$RESPONSE" | grep -q '"id"'; then
    echo "✅ Conexión a Supabase configurada exitosamente!"
    echo "🌐 Accede a Metabase: http://192.168.88.68:3000"
    echo "👤 Usuario: admin@metabase.local"
    echo "🔑 Contraseña: admin123"
else
    echo "❌ Error configurando la conexión:"
    echo "$RESPONSE"
fi





