# ============================================================
# FASE III — f) Frontend Shiny · configuración global
# Conexión a MongoDB y funciones auxiliares compartidas por
# ui.R y server.R.
# ============================================================

suppressMessages({
  library(shiny)
  library(shinydashboard)
  library(DT)
  library(mongolite)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
})

URI <- "mongodb://localhost:27017"
BD  <- "contratistas_mineros_minem"

# Conexiones: se crean UNA sola vez por colección y se reutilizan en toda la app,
# en lugar de abrir y descartar una conexión nueva en cada operación.
.conexiones <- new.env(parent = emptyenv())
mongo_col <- function(coleccion) {
  if (is.null(.conexiones[[coleccion]])) {
    .conexiones[[coleccion]] <- mongo(collection = coleccion, db = BD, url = URI)
  }
  .conexiones[[coleccion]]
}

col_contratistas <- function() mongo_col("contratistas")
col_ubicaciones  <- function() mongo_col("ubicaciones")
col_segmentos    <- function() mongo_col("segmentos_riesgo")

# Sistema de color de la app (tokens R, espejo de las variables CSS de ui.R).
# La escala de prioridad es monótona en luminosidad (segura para daltonismo):
# el nivel siempre se acompaña de su etiqueta de texto, no depende solo del color.
COLOR_PRIORIDAD <- c("Muy Alta" = "#8f2d1e",  # ladrillo profundo
                     "Alta"     = "#c0562a",  # naranja quemado
                     "Media"    = "#c98a3c",  # ocre
                     "Baja"     = "#8795a1")  # pizarra neutra
# Paleta institucional para los gráficos (unifica los tres azules previos)
COL_ACENTO  <- "#0d6b73"  # teal institucional
COL_ALERTA  <- "#a8412a"  # rust (segunda serie / "sin contacto")
COL_NEUTRO  <- "#8795a1"  # pizarra neutra

# ------------------------------------------------------------
# Lecturas base (con join a ubicación y segmento) para la tabla
# y los filtros del explorador.
# ------------------------------------------------------------
leer_contratistas <- function() {
  col_contratistas()$aggregate('[
    { "$lookup": { "from": "ubicaciones", "localField": "ubicacion_id",
        "foreignField": "id_ubicacion", "as": "u" } },
    { "$unwind": "$u" },
    { "$lookup": { "from": "segmentos_riesgo", "localField": "segmento_id",
        "foreignField": "id_segmento", "as": "s" } },
    { "$unwind": { "path": "$s", "preserveNullAndEmptyArrays": true } },
    { "$project": {
        "_id": 0, "ruc": 1, "razon_social": 1,
        "departamento": "$u.departamento", "provincia": "$u.provincia",
        "distrito": "$u.distrito", "macrozona": "$u.macrozona",
        "perfil_actividad": 1, "amplitud_actividad_actual": 1,
        "num_autorizaciones": 1, "antiguedad_anios": 1, "recencia_anios": 1,
        "telefono_referencia": 1, "indice_completitud_contacto": 1,
        "representante_actual": 1,
        "segmento_id": 1,
        "segmento": "$s.nombre_segmento",
        "prioridad": "$s.nivel_prioridad_fiscalizacion",
        "activo": { "$ifNull": ["$activo", true] } } }
  ]')
}

leer_segmentos <- function() {
  col_segmentos()$find('{}', sort = '{"id_segmento": 1}')
}

leer_ubicaciones <- function() col_ubicaciones()$find('{}')

# Historial embebido de un contratista por RUC
leer_historial <- function(ruc) {
  doc <- col_contratistas()$iterate(sprintf('{"ruc": "%s"}', ruc))$one()
  if (is.null(doc) || is.null(doc$historial_autorizaciones)) return(NULL)
  do.call(rbind, lapply(doc$historial_autorizaciones, function(h) {
    data.frame(
      orden = h$orden_cronologico,
      numero_resolucion = h$numero_resolucion,
      fecha = format(as.Date(h$fecha_resolucion), "%d/%m/%Y"),
      representante = h$representante_legal,
      amplitud = h$amplitud_actividad,
      vigente = ifelse(isTRUE(h$es_autorizacion_vigente), "Sí", "No"),
      stringsAsFactors = FALSE)
  }))
}

# ------------------------------------------------------------
# MANIPULACIÓN DE DATOS (CRUD sobre MongoDB desde la interfaz)
# ------------------------------------------------------------

