# Troubleshooting: Error DNS "kong" en n8n

## ⚠️ Prevención

**IMPORTANTE**: Este problema se puede prevenir configurando n8n correctamente desde el inicio.

### Checklist de Configuración Inicial

Antes de usar workflows de n8n con Supabase, verifica:

- [ ] n8n está conectado a la red `ps_admin_default`
- [ ] Los servicios systemd están activos (`n8n-network.service` y `n8n-network.timer`)
- [ ] n8n puede resolver el hostname "kong": `docker exec n8n ping -c 1 kong`

### Configuración Automática

Los servicios systemd deberían estar configurados automáticamente. Si no lo están:

```bash
# Instalar servicios
sudo cp scripts/n8n-network.service /etc/systemd/system/
sudo cp scripts/n8n-network.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now n8n-network.service
sudo systemctl enable --now n8n-network.timer
```

---

## Problema

Al ejecutar workflows de n8n que usan Supabase, aparece el error:

```
The DNS server returned an error, perhaps the server is offline
Error code: EAI_AGAIN
Full message: getaddrinfo EAI_AGAIN kong
```

## Causa

El contenedor n8n está en una red Docker diferente a la red donde está Supabase. El workflow intenta conectarse a Supabase usando el hostname "kong" (API Gateway interno de Supabase), pero n8n no puede resolver ese hostname porque no está en la misma red.

- **Red de n8n**: `n8n_n8n_network`
- **Red de Supabase**: `ps_admin_default`
- **Hostname "kong"**: Solo resuelve dentro de la red `ps_admin_default`

## Solución

Conectar el contenedor n8n a la red de Supabase:

```bash
docker network connect ps_admin_default n8n
```

## Verificación

Después de aplicar la solución, verifica que n8n puede resolver "kong":

```bash
# Verificar resolución DNS
docker exec n8n ping -c 1 kong

# Verificar conectividad HTTP
docker exec n8n wget -q -O- --timeout=5 http://kong:8000/rest/v1/ | head -5
```

Si ambos comandos funcionan, el problema está resuelto.

## Solución Permanente

**✅ IMPLEMENTADO**: La solución permanente está configurada usando systemd.

### Servicios Systemd Instalados

1. **n8n-network.service**: Conecta n8n a la red de Supabase al iniciar el sistema
2. **n8n-network.timer**: Verifica y reconecta cada 5 minutos (por si n8n se reinicia)

### Verificar Estado

```bash
# Ver estado del servicio
sudo systemctl status n8n-network.service

# Ver estado del timer
sudo systemctl status n8n-network.timer

# Ver logs
sudo journalctl -u n8n-network.service -f
```

### Scripts Disponibles

- **`scripts/fix-n8n-network.sh`**: Script principal usado por systemd
- **`scripts/ensure-n8n-network.sh`**: Script idempotente que se puede ejecutar manualmente

### Ejecutar Manualmente

Si necesitas reconectar manualmente:

```bash
./scripts/ensure-n8n-network.sh
```

### Alternativas (si no se usa systemd)

#### Opción 1: Agregar a la configuración de Docker

Si n8n se ejecuta con `docker run`, agregar el parámetro:

```bash
docker run ... --network ps_admin_default ...
```

O si usa docker-compose, agregar en el archivo:

```yaml
services:
  n8n:
    networks:
      - n8n_n8n_network  # Red original
      - ps_admin_default  # Red de Supabase
```

#### Opción 2: Cron Job

Agregar a crontab para ejecutar cada 5 minutos:

```bash
*/5 * * * * /home/metabase/scripts/ensure-n8n-network.sh >/dev/null 2>&1
```

## Notas

- Esta solución permite que n8n acceda a Supabase usando el hostname "kong"
- n8n mantiene su red original (`n8n_n8n_network`) y también tiene acceso a `ps_admin_default`
- Si cambias la configuración de red de Supabase, actualiza este documento

## Referencias

- Documentación de Supabase: `docs/SUPABASE_ANON_KEY.md`
- Guía de n8n: `docs/shared/n8n/n8n-integration-guide.md`
