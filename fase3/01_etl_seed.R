# ============================================================
# FASE III — Paso 0: ETL de carga inicial (seed)
# Proyecto: Contratistas Mineros MINEM — MongoDB + R
# Implementa el ETL diseñado en la Fase II:
#   2.6.1   Extracción
#   2.6.2.1 Eliminación de duplicados exactos
#   2.6.2.2 Estandarización de tipos de datos
#   2.6.2.3 Conversión de indicadores de actividad a booleano
#   2.6.2.4 Normalización geográfica (catálogo Ubicacion)
#   2.6.2.5 Enriquecimiento del historial de autorizaciones
#   2.6.2.6 Agregación del perfil Contratista y armado del documento
#   2.6.3   Carga (solo inserta; único índice: ruc único)
# ============================================================

library(readxl)
library(dplyr)
library(lubridate)
library(stringr)
library(purrr)
library(mongolite)
library(jsonlite)

DIR_SALIDAS <- file.path("fase3", "salidas")

# ------------------------------------------------------------
# 2.6.1 EXTRACCIÓN
# ------------------------------------------------------------
extraer_contratistas_minem <- function(ruta_archivo) {

  if (!file.exists(ruta_archivo)) {
    stop("Archivo fuente no encontrado: ", ruta_archivo)
  }

  # El archivo de datosabiertos.gob.pe publica 5 filas de título
  # combinado antes de la fila real de encabezados (fila 6).
  df_crudo <- read_excel(ruta_archivo, skip = 5, col_names = TRUE)

  columnas_esperadas <- c("REGISTRO", "R.D", "FECHA R.D", "CONTRATISTA", "RUC",
                          "DOMICILIO", "DISTRITO", "PROVINCIA", "DEPARTAMENTO",
                          "TELEFONO", "REPRESENTANTE", "EXPLORACION",
                          "EXPLOTACION", "DESARROLLO", "BENEFICIO")

  if (!all(columnas_esperadas %in% colnames(df_crudo))) {
    stop("El esquema del archivo fuente no coincide con el esperado.")
  }

  if (nrow(df_crudo) == 0) {
    stop("El archivo no contiene registros.")
  }

  message("Extracción completada: ", nrow(df_crudo), " filas, ",
          ncol(df_crudo), " columnas.")

  saveRDS(df_crudo, file.path(DIR_SALIDAS, "01_extraido_crudo.rds"))
  return(df_crudo)
}

# ------------------------------------------------------------
# 2.6.2.1 ELIMINACIÓN DE DUPLICADOS EXACTOS
# ------------------------------------------------------------
eliminar_duplicados_exactos <- function(df_crudo) {
  filas_iniciales <- nrow(df_crudo)

  df_sin_duplicados <- df_crudo %>% distinct()

  filas_finales <- nrow(df_sin_duplicados)
  message("Duplicados eliminados: ", filas_iniciales - filas_finales,
          " (de ", filas_iniciales, " a ", filas_finales, " filas)")

  return(df_sin_duplicados)
}

# ------------------------------------------------------------
# 2.6.2.2 ESTANDARIZACIÓN DE TIPOS DE DATOS
# ------------------------------------------------------------
estandarizar_tipos <- function(df_sin_duplicados) {

  df_tipado <- df_sin_duplicados %>%
    mutate(
      fecha_resolucion = dmy(`FECHA R.D`),
      ruc = as.character(RUC),
      `R.D` = str_trim(`R.D`),
      CONTRATISTA = str_trim(CONTRATISTA),
      REPRESENTANTE = str_trim(REPRESENTANTE)
    )

  n_fechas_invalidas <- sum(is.na(df_tipado$fecha_resolucion))
  if (n_fechas_invalidas > 0) {
    warning(n_fechas_invalidas, " fecha(s) no pudieron ser convertidas.")
  }

  message("Estandarización completada: rango de fechas ",
          min(df_tipado$fecha_resolucion), " a ", max(df_tipado$fecha_resolucion))

  return(df_tipado)
}