# Actualizar teléfono de referencia (y recalcular la contactabilidad)
actualizar_telefono <- function(ruc, telefono) {
  telefono <- trimws(telefono)
  tiene <- nchar(telefono) > 0
  col_contratistas()$update(
    query  = sprintf('{"ruc": "%s"}', ruc),
    update = sprintf('{"$set": {"telefono_referencia": %s,
                      "indice_completitud_contacto": %s}}',
                     if (tiene) sprintf('"%s"', telefono) else "null",
                     tolower(as.character(tiene)))
  )
}

# Baja LÓGICA: en un padrón regulatorio no se elimina físicamente un
# contratista (se perdería el registro y su historial). Se marca como
# inactivo mediante un campo `activo`, operación reversible.
marcar_inactivo <- function(ruc) {
  col_contratistas()$update(
    query  = sprintf('{"ruc": "%s"}', ruc),
    update = '{"$set": {"activo": false}}'
  )
}
reactivar_contratista <- function(ruc) {
  col_contratistas()$update(
    query  = sprintf('{"ruc": "%s"}', ruc),
    update = '{"$set": {"activo": true}}'
  )
}

# Reasignar manualmente el segmento de un contratista
reasignar_segmento <- function(ruc, id_segmento) {
  col_contratistas()$update(
    query  = sprintf('{"ruc": "%s"}', ruc),
    update = sprintf('{"$set": {"segmento_id": %d}}', as.integer(id_segmento))
  )
}

# CREAR un contratista nuevo (una autorización inicial). Calcula los campos
# derivados (perfil, antigüedad, recencia, amplitud, contactabilidad) y guarda
# las fechas como tipo Date nativo (envoltura {"$date": ...}). Devuelve TRUE si
# se insertó. `segmento_id` nace nulo: se asigna al recalcular los grupos.
crear_contratista <- function(ruc, razon_social, ubicacion_id, telefono,
                              representante, numero_resolucion, fecha_resolucion,
                              registro_minem, exploracion, explotacion,
                              desarrollo, beneficio) {
  amp <- sum(exploracion, explotacion, desarrollo, beneficio)
  perfil <- if (amp >= 4) "actividad_integral"
            else if (amp >= 2) "multi_actividad_parcial"
            else if (amp == 1) "mono_actividad"
            else "sin_actividad"
  iso   <- function(d) list(`$date` = format(as.Date(d), "%Y-%m-%dT00:00:00Z"))
  fecha <- as.Date(fecha_resolucion)
  hoy   <- Sys.Date()
  tel   <- trimws(telefono)
  tiene_tel <- nchar(tel) > 0

  historial <- list(list(
    numero_resolucion       = numero_resolucion,
    fecha_resolucion        = iso(fecha),
    registro_origen_minem   = registro_minem,
    representante_legal     = representante,
    actividades = list(exploracion = exploracion, explotacion = explotacion,
                       desarrollo  = desarrollo,  beneficio   = beneficio),
    amplitud_actividad      = amp,
    orden_cronologico       = 1L,
    es_autorizacion_vigente = TRUE
  ))

  doc <- list(
    ruc                         = ruc,
    razon_social                = razon_social,
    ubicacion_id                = as.integer(ubicacion_id),
    telefono_referencia         = if (tiene_tel) tel else NA,
    representante_actual        = representante,
    fecha_primer_registro       = iso(fecha),
    fecha_ultimo_registro       = iso(fecha),
    antiguedad_anios            = round(as.numeric(hoy - fecha) / 365.25, 2),
    recencia_anios              = round(as.numeric(hoy - fecha) / 365.25, 2),
    num_autorizaciones          = 1L,
    amplitud_actividad_actual   = amp,
    perfil_actividad            = perfil,
    indice_completitud_contacto = tiene_tel,
    segmento_id                 = NA,
    activo                      = TRUE,
    historial_autorizaciones    = historial
  )
  col_contratistas()$insert(jsonlite::toJSON(doc, auto_unbox = TRUE, na = "null"))
  invisible(TRUE)
}

# Explicación del puntaje de prioridad (0–1), en lenguaje de supervisor.
TEXTO_INDICE_RIESGO <- paste(
  "El puntaje de prioridad (de 0 a 1) resume, en un solo número, qué tan urgente es",
  "supervisar a cada grupo. Combina cuatro criterios: cuántas actividades mineras",
  "tiene autorizadas la empresa (a mayor alcance, mayor riesgo), si tiene o no",
  "teléfono de contacto, si opera en Regiones —donde la inspección presencial es más",
  "costosa— y hace cuánto no renueva su autorización. A mayor puntaje, antes debe",
  "fiscalizarse el grupo.")

