# ============================================================
# FASE III — b) Consultas de negocio
# Cada consulta se ejecuta con el framework de agregación de
# MongoDB (mongolite) e indica explícitamente qué REGLA DE
# NEGOCIO (RN) y qué REQUERIMIENTO DE EMPRESA (REQ) satisface.
# ------------------------------------------------------------
# Contexto: Dirección General de Minería (DGM) del MINEM.
# Problema: recursos de fiscalización limitados frente a 2,521
# contratistas. Se necesita priorizar y focalizar la supervisión.
#
# CATÁLOGO DE REGLAS DE NEGOCIO
#   RN1  La exposición operativa de un contratista crece con su
#        amplitud de actividad autorizada (0-4). amplitud=4
#        ("actividad_integral") = máxima exposición.
#   RN2  La contactabilidad es baja cuando el contratista no tiene
#        teléfono de referencia (indice_completitud_contacto=FALSE).
#   RN3  La complejidad logística de fiscalización es mayor en
#        macrozona "Regiones" que en "Lima_Callao".
#   RN4  Un contratista es prioritario para fiscalización cuando
#        combina alta exposición (RN1), baja contactabilidad (RN2)
#        y difícil acceso (RN3).
#   RN5  El dinamismo de una empresa se refleja en su número de
#        autorizaciones/renovaciones (num_autorizaciones) y en el
#        cambio de amplitud entre su primera y su última autorización.
#
# CATÁLOGO DE REQUERIMIENTOS DE EMPRESA (DGM)
#   REQ1 Priorizar la fiscalización hacia los contratistas de mayor
#        exposición operativa.
#   REQ2 Focalizar campañas de actualización de datos de contacto
#        hacia contratistas con baja contactabilidad.
#   REQ3 Planificar la distribución geográfica de equipos de
#        supervisión según la concentración de contratistas.
#   REQ4 Monitorear la evolución del sector (ingreso de nuevas
#        empresas al padrón a lo largo del tiempo).
#   REQ5 Diseñar estrategias diferenciadas según el perfil de
#        actividad de cada segmento de contratistas.
# ============================================================

suppressMessages({
  library(mongolite)
  library(dplyr)
  library(jsonlite)
})

URI <- "mongodb://localhost:27017"
BD  <- "contratistas_mineros_minem"

con_contratistas <- mongo("contratistas", db = BD, url = URI)
con_ubicaciones  <- mongo("ubicaciones",  db = BD, url = URI)

DIR_SALIDAS <- file.path("fase3", "salidas")
dir.create(DIR_SALIDAS, showWarnings = FALSE, recursive = TRUE)

titulo <- function(id, rn, req, texto) {
  cat("\n============================================================\n")
  cat(id, "—", texto, "\n")
  cat("Satisface:", rn, "|", req, "\n")
  cat("------------------------------------------------------------\n")
}

resultados <- list()

# ------------------------------------------------------------
# CONSULTA C1 — Distribución de contratistas por perfil de actividad
# RN1 (exposición por amplitud) · REQ1 (priorización) · REQ5 (estrategias)
# ------------------------------------------------------------
titulo("C1", "RN1", "REQ1 / REQ5",
       "Distribución de contratistas por perfil de actividad (exposición operativa)")

c1 <- con_contratistas$aggregate('[
  { "$group": {
      "_id": "$perfil_actividad",
      "n_contratistas": { "$sum": 1 },
      "amplitud_promedio": { "$avg": "$amplitud_actividad_actual" }
  }},
  { "$sort": { "n_contratistas": -1 } }
]') %>%
  mutate(porcentaje = round(n_contratistas / sum(n_contratistas) * 100, 1),
         amplitud_promedio = round(amplitud_promedio, 2)) %>%
  rename(perfil_actividad = `_id`)
print(c1)
resultados$C1 <- c1

# ------------------------------------------------------------
# CONSULTA C2 — Departamentos que concentran contratistas de alta
# exposición (actividad integral, amplitud = 4)
# RN1 · RN3 · REQ1 (priorización) · REQ3 (distribución geográfica)
# ------------------------------------------------------------
titulo("C2", "RN1 / RN3", "REQ1 / REQ3",
       "Top departamentos con más contratistas de actividad integral (amplitud=4)")

