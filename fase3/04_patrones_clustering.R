# ============================================================
# FASE III — c) Aplicar las reglas de negocio para generar
#              patrones (clustering) que mejoren la toma de
#              decisiones empresariales.
# ------------------------------------------------------------
# Técnica: K-means (segmentación no supervisada), la seleccionada
# como principal en la Fase II (sección 2.1.6).
#
# Las reglas de negocio (RN) orientan la selección de variables
# predictoras del modelo:
#   RN1 -> amplitud_actividad_actual   (exposición operativa)
#   RN2 -> indice_completitud_contacto (contactabilidad)
#   RN3 -> macrozona (Regiones)        (complejidad logística)
#   RN5 -> num_autorizaciones, antiguedad_anios, recencia_anios
#          (dinamismo / trayectoria)
#
# Salida: cada contratista recibe un segmento; la colección
# 'segmentos_riesgo' se puebla con el perfil de cada segmento y
# el campo 'segmento_id' de cada contratista se actualiza.
# ============================================================

suppressMessages({
  library(mongolite)
  library(dplyr)
  library(jsonlite)
  library(cluster)
})

set.seed(2026)  # reproducibilidad

URI <- "mongodb://localhost:27017"
BD  <- "contratistas_mineros_minem"
DIR_SALIDAS <- file.path("fase3", "salidas")
dir.create(DIR_SALIDAS, showWarnings = FALSE, recursive = TRUE)

con_contratistas <- mongo("contratistas",     db = BD, url = URI)
con_ubicaciones  <- mongo("ubicaciones",      db = BD, url = URI)
con_segmentos    <- mongo("segmentos_riesgo", db = BD, url = URI)

# ------------------------------------------------------------
# 1. EXTRAER las variables predictoras desde MongoDB (join con ubicación)
# ------------------------------------------------------------
cat("1. Extrayendo variables predictoras desde MongoDB...\n")

datos <- con_contratistas$aggregate('[
  { "$match": { "activo": { "$ne": false } } },
  { "$lookup": {
      "from": "ubicaciones", "localField": "ubicacion_id",
      "foreignField": "id_ubicacion", "as": "ubic" } },
  { "$unwind": "$ubic" },
  { "$project": {
      "_id": 0, "ruc": 1,
      "amplitud_actividad_actual": 1,
      "num_autorizaciones": 1,
      "antiguedad_anios": 1,
      "recencia_anios": 1,
      "contacto": { "$cond": ["$indice_completitud_contacto", 1, 0] },
      "es_regiones": { "$cond": [ { "$eq": ["$ubic.macrozona", "Regiones"] }, 1, 0 ] }
  }}
]')

cat("   Contratistas extraídos:", nrow(datos), "| Variables:",
    paste(setdiff(names(datos), "ruc"), collapse = ", "), "\n")

# Orden fijo por RUC: k-means depende del orden de las filas y MongoDB no
# garantiza un orden estable entre lecturas. Ordenar hace el resultado
# reproducible (mismos grupos con los mismos datos).
datos <- datos[order(datos$ruc), ]

# ------------------------------------------------------------
# 2. PREPARAR la matriz: variables numéricas estandarizadas (z-score)
#    (k-means usa distancia euclídea; la estandarización evita que
#     una variable de mayor escala domine a las demás)
# ------------------------------------------------------------
cat("2. Estandarizando variables (z-score)...\n")

vars <- c("amplitud_actividad_actual", "num_autorizaciones",
          "antiguedad_anios", "recencia_anios", "contacto", "es_regiones")
X <- scale(datos[, vars])

# ------------------------------------------------------------
# 3. ELEGIR k: método del codo (WSS) + silueta promedio
# ------------------------------------------------------------
cat("3. Evaluando número de clústeres (k = 2..8)...\n")

eval_k <- data.frame(k = 2:8, wss = NA_real_, silueta = NA_real_)
for (i in seq_len(nrow(eval_k))) {
  k <- eval_k$k[i]
  km <- kmeans(X, centers = k, nstart = 25, iter.max = 100)
  eval_k$wss[i] <- km$tot.withinss
  sil <- silhouette(km$cluster, dist(X))
  eval_k$silueta[i] <- mean(sil[, 3])
}
eval_k$wss <- round(eval_k$wss, 0)
eval_k$silueta <- round(eval_k$silueta, 3)
print(eval_k)
write.csv(eval_k, file.path(DIR_SALIDAS, "clustering_eleccion_k.csv"), row.names = FALSE)

