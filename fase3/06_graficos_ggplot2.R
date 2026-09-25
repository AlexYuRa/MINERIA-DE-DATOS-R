# ============================================================
# FASE III — e) Gráficos de los resultados con ggplot2 y su
#              significado en cuanto a la evolución del negocio.
# ------------------------------------------------------------
# Genera 6 gráficos (PNG) a partir de las consultas de negocio (b)
# y de los patrones del clustering (c), leídos desde MongoDB /
# archivos de resultados. Cada gráfico se acompaña de su lectura
# de negocio (impresa en consola y en el README).
# ============================================================

suppressMessages({
  library(mongolite)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
})

URI <- "mongodb://localhost:27017"
BD  <- "contratistas_mineros_minem"
DIR_SALIDAS <- file.path("fase3", "salidas")
DIR_GRAF    <- file.path(DIR_SALIDAS, "graficos")
dir.create(DIR_GRAF, showWarnings = FALSE, recursive = TRUE)

con_contratistas <- mongo("contratistas",     db = BD, url = URI)
con_segmentos    <- mongo("segmentos_riesgo", db = BD, url = URI)

# Resultados ya calculados en pasos previos
consultas <- readRDS(file.path(DIR_SALIDAS, "consultas_resultados.rds"))
modelo    <- readRDS(file.path(DIR_SALIDAS, "clustering_modelo.rds"))

# Tema y paleta comunes (aspecto sobrio y legible para el informe)
tema <- theme_minimal(base_size = 12) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "grey30", size = 10.5),
    plot.caption  = element_text(color = "grey45", size = 8, hjust = 0),
    panel.grid.minor = element_blank(),
    legend.position = "top"
  )
AZUL <- "#2c6fbb"; NARANJA <- "#e07b39"; GRIS <- "#8a8a8a"
CAP  <- "Fuente: Padrón Contratistas Mineros MINEM (corte 20/06/2026) · Fase III"

guardar <- function(p, archivo, w = 9, h = 5.5) {
  ggsave(file.path(DIR_GRAF, archivo), p, width = w, height = h, dpi = 120, bg = "white")
  cat("   [OK] ", archivo, "\n")
}

cat("Generando gráficos ggplot2...\n\n")

# ------------------------------------------------------------
# G1 — Evolución anual del ingreso de nuevas empresas (C5)
# ------------------------------------------------------------
c5 <- consultas$C5
esc <- max(c5$nuevas_empresas) / max(c5$acumulado)  # escala para eje secundario

g1 <- ggplot(c5, aes(x = anio)) +
  geom_col(aes(y = nuevas_empresas), fill = AZUL, alpha = 0.85) +
  geom_line(aes(y = acumulado * esc), color = NARANJA, linewidth = 1.1) +
  geom_point(aes(y = acumulado * esc), color = NARANJA, size = 1.6) +
  scale_y_continuous(
    name = "Nuevas empresas por año",
    sec.axis = sec_axis(~ . / esc, name = "Padrón acumulado")) +
  scale_x_continuous(breaks = seq(2008, 2026, 2)) +
  labs(title = "Evolución del ingreso de contratistas mineros (2008–2026)",
       subtitle = "Barras: altas anuales · Línea: padrón acumulado",
       x = NULL, caption = CAP) +
  tema
guardar(g1, "G1_evolucion_anual.png")

# ------------------------------------------------------------
# G2 — Distribución por perfil de actividad (C1)
# ------------------------------------------------------------
c1 <- consultas$C1 %>%
  mutate(perfil_actividad = recode(perfil_actividad,
           "actividad_integral"      = "Actividad integral (4)",
           "multi_actividad_parcial" = "Multi-actividad parcial (2-3)",
           "mono_actividad"          = "Mono-actividad (1)"),
         perfil_actividad = factor(perfil_actividad,
           levels = c("Mono-actividad (1)", "Multi-actividad parcial (2-3)",
                      "Actividad integral (4)")))

g2 <- ggplot(c1, aes(x = perfil_actividad, y = n_contratistas, fill = perfil_actividad)) +
  geom_col(width = 0.65, show.legend = FALSE) +
  geom_text(aes(label = paste0(n_contratistas, "\n(", porcentaje, "%)")),
            vjust = -0.2, size = 3.6) +
  scale_fill_manual(values = c(GRIS, AZUL, NARANJA)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Perfil de exposición operativa de los contratistas",
       subtitle = "A mayor amplitud de actividad autorizada, mayor exposición operativa (RN1)",
       x = NULL, y = "N° de contratistas", caption = CAP) +
  tema
guardar(g2, "G2_perfil_actividad.png")

# ------------------------------------------------------------
# G3 — Contactabilidad por macrozona (C3)
# ------------------------------------------------------------
c3 <- consultas$C3 %>%
  select(macrozona, con_telefono, sin_telefono) %>%
  pivot_longer(-macrozona, names_to = "estado", values_to = "n") %>%
  mutate(estado = recode(estado, "con_telefono" = "Con teléfono",
                         "sin_telefono" = "Sin teléfono"),
         macrozona = recode(macrozona, "Lima_Callao" = "Lima y Callao")) %>%
  group_by(macrozona) %>%
  mutate(prop = n / sum(n)) %>%
  ungroup()