c2 <- con_contratistas$aggregate('[
  { "$match": { "amplitud_actividad_actual": 4 } },
  { "$lookup": {
      "from": "ubicaciones", "localField": "ubicacion_id",
      "foreignField": "id_ubicacion", "as": "ubic" } },
  { "$unwind": "$ubic" },
  { "$group": {
      "_id": { "departamento": "$ubic.departamento", "macrozona": "$ubic.macrozona" },
      "n_integral": { "$sum": 1 } } },
  { "$sort": { "n_integral": -1 } },
  { "$limit": 10 }
]')
c2 <- data.frame(
  departamento = c2$`_id`$departamento,
  macrozona    = c2$`_id`$macrozona,
  n_integral   = c2$n_integral
)
print(c2)
resultados$C2 <- c2

# ------------------------------------------------------------
# CONSULTA C3 — Contactabilidad por macrozona
# RN2 (contactabilidad) · RN3 · REQ2 (campañas de contacto)
# ------------------------------------------------------------
titulo("C3", "RN2 / RN3", "REQ2",
       "Contactabilidad (con/sin teléfono) por macrozona geográfica")

c3 <- con_contratistas$aggregate('[
  { "$lookup": {
      "from": "ubicaciones", "localField": "ubicacion_id",
      "foreignField": "id_ubicacion", "as": "ubic" } },
  { "$unwind": "$ubic" },
  { "$group": {
      "_id": "$ubic.macrozona",
      "total": { "$sum": 1 },
      "con_telefono": { "$sum": { "$cond": ["$indice_completitud_contacto", 1, 0] } }
  }}
]') %>%
  rename(macrozona = `_id`) %>%
  mutate(sin_telefono = total - con_telefono,
         pct_sin_telefono = round(sin_telefono / total * 100, 1))
print(c3)
resultados$C3 <- c3

# ------------------------------------------------------------
# CONSULTA C4 — Contratistas PRIORITARIOS para fiscalización
# RN4 (regla combinada) · REQ1 (priorización)
# Alta exposición (amplitud=4) + sin teléfono + en Regiones
# ------------------------------------------------------------
titulo("C4", "RN4 (RN1+RN2+RN3)", "REQ1",
       "Contratistas prioritarios: amplitud=4, sin teléfono y en Regiones")

# Se filtran primero las dos condiciones que NO dependen del join
# (amplitud y contacto) para reducir el conjunto antes del $lookup, y
# recién después se resuelve la ubicación y se filtra por macrozona.
# Ese $match inicial aprovecha el índice {amplitud_actividad_actual,
# indice_completitud_contacto} y el $lookup, el índice id_ubicacion.
c4 <- con_contratistas$aggregate('[
  { "$match": {
      "amplitud_actividad_actual": 4,
      "indice_completitud_contacto": false } },
  { "$lookup": {
      "from": "ubicaciones", "localField": "ubicacion_id",
      "foreignField": "id_ubicacion", "as": "ubic" } },
  { "$unwind": "$ubic" },
  { "$match": { "ubic.macrozona": "Regiones" } },
  { "$project": {
      "_id": 0, "ruc": 1, "razon_social": 1,
      "departamento": "$ubic.departamento",
      "provincia": "$ubic.provincia",
      "antiguedad_anios": 1, "num_autorizaciones": 1 } },
  { "$sort": { "antiguedad_anios": -1 } }
]')
cat("Total de contratistas prioritarios:", nrow(c4), "\n")
cat("Primeros 10 (por antigüedad):\n")
print(head(c4, 10))
resultados$C4 <- c4

# ------------------------------------------------------------
# CONSULTA C5 — Evolución anual del ingreso de nuevas empresas
# RN5 (dinamismo del sector) · REQ4 (monitoreo de evolución)
# Cuenta contratistas según el año de su PRIMER registro.
# ------------------------------------------------------------
titulo("C5", "RN5", "REQ4",
       "Evolución anual del ingreso de nuevas empresas al padrón (2008-2026)")

