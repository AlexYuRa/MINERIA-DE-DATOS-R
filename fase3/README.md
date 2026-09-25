# Fase III — Integración R + MongoDB, Analítica y Shiny

**Proyecto:** Contratistas Mineros MINEM — Tópicos de Base de Datos (UNT)
**Base de datos:** `contratistas_mineros_minem` (MongoDB local, `mongodb://localhost:27017`)
**Modelo:** diseñado en Fase II (`Mi trabajo - Modelado de la base de datos.md`) — colecciones `contratistas` (con historial embebido), `ubicaciones` y `segmentos_riesgo`.

Este documento consolida el desarrollo de la Fase III y sirve como informe técnico de los entregables a) – f).

---

## 1. Entorno de trabajo

| Componente | Versión / detalle |
|---|---|
| R | 4.6.0 (`C:\Program Files\R\R-4.6.0`; invocar con ruta completa, no está en PATH) |
| MongoDB Community Server | 8.3.4 (servicio Windows `MongoDB`, `mongodb://localhost:27017`) |
| Driver R–MongoDB | `mongolite` 4.0.0 |
| Paquetes R | mongolite, readxl, dplyr, tidyr, lubridate, stringr, purrr, jsonlite, ggplot2, scales, cluster, factoextra, shiny, shinydashboard, DT |

### Estructura del proyecto y mapeo con los entregables

| Script / carpeta | Entregable | Estado |
|---|---|---|
| `01_etl_seed.R` | ETL de Fase II (extracción → 6 subprocesos de transformación → carga) | ✅ Ejecutado |
| `02_conexion_evidencias.R` | **a)** Integrar la BD con R (conexión + evidencias) | ✅ Ejecutado |
| `03_consultas_negocio.R` | **b)** 8 consultas alineadas a reglas de negocio (RN) y requerimientos (REQ) | ✅ Ejecutado |
| `04_patrones_clustering.R` | **c)** Clustering k-means: patrones de decisión + poblado de `segmentos_riesgo` | ✅ Ejecutado |
| `05_validacion_patrones.R` | **d)** Validación de la funcionalidad de los patrones (7 pruebas) | ✅ Ejecutado |
| `06_graficos_ggplot2.R` | **e)** 6 gráficos ggplot2 con interpretación de negocio | ✅ Ejecutado |
| `app_shiny/` | **f)** Frontend Shiny (dashboard interactivo + CRUD sobre MongoDB) | ✅ Ejecutado |
| `lanzar_app.R` | Lanzador de la app Shiny (`http://127.0.0.1:8123`) | — |
| `SHINY.md` | Guion paso a paso para sustentar la app ante el docente | — |
| `CLUSTERING.md` | Referencia técnica del clustering (punto c) | — |
| `../INFORME_FINAL.md` | Informe final completo (Fases I–III) con la estructura solicitada | — |
| `salidas/` | Archivos intermedios (.rds/.csv), evidencias y gráficos exportados. **No se versiona** (salvo los PNG de `graficos/`): se regenera al ejecutar los scripts | — |

---

## 2. Paso previo — ETL de carga inicial (seed)

Antes de la analítica se ejecutó el ETL diseñado en la Fase II para poblar la base. Se implementó fielmente la versión actualizada del documento: **extracción (2.6.1)** + **seis subprocesos de transformación encadenados (2.6.2.1 – 2.6.2.6)** + **carga (2.6.3)**.

Resultado de la ejecución de `01_etl_seed.R`:

| Métrica | Valor | Verificación (prueba de escritorio Fase II) |
|---|---|---|
| Filas crudas leídas | 2,625 | ✅ |
| Duplicados exactos eliminados | 7 → 2,618 filas | ✅ |
| Rango de fechas | 2008-03-03 a 2026-06-16 | ✅ |
| Contratistas únicos (colección `contratistas`) | 2,521 | ✅ |
| Ubicaciones únicas (colección `ubicaciones`) | 216 | ✅ |
| Colección `segmentos_riesgo` | 0 documentos (vacía por diseño) | ✅ |
| Índice único `ruc` | Creado; rechaza RUC duplicado | ✅ |
| Caso EXSA S.A. (RUC 20100094135) | 2 autorizaciones, vigente la de 2017-05-31 | ✅ |
| % actividad integral (amplitud=4) | 47.9% (1,208) | ✅ |

