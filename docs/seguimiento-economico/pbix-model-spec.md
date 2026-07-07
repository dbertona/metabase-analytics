# Spec del modelo — Seguimiento Económico PS

Extraído del `.pbix` (backup XPress9 + pbixray). Dataset cloud ID: `bd3dc81a-3bd3-4699-8fc6-f039c79c1821`.

## Tabla central: Facturacion

```powerquery
Facturacion = Table.Combine({
  Lineas PLanificacion,   -- planificacionMes, Tipo "P"
  Lineas Proyectos,       -- movimientosProyectosMes, Tipo "R"
  Lineas Expedientes,     -- expedienteMes, Tipo "P"
  Meses Cerrados          -- mesesCerrados, Tipo "R"
})
```

### Transformaciones comunes (Power Query → SQL)

| Campo PBI | Lógica |
|-----------|--------|
| `Facturado` | `probability = 0 → invoice` else `invoice * probability / 100` |
| `%` | `probability = 0 → 100` else `probability` |
| `Coste` | `probability = 0 → cost` else `cost * probability / 100` |
| `Cantidad` | Igual que Coste sobre `quantity` |
| `CodigoUnicoDepartamento` | `Empresa & ":" & departamento` |
| `EmpresaAño` | `Empresa & ":" & year` |
| `EmpresaRecurso` | `Empresa & ":" & nr` |
| `FachaCalculada` | `date(1, month, year)` |
| `Encabezado` | `job & " --- " & left(descripcion, 36)` |
| `Facturacion_NoCero` | `IF Facturado <> 0 THEN Facturado` |
| `MesTex` | `FORMAT(month, "00")` |
| `AñoMes` | `MesTex & "/" & year` |

### Filtros por origen

**Lineas PLanificacion:** `estado IN (Open, Planning)`; filtro budget: `year < budget_year OR (year = budget_year AND month <= budget_month)`; `Tipo = P`.

**Lineas Proyectos:** excluir Kilometraje y Resource en facturación; `Invoice = -InvoiceSinKilometros`; `Tipo = R`.

**Lineas Expedientes:** excluir status Completed/Lost; `Tipo = P`.

**Meses Cerrados:** solo meses `Close`; enriquecido con datos de Proyectos; `cost = 0`.

## Medidas DAX (26)

| Tabla | Medida | SQL equivalente |
|-------|--------|-----------------|
| Facturacion | Margen% | `(SUM(facturado)-SUM(coste))/NULLIF(SUM(facturado),0)` |
| Facturacion | Margen€ | `SUM(facturado)-SUM(coste)` |
| Facturacion | TotalVenta | `SUM(facturado)` |
| Facturacion | TotalGasto | `SUM(coste)` |
| Facturacion | AcumuladaVenta | YTD sobre `FachaCalculada` |
| Facturacion | AcumuladoGasto | YTD coste |
| Facturacion | AcumuladoMargen% | `(AcumuladaVenta-AcumuladoGasto)/AcumuladaVenta` |
| Facturacion | AcumuladoMargen€ | `AcumuladaVenta - AcumuladoGasto` |
| Facturacion | CrecimientoFacturacion% | YoY sobre `Facturacion_NoCero` |
| Facturacion | CrecimientoObjetivo% | Objetivos billingTarget vs facturación año anterior |
| Objetivos | MArgenReal% | `(billingTarget-costTarget)/billingTarget` |
| Objetivos | Beneficio€ | `billingTarget - costTarget` |
| HistoricoPlanificacion | Margen%Historico | Igual que Margen% sobre invoice/cost |
| FacturacionRecursos | HorasPlanificadasfiltradas | SUM Cantidad filtrado por departamento recurso |

## Relaciones clave

- `Facturacion[CodigoUnicoDepartamento]` → `Departamentos[CodigoUnicoDepartamento]`
- `Facturacion[EmpresaAño]` → `Años[EmpresaAño]`
- `Facturacion[Empresa]` → `Empresas[Display_Name]`
- `Facturacion[job]` ↔ `Proyectos[Codigo]` (M:M)

## Empresas incluidas

Power Query filtra: `Power Lab Iberia`, `Power Solution Iberia` (Display_Name: PS LAB CONSULTING SL, Power Solution Iberia SL).