c5 <- con_contratistas$aggregate('[
  { "$group": {
      "_id": { "$year": "$fecha_primer_registro" },
      "nuevas_empresas": { "$sum": 1 } } },
  { "$sort": { "_id": 1 } }
]') %>%
  rename(anio = `_id`) %>%
  mutate(acumulado = cumsum(nuevas_empresas))
print(c5)
resultados$C5 <- c5

# ------------------------------------------------------------
# CONSULTA C6 — Relación amplitud de actividad vs frecuencia de renovación
# RN1 · RN5 · REQ5 (estrategias diferenciadas)
# ------------------------------------------------------------
titulo("C6", "RN1 / RN5", "REQ5",
       "Amplitud de actividad vs. antigüedad y frecuencia de renovación")

c6 <- con_contratistas$aggregate('[
  { "$group": {
      "_id": "$amplitud_actividad_actual",
      "n_contratistas": { "$sum": 1 },
      "antiguedad_prom": { "$avg": "$antiguedad_anios" },
      "renovaciones_prom": { "$avg": "$num_autorizaciones" },
      "recencia_prom": { "$avg": "$recencia_anios" } } },
  { "$sort": { "_id": 1 } }
]') %>%
  rename(amplitud_actividad = `_id`) %>%
  mutate(across(c(antiguedad_prom, renovaciones_prom, recencia_prom), ~ round(.x, 2)))
print(c6)
resultados$C6 <- c6

# ------------------------------------------------------------
# CONSULTA C7 — Empresas más dinámicas (con más renovaciones/ampliaciones)
# RN5 (dinamismo) · REQ1 / REQ4
# ------------------------------------------------------------
titulo("C7", "RN5", "REQ1 / REQ4",
       "Contratistas con mayor número de autorizaciones históricas (más dinámicos)")

c7 <- con_contratistas$find(
  query  = '{"num_autorizaciones": {"$gte": 2}}',
  fields = '{"_id":0, "ruc":1, "razon_social":1, "num_autorizaciones":1,
             "amplitud_actividad_actual":1, "antiguedad_anios":1}',
  sort   = '{"num_autorizaciones": -1, "antiguedad_anios": -1}',
  limit  = 15
)
cat("Contratistas con 2+ autorizaciones:",
    con_contratistas$count('{"num_autorizaciones": {"$gte": 2}}'), "\n")
print(c7)
resultados$C7 <- c7

# ------------------------------------------------------------
# CONSULTA C8 — Concentración geográfica global (para ubicar oficinas)
# RN3 · REQ3 (distribución de equipos de supervisión)
# ------------------------------------------------------------
titulo("C8", "RN3", "REQ3",
       "Concentración de contratistas por departamento (planificación de oficinas)")

c8 <- con_contratistas$aggregate('[
  { "$lookup": {
      "from": "ubicaciones", "localField": "ubicacion_id",
      "foreignField": "id_ubicacion", "as": "ubic" } },
  { "$unwind": "$ubic" },
  { "$group": {
      "_id": "$ubic.departamento",
      "n_contratistas": { "$sum": 1 },
      "n_alta_exposicion": { "$sum": { "$cond": [ { "$eq": ["$amplitud_actividad_actual", 4] }, 1, 0 ] } }
  }},
  { "$sort": { "n_contratistas": -1 } }
]') %>%
  rename(departamento = `_id`) %>%
  mutate(pct_del_total = round(n_contratistas / sum(n_contratistas) * 100, 1))
print(head(c8, 12))
resultados$C8 <- c8

# ------------------------------------------------------------
# Persistir todos los resultados para gráficos (e) y Shiny (f)
# ------------------------------------------------------------
saveRDS(resultados, file.path(DIR_SALIDAS, "consultas_resultados.rds"))
for (nm in names(resultados)) {
  write.csv(resultados[[nm]],
            file.path(DIR_SALIDAS, paste0("consulta_", nm, ".csv")),
            row.names = FALSE, fileEncoding = "UTF-8")
}

cat("\n============================================================\n")
cat("8 consultas de negocio ejecutadas y guardadas en fase3/salidas/.\n")
cat("============================================================\n")