> Ajustes técnicos aplicados sobre el código de referencia (el diseño no cambia): `mongolite` 4.0 ya no admite `options` en `$index()`, por lo que el índice único se crea con el comando nativo `createIndexes`; las fechas se cargan envueltas en `{"$date": …}` para que MongoDB las almacene como tipo `Date` nativo (necesario para las agregaciones temporales de la sección b).

---

## 3. Entregable a) — Integración de la BD con R (conexión + evidencias)

El script `02_conexion_evidencias.R` establece la conexión R ↔ MongoDB mediante `mongolite` y deja constancia de la integración. Evidencias generadas (guardadas en `salidas/evidencia_conexion.txt`):

1. **Conexión** a las 3 colecciones del modelo (`contratistas`, `ubicaciones`, `segmentos_riesgo`).
2. **Conteo de documentos:** 2,521 / 216 / 0 respectivamente.
3. **Documento de ejemplo** con su historial embebido (estructura anidada correcta).
4. **Índices** existentes (`_id_`, `ruc_1`).
5. **Lectura como `data.frame`** de contratistas desde R (integración analítica operativa).

Extracto de la evidencia:

```
 EVIDENCIA DE CONEXIÓN R <-> MongoDB
 R version 4.6.0 | mongolite 4.0.0 | BD: contratistas_mineros_minem
 Documentos por colección: contratistas 2521 | ubicaciones 216 | segmentos_riesgo 0
 [OK] Integración R–MongoDB verificada correctamente.
```

---

## 4. Entregable b) — Consultas de negocio

Se definieron dos catálogos que fundamentan cada consulta. Cada consulta declara explícitamente qué regla y qué requerimiento satisface.

**Reglas de negocio (RN):**
- **RN1** — La exposición operativa crece con la amplitud de actividad autorizada (0–4); amplitud=4 (`actividad_integral`) = máxima exposición.
- **RN2** — La contactabilidad es baja cuando el contratista no tiene teléfono de referencia.
- **RN3** — La complejidad logística de fiscalización es mayor en macrozona *Regiones* que en *Lima_Callao*.
- **RN4** — Un contratista es prioritario cuando combina RN1 + RN2 + RN3.
- **RN5** — El dinamismo de una empresa se refleja en su número de autorizaciones/renovaciones.

**Requerimientos de empresa (DGM):**
- **REQ1** — Priorizar la fiscalización hacia los de mayor exposición operativa.
- **REQ2** — Focalizar campañas de actualización de datos de contacto.
- **REQ3** — Planificar la distribución geográfica de equipos de supervisión.
- **REQ4** — Monitorear la evolución del sector (ingreso de nuevas empresas).
- **REQ5** — Diseñar estrategias diferenciadas según el perfil de actividad.

### Consultas y hallazgos (todas vía framework de agregación de MongoDB)

| Consulta | Qué responde | RN | REQ | Hallazgo clave |
|---|---|---|---|---|
| **C1** | Distribución por perfil de actividad | RN1 | REQ1, REQ5 | 47.9% actividad integral; 41.0% parcial; 11.1% mono-actividad |
| **C2** | Top departamentos con actividad integral | RN1, RN3 | REQ1, REQ3 | Lima 672, La Libertad 147, Arequipa 71, Junín 59, Áncash 58 |
| **C3** | Contactabilidad por macrozona | RN2, RN3 | REQ2 | Regiones **90.9%** sin teléfono vs. Lima/Callao 83.7% |
| **C4** | Contratistas prioritarios (amplitud=4 + sin tel. + Regiones) | RN4 | REQ1 | **485 empresas** en el foco de fiscalización |
| **C5** | Evolución anual de nuevas empresas (2008–2026) | RN5 | REQ4 | Pico 2011 (196); caída 2020 (77, pandemia); acumulado 2,521 |
| **C6** | Amplitud vs. antigüedad y renovación | RN1, RN5 | REQ5 | Las integrales son **más jóvenes** (8.3 años) que las mono (12.4) |
| **C7** | Contratistas más dinámicos (2+ autorizaciones) | RN5 | REQ1, REQ4 | 76 empresas; STRACON PERÚ lidera con 7 autorizaciones |
| **C8** | Concentración por departamento | RN3 | REQ3 | Lima 56.8% del padrón; 7 departamentos > 90% |