# ------------------------------------------------------------
# 2.6.2.3 CONVERSIÓN DE INDICADORES DE ACTIVIDAD A BOOLEANO
# ------------------------------------------------------------
convertir_indicadores_booleanos <- function(df_tipado) {

  df_booleano <- df_tipado %>%
    mutate(
      autoriza_exploracion = !is.na(EXPLORACION),
      autoriza_explotacion = !is.na(EXPLOTACION),
      autoriza_desarrollo  = !is.na(DESARROLLO),
      autoriza_beneficio   = !is.na(BENEFICIO)
    )

  message("Conversión completada. % autorizado por actividad — ",
          "Exploración: ", round(mean(df_booleano$autoriza_exploracion) * 100, 1), "%, ",
          "Explotación: ", round(mean(df_booleano$autoriza_explotacion) * 100, 1), "%, ",
          "Desarrollo: ", round(mean(df_booleano$autoriza_desarrollo) * 100, 1), "%, ",
          "Beneficio: ", round(mean(df_booleano$autoriza_beneficio) * 100, 1), "%")

  return(df_booleano)
}

# ------------------------------------------------------------
# 2.6.2.4 NORMALIZACIÓN GEOGRÁFICA (CATÁLOGO UBICACION)
# ------------------------------------------------------------
normalizar_geografia <- function(df_booleano) {

  ubicaciones <- df_booleano %>%
    distinct(DISTRITO, PROVINCIA, DEPARTAMENTO) %>%
    mutate(
      macrozona = if_else(DEPARTAMENTO %in% c("LIMA", "CALLAO"),
                          "Lima_Callao", "Regiones"),
      id_ubicacion = row_number()
    ) %>%
    rename(distrito = DISTRITO, provincia = PROVINCIA, departamento = DEPARTAMENTO)

  df_con_ubicacion <- df_booleano %>%
    left_join(ubicaciones, by = c("DISTRITO" = "distrito",
                                  "PROVINCIA" = "provincia",
                                  "DEPARTAMENTO" = "departamento"))

  n_huerfanas <- sum(is.na(df_con_ubicacion$id_ubicacion))
  if (n_huerfanas > 0) warning(n_huerfanas, " fila(s) sin ubicación asociada.")

  message("Ubicaciones únicas: ", nrow(ubicaciones))

  return(list(ubicaciones = ubicaciones, df_con_ubicacion = df_con_ubicacion))
}

# ------------------------------------------------------------
# 2.6.2.5 ENRIQUECIMIENTO DEL HISTORIAL DE AUTORIZACIONES
# ------------------------------------------------------------
enriquecer_historial <- function(df_con_ubicacion) {

  historial <- df_con_ubicacion %>%
    mutate(
      amplitud_actividad = autoriza_exploracion + autoriza_explotacion +
                           autoriza_desarrollo + autoriza_beneficio
    ) %>%
    group_by(ruc) %>%
    arrange(fecha_resolucion, .by_group = TRUE) %>%
    mutate(
      orden_cronologico = row_number(),
      es_autorizacion_vigente = orden_cronologico == max(orden_cronologico)
    ) %>%
    ungroup() %>%
    rename(
      numero_resolucion     = `R.D`,
      registro_origen_minem = REGISTRO,
      representante_legal   = REPRESENTANTE,
      razon_social          = CONTRATISTA,
      telefono_registro     = TELEFONO
    )

  message("Historial enriquecido: ", nrow(historial), " autorizaciones, ",
          n_distinct(historial$ruc), " contratistas distintos.")

  return(historial)
}