# Acción de fiscalización recomendada por nivel de prioridad. Traduce el
# resultado del clustering en una decisión operativa para el funcionario DGM.
ACCION_PRIORIDAD <- c(
  "Muy Alta" = "Fiscalizar primero. Alta exposición operativa y difícil seguimiento: programar inspección presencial prioritaria y verificar vigencia.",
  "Alta"     = "Fiscalización preferente dentro del ciclo regular. Confirmar datos de contacto y actividad reciente antes de programar visita.",
  "Media"    = "Seguimiento periódico. Incluir en campañas de actualización de datos y revisar ante cambios en su actividad.",
  "Baja"     = "Seguimiento rutinario. Menor prioridad relativa de inspección presencial; monitoreo documental estándar."
)

# ------------------------------------------------------------
# RECÁLCULO DE LOS GRUPOS DE RIESGO (clustering) desde la interfaz.
# Reproduce la lógica de 04_patrones_clustering.R, pero trabajando solo
# contra MongoDB (sin escribir archivos). Se invoca desde el botón
# "Recalcular grupos" tras editar datos. IMPORTANTE: debe mantenerse en
# sincronía con 04_patrones_clustering.R (misma semilla, variables,
# ponderaciones y reglas de etiquetado).
recalcular_grupos <- function() {
  set.seed(2026)
  cc <- col_contratistas()
  cs <- col_segmentos()

  # Solo se agrupan los contratistas ACTIVOS: un contratista dado de baja no
  # es objetivo de fiscalización, no debe influir en los grupos ni contarse.
  datos <- cc$aggregate('[
    { "$match": { "activo": { "$ne": false } } },
    { "$lookup": { "from": "ubicaciones", "localField": "ubicacion_id",
        "foreignField": "id_ubicacion", "as": "ubic" } },
    { "$unwind": "$ubic" },
    { "$project": {
        "_id": 0, "ruc": 1,
        "amplitud_actividad_actual": 1, "num_autorizaciones": 1,
        "antiguedad_anios": 1, "recencia_anios": 1,
        "contacto": { "$cond": ["$indice_completitud_contacto", 1, 0] },
        "es_regiones": { "$cond": [ { "$eq": ["$ubic.macrozona", "Regiones"] }, 1, 0 ] } } }
  ]')

  # Orden fijo por RUC: k-means depende del orden de las filas y MongoDB no
  # garantiza un orden estable entre lecturas. Ordenar hace el resultado
  # reproducible (siempre el mismo con los mismos datos).
  datos <- datos[order(datos$ruc), ]

  vars <- c("amplitud_actividad_actual", "num_autorizaciones",
            "antiguedad_anios", "recencia_anios", "contacto", "es_regiones")
  X  <- scale(datos[, vars])
  # Reproduce la secuencia de 04_patrones_clustering.R: la evaluación de
  # k = 2..8 consume el generador aleatorio antes del ajuste final; se
  # repite aquí para obtener EXACTAMENTE la misma partición canónica.
  for (k in 2:8) kmeans(X, centers = k, nstart = 25, iter.max = 100)
  km <- kmeans(X, centers = 4, nstart = 50, iter.max = 100)
  datos$cluster <- km$cluster

  perfil <- datos %>%
    group_by(cluster) %>%
    summarise(
      n = n(),
      amplitud     = round(mean(amplitud_actividad_actual), 2),
      renovaciones = round(mean(num_autorizaciones), 2),
      antiguedad   = round(mean(antiguedad_anios), 1),
      recencia     = round(mean(recencia_anios), 1),
      pct_con_contacto = round(mean(contacto) * 100, 1),
      pct_regiones     = round(mean(es_regiones) * 100, 1),
      .groups = "drop") %>%
    mutate(
      indice_riesgo = (amplitud / 4) * 0.40 +
        ((100 - pct_con_contacto) / 100) * 0.25 +
        (pct_regiones / 100) * 0.20 +
        pmin(recencia / max(recencia), 1) * 0.15,
      indice_riesgo = round(indice_riesgo, 3))

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

  perfil <- perfil %>%
    arrange(desc(indice_riesgo)) %>%
    mutate(rank_riesgo = row_number(),
           nivel_prioridad_fiscalizacion = case_when(
             rank_riesgo == 1 ~ "Muy Alta",
             rank_riesgo == 2 ~ "Alta",
             rank_riesgo == 3 ~ "Media",
             TRUE             ~ "Baja"))

  perfil$descripcion <- with(perfil, sprintf(
    "Segmento con amplitud promedio %.1f/4, %.0f%% con contacto telefónico, %.0f%% en Regiones, antigüedad promedio %.1f años y recencia %.1f años. Agrupa %d contratistas.",
    amplitud, pct_con_contacto, pct_regiones, antiguedad, recencia, n))

  cs$drop()
  fecha_hoy <- format(Sys.Date(), "%Y-%m-%dT00:00:00Z")
  mapa_id <- list()
  for (i in seq_len(nrow(perfil))) {
    id_segmento <- perfil$rank_riesgo[i]
    mapa_id[[as.character(perfil$cluster[i])]] <- id_segmento
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
      algoritmo_utilizado           = "k-means (k=4, nstart=50)")
    cs$insert(jsonlite::toJSON(doc, auto_unbox = TRUE))
  }

  datos$id_segmento <- vapply(datos$cluster,
                              function(c) mapa_id[[as.character(c)]], numeric(1))
  for (i in seq_len(nrow(datos))) {
    cc$update(
      query  = sprintf('{"ruc": "%s"}', datos$ruc[i]),
      update = sprintf('{"$set": {"segmento_id": %d}}', as.integer(datos$id_segmento[i])))
  }
  invisible(nrow(datos))
}