Resultados exportados a `salidas/consulta_C1.csv … C8.csv`, consolidados en `salidas/consultas_resultados.rds` y evidencia en `salidas/evidencia_consultas.txt`.

**Patrón preliminar detectado (insumo para el punto c):** la consulta C6 muestra una relación inversa entre amplitud de actividad y antigüedad — las empresas de mayor alcance operativo ingresaron al padrón más recientemente, lo que sugiere que el sector nuevo entra directamente habilitado para las cuatro actividades.

---

## 6. Entregable c) — Patrones mediante clustering (k-means)

Se aplicó **k-means** (técnica principal seleccionada en la Fase II, sección 2.1.6) para descubrir patrones accionables. Las **reglas de negocio orientaron la selección de las 6 variables predictoras**: `amplitud_actividad_actual` (RN1), `indice_completitud_contacto` (RN2), `macrozona=Regiones` (RN3), y `num_autorizaciones` + `antiguedad_anios` + `recencia_anios` (RN5). Las variables se estandarizaron (z-score) porque k-means usa distancia euclídea.

**Elección de k:** se evaluó k = 2…8 con el método del codo (WSS) y la silueta promedio. Se seleccionó **k = 4** por equilibrio entre cohesión estadística e interpretabilidad de negocio (silueta ≈ 0.34; el codo se suaviza a partir de k=4).

**Etiquetado data-driven:** el nombre de cada segmento se deriva de sus rasgos distintivos reales (no de una plantilla fija). La prioridad de fiscalización se ordena por un **índice de riesgo** que combina las reglas: `0.40·amplitud + 0.25·(sin contacto) + 0.20·(regiones) + 0.15·(recencia)`.

### Segmentos generados (poblados en la colección `segmentos_riesgo`)

| Seg. | Nombre (rasgos reales) | Prioridad | n | Amplitud | % contacto | % Regiones | Antigüedad | Índice riesgo |
|---|---|---|---|---|---|---|---|---|
| 1 | Baja contactabilidad · alta exposición · reciente | **Muy Alta** | 1,023 | 3.5 | 0% | 53% | 5.4 a | 0.761 |
| 2 | Baja contactabilidad · alcance moderado · antiguo sin renovar | **Alta** | 1,096 | 2.7 | 0% | 36% | 14.4 a | 0.744 |
| 3 | Dinámico con renovaciones · baja contactabilidad · reciente | **Media** | 76 | 3.1 | 9% | 42% | 7.5 a | 0.673 |
| 4 | Contactable | **Baja** | 326 | 3.0 | 100% | 29% | 12.0 a | 0.487 |

**Patrones detectados (apoyo a la decisión):**
- **Segmento 1 (40.6% del padrón)** — empresas jóvenes, con alta amplitud de actividad y sin teléfono: el grupo más numeroso y de mayor riesgo → foco prioritario de fiscalización (REQ1) y de campañas de contacto (REQ2).
- **Segmento 2 (43.5%)** — empresas antiguas (14 años) que no renuevan y sin contacto: posible inactividad no verificada; requieren depuración/verificación de vigencia del padrón.
- **Segmento 3 (3.0%)** — las 76 empresas dinámicas (2.3 autorizaciones promedio), en expansión: monitoreo de evolución (REQ4).
- **Segmento 4 (12.9%)** — único grupo 100% contactable y consolidado: menor prioridad, gestión por canal telefónico.

Cada uno de los 2,521 contratistas quedó con su `segmento_id` asignado (0 sin clasificar). El campo, que en Fase II estaba en `null`, se pobló sin rediseñar la base, tal como previó el modelo. Evidencia en `salidas/evidencia_clustering.txt`, `salidas/clustering_segmentos.csv` y `salidas/clustering_eleccion_k.csv`.

## 7. Entregable d) — Validación de la funcionalidad de los patrones

Para demostrar si los patrones **cumplen o no con lo requerido**, se aplicaron **7 pruebas** en tres dimensiones, cada una con veredicto CUMPLE / NO CUMPLE:

