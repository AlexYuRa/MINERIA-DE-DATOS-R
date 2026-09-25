# Cómo funciona el clustering en este proyecto

Documento de referencia técnica sobre el punto c) de Fase III: el agrupamiento de contratistas en segmentos de riesgo mediante k-means. Explica qué hace, cómo lo hace, y cómo se valida y se mantiene reproducible.

Archivos involucrados:
- `fase3/04_patrones_clustering.R` — script original que genera el clustering (fuente de verdad).
- `fase3/05_validacion_patrones.R` — las 7 pruebas de validación.
- `fase3/app_shiny/global.R` (función `recalcular_grupos()`) — réplica del mismo proceso, invocable desde la app.

---

## 1. Qué problema resuelve

La DGM tiene 2,521 contratistas autorizados y una capacidad de fiscalización limitada. No puede inspeccionar a todos con la misma frecuencia. El clustering responde a: **¿cómo agrupar a las empresas en perfiles de riesgo, sin tener una etiqueta previa de "riesgo real", para poder priorizar la fiscalización?**

Es un problema de **aprendizaje no supervisado**: no existe una columna "riesgo correcto" en el dataset contra la cual entrenar un modelo. Se usa clustering (k-means) para descubrir agrupamientos naturales en los datos, y luego se traduce ese agrupamiento a un criterio de negocio (prioridad de fiscalización).

---

## 2. Las 6 variables de entrada

El clustering no usa todas las columnas del contratista — usa 6, cada una ligada explícitamente a una regla de negocio (RN):

| Variable | Regla de negocio | Qué mide |
|---|---|---|
| `amplitud_actividad_actual` | RN1 (exposición operativa) | Cuántas de las 4 actividades mineras tiene autorizadas (0–4) |
| `num_autorizaciones` | RN5 (dinamismo) | Cuántas veces ha renovado/ampliado su autorización |
| `antiguedad_anios` | RN5 (trayectoria) | Años desde su primer registro |
| `recencia_anios` | RN5 (inactividad) | Años desde su última autorización |
| `contacto` (0/1) | RN2 (contactabilidad) | Si tiene teléfono de referencia |
| `es_regiones` (0/1) | RN3 (complejidad logística) | Si está fuera de Lima/Callao |

Estas variables se extraen de MongoDB con una agregación que hace `$lookup` contra `ubicaciones` (para saber la macrozona) y convierte los booleanos a 0/1:

```r
datos <- con_contratistas$aggregate('[
  { "$match": { "activo": { "$ne": false } } },
  { "$lookup": { "from": "ubicaciones", "localField": "ubicacion_id",
      "foreignField": "id_ubicacion", "as": "ubic" } },
  { "$unwind": "$ubic" },
  { "$project": {
      "_id": 0, "ruc": 1,
      "amplitud_actividad_actual": 1, "num_autorizaciones": 1,
      "antiguedad_anios": 1, "recencia_anios": 1,
      "contacto": { "$cond": ["$indice_completitud_contacto", 1, 0] },
      "es_regiones": { "$cond": [ { "$eq": ["$ubic.macrozona", "Regiones"] }, 1, 0 ] }
  }}
]')
```

Nota: solo se agrupan contratistas **activos** (los dados de baja lógica quedan fuera, no distorsionan el agrupamiento).

---

## 3. Estandarización (z-score)

k-means mide **distancias** entre empresas (distancia euclídea). Si dejáramos las variables en su escala original, `antiguedad_anios` (rango ~0–18) dominaría completamente sobre `contacto` (rango 0–1), aunque ambas sean igual de importantes conceptualmente.

```r
vars <- c("amplitud_actividad_actual", "num_autorizaciones",
          "antiguedad_anios", "recencia_anios", "contacto", "es_regiones")
X <- scale(datos[, vars])
```

`scale()` transforma cada variable para que tenga media 0 y desviación estándar 1. Así todas "pesan" lo mismo en el cálculo de distancia, salvo por la ponderación que se les da después en el índice de riesgo (sección 6).

