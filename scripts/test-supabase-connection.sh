#!/bin/bash

# Script para probar la conexión a Supabase
# Uso: ./scripts/test-supabase-connection.sh

echo "🔍 PROBANDO CONEXIÓN A SUPABASE"
echo "================================"
echo ""

# Verificar conectividad básica
echo "1. 📡 Conectividad básica..."
if docker compose exec metabase ping -c 2 db.qfpswxjunoepznrpsltt.supabase.co > /dev/null 2>&1; then
    echo "   ✅ Ping exitoso"
else
    echo "   ❌ Ping fallido"
    exit 1
fi

# Verificar puerto 5432
echo "2. 🔌 Puerto 5432..."
if timeout 10 docker compose exec metabase nc -zv db.qfpswxjunoepznrpsltt.supabase.co 5432 > /dev/null 2>&1; then
    echo "   ✅ Puerto 5432 accesible"
else
    echo "   ❌ Puerto 5432 no accesible"
    echo "   💡 Necesitas agregar la IP 213.4.20.44 a Supabase"
fi

# Verificar SSL
echo "3. 🔒 Conexión SSL..."
if timeout 10 docker compose exec metabase openssl s_client -connect db.qfpswxjunoepznrpsltt.supabase.co:5432 -starttls postgres > /dev/null 2>&1; then
    echo "   ✅ SSL funcionando"
else
    echo "   ❌ SSL no funcionando"
fi

echo ""
echo "📋 PRÓXIMOS PASOS:"
echo "1. Ve a: https://supabase.com/dashboard"
echo "2. Proyecto: qfpswxjunoepznrpsltt"
echo "3. Settings > Database"
echo "4. Agrega IP: 213.4.20.44"
echo "5. Ejecuta este script de nuevo"