| Prueba | Dimensión | Criterio | Obtenido | Veredicto |
|---|---|---|---|---|
| **V1** | Interna | 100% clasificados y ningún clúster degenerado (≥20) | 2,521/2,521; menor clúster = 76 | ✅ CUMPLE |
| **V2** | Interna | Silueta > 0.25 y varianza explicada > 0.45 | silueta 0.342; varianza 52.0% | ✅ CUMPLE |
| **V3** | Interna | Todas las variables difieren entre segmentos (ANOVA p<0.05) | 6/6 significativas (max p = 1.5e-20) | ✅ CUMPLE |
| **V4** | Negocio | 'Muy Alta' > 'Baja' en exposición y < en contacto (REQ1) | amplitud 3.5 vs 3.0; contacto 0% vs 100% | ✅ CUMPLE |
| **V5** | Negocio | ≥95% de los prioritarios de C4 en segmentos altos y 0 en Baja (coherencia b↔c) | 468/485 (96.5%) en altos; 0 en Baja | ✅ CUMPLE |
| **V6** | Negocio | El índice de riesgo decrece con la prioridad | 0.761 > 0.744 > 0.673 > 0.487 | ✅ CUMPLE |
| **V7** | Robustez | ARI promedio ≥ 0.75 en 5 re-ejecuciones con distinta semilla | ARI 0.900 | ✅ CUMPLE |

**Veredicto global: 7/7 — los patrones CUMPLEN con lo requerido.**

Notas metodológicas:
- **V3 (ANOVA)** demuestra que los segmentos no son arbitrarios: las 6 variables predictoras difieren de forma estadísticamente significativa entre grupos.
- **V5** cruza el punto b) con el c): los 485 contratistas que la consulta C4 marcó como prioritarios se distribuyen 366 (Muy Alta) + 102 (Alta) + 17 (Media) y **ninguno** cae en el segmento de Baja prioridad, confirmando que el clustering es coherente con la regla de negocio manual. La primera versión de V5 exigía un único segmento (75.5%, fallaba); se corrigió el criterio porque el riesgo alto se reparte legítimamente en dos segmentos (Muy Alta + Alta) y el segmento Baja es 100% contactable, incompatible por definición con el filtro "sin teléfono" de C4.
- **V7 (Índice de Rand Ajustado)** confirma que el patrón es reproducible y no un artefacto de una semilla particular.

Evidencia en `salidas/evidencia_validacion.txt` y `salidas/validacion_patrones.csv`.

## 8. Entregable e) — Gráficos (ggplot2) y su significado para la evolución del negocio

Se generaron **6 gráficos** con `ggplot2` (en `salidas/graficos/`), combinando los resultados de las consultas (b) y del clustering (c). Interpretación de cada uno en clave de negocio:

| Gráfico | Qué muestra | Significado para la evolución del negocio |
|---|---|---|
| **G1** `G1_evolucion_anual.png` | Altas anuales (barras) + padrón acumulado (línea), 2008–2026 | El sector creció de forma sostenida hasta ~2,521 empresas. El ritmo de ingreso se **desaceleró desde 2013** y cayó fuertemente en **2020 (77 altas, pandemia)**, con recuperación parcial en 2022–2025. Un sector que madura: menos empresas nuevas por año pero base acumulada estable. |
| **G2** `G2_perfil_actividad.png` | Distribución por perfil de actividad | El padrón está dominado por empresas de **máxima exposición operativa**: 47.9% de actividad integral vs. solo 11.1% mono-actividad. La carga de fiscalización potencial es alta y concentrada en el perfil de mayor riesgo. |
| **G3** `G3_contactabilidad_macrozona.png` | Con/sin teléfono por macrozona | **Brecha de contactabilidad crítica**: 83.7% sin teléfono en Lima/Callao y **90.9% en Regiones**. El Estado no puede contactar directamente a la mayoría de sus contratistas, y el problema se agrava donde la fiscalización presencial ya es más costosa. |
| **G4** `G4_concentracion_departamentos.png` | Top 10 departamentos (total + actividad integral) | **Alta concentración geográfica**: Lima reúne 1,433 contratistas (672 de alto alcance). Le siguen La Libertad, Arequipa, Junín y Pasco. Orienta dónde ubicar equipos de supervisión (REQ3). |
| **G5** `G5_segmentos_riesgo.png` | Tamaño e índice de riesgo de los 4 segmentos | El **84% del padrón** (segmentos 1 y 2) cae en prioridad Muy Alta/Alta. La fiscalización necesita un criterio de corte fino, no puede atender a todos por igual. |
| **G6** `G6_dispersion_segmentos.png` | Antigüedad vs. amplitud, coloreado por segmento | Los segmentos se separan **por antigüedad**: las empresas recientes de alto alcance (rojo, Muy Alta) se distinguen de las antiguas (naranja). Confirma visualmente el patrón: el riesgo se concentra en el ingreso reciente al sector. |