**Limitación metodológica conocida (documentada en el informe, no oculta):** estandarizar variables binarias (0/1) junto con continuas tiene un efecto secundario — las binarias, al tener solo dos valores posibles, generan particiones muy "limpias" del espacio y pueden dominar la asignación de clústeres frente a variables continuas con solapamiento natural. Se verificó empíricamente que esto ocurre parcialmente con la variable `contacto` en uno de los grupos (ver sección 8).

---

## 4. Elegir k: método del codo + silueta

Antes de decidir en cuántos grupos dividir, se prueban varios valores de k (de 2 a 8) y se mide, para cada uno:
- **WSS** (within-cluster sum of squares / suma de cuadrados intra-clúster): qué tan compactos son los grupos. Baja siempre que k sube; interesa dónde deja de bajar mucho (el "codo").
- **Silueta promedio**: qué tan bien separado está cada punto de los demás grupos frente a su propio grupo. Va de -1 a 1; más alto es mejor.

```r
eval_k <- data.frame(k = 2:8, wss = NA_real_, silueta = NA_real_)
for (i in seq_len(nrow(eval_k))) {
  k <- eval_k$k[i]
  km <- kmeans(X, centers = k, nstart = 25, iter.max = 100)
  eval_k$wss[i] <- km$tot.withinss
  sil <- silhouette(km$cluster, dist(X))
  eval_k$silueta[i] <- mean(sil[, 3])
}
```

Resultado real (verificado contra la base de datos):

| k | WSS | Silueta |
|---|---|---|
| 2 | 11,028 | 0.284 |
| 3 | 8,971 | 0.325 |
| **4** | **7,257** | **0.342** |
| 5 | 6,054 | 0.343 |
| 6 | 5,129 | 0.367 |
| 7 | 4,503 | 0.370 |
| 8 | 4,047 | 0.396 |

**Por qué se eligió k = 4 y no un valor "mejor" en silueta:**
- La silueta mejora con k más alto, pero de forma marginal después de k=4 (0.342 → 0.343 entre k=4 y k=5 — casi no cambia).
- Un k más alto complica la interpretación de negocio. El objetivo no es la partición estadísticamente "más pura", sino una que la DGM pueda operar: **4 niveles de prioridad (Muy Alta, Alta, Media, Baja)** es un esquema simple y accionable.
- Es una decisión documentada de **criterio de negocio moderando al criterio puramente estadístico** — práctica reconocida en clustering aplicado, no una elección arbitraria.

**Nota honesta sobre la silueta de 0.342:** en la escala de referencia de Kaufman & Rousseeuw, 0.26–0.50 se interpreta como "estructura débil/artificial, que podría encontrarse por otros medios" (no "estructura fuerte"). Esto no invalida el resultado — pero es la razón por la que el plan de validación (sección 7) no se apoya solo en la silueta, sino en 7 pruebas independientes en 3 dimensiones distintas.

---

## 5. Ejecutar el k-means final

```r
set.seed(2026)
km_final <- kmeans(X, centers = 4, nstart = 50, iter.max = 100)
datos$cluster <- km_final$cluster
```

**Qué hace el algoritmo, paso a paso (intuición):**
1. Coloca 4 "centros" (centroides) en puntos del espacio de 6 dimensiones.
2. Asigna cada empresa al centro más cercano (distancia euclídea).
3. Recalcula cada centro como el promedio de las empresas que le tocaron.
4. Repite 2–3 hasta que las asignaciones ya no cambian (converge).

**`nstart = 50`:** el resultado de k-means depende del punto de partida de los centros (es un algoritmo con componente aleatoria). Para no quedarse con una mala solución por mala suerte, se repite el proceso completo 50 veces desde puntos de partida distintos y se conserva la mejor (menor WSS total).

