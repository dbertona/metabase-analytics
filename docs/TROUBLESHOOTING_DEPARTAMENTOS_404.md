# Troubleshooting: Error 404 en Endpoint Departamentos

## Problema

El workflow 004 está intentando acceder a `/Departamentos` pero Business Central devuelve 404:

```
No HTTP resource was found that matches the request URI
'.../companies(...)/Departamentos?...'
```

## Causas Posibles

### 1. Query no publicado en Business Central

El query `PS_Departamentos` (ID 7000104) puede no estar publicado o activo en BC.

**Solución:**
1. Abrir Business Central
2. Ir a **API Management** o **Web Services**
3. Buscar el query `PS_Departamentos` (ID 7000104)
4. Verificar que esté:
   - ✅ Publicado
   - ✅ Activo
   - ✅ EntitySetName = `Departamentos`
   - ✅ EntityName = `Departamentos`

### 2. Nombre del endpoint incorrecto

El `EntitySetName` en el query puede ser diferente a `Departamentos`.

**Verificación:**
- Revisar el query en BC y confirmar el `EntitySetName` exacto
- Puede ser que necesite ser `PS_Departamentos` en lugar de `Departamentos`

### 3. Query no compilado o con errores

El query puede tener errores de compilación.

**Solución:**
1. Abrir el query en BC
2. Compilar y verificar que no haya errores
3. Publicar nuevamente

## Verificación del Endpoint

### Probar el endpoint directamente

```bash
# Obtener token OAuth2 primero, luego:
curl -X GET \
  "https://api.businesscentral.dynamics.com/v2.0/a18dc497-a8b8-4740-b723-65362ab7a3fb/Pruebas_PS/api/Power_Solution/PS_API/v2.0/companies(COMPANY_ID)/Departamentos" \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json"
```

### Verificar endpoints disponibles

Listar todos los endpoints disponibles para ver si existe con otro nombre:

```bash
curl -X GET \
  "https://api.businesscentral.dynamics.com/v2.0/a18dc497-a8b8-4740-b723-65362ab7a3fb/Pruebas_PS/api/Power_Solution/PS_API/v2.0/" \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" | \
  jq '.value[] | select(.name | contains("Depart") or contains("Dpto"))'
```

## Soluciones Alternativas

### Opción 1: Verificar y corregir el nombre del endpoint

Si el `EntitySetName` es diferente, actualizar el workflow:

```json
// Cambiar de:
')/Departamentos?$select=...

// A (si el EntitySetName es diferente):
')/PS_Departamentos?$select=...
// O
')/DimensionValues?$filter=dimensionCode eq 'DPTO'&$select=...
```

### Opción 2: Usar endpoint genérico de Dimension Values

Si el query no está disponible, podríamos usar el endpoint genérico de Dimension Values con filtro:

```
/DimensionValues?$filter=dimensionCode eq 'DPTO'&$select=code,name,lastModifiedDateTime
```

### Opción 3: Verificar publicación del query

1. En BC, ir a **API Management**
2. Buscar query ID `7000104` o nombre `PS_Departamentos`
3. Verificar configuración:
   - Object Type: Query
   - Object ID: 7000104
   - Service Name: PS_API
   - Published: ✅ Sí

## Próximos Pasos

1. **Verificar en BC** que el query esté publicado
2. **Probar el endpoint** directamente con curl/Postman
3. **Si el nombre es diferente**, actualizar el workflow
4. **Si no existe**, considerar usar DimensionValues con filtro

## Nota

El query que proporcionaste tiene:
- `EntityName = 'Departamentos'`
- `EntitySetName = 'Departamentos'`

Esto debería crear el endpoint `/Departamentos`, pero el 404 sugiere que:
- El query no está publicado
- El query tiene errores
- El nombre del endpoint es diferente en la práctica