g3 <- ggplot(c3, aes(x = macrozona, y = prop, fill = estado)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = paste0(percent(prop, accuracy = 0.1), "\n(", comma(n), ")")),
            position = position_stack(vjust = 0.5), size = 3.6, color = "white") +
  scale_y_continuous(labels = percent) +
  scale_fill_manual(values = c("Con teléfono" = AZUL, "Sin teléfono" = NARANJA)) +
  labs(title = "Contactabilidad de los contratistas por macrozona",
       subtitle = "La baja contactabilidad (sin teléfono) es aún mayor en Regiones (RN2/RN3)",
       x = NULL, y = NULL, fill = NULL, caption = CAP) +
  tema
guardar(g3, "G3_contactabilidad_macrozona.png")

# ------------------------------------------------------------
# G4 — Concentración geográfica: top departamentos (C8)
# ------------------------------------------------------------
c8 <- consultas$C8 %>%
  slice_max(n_contratistas, n = 10) %>%
  mutate(departamento = reorder(departamento, n_contratistas))

g4 <- ggplot(c8, aes(x = departamento)) +
  geom_col(aes(y = n_contratistas), fill = GRIS, alpha = 0.55, width = 0.7) +
  geom_col(aes(y = n_alta_exposicion), fill = NARANJA, width = 0.7) +
  geom_text(aes(y = n_contratistas, label = n_contratistas), hjust = -0.2, size = 3.2) +
  coord_flip() +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = "Concentración de contratistas por departamento (top 10)",
       subtitle = "Gris: total de contratistas · Naranja: de actividad integral (amplitud = 4)",
       x = NULL, y = "N° de contratistas", caption = CAP) +
  tema
guardar(g4, "G4_concentracion_departamentos.png")

# ------------------------------------------------------------
# G5 — Segmentos de riesgo generados por el clustering (c)
# ------------------------------------------------------------
seg <- con_segmentos$find('{}', sort = '{"id_segmento":1}') %>%
  mutate(
    etiqueta = paste0("Seg. ", id_segmento, "\n", nivel_prioridad_fiscalizacion),
    nivel = factor(nivel_prioridad_fiscalizacion,
                   levels = c("Muy Alta", "Alta", "Media", "Baja")),
    etiqueta = reorder(etiqueta, -indice_riesgo))

g5 <- ggplot(seg, aes(x = etiqueta, y = n_contratistas, fill = nivel)) +
  geom_col(width = 0.68) +
  geom_text(aes(label = paste0(n_contratistas, " empresas\nriesgo ", indice_riesgo)),
            vjust = -0.2, size = 3.2) +
  scale_fill_manual(values = c("Muy Alta" = "#c0392b", "Alta" = "#e07b39",
                               "Media" = "#f1c40f", "Baja" = "#27ae60")) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
  labs(title = "Segmentos de riesgo de fiscalización (k-means, k = 4)",
       subtitle = "Tamaño de cada segmento y su índice de riesgo · patrón para priorizar (REQ1)",
       x = NULL, y = "N° de contratistas", fill = "Prioridad", caption = CAP) +
  tema
guardar(g5, "G5_segmentos_riesgo.png")

# ------------------------------------------------------------
# G6 — Cómo separan los segmentos: antigüedad vs. amplitud
# ------------------------------------------------------------
# El 'datos' guardado tiene 'cluster'; se mapea a id_segmento vía perfil
# (rank_riesgo = id_segmento) y de ahí al nivel de prioridad.
mapa_cluster <- modelo$perfil %>% select(cluster, id_segmento = rank_riesgo)
datos <- modelo$datos %>%
  left_join(mapa_cluster, by = "cluster") %>%
  left_join(seg %>% select(id_segmento, nivel_prioridad_fiscalizacion),
            by = "id_segmento") %>%
  mutate(nivel = factor(nivel_prioridad_fiscalizacion,
                        levels = c("Muy Alta", "Alta", "Media", "Baja")))

g6 <- ggplot(datos, aes(x = antiguedad_anios, y = amplitud_actividad_actual,
                        color = nivel)) +
  geom_jitter(width = 0.15, height = 0.18, alpha = 0.35, size = 1.1) +
  scale_color_manual(values = c("Muy Alta" = "#c0392b", "Alta" = "#e07b39",
                                "Media" = "#f1c40f", "Baja" = "#27ae60")) +
  scale_y_continuous(breaks = 1:4) +
  guides(color = guide_legend(override.aes = list(alpha = 1, size = 2.5))) +
  labs(title = "Cómo se separan los segmentos de contratistas",
       subtitle = "La antigüedad separa los segmentos recientes de alto riesgo (rojo) de los antiguos (naranja)",
       x = "Antigüedad en el padrón (años)", y = "Amplitud de actividad (0–4)",
       color = "Prioridad", caption = CAP) +
  tema
guardar(g6, "G6_dispersion_segmentos.png")

cat("\n============================================================\n")
cat("6 gráficos ggplot2 generados en fase3/salidas/graficos/.\n")
cat("============================================================\n")