**`set.seed(2026)`:** fija la semilla del generador aleatorio para que el resultado sea reproducible — cualquiera que corra el script con los mismos datos obtiene exactamente el mismo agrupamiento.

**Resultado real (4 grupos, tamaños actuales de la BD):**

| Clúster | n | Amplitud prom. | Renovaciones prom. | Antigüedad | Recencia | % con contacto | % Regiones |
|---|---|---|---|---|---|---|---|
| 1 | 1,096 | 2.73 | 1.0 | 14.4 | 14.4 | 0% | 0% |
| 2 | 76 | 3.14 | 2.28 | 7.5 | 4.6 | 9.2% | — |
| 3 | 1,023 | 3.49 | 1.0 | 5.4 | 5.4 | 0.1% | — |
| 4 | 326 | ~3.0 | 1.0 | — | — | 100% | — |

(Los números de cluster 1–4 aquí son los que asigna `kmeans()` internamente y **no** corresponden al orden de prioridad final — eso se recalcula en el siguiente paso.)

---

## 6. Traducir los grupos a un índice de riesgo

Un clúster por sí solo no dice "qué tan urgente es fiscalizarlo". Para eso se calcula, por grupo, un **índice de riesgo** (puntaje de 0 a 1) que pondera 4 de las reglas de negocio:

```r
indice_riesgo =
  (amplitud / 4)                          * 0.40 +   # RN1: exposición operativa
  ((100 - pct_con_contacto) / 100)        * 0.25 +   # RN2: baja contactabilidad
  (pct_regiones / 100)                    * 0.20 +   # RN3: complejidad logística
  pmin(recencia / max(recencia), 1)       * 0.15     # RN5: antigüedad sin renovar
```

**Por qué esos pesos:** la exposición operativa (RN1) pesa más (40%) porque es el factor directo de "qué tanto puede salir mal" en una empresa con actividad integral. La contactabilidad (25%) y la ubicación (20%) pesan porque determinan qué tan **difícil** es fiscalizar, no cuánto riesgo intrínseco tiene la empresa — por eso pesan menos que la exposición. La recencia (15%) es la señal más débil de las cuatro (podría ser simplemente una empresa que aún no le toca renovar).

Puntajes reales actuales:

| Prioridad | Puntaje | Nombre del grupo (data-driven) | n |
|---|---|---|---|
| Muy Alta | 0.761 | Baja contactabilidad · alta exposición · reciente | 1,023 |
| Alta | 0.744 | Baja contactabilidad · alcance moderado · sin renovar / antiguo | 1,096 |
| Media | 0.673 | Dinámico con renovaciones · baja contactabilidad · reciente | 76 |
| Baja | 0.487 | Contactable | 326 |

---

## 7. Nombrar los grupos (etiquetado data-driven)

Los nombres de los grupos (p. ej. "Baja contactabilidad · alta exposición · reciente") **no son una plantilla fija** — se generan a partir de los rasgos propios de cada grupo, comparando sus promedios contra umbrales:

```r
etiquetar <- function(fila) {
  rasgos <- c()
  if (fila$renovaciones >= 1.5) rasgos <- c(rasgos, "dinámico con renovaciones")
  if (fila$pct_con_contacto >= 80) rasgos <- c(rasgos, "contactable")
  else if (fila$pct_con_contacto <= 10) rasgos <- c(rasgos, "baja contactabilidad")
  if (fila$amplitud >= 3.4) rasgos <- c(rasgos, "alta exposición")
  else if (fila$amplitud <= 2.8) rasgos <- c(rasgos, "alcance moderado")
  if (fila$recencia >= media_recencia * 1.2) rasgos <- c(rasgos, "sin renovar / antiguo")
  else if (fila$recencia <= media_recencia * 0.6) rasgos <- c(rasgos, "reciente")
  ...
}
```

El primer rasgo que aplica se vuelve el nombre principal; los demás se listan como calificadores. Esto asegura que el nombre describa **lo que el análisis realmente encontró**, no una categoría inventada de antemano.

