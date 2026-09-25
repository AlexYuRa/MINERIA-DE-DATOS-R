# ============================================================
# FASE III — d) Validar la funcionalidad de los resultados
#              generados por los patrones creados, para demostrar
#              si cumplen o no con lo requerido.
# ------------------------------------------------------------
# Se aplican 7 pruebas de validación agrupadas en 3 dimensiones:
#   A) Validez INTERNA del clustering (¿los grupos son reales?)
#   B) Validez de NEGOCIO (¿sirven a los requerimientos REQ1..REQ5?)
#   C) ROBUSTEZ (¿el patrón es estable y reproducible?)
# Cada prueba emite un veredicto CUMPLE / NO CUMPLE.
# ============================================================

suppressMessages({
  library(mongolite)
  library(dplyr)
  library(cluster)
})

set.seed(2026)
URI <- "mongodb://localhost:27017"
BD  <- "contratistas_mineros_minem"
DIR_SALIDAS <- file.path("fase3", "salidas")

con_contratistas <- mongo("contratistas",     db = BD, url = URI)
con_segmentos    <- mongo("segmentos_riesgo", db = BD, url = URI)

# Cargar el modelo generado en el punto c)
modelo <- readRDS(file.path(DIR_SALIDAS, "clustering_modelo.rds"))
datos  <- modelo$datos
perfil <- modelo$perfil
km     <- modelo$km

vars <- c("amplitud_actividad_actual", "num_autorizaciones",
          "antiguedad_anios", "recencia_anios", "contacto", "es_regiones")
X <- scale(datos[, vars])

resultados_val <- data.frame(prueba = character(), dimension = character(),
                             criterio = character(), obtenido = character(),
                             veredicto = character(), stringsAsFactors = FALSE)

registrar <- function(prueba, dimension, criterio, obtenido, cumple) {
  v <- ifelse(cumple, "CUMPLE", "NO CUMPLE")
  cat(sprintf("[%s] %s\n         Criterio: %s\n         Obtenido: %s\n\n",
              v, prueba, criterio, obtenido))
  resultados_val <<- rbind(resultados_val,
    data.frame(prueba = prueba, dimension = dimension, criterio = criterio,
               obtenido = obtenido, veredicto = v, stringsAsFactors = FALSE))
}

# Índice de Rand Ajustado (ARI) — Hubert & Arabie (1985). Mide la
# concordancia entre dos particiones corrigiendo el acuerdo esperado por
# azar (0 = azar, 1 = particiones idénticas). Se usa en V6 (concordancia
# entre algoritmos distintos) y en V7 (estabilidad entre semillas).
ari <- function(a, b) {
  tab <- table(a, b); n <- sum(tab)
  comb2 <- function(x) x * (x - 1) / 2
  sij <- sum(comb2(tab)); si <- sum(comb2(rowSums(tab))); sj <- sum(comb2(colSums(tab)))
  esp <- si * sj / comb2(n); mx <- (si + sj) / 2
  (sij - esp) / (mx - esp)
}

cat("============================================================\n")
cat(" VALIDACIÓN DE LOS PATRONES (SEGMENTOS) — Fase III d)\n")
cat("============================================================\n\n")

# ------------------------------------------------------------
# A) VALIDEZ INTERNA
# ------------------------------------------------------------

# V1 — Cobertura total y ausencia de clústeres degenerados
# El umbral de no-degeneración se fija de forma PROPORCIONAL al padrón
# (>= 1% del total) en lugar de un valor absoluto arbitrario, de modo que
# el criterio siga siendo significativo si el modelo se reejecuta sobre un
# padrón de tamaño distinto.
n_total     <- con_contratistas$count()
n_asignados <- con_contratistas$count('{"segmento_id": {"$ne": null}}')
tam <- as.numeric(table(datos$cluster))
min_pct <- round(min(tam) / sum(tam) * 100, 1)
umbral_min <- ceiling(0.01 * sum(tam))   # 1% del padrón
cumple_v1 <- (n_asignados == n_total) && (min(tam) >= umbral_min)
registrar("V1", "Interna",
          sprintf("100%% de contratistas clasificados y ningún clúster degenerado (>=1%% del padrón, >=%d miembros)",
                  umbral_min),
          sprintf("%d/%d asignados; clúster más pequeño = %d (%.1f%%)",
                  n_asignados, n_total, min(tam), min_pct),
          cumple_v1)