K <- 4  # decisión: 4 segmentos, coherente con la interpretación de negocio
cat("   -> Se selecciona k =", K, "segmentos.\n")

# ------------------------------------------------------------
# 4. EJECUTAR K-means final
# ------------------------------------------------------------
cat("4. Ejecutando K-means final con k =", K, "...\n")
km_final <- kmeans(X, centers = K, nstart = 50, iter.max = 100)
datos$cluster <- km_final$cluster

# Perfil promedio de cada clúster (en la escala original, interpretable)
perfil <- datos %>%
  group_by(cluster) %>%
  summarise(
    n = n(),
    amplitud   = round(mean(amplitud_actividad_actual), 2),
    renovaciones = round(mean(num_autorizaciones), 2),
    antiguedad = round(mean(antiguedad_anios), 1),
    recencia   = round(mean(recencia_anios), 1),
    pct_con_contacto = round(mean(contacto) * 100, 1),
    pct_regiones     = round(mean(es_regiones) * 100, 1),
    .groups = "drop"
  )
cat("\nPerfil promedio por clúster:\n")
print(perfil)

# ------------------------------------------------------------
# 5. APLICAR LAS REGLAS DE NEGOCIO: traducir cada clúster a un
#    segmento de riesgo con nombre, descripción y prioridad.
#    Índice de riesgo = combinación de las reglas RN1..RN5:
#      + amplitud (RN1), + %sin contacto (RN2), + %regiones (RN3),
#      + antigüedad y recencia (RN5, señal de posible inactividad).
# ------------------------------------------------------------
cat("\n5. Aplicando reglas de negocio para etiquetar segmentos...\n")

# 5a. Índice de riesgo (para ORDENAR la prioridad de fiscalización)
perfil <- perfil %>%
  mutate(
    indice_riesgo =
      (amplitud / 4) * 0.40 +               # RN1: exposición operativa
      ((100 - pct_con_contacto) / 100) * 0.25 +  # RN2: baja contactabilidad
      (pct_regiones / 100) * 0.20 +         # RN3: complejidad logística
      pmin(recencia / max(recencia), 1) * 0.15,  # RN5: antigüedad sin renovar
    indice_riesgo = round(indice_riesgo, 3)
  )

# 5b. Nombre del segmento DERIVADO de los rasgos propios de cada clúster
#     (no de una plantilla fija): se identifica el rasgo distintivo.
media_recencia <- mean(datos$recencia_anios)
etiquetar <- function(fila) {
  rasgos <- c()
  if (fila$renovaciones >= 1.5) rasgos <- c(rasgos, "dinámico con renovaciones")
  if (fila$pct_con_contacto >= 80) rasgos <- c(rasgos, "contactable")
  else if (fila$pct_con_contacto <= 10) rasgos <- c(rasgos, "baja contactabilidad")
  if (fila$amplitud >= 3.4) rasgos <- c(rasgos, "alta exposición")
  else if (fila$amplitud <= 2.8) rasgos <- c(rasgos, "alcance moderado")
  if (fila$recencia >= media_recencia * 1.2) rasgos <- c(rasgos, "sin renovar / antiguo")
  else if (fila$recencia <= media_recencia * 0.6) rasgos <- c(rasgos, "reciente")
  if (length(rasgos) == 0) rasgos <- "perfil mixto"
  paste(toupper(substring(rasgos[1], 1, 1)), substring(rasgos[1], 2),
        if (length(rasgos) > 1) paste0(" · ", paste(rasgos[-1], collapse = " · ")) else "",
        sep = "")
}
perfil$nombre_segmento <- vapply(seq_len(nrow(perfil)),
                                 function(i) etiquetar(perfil[i, ]), character(1))

# 5c. Prioridad de fiscalización según el ranking del índice de riesgo
perfil <- perfil %>%
  arrange(desc(indice_riesgo)) %>%
  mutate(
    rank_riesgo = row_number(),
    nivel_prioridad_fiscalizacion = case_when(
      rank_riesgo == 1 ~ "Muy Alta",
      rank_riesgo == 2 ~ "Alta",
      rank_riesgo == 3 ~ "Media",
      TRUE             ~ "Baja"
    )
  )