---

## 8. Ordenar por prioridad y guardar en MongoDB

Una vez calculado el índice de riesgo, los grupos se ordenan de mayor a menor y se les asigna la etiqueta de prioridad:

```r
perfil <- perfil %>%
  arrange(desc(indice_riesgo)) %>%
  mutate(rank_riesgo = row_number(),
         nivel_prioridad_fiscalizacion = case_when(
           rank_riesgo == 1 ~ "Muy Alta",
           rank_riesgo == 2 ~ "Alta",
           rank_riesgo == 3 ~ "Media",
           TRUE             ~ "Baja"))
```

Luego se guarda en dos lugares de MongoDB:
1. **Colección `segmentos_riesgo`**: un documento por grupo, con su nombre, descripción, prioridad, índice de riesgo y estadísticas.
2. **Campo `segmento_id` en cada contratista**: se actualiza documento por documento (`$set`) para que cada empresa quede vinculada a su grupo.

**Nota metodológica sobre un hallazgo ya investigado (correlación antigüedad-recencia):** se detectó que `antiguedad_anios` y `recencia_anios` tienen una correlación de 0.984 en el conjunto completo (y 1.000 en el 97% de empresas con una sola autorización) — es decir, casi la misma información entra dos veces al cálculo de distancia. Se evaluó un modelo alternativo con solo 3 variables continuas, que mejoraba la silueta (0.451 vs 0.342), pero **hacía desaparecer como grupo diferenciado** al segmento "100% contactable" (el de prioridad Baja), que resultó dominado en 97.6% por la variable binaria `contacto`. Tras este análisis se decidió **mantener las 6 variables originales**, documentando ambas limitaciones (correlación y dominancia binaria) como trade-off consciente y no como defecto oculto.

---

## 9. Validación: ¿el clustering realmente sirve?

Como es no supervisado, no hay una "tasa de acierto" que calcular. En su lugar, `05_validacion_patrones.R` corre **7 pruebas** en 3 dimensiones, cada una con criterio de CUMPLE/NO CUMPLE:

### A) Validez interna (¿los grupos son reales?)

| Prueba | Qué comprueba | Resultado |
|---|---|---|
| **V1** — Cobertura | 100% de empresas clasificadas y ningún grupo degenerado (umbral proporcional: ≥1% del padrón) | 2,521/2,521 asignados; grupo más chico = 76 (3.0%) → **CUMPLE** |
| **V2** — Cohesión/separación | Silueta > 0.25 y varianza explicada (between/total) > 0.45 | silueta 0.342, varianza 52.0% → **CUMPLE** |
| **V3** — Separación estadística | ANOVA: las 6 variables difieren entre grupos (p < 0.05) | 6/6 significativas (máx. p = 1.5×10⁻²⁰) → **CUMPLE**, con nota: el ANOVA se corre sobre las mismas variables que k-means usó para formar los grupos, así que un resultado significativo es esperable casi por construcción; se interpreta como "la partición no es degenerada", no como validez externa independiente |

### B) Validez de negocio (¿sirven para decidir?)

| Prueba | Qué comprueba | Resultado |
|---|---|---|
| **V4** — Discriminación de riesgo | El grupo "Muy Alta" supera al "Baja" en exposición y lo subpasa en contacto | Muy Alta: amplitud 3.5 / contacto 0% vs Baja: amplitud 3.0 / contacto 100% → **CUMPLE** |
| **V5** — Coherencia con las consultas | ≥95% de los 485 contratistas "prioritarios" (consulta C4) caen en grupos de alta prioridad y 0 en el de Baja | 468/485 (96.5%) en alta prioridad, 0 en Baja → **CUMPLE** |

### C) Robustez (¿el patrón es estable?)