# ------------------------------------------------------------
# 2.6.2.6 AGREGACIÓN DEL PERFIL CONTRATISTA Y ARMADO DEL DOCUMENTO
# ------------------------------------------------------------
agregar_contratista_y_armar_documento <- function(historial) {

  fecha_corte <- as.Date("2026-06-20")

  # 1. Agregación por RUC -> entidad Contratista
  contratistas <- historial %>%
    group_by(ruc) %>%
    summarise(
      razon_social              = first(razon_social),
      id_ubicacion              = first(id_ubicacion),
      telefono_referencia       = last(na.omit(c(telefono_registro, NA))[1]),
      representante_actual      = representante_legal[es_autorizacion_vigente][1],
      fecha_primer_registro     = min(fecha_resolucion),
      fecha_ultimo_registro     = max(fecha_resolucion),
      num_autorizaciones        = n(),
      amplitud_actividad_actual = amplitud_actividad[es_autorizacion_vigente][1],
      .groups = "drop"
    ) %>%
    mutate(
      antiguedad_anios = as.numeric(fecha_corte - fecha_primer_registro) / 365.25,
      recencia_anios   = as.numeric(fecha_corte - fecha_ultimo_registro) / 365.25,
      perfil_actividad = case_when(
        amplitud_actividad_actual == 4 ~ "actividad_integral",
        amplitud_actividad_actual == 1 ~ "mono_actividad",
        TRUE ~ "multi_actividad_parcial"
      ),
      indice_completitud_contacto = !is.na(telefono_referencia),
      id_segmento_riesgo = NA_character_   # se asigna en Fase III
    )

  # 2. Armado del documento anidado (listo para que Carga solo lo inserte).
  #    Las fechas se envuelven en {"$date": ...} para que MongoDB las
  #    almacene como tipo Date nativo y no como texto.
  fecha_mongo <- function(f) list(`$date` = format(f, "%Y-%m-%dT00:00:00Z"))

  documentos_mongo <- contratistas %>%
    split(seq(nrow(.))) %>%
    map(function(empresa) {
      hist_empresa <- historial %>%
        filter(ruc == empresa$ruc) %>%
        arrange(orden_cronologico)

      historial_lista <- lapply(seq_len(nrow(hist_empresa)), function(i) {
        fila <- hist_empresa[i, ]
        list(
          numero_resolucion     = fila$numero_resolucion,
          fecha_resolucion      = fecha_mongo(fila$fecha_resolucion),
          registro_origen_minem = as.character(fila$registro_origen_minem),
          representante_legal   = fila$representante_legal,
          actividades = list(
            exploracion = fila$autoriza_exploracion,
            explotacion = fila$autoriza_explotacion,
            desarrollo  = fila$autoriza_desarrollo,
            beneficio   = fila$autoriza_beneficio
          ),
          amplitud_actividad      = fila$amplitud_actividad,
          orden_cronologico       = fila$orden_cronologico,
          es_autorizacion_vigente = fila$es_autorizacion_vigente
        )
      })

      list(
        ruc                          = empresa$ruc,
        razon_social                 = empresa$razon_social,
        ubicacion_id                 = empresa$id_ubicacion,
        telefono_referencia          = empresa$telefono_referencia,
        representante_actual         = empresa$representante_actual,
        fecha_primer_registro        = fecha_mongo(empresa$fecha_primer_registro),
        fecha_ultimo_registro        = fecha_mongo(empresa$fecha_ultimo_registro),
        antiguedad_anios             = round(empresa$antiguedad_anios, 2),
        recencia_anios               = round(empresa$recencia_anios, 2),
        num_autorizaciones           = empresa$num_autorizaciones,
        amplitud_actividad_actual    = empresa$amplitud_actividad_actual,
        perfil_actividad             = empresa$perfil_actividad,
        indice_completitud_contacto  = empresa$indice_completitud_contacto,
        segmento_id                  = NA,   # se asigna en Fase III
        historial_autorizaciones     = historial_lista
      )
    })

  message("Agregación completada: ", nrow(contratistas), " contratistas, ",
          length(documentos_mongo), " documentos armados y listos para Carga.")

  saveRDS(contratistas, file.path(DIR_SALIDAS, "03_contratistas.rds"))
  saveRDS(documentos_mongo, file.path(DIR_SALIDAS, "03_documentos_mongo.rds"))

  return(list(contratistas = contratistas, documentos_mongo = documentos_mongo))
}