# Catálogo de reportes disponibles desde la interfaz. Cada uno se presenta al
# usuario (analista/supervisor) con un nombre en lenguaje llano y una explicación
# de QUÉ responde y QUÉ decisión de fiscalización ayuda a tomar. El campo `id`
# es de uso interno (identifica la consulta a ejecutar) y no se muestra.
CONSULTAS <- list(
  "Contratistas por nivel de exposición" = list(id = "C1",
    desc = "Cuántas empresas hay según cuántas actividades mineras tienen autorizadas, desde alcance parcial hasta actividad integral.",
    accion = "Dimensiona cuántas empresas son de alto alcance para decidir cuánto esfuerzo de supervisión requieren."),
  "Departamentos con más empresas de alto alcance" = list(id = "C2",
    desc = "En qué departamentos se concentran las empresas autorizadas para las cuatro actividades mineras (las de mayor exposición).",
    accion = "Orienta hacia dónde desplegar los equipos de inspección."),
  "Contactabilidad por zona (Lima/Callao y Regiones)" = list(id = "C3",
    desc = "Qué proporción de empresas tiene o no teléfono de contacto, comparando Lima y Callao con el resto de Regiones.",
    accion = "Focaliza las campañas de actualización de datos de contacto donde la brecha es mayor."),
  "Contratistas prioritarios para fiscalizar" = list(id = "C4",
    desc = "Lista de las empresas que combinan alto alcance de actividad, sin teléfono de contacto y ubicadas en Regiones.",
    accion = "Es la lista corta para fiscalizar primero: mayor riesgo y mayor dificultad de seguimiento."),
  "Ingreso de nuevas empresas por año" = list(id = "C5",
    desc = "Cuántas empresas nuevas ingresaron al padrón cada año, y el total acumulado.",
    accion = "Permite anticipar la carga de supervisión según cómo crece el sector."),
  "Exposición según antigüedad y renovaciones" = list(id = "C6",
    desc = "Cómo se relaciona el alcance de actividad con la antigüedad de la empresa y su frecuencia de renovación.",
    accion = "Ayuda a diferenciar el trato según el perfil y la trayectoria de cada grupo de empresas."),
  "Empresas más activas (más renovaciones)" = list(id = "C7",
    desc = "Empresas con más autorizaciones a lo largo del tiempo (renovaciones o ampliaciones), señal de mayor actividad.",
    accion = "Identifica a los actores más activos y recurrentes, que conviene seguir de cerca."),
  "Concentración de empresas por departamento" = list(id = "C8",
    desc = "Cuántas empresas hay en cada departamento y cuántas de ellas son de alto alcance.",
    accion = "Es la base para ubicar oficinas y repartir la capacidad de supervisión por el territorio.")
)

