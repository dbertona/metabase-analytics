#!/bin/bash

# Script para crear un endpoint API que exponga los datos de Supabase para Metabase
# Uso: ./scripts/create-api-endpoint.sh

set -e

echo "🔧 Creando endpoint API para Metabase..."

# Crear directorio para el endpoint
mkdir -p /opt/metabase-docker/api

# Crear endpoint que exponga los datos de Supabase
cat > /opt/metabase-docker/api/supabase-api.js << 'EOF'
const express = require('express');
const { createClient } = require('@supabase/supabase-js');

const app = express();
const PORT = 3001;

// Configuración de Supabase
const supabaseUrl = 'https://qfpswxjunoepznrpsltt.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFmcHN3eGp1bm9lcHpucnBzbHR0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1Mzg3MTA3OSwiZXhwIjoyMDY5NDQ3MDc5fQ.PxpfuFsfvpeEPHCEiWhRn0SD1WxngTAEppJ-65QTTOQ';

const supabase = createClient(supabaseUrl, supabaseKey);

// Middleware
app.use(express.json());
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
    next();
});

// Endpoint para obtener datos de jobs
app.get('/api/jobs', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('job')
            .select('*');

        if (error) throw error;
        res.json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para obtener datos de timesheet
app.get('/api/timesheet', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('timesheet')
            .select('*');

        if (error) throw error;
        res.json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para obtener datos de recursos
app.get('/api/resources', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('resource')
            .select('*');

        if (error) throw error;
        res.json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Endpoint para obtener datos de calendario
app.get('/api/calendar', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('calendar_period_days')
            .select('*');

        if (error) throw error;
        res.json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Endpoint de salud
app.get('/health', (req, res) => {
    res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
    console.log(`🚀 API de Supabase ejecutándose en puerto ${PORT}`);
    console.log(`📊 Endpoints disponibles:`);
    console.log(`   - GET /api/jobs`);
    console.log(`   - GET /api/timesheet`);
    console.log(`   - GET /api/resources`);
    console.log(`   - GET /api/calendar`);
    console.log(`   - GET /health`);
});
EOF

# Crear package.json para el endpoint
cat > /opt/metabase-docker/api/package.json << 'EOF'
{
  "name": "supabase-api-endpoint",
  "version": "1.0.0",
  "description": "API endpoint para Metabase con datos de Supabase",
  "main": "supabase-api.js",
  "scripts": {
    "start": "node supabase-api.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "@supabase/supabase-js": "^2.38.0"
  }
}
EOF

# Crear script de inicio
cat > /opt/metabase-docker/scripts/start-api.sh << 'EOF'
#!/bin/bash
cd /opt/metabase-docker/api
npm install
node supabase-api.js
EOF

chmod +x /opt/metabase-docker/scripts/start-api.sh

echo "✅ Endpoint API creado exitosamente!"
echo ""
echo "🚀 Para iniciar el endpoint API:"
echo "   cd /opt/metabase-docker && ./scripts/start-api.sh"
echo ""
echo "📊 Endpoints disponibles:"
echo "   - http://192.168.88.68:3001/api/jobs"
echo "   - http://192.168.88.68:3001/api/timesheet"
echo "   - http://192.168.88.68:3001/api/resources"
echo "   - http://192.168.88.68:3001/api/calendar"
echo ""
echo "🔧 Para conectar en Metabase:"
echo "   1. Ve a Settings > Admin > Databases"
echo "   2. Add database > Other"
echo "   3. URL: http://192.168.88.68:3001/api/timesheet"
echo "   4. O usa 'Generic Database' con los endpoints individuales"