perfil$descripcion <- with(perfil, sprintf(
  "Segmento con amplitud promedio %.1f/4, %.0f%% con contacto telefónico, %.0f%% en Regiones, antigüedad promedio %.1f años y recencia %.1f años. Agrupa %d contratistas.",
  amplitud, pct_con_contacto, pct_regiones, antiguedad, recencia, n))

cat("\nSegmentos de riesgo generados:\n")
print(perfil[, c("cluster", "n", "nombre_segmento",
                 "nivel_prioridad_fiscalizacion", "indice_riesgo")])

saveRDS(list(datos = datos, perfil = perfil, km = km_final, eval_k = eval_k),
        file.path(DIR_SALIDAS, "clustering_modelo.rds"))
write.csv(perfil, file.path(DIR_SALIDAS, "clustering_segmentos.csv"), row.names = FALSE)

# ------------------------------------------------------------
# 6. POBLAR la colección 'segmentos_riesgo' (antes vacía)
# ------------------------------------------------------------
cat("\n6. Poblando la colección 'segmentos_riesgo' en MongoDB...\n")
con_segmentos$drop()

fecha_hoy <- format(Sys.Date(), "%Y-%m-%dT00:00:00Z")
mapa_id_segmento <- list()  # cluster (kmeans) -> id_segmento estable (1..K por riesgo)

for (i in seq_len(nrow(perfil))) {
  id_segmento <- perfil$rank_riesgo[i]
  mapa_id_segmento[[as.character(perfil$cluster[i])]] <- id_segmento

  doc <- list(
    id_segmento                   = id_segmento,
    nombre_segmento               = perfil$nombre_segmento[i],
    descripcion                   = perfil$descripcion[i],
    nivel_prioridad_fiscalizacion = perfil$nivel_prioridad_fiscalizacion[i],
    indice_riesgo                 = perfil$indice_riesgo[i],
    n_contratistas                = perfil$n[i],
    amplitud_promedio             = perfil$amplitud[i],
    pct_con_contacto              = perfil$pct_con_contacto[i],
    pct_regiones                  = perfil$pct_regiones[i],
    fecha_generacion_modelo       = list(`$date` = fecha_hoy),
    algoritmo_utilizado           = "k-means (k=4, nstart=50)"
  )
  con_segmentos$insert(toJSON(doc, auto_unbox = TRUE))
}
cat("   Documentos en 'segmentos_riesgo':", con_segmentos$count(), "\n")

# ------------------------------------------------------------
# 7. ASIGNAR el segmento a cada contratista (update de segmento_id)
# ------------------------------------------------------------
cat("7. Asignando segmento_id a cada contratista...\n")
datos$id_segmento <- vapply(datos$cluster,
                            function(c) mapa_id_segmento[[as.character(c)]],
                            numeric(1))

for (i in seq_len(nrow(datos))) {
  con_contratistas$update(
    query  = toJSON(list(ruc = datos$ruc[i]), auto_unbox = TRUE),
    update = toJSON(list(`$set` = list(segmento_id = datos$id_segmento[i])),
                    auto_unbox = TRUE)
  )
}

n_asignados <- con_contratistas$count('{"segmento_id": {"$ne": null}}')
cat("   Contratistas con segmento asignado:", n_asignados, "/", nrow(datos), "\n")

# 7b. Índice sobre segmento_id, ya poblado. Acelera las consultas y
#     agregaciones que filtran o agrupan contratistas por su segmento de
#     riesgo (validación V5 y explorador/segmentos de la app Shiny).
con_contratistas$run(paste0(
  '{"createIndexes": "contratistas", ',
  '"indexes": [{"key": {"segmento_id": 1}, "name": "segmento_id_1"}]}'
))
cat("   Índice 'segmento_id_1' creado sobre la colección 'contratistas'.\n")

cat("\n============================================================\n")
cat("Punto c) completado: patrones (4 segmentos) generados con\n")
cat("k-means, colección 'segmentos_riesgo' poblada y cada\n")
cat("contratista clasificado. Insumo directo para REQ1 (priorización).\n")
cat("============================================================\n")
