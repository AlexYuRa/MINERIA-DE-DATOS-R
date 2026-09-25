# ============================================================
# FASE III — Evidencia: exportar el dataset transformado por el ETL
#             a formato .xlsx para entrega académica.
# ------------------------------------------------------------
# Toma la salida de 01_etl_seed.R (guardada en fase3/salidas/*.rds)
# y la vuelca en un único Excel con dos hojas:
#   1) contratistas_transformado : tabla agregada por RUC, resultado
#      final del paso 2.6.2.6 (perfil, ubicación, contacto, etc.)
#   2) historial_autorizaciones  : historial enriquecido (2.6.2.5),
#      reconstruido a partir de los documentos ya anidados.
# No vuelve a ejecutar el ETL ni requiere conexión a MongoDB:
# solo lee los .rds que 01_etl_seed.R ya dejó en fase3/salidas.
# ============================================================

if (!requireNamespace("writexl", quietly = TRUE)) {
  install.packages("writexl")
}

suppressMessages({
  library(dplyr)
  library(purrr)
  library(writexl)
})

DIR_SALIDAS <- file.path("fase3", "salidas")

ruta_contratistas <- file.path(DIR_SALIDAS, "03_contratistas.rds")
ruta_documentos    <- file.path(DIR_SALIDAS, "03_documentos_mongo.rds")

if (!file.exists(ruta_contratistas) || !file.exists(ruta_documentos)) {
  stop("No se encontraron ", ruta_contratistas, " / ", ruta_documentos,
       ". Ejecuta primero fase3/01_etl_seed.R para generarlos.")
}

contratistas    <- readRDS(ruta_contratistas)
documentos_mongo <- readRDS(ruta_documentos)

# Reconstruir el historial enriquecido en formato plano (una fila por
# autorización) a partir del historial anidado dentro de cada documento.
historial_plano <- map_dfr(documentos_mongo, function(doc) {
  map_dfr(doc$historial_autorizaciones, function(h) {
    data.frame(
      ruc                     = doc$ruc,
      razon_social            = doc$razon_social,
      numero_resolucion       = h$numero_resolucion,
      fecha_resolucion        = as.Date(substr(h$fecha_resolucion$`$date`, 1, 10)),
      registro_origen_minem   = h$registro_origen_minem,
      representante_legal     = h$representante_legal,
      exploracion             = h$actividades$exploracion,
      explotacion             = h$actividades$explotacion,
      desarrollo              = h$actividades$desarrollo,
      beneficio               = h$actividades$beneficio,
      amplitud_actividad      = h$amplitud_actividad,
      orden_cronologico       = h$orden_cronologico,
      es_autorizacion_vigente = h$es_autorizacion_vigente,
      stringsAsFactors = FALSE
    )
  })
})

ruta_salida <- file.path(DIR_SALIDAS, "evidencia_etl_transformado.xlsx")

write_xlsx(
  list(
    contratistas_transformado = contratistas,
    historial_autorizaciones  = historial_plano
  ),
  path = ruta_salida
)

message("Evidencia exportada: ", ruta_salida, " (",
        nrow(contratistas), " contratistas, ",
        nrow(historial_plano), " autorizaciones)")