# ------------------------------------------------------------
# 2.6.3 CARGA
# (Solo inserta lo ya armado en 2.6.2.6. Único índice de Fase II:
#  ruc único. Los índices de optimización analítica de la sección
#  2.5.4 se definirán en Fase III según las consultas reales.)
# ------------------------------------------------------------
cargar_contratistas_minem <- function(ubicaciones, documentos_mongo,
                                      uri_mongo = "mongodb://localhost:27017",
                                      base_datos = "contratistas_mineros_minem") {

  # 1. Cargar catálogo de ubicaciones (ya construido en 2.6.2.4)
  col_ubicaciones <- mongo(collection = "ubicaciones", db = base_datos, url = uri_mongo)
  col_ubicaciones$drop()
  col_ubicaciones$insert(ubicaciones)

  # 1b. Índice sobre el campo de resolución del $lookup geográfico.
  #     Las consultas C2/C3/C4/C8 y la extracción de predictoras del
  #     clustering unen contratistas.ubicacion_id -> ubicaciones.id_ubicacion.
  #     El motor de MongoDB solo aprovecha un índice sobre el 'foreignField'
  #     (id_ubicacion, aquí), NO sobre el 'localField'; por eso el índice de
  #     optimización del join se define en la colección 'ubicaciones'.
  col_ubicaciones$run(paste0(
    '{"createIndexes": "ubicaciones", ',
    '"indexes": [{"key": {"id_ubicacion": 1}, "name": "id_ubicacion_1"}]}'
  ))

  # 2. Inicializar colección de segmentos de riesgo (vacía; se puebla en Fase III)
  col_segmentos <- mongo(collection = "segmentos_riesgo", db = base_datos, url = uri_mongo)
  col_segmentos$drop()
  message("Colección 'segmentos_riesgo' inicializada sin datos (pendiente del clustering de Fase III).")

  # 3. Insertar los documentos ya armados en 2.6.2.6 (sin transformarlos)
  col_contratistas <- mongo(collection = "contratistas", db = base_datos, url = uri_mongo)
  col_contratistas$drop()
  json_docs <- vapply(documentos_mongo,
                      function(doc) as.character(toJSON(doc, auto_unbox = TRUE, na = "null")),
                      character(1))
  col_contratistas$insert(json_docs)

  # 4. Índices de la colección 'contratistas'.
  #    mongolite >= 4.0 ya no acepta el argumento 'options' en $index(),
  #    por lo que los índices se crean con el comando nativo createIndexes.
  #    - ruc (único): regla de integridad de la llave natural (RI-4), carga idempotente.
  #    - {amplitud_actividad_actual, indice_completitud_contacto} (compuesto): acelera
  #      el filtro de priorización de C2/C4 (empresas de alta exposición sin contacto),
  #      la consulta que identifica a los contratistas prioritarios de fiscalización.
  #    El índice sobre segmento_id se crea en 04_patrones_clustering.R, una vez que el
  #    clustering puebla ese campo (en esta etapa nace nulo para todos los documentos).
  col_contratistas$run(paste0(
    '{"createIndexes": "contratistas", ',
    '"indexes": [',
    '{"key": {"ruc": 1}, "name": "ruc_1", "unique": true},',
    '{"key": {"amplitud_actividad_actual": 1, "indice_completitud_contacto": 1}, "name": "amplitud_contacto_1"}',
    ']}'
  ))

  message("Carga completada: ", col_contratistas$count(), " contratistas insertados en '",
          base_datos, ".contratistas'. Índices de optimización analítica (sección 2.5.4) ",
          "creados según los patrones de consulta reales de la Fase III.")

  invisible(list(ubicaciones = col_ubicaciones$count(),
                 contratistas = col_contratistas$count(),
                 segmentos_riesgo = col_segmentos$count()))
}

# ------------------------------------------------------------
# EJECUCIÓN ENCADENADA (2.6.1 -> 2.6.2.1 ... 2.6.2.6 -> 2.6.3)
# ------------------------------------------------------------
if (sys.nframe() == 0) {
  dir.create(DIR_SALIDAS, recursive = TRUE, showWarnings = FALSE)

  ruta <- list.files(pattern = "^Contratistas_Mineros.*\\.xlsx$")[1]
  if (is.na(ruta)) stop("No se encontró el archivo Excel del dataset en el directorio actual.")
  message("Archivo fuente: ", ruta)

  df_crudo          <- extraer_contratistas_minem(ruta)                 # 2.6.1
  df_sin_duplicados <- eliminar_duplicados_exactos(df_crudo)            # 2.6.2.1
  df_tipado         <- estandarizar_tipos(df_sin_duplicados)            # 2.6.2.2
  df_booleano       <- convertir_indicadores_booleanos(df_tipado)       # 2.6.2.3
  geo               <- normalizar_geografia(df_booleano)                # 2.6.2.4
  historial         <- enriquecer_historial(geo$df_con_ubicacion)       # 2.6.2.5
  resultado         <- agregar_contratista_y_armar_documento(historial) # 2.6.2.6
  cargar_contratistas_minem(geo$ubicaciones, resultado$documentos_mongo) # 2.6.3
}