ejecutar_consulta <- function(clave) {
  cc <- col_contratistas()
  # `clave` puede ser el nombre visible del reporte o directamente el id interno
  id <- if (!is.null(CONSULTAS[[clave]])) CONSULTAS[[clave]]$id else clave
  # Todos los reportes excluyen a los contratistas dados de baja (inactivos).
  # "activo": {"$ne": false} incluye a los activos y a los que aún no tienen el
  # campo (ausencia = activo).
  switch(id,
    "C1" = cc$aggregate('[{"$match":{"activo":{"$ne":false}}},
             {"$group":{"_id":"$perfil_actividad","n":{"$sum":1}}},{"$sort":{"n":-1}}]') %>%
             rename(perfil_actividad = `_id`, n_contratistas = n),
    "C2" = { r <- cc$aggregate('[{"$match":{"activo":{"$ne":false},"amplitud_actividad_actual":4}},
              {"$lookup":{"from":"ubicaciones","localField":"ubicacion_id","foreignField":"id_ubicacion","as":"u"}},
              {"$unwind":"$u"},{"$group":{"_id":"$u.departamento","n_integral":{"$sum":1}}},
              {"$sort":{"n_integral":-1}},{"$limit":10}]')
              data.frame(departamento = r$`_id`, n_integral = r$n_integral) },
    "C3" = cc$aggregate('[{"$match":{"activo":{"$ne":false}}},
              {"$lookup":{"from":"ubicaciones","localField":"ubicacion_id","foreignField":"id_ubicacion","as":"u"}},
              {"$unwind":"$u"},{"$group":{"_id":"$u.macrozona","total":{"$sum":1},
              "con_telefono":{"$sum":{"$cond":["$indice_completitud_contacto",1,0]}}}}]') %>%
              rename(macrozona = `_id`) %>% mutate(sin_telefono = total - con_telefono,
              pct_sin_telefono = round(sin_telefono/total*100,1)),
    "C4" = cc$aggregate('[{"$match":{"activo":{"$ne":false},"amplitud_actividad_actual":4,"indice_completitud_contacto":false}},
              {"$lookup":{"from":"ubicaciones","localField":"ubicacion_id","foreignField":"id_ubicacion","as":"u"}},
              {"$unwind":"$u"},{"$match":{"u.macrozona":"Regiones"}},
              {"$project":{"_id":0,"ruc":1,"razon_social":1,"departamento":"$u.departamento","antiguedad_anios":1}},
              {"$sort":{"antiguedad_anios":-1}}]'),
    "C5" = cc$aggregate('[{"$match":{"activo":{"$ne":false}}},
              {"$group":{"_id":{"$year":"$fecha_primer_registro"},"nuevas_empresas":{"$sum":1}}},{"$sort":{"_id":1}}]') %>%
              rename(anio = `_id`) %>% mutate(acumulado = cumsum(nuevas_empresas)),
    "C6" = cc$aggregate('[{"$match":{"activo":{"$ne":false}}},
              {"$group":{"_id":"$amplitud_actividad_actual","n_contratistas":{"$sum":1},
              "antiguedad_prom":{"$avg":"$antiguedad_anios"},"renovaciones_prom":{"$avg":"$num_autorizaciones"}}},{"$sort":{"_id":1}}]') %>%
              rename(amplitud = `_id`) %>% mutate(across(c(antiguedad_prom, renovaciones_prom), ~round(.x,2))),
    "C7" = cc$find('{"num_autorizaciones":{"$gte":2},"activo":{"$ne":false}}',
              fields = '{"_id":0,"ruc":1,"razon_social":1,"num_autorizaciones":1,"amplitud_actividad_actual":1}',
              sort = '{"num_autorizaciones":-1}', limit = 20),
    "C8" = { r <- cc$aggregate('[{"$match":{"activo":{"$ne":false}}},
              {"$lookup":{"from":"ubicaciones","localField":"ubicacion_id","foreignField":"id_ubicacion","as":"u"}},
              {"$unwind":"$u"},{"$group":{"_id":"$u.departamento","n_contratistas":{"$sum":1},
              "n_alta_exposicion":{"$sum":{"$cond":[{"$eq":["$amplitud_actividad_actual",4]},1,0]}}}},{"$sort":{"n_contratistas":-1}}]')
              data.frame(departamento = r$`_id`, n_contratistas = r$n_contratistas, n_alta_exposicion = r$n_alta_exposicion) }
  )
}
