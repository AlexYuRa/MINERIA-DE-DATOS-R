# ============================================================
# FASE III — Agregar UN contratista nuevo a la base MongoDB
# ------------------------------------------------------------
# Uso:
#   1) Edita la sección "1) DATOS DE LA EMPRESA".
#   2) Ejecuta desde la raíz del proyecto:
#        & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" fase3\agregar_contratista.R
#   3) Abre la app y presiona "Recalcular grupos de riesgo" para que el
#      nuevo contratista quede clasificado en un grupo.
#
# El script calcula solo los campos derivados (perfil de actividad,
# antigüedad, recencia, amplitud, nº de autorizaciones, contactabilidad),
# maneja las fechas como tipo Date nativo y valida RUC y ubicación.
# ============================================================

suppressMessages({ library(mongolite); library(jsonlite) })

URI <- "mongodb://localhost:27017"
BD  <- "contratistas_mineros_minem"
con_contratistas <- mongo("contratistas", db = BD, url = URI)
con_ubicaciones  <- mongo("ubicaciones",  db = BD, url = URI)

# ¿No sabes el id de la ubicación? Lista las de un departamento:
#   listar_ubicaciones("LIMA")
listar_ubicaciones <- function(depto = NULL) {
  q <- if (is.null(depto)) "{}" else sprintf('{"departamento": "%s"}', toupper(depto))
  con_ubicaciones$find(q, fields = '{"_id":0,"id_ubicacion":1,"departamento":1,
                                      "provincia":1,"distrito":1,"macrozona":1}')
}

# ============================================================
# 1) DATOS DE LA EMPRESA  — EDITA ESTO
# ============================================================
ruc           <- "20123456789"                 # RUC (11 dígitos, único)
razon_social  <- "NUEVA CONTRATISTA S.A.C."
ubicacion_id  <- 3                              # id de ubicaciones (1..216)
telefono      <- "044-123456"                   # "" si no tiene teléfono
representante <- "PEREZ GOMEZ JUAN"

# Autorizaciones (Resoluciones Directorales), en cualquier orden — el script
# las ordena por fecha. Una empresa nueva normalmente tiene una sola.
autorizaciones <- list(
  list(
    numero_resolucion = "123-2024-MINEM/DGM",
    fecha             = "15/03/2024",           # dd/mm/aaaa
    registro_minem    = "12345678",
    representante     = "PEREZ GOMEZ JUAN",
    exploracion = TRUE, explotacion = TRUE, desarrollo = FALSE, beneficio = FALSE
  )
  # , list(numero_resolucion = "...", fecha = "dd/mm/aaaa", ...)   # más R.D. aquí
)

# ============================================================
# 2) CÁLCULO E INSERCIÓN  — no necesitas tocar nada de aquí abajo
# ============================================================

# --- Validaciones ---
if (con_contratistas$count(sprintf('{"ruc": "%s"}', ruc)) > 0)
  stop("Ya existe un contratista con el RUC ", ruc)
if (con_ubicaciones$count(sprintf('{"id_ubicacion": %d}', as.integer(ubicacion_id))) == 0)
  stop("La ubicacion_id ", ubicacion_id,
       " no existe. Usa listar_ubicaciones('LIMA') para ver opciones válidas.")

clasificar_perfil <- function(amplitud) {
  if (amplitud >= 4) "actividad_integral"
  else if (amplitud >= 2) "multi_actividad_parcial"
  else if (amplitud == 1) "mono_actividad"
  else "sin_actividad"
}

iso <- function(d) list(`$date` = format(d, "%Y-%m-%dT00:00:00Z"))

# --- Historial embebido (ordenado por fecha) ---
fechas <- as.Date(vapply(autorizaciones, function(a) a$fecha, character(1)),
                  format = "%d/%m/%Y")
if (any(is.na(fechas))) stop("Alguna fecha no tiene el formato dd/mm/aaaa.")
orden <- order(fechas)

historial <- lapply(seq_along(orden), function(i) {
  a   <- autorizaciones[[orden[i]]]
  amp <- sum(a$exploracion, a$explotacion, a$desarrollo, a$beneficio)
  list(
    numero_resolucion       = a$numero_resolucion,
    fecha_resolucion        = iso(fechas[orden[i]]),
    registro_origen_minem   = a$registro_minem,
    representante_legal     = a$representante,
    actividades = list(exploracion = a$exploracion, explotacion = a$explotacion,
                       desarrollo  = a$desarrollo,  beneficio   = a$beneficio),
    amplitud_actividad      = amp,
    orden_cronologico       = i,
    es_autorizacion_vigente = (i == length(orden))
  )
})

# --- Campos derivados del contratista ---
hoy          <- Sys.Date()
fecha_primer <- min(fechas)
fecha_ultimo <- max(fechas)
amplitud_actual <- historial[[length(historial)]]$amplitud_actividad  # de la ÚLTIMA R.D.
tiene_tel <- nchar(trimws(telefono)) > 0

doc <- list(
  ruc                         = ruc,
  razon_social                = razon_social,
  ubicacion_id                = as.integer(ubicacion_id),
  telefono_referencia         = if (tiene_tel) trimws(telefono) else NA,
  representante_actual        = representante,
  fecha_primer_registro       = iso(fecha_primer),
  fecha_ultimo_registro       = iso(fecha_ultimo),
  antiguedad_anios            = round(as.numeric(hoy - fecha_primer) / 365.25, 2),
  recencia_anios              = round(as.numeric(hoy - fecha_ultimo) / 365.25, 2),
  num_autorizaciones          = length(historial),
  amplitud_actividad_actual   = amplitud_actual,
  perfil_actividad            = clasificar_perfil(amplitud_actual),
  indice_completitud_contacto = tiene_tel,
  segmento_id                 = NA,     # se asigna al recalcular los grupos
  activo                      = TRUE,
  historial_autorizaciones    = historial
)

con_contratistas$insert(toJSON(doc, auto_unbox = TRUE, na = "null"))

cat("\n Contratista agregado:", ruc, "-", razon_social, "\n")
cat(" Total de contratistas ahora:", con_contratistas$count(), "\n")
cat(" NOTA: quedó sin grupo de riesgo (segmento_id vacío).\n")
cat("       Presiona 'Recalcular grupos de riesgo' en la app (o corre\n")
cat("       04_patrones_clustering.R) para clasificarlo.\n")
