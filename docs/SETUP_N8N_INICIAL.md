# Configuración Inicial de n8n

Esta guía documenta los pasos obligatorios para configurar n8n correctamente antes de usar workflows que interactúan con Supabase.

---

## ✅ Checklist de Configuración Inicial

### 1. Conectar n8n a la Red de Supabase

**🔴 CRÍTICO**: n8n debe estar conectado a la red de Supabase para poder resolver el hostname "kong".

#### Verificación

```bash
# Verificar si n8n puede resolver "kong"
docker exec n8n ping -c 1 kong
```

Si el comando falla, ejecutar:

```bash
# Solución automática (recomendada)
./scripts/ensure-n8n-network.sh

# O manualmente
docker network connect ps_admin_default n8n
```

#### Configuración Permanente con Systemd

Solo necesario en hosts donde corre el contenedor Docker **`n8n`** (p. ej. VM con n8n local).
En **VM 100 (Analytics/Superset)** el sync n8n está en **VM 101** — el servicio se omite sin error si no hay `n8n`.

```bash
# Verificar que los servicios estén activos
sudo systemctl status n8n-network.service
sudo systemctl status n8n-network.timer

# Si no están activos, instalarlos:
sudo cp scripts/n8n-network.service /etc/systemd/system/
sudo cp scripts/n8n-network.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now n8n-network.service
sudo systemctl enable --now n8n-network.timer
```

**📚 Documentación completa**: `docs/TROUBLESHOOTING_N8N_KONG_DNS.md`

---

### 2. Configurar Credenciales en n8n

#### Credencial de Supabase

1. Acceder a n8n: `http://localhost:5678` o `http://192.168.36.100:5678`
2. Ir a **Settings** → **Credentials**
3. Crear credencial **Supabase**:
   - **Name**: `Supabase Analytics`
   - **Host**: `kong` (o `localhost:8000` si no está en la red)
   - **Service Role Key**: Ver `docs/SUPABASE_ANON_KEY.md`

#### Credencial de PostgreSQL (Opcional)

Si usas el nodo Postgres directamente:

1. Crear credencial **Postgres**:
   - **Name**: `Postgres Supabase`
   - **Host**: `localhost`
   - **Port**: `5433`
   - **Database**: `postgres`
   - **User**: `postgres`
   - **Password**: Ver `docs/CREDENCIALES_POSTGRES_SUPABASE.md`

**📚 Documentación completa**: `docs/CREDENCIALES_POSTGRES_SUPABASE.md`

---

### 3. Verificar Conectividad

Después de configurar, verifica que todo funciona:

```bash
# Verificar resolución DNS de "kong"
docker exec n8n ping -c 1 kong

# Verificar conectividad HTTP a Supabase
docker exec n8n wget -q -O- --timeout=5 http://kong:8000/rest/v1/ | head -5

# Verificar que los servicios systemd están activos
sudo systemctl status n8n-network.service
sudo systemctl status n8n-network.timer
```

---

## 🔄 Después de Reiniciar n8n

Si reinicias el contenedor n8n, verifica que la conexión se mantiene:

```bash
# Verificar conexión
docker exec n8n ping -c 1 kong

# Si falla, reconectar
./scripts/ensure-n8n-network.sh
```

Los servicios systemd deberían reconectar automáticamente, pero si hay problemas, ejecuta el script manualmente.

---

## 📚 Referencias

- **Troubleshooting DNS kong**: `docs/TROUBLESHOOTING_N8N_KONG_DNS.md`
- **Guía de integración n8n**: `docs/shared/n8n/n8n-integration-guide.md`
- **Credenciales Supabase**: `docs/SUPABASE_ANON_KEY.md`
- **Credenciales PostgreSQL**: `docs/CREDENCIALES_POSTGRES_SUPABASE.md`

---

## ⚠️ Problemas Comunes

### Error: "getaddrinfo EAI_AGAIN kong"

**Causa**: n8n no está conectado a la red de Supabase.

**Solución**: Ver sección "1. Conectar n8n a la Red de Supabase" arriba.

### Error: "Credentials not found"

**Causa**: Las credenciales no están configuradas en n8n.

**Solución**: Ver sección "2. Configurar Credenciales en n8n" arriba.

### Los servicios systemd no están activos

**Solución**:

```bash
sudo systemctl enable --now n8n-network.service
sudo systemctl enable --now n8n-network.timer
```

---

## ✅ Verificación Final

Antes de usar workflows de n8n con Supabase, asegúrate de:

- [ ] n8n puede resolver "kong": `docker exec n8n ping -c 1 kong`
- [ ] Los servicios systemd están activos
- [ ] Las credenciales están configuradas en n8n
- [ ] Puedes acceder a la UI de n8n

Si todos los checks pasan, estás listo para usar workflows de n8n con Supabase.