| Prueba | Qué comprueba | Resultado |
|---|---|---|
| **V6** — Convergencia entre algoritmos | Un algoritmo **distinto** de k-means (jerárquico de Ward, cortado a 4 grupos) debe recuperar una partición similar | ARI(k-means, Ward) = 0.804 ≥ 0.60 → **CUMPLE** |
| **V7** — Reproducibilidad | Re-ejecutar k-means con 5 semillas distintas; medir el Índice de Rand Ajustado (ARI) promedio contra el modelo base | ARI promedio 0.900 (rango 0.511–1.000) ≥ 0.75 → **CUMPLE** |

**Veredicto global: 7 de 7 pruebas CUMPLEN.**

> Nota sobre V6: originalmente esta prueba verificaba que la prioridad decreciera monótonamente junto con el índice de riesgo. Se identificó que esa versión era **tautológica** — la prioridad se deriva justamente de ordenar por ese índice, así que la prueba no podía fallar salvo por un bug de código. Se reemplazó por la comparación contra un algoritmo independiente (Ward), que sí aporta evidencia real de que los grupos no son un artefacto del método.

---

## 10. Reproducibilidad: un detalle técnico importante

k-means es sensible a **dos cosas** además de la semilla:
1. **El orden de las filas** de entrada (aunque parezca que no debería importar).
2. **La secuencia de números aleatorios consumidos** antes de correr el ajuste final.

Al construir el botón "Recalcular grupos" en la app (que reproduce este mismo proceso contra MongoDB, sin pasar por archivos), se detectó que MongoDB no garantiza un orden fijo entre lecturas — dos ejecuciones podían dar 1,027/1,092 en vez de 1,023/1,096 (los mismos 4 perfiles, pero ~4 empresas cambiando de lado en la frontera Muy Alta/Alta). Se corrigió:

```r
# En 04_patrones_clustering.R y en recalcular_grupos() (global.R):
datos <- datos[order(datos$ruc), ]
```

Y además, `recalcular_grupos()` reproduce el mismo bucle de evaluación de k = 2..8 que corre `04` antes del ajuste final (ese bucle consume el generador aleatorio), para que ambos caminos den **exactamente** el mismo resultado. Verificado: con estos ajustes, recalcular desde la app reproduce 1,023/1,096/76/326 de forma idéntica al script original.

---

## 11. Cuándo se recalcula (y cuándo no)

- **No es automático.** El clustering es una "foto" de los datos en el momento en que se ejecutó. Si se editan datos desde la app (teléfono, reasignación manual, baja lógica), los grupos existentes en `segmentos_riesgo` **no se actualizan solos**.
- **Para actualizarlo:** botón "Recalcular grupos de riesgo" en la pestaña de Grupos (llama a `recalcular_grupos()`), o re-ejecutar `04_patrones_clustering.R` manualmente.
- **Los contratistas inactivos (baja lógica) se excluyen** de la extracción de variables — no participan del agrupamiento ni se cuentan en sus estadísticas.

---

## 12. Resumen del flujo completo

```
MongoDB (contratistas + ubicaciones)
        │
        ▼
Extraer 6 variables por empresa (activos únicamente)
        │
        ▼
Ordenar por RUC (reproducibilidad) + estandarizar (z-score)
        │
        ▼
Evaluar k = 2..8 (codo + silueta) → decisión de negocio: k = 4
        │
        ▼
k-means final (seed=2026, nstart=50) → 4 clústeres
        │
        ▼
Perfilar cada clúster → calcular índice de riesgo (RN1+RN2+RN3+RN5)
        │
        ▼
Etiquetar (data-driven) + ordenar por prioridad (Muy Alta…Baja)
        │
        ▼
Guardar en `segmentos_riesgo` + actualizar `segmento_id` en cada contratista
        │
        ▼
Validar: 7 pruebas en 3 dimensiones (interna / negocio / robustez) → 7/7 CUMPLE
        │
        ▼
Mostrar en la app: tabla, fichas de acción, gráfico, filtro por grupo
```