# V2 — Calidad de cohesión/separación: silueta promedio y ratio B/T
sil <- silhouette(km$cluster, dist(X))
sil_prom <- mean(sil[, 3])
ratio_bt <- km$betweenss / km$totss
cumple_v2 <- (sil_prom > 0.25) && (ratio_bt > 0.45)
registrar("V2", "Interna",
          "Silueta promedio > 0.25 y varianza explicada (between/total) > 0.45",
          sprintf("silueta = %.3f; varianza explicada = %.1f%%",
                  sil_prom, ratio_bt * 100),
          cumple_v2)

# V3 — Separación estadística: ANOVA por variable (los segmentos difieren)
# NOTA METODOLÓGICA: el ANOVA se calcula sobre las MISMAS variables que
# k-means empleó para formar los grupos; como el algoritmo minimiza la
# varianza intra-clúster en esas variables, un resultado significativo es
# esperable casi por construcción (más aún con n=2521, de alto poder). Por
# ello V3 se interpreta como confirmación de que la partición NO es
# degenerada (todas las variables aportan separación), y no como evidencia
# de validez externa e independiente del modelo.
pvals <- sapply(vars, function(v) {
  df <- data.frame(y = datos[[v]], g = factor(datos$cluster))
  summary(aov(y ~ g, data = df))[[1]][["Pr(>F)"]][1]
})
n_signif <- sum(pvals < 0.05)
cumple_v3 <- n_signif == length(vars)
registrar("V3", "Interna",
          "Todas las variables predictoras difieren entre segmentos (ANOVA p < 0.05)",
          sprintf("%d/%d variables significativas (max p = %.3g)",
                  n_signif, length(vars), max(pvals)),
          cumple_v3)

# ------------------------------------------------------------
# B) VALIDEZ DE NEGOCIO
# ------------------------------------------------------------

# V4 — Discriminación de riesgo (REQ1): el segmento de Muy Alta prioridad
#      debe tener MAYOR amplitud y MENOR contacto que el de Baja prioridad.
seg <- con_segmentos$find('{}', sort = '{"id_segmento":1}')
muy_alta <- seg[seg$nivel_prioridad_fiscalizacion == "Muy Alta", ]
baja     <- seg[seg$nivel_prioridad_fiscalizacion == "Baja", ]
cumple_v4 <- (muy_alta$amplitud_promedio > baja$amplitud_promedio) &&
             (muy_alta$pct_con_contacto  < baja$pct_con_contacto)
registrar("V4", "Negocio",
          "El segmento 'Muy Alta' supera al 'Baja' en exposición y lo subpasa en contacto (REQ1)",
          sprintf("Muy Alta: amplitud %.1f / contacto %.0f%% | Baja: amplitud %.1f / contacto %.0f%%",
                  muy_alta$amplitud_promedio, muy_alta$pct_con_contacto,
                  baja$amplitud_promedio, baja$pct_con_contacto),
          cumple_v4)

