#!/bin/bash

# Script para configurar Metabase automáticamente
# Uso: ./scripts/setup-metabase.sh

set -e

echo "🚀 Configurando Metabase automáticamente..."

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

echo "🔧 Metabase está funcionando correctamente!"
echo ""
echo "📋 INSTRUCCIONES PARA CONFIGURAR SUPABASE:"
echo ""
echo "1. 🌐 Accede a: http://192.168.88.68:3000"
echo "2. 👤 Crea tu cuenta de administrador"
echo "3. 🗄️ Ve a Settings > Admin > Databases"
echo "4. ➕ Haz clic en 'Add database'"
echo "5. 🐘 Selecciona 'PostgreSQL'"
echo ""
echo "📝 DATOS DE CONEXIÓN A SUPABASE:"
echo "   Name: Supabase Timesheet"
echo "   Host: db.qfpswxjunoepznrpsltt.supabase.co"
echo "   Port: 5432"
echo "   Database name: postgres"
echo "   Username: postgres"
echo "   Password: [OBTENER DESDE SUPABASE DASHBOARD]"
echo "   SSL Mode: require"
echo ""
echo "🔑 PARA OBTENER LA CONTRASEÑA:"
echo "   1. Ve a: https://supabase.com/dashboard"
echo "   2. Selecciona tu proyecto: qfpswxjunoepznrpsltt"
echo "   3. Ve a Settings > Database"
echo "   4. Busca 'Connection string' o 'Database password'"
echo "   5. Copia la contraseña"
echo ""
echo "✅ Una vez configurado, tendrás acceso a todas las tablas de tu aplicación timesheet"