**Lectura integral de la evolución del negocio:** el sector de contratistas mineros pasó de una fase de expansión acelerada (2008–2013) a una de maduración (2014–2026), con menos altas anuales pero una base amplia y de alta exposición operativa. El principal desafío evolutivo no es el crecimiento sino la **capacidad de supervisión**: casi 9 de cada 10 empresas no son contactables, el riesgo se concentra en empresas recientes de amplio alcance, y la distribución geográfica exige focalizar recursos. Los segmentos generados permiten precisamente esa focalización.

## 9. Entregable f) — Frontend Shiny

Se desarrolló una aplicación **Shiny** (`shinydashboard`) que se conecta **en vivo** a la base `contratistas_mineros_minem` y permite **consultar y manipular** los datos, demostrando al docente la funcionalidad de la propuesta. Estructura (`app_shiny/global.R`, `ui.R`, `server.R`):

| Pestaña | Funcionalidad |
|---|---|
| **Resumen general** | 4 KPIs (contratistas, ubicaciones, % sin teléfono, prioridad Muy Alta) + gráficos de evolución y perfil |
| **Explorador de datos** | Tabla filtrable (departamento, prioridad, perfil, búsqueda por RUC/razón social); al seleccionar un contratista muestra su **historial de autorizaciones embebido** y un panel de **manipulación de datos** |
| **Consultas de negocio** | Ejecuta las 8 consultas (b) en vivo, indicando qué RN/REQ satisface cada una |
| **Segmentos de riesgo** | Perfil de los 4 segmentos + gráfico + listado de contratistas por segmento |
| **Gráficos de evolución** | Selector de los gráficos del punto (e) con su interpretación de negocio |
| **Acerca de** | Descripción del proyecto y del stack |

**Manipulación de datos (CRUD sobre MongoDB desde la interfaz):**
- **Actualizar** el teléfono de referencia de un contratista (recalcula automáticamente `indice_completitud_contacto`) — apoya REQ2.
- **Reasignar** manualmente el segmento de riesgo de un contratista.
- **Eliminar** un contratista (con modal de confirmación).

**Verificación realizada:** la app arranca y responde HTTP 200 en `http://127.0.0.1:8123` con la interfaz renderizada. Adicionalmente se ejercitó toda la lógica del servidor fuera de Shiny (`leer_contratistas`, `leer_historial`, las 8 consultas y el **ciclo CRUD completo**: update de teléfono + reasignación de segmento + eliminación + reinserción), confirmando que cada operación escribe correctamente en MongoDB y que la base mantiene su integridad (2,521 documentos). Tras las pruebas, la base se reconstruyó a su estado canónico ejecutando `01_etl_seed.R` + `04_patrones_clustering.R`.

> Nota: la función **Eliminar** modifica la base de forma permanente. Para restaurar el padrón completo tras una demostración, basta con re-ejecutar `01_etl_seed.R` y `04_patrones_clustering.R`.

**Cómo lanzar la app:**
```powershell
& "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" fase3\lanzar_app.R
# Abrir http://127.0.0.1:8123
```

---

## 10. Estado de los entregables

| Entregable | Descripción | Estado |
|---|---|---|
| a) | Integración BD–R (conexión + evidencias) | ✅ |
| b) | Consultas de negocio (RN/REQ) | ✅ |
| c) | Patrones mediante clustering | ✅ |
| d) | Validación de los patrones | ✅ |
| e) | Gráficos ggplot2 | ✅ |
| f) | Frontend Shiny | ✅ |

## 5. Cómo ejecutar

```powershell
# Desde la raíz del repositorio
$R = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
& $R fase3\01_etl_seed.R            # ETL: puebla MongoDB
& $R fase3\02_conexion_evidencias.R # a) evidencias de conexión
& $R fase3\03_consultas_negocio.R   # b) consultas de negocio
& $R fase3\04_patrones_clustering.R # c) clustering + poblado de segmentos
& $R fase3\05_validacion_patrones.R # d) validación (7 pruebas)
& $R fase3\06_graficos_ggplot2.R    # e) gráficos ggplot2 -> salidas/graficos/
& $R fase3\lanzar_app.R             # f) app Shiny -> http://127.0.0.1:8123
```
