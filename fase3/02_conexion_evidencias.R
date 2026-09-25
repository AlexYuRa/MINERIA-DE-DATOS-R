# ============================================================
# FASE III — a) Integración de la BD con R
# Conexión R <-> MongoDB y evidencias de la integración
# BD: contratistas_mineros_minem (poblada por 01_etl_seed.R)
# ============================================================

library(mongolite)

URI  <- "mongodb://localhost:27017"
BD   <- "contratistas_mineros_minem"

cat("==============================================================\n")
cat(" EVIDENCIA DE CONEXIÓN R <-> MongoDB\n")
cat(" Fecha/hora de ejecución:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(" R:", R.version.string, "\n")
cat(" Paquete: mongolite", as.character(packageVersion("mongolite")), "\n")
cat(" URI:", URI, " | Base de datos:", BD, "\n")
cat("==============================================================\n\n")

# --- 1. Conexión a cada colección del modelo (Fase II, sección 2.5)
con_contratistas <- mongo(collection = "contratistas",     db = BD, url = URI)
con_ubicaciones  <- mongo(collection = "ubicaciones",      db = BD, url = URI)
con_segmentos    <- mongo(collection = "segmentos_riesgo", db = BD, url = URI)

cat("[OK] Conexión establecida con las 3 colecciones del modelo.\n\n")

# --- 2. Evidencia: conteo de documentos por colección
cat("Documentos por colección:\n")
cat("  - contratistas     :", con_contratistas$count(), "\n")
cat("  - ubicaciones      :", con_ubicaciones$count(), "\n")
cat("  - segmentos_riesgo :", con_segmentos$count(),
    "(vacía: se puebla tras el clustering)\n\n")

# --- 3. Evidencia: documento de ejemplo (primer contratista)
cat("Documento de ejemplo (colección 'contratistas'):\n")
ejemplo <- con_contratistas$iterate(limit = 1)$one()
str(ejemplo, max.level = 2)

# --- 4. Evidencia: índices creados
cat("\nÍndices en 'contratistas':\n")
print(con_contratistas$index()[, c("name", "key")])

# --- 5. Evidencia: lectura desde R como data.frame (integración analítica)
df <- con_contratistas$find(
  query  = '{}',
  fields = '{"ruc":1, "razon_social":1, "perfil_actividad":1,
             "amplitud_actividad_actual":1, "antiguedad_anios":1, "_id":0}',
  limit  = 5
)
cat("\nPrimeros 5 contratistas leídos desde R (data.frame):\n")
print(df)

cat("\n[OK] Integración R–MongoDB verificada correctamente.\n")