# V5 — Consistencia con las consultas de negocio (b): los 485 contratistas
#      "prioritarios" de C4 (amplitud=4 + sin tel + Regiones) deben concentrarse
#      en los segmentos de ALTA prioridad (Muy Alta + Alta) y NO aparecer en el
#      segmento de Baja prioridad. C4 es un filtro rígido de 3 condiciones; el
#      clustering usa 6 variables y reparte el riesgo alto en 2 segmentos.
ids_alta_prioridad <- seg$id_segmento[seg$nivel_prioridad_fiscalizacion %in% c("Muy Alta","Alta")]
id_baja <- baja$id_segmento
# Mismo patrón de C4: se filtran primero las condiciones que no dependen
# del join para reducir el conjunto antes del $lookup.
distrib_prior <- con_contratistas$aggregate('[
  { "$match": { "amplitud_actividad_actual": 4,
                "indice_completitud_contacto": false } },
  { "$lookup": { "from": "ubicaciones", "localField": "ubicacion_id",
      "foreignField": "id_ubicacion", "as": "u" } },
  { "$unwind": "$u" },
  { "$match": { "u.macrozona": "Regiones" } },
  { "$group": { "_id": "$segmento_id", "n": { "$sum": 1 } } },
  { "$sort": { "_id": 1 } }
]')
total_prior <- sum(distrib_prior$n)
en_alta     <- sum(distrib_prior$n[distrib_prior$`_id` %in% ids_alta_prioridad])
en_baja     <- sum(distrib_prior$n[distrib_prior$`_id` == id_baja])
pct_en_alta <- round(en_alta / total_prior * 100, 1)
cat("         Distribución de los", total_prior, "prioritarios de C4 por segmento:\n")
print(distrib_prior)
cumple_v5 <- (pct_en_alta >= 95) && (en_baja == 0)
registrar("V5", "Negocio",
          "≥95% de los prioritarios de C4 caen en segmentos de alta prioridad y 0 en el de Baja (coherencia b<->c)",
          sprintf("%d de %d (%.1f%%) en segmentos de alta prioridad; %d en el segmento Baja",
                  en_alta, total_prior, pct_en_alta, en_baja),
          cumple_v5)

# ------------------------------------------------------------
# C) ROBUSTEZ
# ------------------------------------------------------------

# V6 — Validez convergente entre algoritmos: un método de clustering
#      INDEPENDIENTE de k-means (jerárquico aglomerativo de Ward, cortado a
#      k=4) debe recuperar una partición sustancialmente concordante. Si los
#      cuatro segmentos reflejan estructura real de los datos —y no un
#      artefacto del método de las k-medias— un algoritmo distinto debe
#      reencontrarlos. Se mide con el ARI (>= 0.60 = acuerdo sustancial).
#      Esta prueba es independiente de la construcción del índice de riesgo,
#      a diferencia de una simple verificación de monotonía prioridad-índice
#      (que sería tautológica, pues la prioridad se deriva del índice).
d_mat     <- dist(X)
part_ward <- cutree(hclust(d_mat, method = "ward.D2"), k = 4)
ari_ward  <- ari(km$cluster, part_ward)
cumple_v6 <- ari_ward >= 0.60
registrar("V6", "Robustez",
          "Un algoritmo independiente (jerárquico de Ward, k=4) recupera una partición concordante (ARI >= 0.60)",
          sprintf("ARI(k-means, Ward) = %.3f", ari_ward),
          cumple_v6)

# V7 — Estabilidad/reproducibilidad: re-ejecutar k-means con 5 semillas
#      distintas y medir el Índice de Rand Ajustado (ARI) vs. el modelo base.
semillas <- c(1, 7, 42, 123, 999)
aris <- sapply(semillas, function(s) {
  set.seed(s)
  km_s <- kmeans(X, centers = 4, nstart = 25, iter.max = 100)
  ari(km$cluster, km_s$cluster)
})
ari_prom <- mean(aris)
cumple_v7 <- ari_prom >= 0.75
registrar("V7", "Robustez",
          "Reproducibilidad alta: ARI promedio ≥ 0.75 en 5 re-ejecuciones con distinta semilla",
          sprintf("ARI promedio = %.3f (rango %.3f–%.3f)", ari_prom, min(aris), max(aris)),
          cumple_v7)

# ------------------------------------------------------------
# VEREDICTO GLOBAL
# ------------------------------------------------------------
n_cumple <- sum(resultados_val$veredicto == "CUMPLE")
cat("============================================================\n")
cat(sprintf(" RESUMEN: %d de %d pruebas CUMPLEN.\n", n_cumple, nrow(resultados_val)))
cat(sprintf(" VEREDICTO GLOBAL: %s\n",
            ifelse(n_cumple == nrow(resultados_val),
                   "Los patrones CUMPLEN con lo requerido.",
                   ifelse(n_cumple >= nrow(resultados_val) - 1,
                          "Los patrones cumplen SUSTANCIALMENTE con lo requerido.",
                          "Los patrones NO cumplen con lo requerido."))))
cat("============================================================\n")

write.csv(resultados_val, file.path(DIR_SALIDAS, "validacion_patrones.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
saveRDS(resultados_val, file.path(DIR_SALIDAS, "validacion_patrones.rds"))
