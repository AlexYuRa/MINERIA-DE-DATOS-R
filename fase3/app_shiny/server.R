# ============================================================
# FASE III — f) Frontend Shiny · Lógica de servidor
# ============================================================

function(input, output, session) {

  # Fuente reactiva: se refresca al manipular datos
  refrescar <- reactiveVal(0)
  datos <- reactive({ refrescar(); leer_contratistas() })
  # Solo contratistas ACTIVOS: base para KPIs, gráficos y listados de grupo.
  # (El explorador usa `datos()` completo, con su propio filtro de Estado.)
  datos_activos <- reactive({ d <- datos(); d[d$activo, ] })
  segmentos <- reactive({ refrescar(); leer_segmentos() })

  # Consultas cacheadas: se recalculan solo cuando cambian los datos (refrescar),
  # no en cada re-render del gráfico (p. ej. al redimensionar la ventana).
  ubicaciones_r <- reactive({ refrescar(); leer_ubicaciones() })
  consulta_c1   <- reactive({ refrescar(); ejecutar_consulta("C1") })
  consulta_c5   <- reactive({ refrescar(); ejecutar_consulta("C5") })

  # Poblar filtros dinámicos al iniciar
  observe({
    d <- datos()
    updateSelectInput(session, "f_departamento",
      choices = c("Todos", sort(unique(d$departamento))))
    updateSelectInput(session, "f_prioridad",
      choices = c("Todas", "Muy Alta", "Alta", "Media", "Baja"))
    updateSelectInput(session, "f_perfil",
      choices = c("Todos", sort(unique(d$perfil_actividad))))
    s <- segmentos()
    updateSelectInput(session, "seg_sel",
      choices = setNames(s$id_segmento,
                         paste0(s$nivel_prioridad_fiscalizacion, " — ", s$nombre_segmento)))
  })

  # ---------------- RESUMEN ----------------
  output$kpi_contratistas <- renderValueBox({
    valueBox(format(nrow(datos_activos()), big.mark = ","), "Contratistas",
             icon = icon("industry"), color = "blue")
  })
  output$kpi_ubicaciones <- renderValueBox({
    valueBox(nrow(ubicaciones_r()), "Ubicaciones", icon = icon("location-dot"),
             color = "aqua")
  })
  output$kpi_sin_contacto <- renderValueBox({
    d <- datos_activos(); pct <- round(mean(!d$indice_completitud_contacto) * 100, 1)
    valueBox(paste0(pct, "%"), "Sin teléfono", icon = icon("phone-slash"),
             color = "orange")
  })
  output$kpi_prioritarios <- renderValueBox({
    d <- datos_activos()
    n <- sum(d$prioridad == "Muy Alta", na.rm = TRUE)
    valueBox(format(n, big.mark = ","), "Prioridad Muy Alta",
             icon = icon("triangle-exclamation"), color = "red")
  })

  output$plot_evolucion <- renderPlot({
    c5 <- consulta_c5()
    ggplot(c5, aes(anio, nuevas_empresas)) +
      geom_col(fill = "#0d6b73", alpha = 0.85) +
      geom_smooth(se = FALSE, color = "#a8412a", linewidth = 1) +
      scale_x_continuous(breaks = seq(min(c5$anio), max(c5$anio), by = 3)) +
      labs(x = NULL, y = "Nuevas empresas") +
      theme_minimal(base_size = 12)
  })

  output$plot_perfil <- renderPlot({
    c1 <- consulta_c1()
    ggplot(c1, aes(reorder(perfil_actividad, n_contratistas), n_contratistas,
                   fill = perfil_actividad)) +
      geom_col(show.legend = FALSE) +
      geom_text(aes(label = n_contratistas), hjust = -0.15, size = 4) +
      coord_flip() +
      scale_fill_manual(values = c("#8795a1", "#0d6b73", "#a8412a")) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
      labs(x = NULL, y = NULL) + theme_minimal(base_size = 12)
  })

  # ---------------- EXPLORADOR ----------------
  datos_filtrados <- reactive({
    d <- datos()
    if (identical(input$f_estado, "Activos"))        d <- d[d$activo, ]
    else if (identical(input$f_estado, "Inactivos")) d <- d[!d$activo, ]
    if (input$f_departamento != "Todos") d <- d[d$departamento == input$f_departamento, ]
    if (input$f_prioridad != "Todas")    d <- d[!is.na(d$prioridad) & d$prioridad == input$f_prioridad, ]
    if (input$f_perfil != "Todos")       d <- d[d$perfil_actividad == input$f_perfil, ]
    if (nchar(trimws(input$f_busqueda)) > 0) {
      q <- toupper(trimws(input$f_busqueda))
      d <- d[grepl(q, toupper(d$razon_social), fixed = TRUE) |
             grepl(q, d$ruc, fixed = TRUE), ]
    }
    d
  })

  output$tabla_contratistas <- renderDT({
    d <- datos_filtrados() %>%
      transmute(RUC = ruc, `Razón social` = razon_social,
                Departamento = departamento, Alcance = perfil_actividad,
                `N° actividades` = amplitud_actividad_actual,
                Teléfono = ifelse(is.na(telefono_referencia), "—", telefono_referencia),
                `Grupo de riesgo` = ifelse(is.na(segmento), "—", segmento),
                Prioridad = ifelse(is.na(prioridad), "—", prioridad),
                Estado = ifelse(activo, "Activo", "Inactivo"))
    datatable(d, selection = "single", rownames = FALSE,
              options = list(pageLength = 8, scrollX = TRUE,
                             language = list(search = "Filtrar:")))
  })

  ruc_sel <- reactive({
    i <- input$tabla_contratistas_rows_selected
    if (is.null(i)) return(NULL)
    datos_filtrados()$ruc[i]
  })

  output$tabla_historial <- renderDT({
    r <- ruc_sel(); if (is.null(r)) return(NULL)
    h <- leer_historial(r); if (is.null(h)) return(NULL)
    datatable(h, rownames = FALSE, options = list(dom = "t", pageLength = 10),
              colnames = c("Orden", "Resolución", "Fecha", "Representante",
                           "N° actividades", "Vigente"))
  })

  output$panel_edicion <- renderUI({
    r <- ruc_sel()
    if (is.null(r)) return(tags$p("Seleccione un contratista en la tabla para editarlo."))
    d <- datos()[datos()$ruc == r, ]
    s <- segmentos()
    activo <- isTRUE(d$activo)
    tagList(
      tags$p(tags$b(d$razon_social), tags$br(), "RUC: ", r,
             if (!activo) tags$span(
               style = paste("margin-left:8px; padding:1px 8px; border-radius:999px;",
                             "background:#8795a1; color:#fff; font-size:11px; font-weight:600;"),
               "Inactivo")),
      textInput("edit_telefono", "Teléfono de referencia",
                value = ifelse(is.na(d$telefono_referencia), "", d$telefono_referencia)),
      selectInput("edit_segmento", "Grupo de riesgo",
                  choices = setNames(s$id_segmento,
                                     paste0(s$nivel_prioridad_fiscalizacion, " — ", s$nombre_segmento)),
                  selected = d$segmento_id),
      actionButton("btn_guardar", "Guardar cambios", icon = icon("floppy-disk"),
                   class = "btn-primary"),
      if (activo)
        actionButton("btn_inactivar", "Marcar como inactivo", icon = icon("ban"),
                     class = "btn-danger")
      else
        actionButton("btn_reactivar", "Reactivar", icon = icon("rotate-left"),
                     class = "btn-primary")
    )
  })

  observeEvent(input$btn_guardar, {
    r <- ruc_sel(); if (is.null(r)) return()
    actualizar_telefono(r, input$edit_telefono)
    reasignar_segmento(r, input$edit_segmento)
    refrescar(refrescar() + 1)
    showNotification("Cambios guardados.", type = "message")
  })

  # ----- CREAR contratista (formulario en modal) -----
  observeEvent(input$btn_nuevo, {
    ubis <- leer_ubicaciones()
    ubi_choices <- setNames(
      ubis$id_ubicacion,
      paste0(ubis$departamento, " / ", ubis$provincia, " / ", ubis$distrito))
    showModal(modalDialog(
      title = "Nuevo contratista", size = "l",
      fluidRow(
        column(6, textInput("nc_ruc", "RUC (11 dígitos)", "")),
        column(6, textInput("nc_razon", "Razón social", ""))),
      fluidRow(
        column(6, selectInput("nc_ubicacion", "Ubicación", choices = ubi_choices)),
        column(6, textInput("nc_telefono", "Teléfono (opcional)", ""))),
      textInput("nc_representante", "Representante legal", ""),
      tags$hr(),
      tags$b("Autorización inicial (Resolución Directoral):"),
      fluidRow(
        column(4, textInput("nc_resolucion", "N° de resolución", "")),
        column(4, dateInput("nc_fecha", "Fecha", value = Sys.Date(),
                            format = "dd/mm/yyyy", language = "es")),
        column(4, textInput("nc_registro", "Registro MINEM (opcional)", ""))),
      tags$b("Actividades autorizadas:"),
      fluidRow(
        column(3, checkboxInput("nc_exploracion", "Exploración", FALSE)),
        column(3, checkboxInput("nc_explotacion", "Explotación", FALSE)),
        column(3, checkboxInput("nc_desarrollo", "Desarrollo", FALSE)),
        column(3, checkboxInput("nc_beneficio", "Beneficio", FALSE))),
      footer = tagList(modalButton("Cancelar"),
                       actionButton("btn_nuevo_ok", "Crear contratista",
                                    icon = icon("plus"), class = "btn-primary"))
    ))
  })

  observeEvent(input$btn_nuevo_ok, {
    ruc   <- trimws(input$nc_ruc)
    razon <- trimws(input$nc_razon)
    amp   <- sum(input$nc_exploracion, input$nc_explotacion,
                 input$nc_desarrollo, input$nc_beneficio)
    # Validaciones (si algo falla, se avisa y se mantiene el formulario abierto)
    if (nchar(ruc) == 0 || nchar(razon) == 0) {
      showNotification("El RUC y la razón social son obligatorios.", type = "error")
      return()
    }
    if (col_contratistas()$count(sprintf('{"ruc": "%s"}', ruc)) > 0) {
      showNotification(paste("Ya existe un contratista con el RUC", ruc), type = "error")
      return()
    }
    if (nchar(trimws(input$nc_resolucion)) == 0) {
      showNotification("El número de resolución es obligatorio.", type = "error")
      return()
    }
    if (amp == 0) {
      showNotification("Selecciona al menos una actividad autorizada.", type = "error")
      return()
    }
    crear_contratista(
      ruc, razon, input$nc_ubicacion, input$nc_telefono,
      trimws(input$nc_representante), trimws(input$nc_resolucion),
      input$nc_fecha, trimws(input$nc_registro),
      input$nc_exploracion, input$nc_explotacion,
      input$nc_desarrollo, input$nc_beneficio)
    removeModal()
    refrescar(refrescar() + 1)
    showNotification(
      paste0("Contratista ", ruc, " creado. Aún sin grupo de riesgo: usa ",
             "'Recalcular grupos de riesgo' para clasificarlo."),
      type = "message", duration = 8)
  })

  # Baja LÓGICA (no borrado físico): marca al contratista como inactivo,
  # con confirmación. Es reversible desde el botón "Reactivar".
  observeEvent(input$btn_inactivar, {
    r <- ruc_sel(); if (is.null(r)) return()
    showModal(modalDialog(
      title = "Marcar como inactivo",
      paste0("¿Marcar como inactivo al contratista con RUC ", r, "? ",
             "No se elimina del padrón; queda oculto del listado y puede reactivarse después."),
      footer = tagList(modalButton("Cancelar"),
                       actionButton("btn_inactivar_ok", "Marcar inactivo",
                                    class = "btn-danger"))
    ))
  })
  observeEvent(input$btn_inactivar_ok, {
    r <- ruc_sel(); if (is.null(r)) return()
    marcar_inactivo(r)
    removeModal()
    refrescar(refrescar() + 1)
    showNotification(paste("Contratista", r, "marcado como inactivo."),
                     type = "warning")
  })
  observeEvent(input$btn_reactivar, {
    r <- ruc_sel(); if (is.null(r)) return()
    reactivar_contratista(r)
    refrescar(refrescar() + 1)
    showNotification(paste("Contratista", r, "reactivado."), type = "message")
  })

  # Recalcular los grupos de riesgo con los datos actuales (re-corre el
  # clustering). Se usa tras editar datos, ya que los grupos no se refrescan
  # solos como sí lo hacen los reportes y gráficos.
  observeEvent(input$btn_recalcular, {
    withProgress(message = "Recalculando grupos de riesgo…", value = 0.5, {
      recalcular_grupos()
    })
    refrescar(refrescar() + 1)
    showNotification("Grupos de riesgo recalculados con los datos actuales.",
                     type = "message", duration = 6)
  })

  # ---------------- CONSULTAS ----------------
  output$consulta_desc <- renderUI({
    m <- CONSULTAS[[input$consulta_sel]]
    tags$div(class = "consulta-desc",
      tags$div(tags$b("Qué responde: "), m$desc),
      tags$div(style = "margin-top:6px;",
               tags$b("Decisión que informa: "), m$accion))
  })
  output$tabla_consulta <- renderDT({
    res <- ejecutar_consulta(input$consulta_sel)
    datatable(res, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
  })

  # ---------------- SEGMENTOS ----------------
  output$tabla_segmentos <- renderDT({
    s <- segmentos() %>%
      transmute(Grupo = nombre_segmento,
                Prioridad = nivel_prioridad_fiscalizacion,
                `Puntaje de prioridad` = indice_riesgo,
                `N° empresas` = n_contratistas,
                `Actividades prom. (0-4)` = amplitud_promedio,
                `% con teléfono` = pct_con_contacto,
                `% en Regiones` = pct_regiones)
    datatable(s, rownames = FALSE, options = list(dom = "t"))
  })

  # Fichas por grupo: descripción general y estable (nombre del grupo +
  # prioridad + qué hacer). Los valores exactos de cada grupo (n° de empresas,
  # % con teléfono, etc.) están en la tabla "Resumen de los grupos" de arriba,
  # que se recalcula con los datos; aquí no se repiten cifras que envejezcan.
  output$fichas_segmentos <- renderUI({
    s <- segmentos()
    s <- s[order(match(s$nivel_prioridad_fiscalizacion, names(COLOR_PRIORIDAD))), ]
    fichas <- lapply(seq_len(nrow(s)), function(i) {
      prio <- s$nivel_prioridad_fiscalizacion[i]
      col  <- COLOR_PRIORIDAD[[prio]]
      tags$div(class = "ficha-seg", style = paste0("border-left-color:", col, ";"),
        tags$h4(s$nombre_segmento[i]),
        tags$p(tags$span(class = "badge-prio", style = paste0("background:", col, ";"),
                         paste("Prioridad", prio))),
        tags$p(tags$span(class = "campo", "Qué hacer: "),
               ACCION_PRIORIDAD[[prio]]))
    })
    tags$div(class = "fichas-grid", fichas)
  })

  output$plot_segmentos <- renderPlot({
    s <- segmentos() %>%
      mutate(nivel = factor(nivel_prioridad_fiscalizacion,
                            levels = names(COLOR_PRIORIDAD)),
             etiqueta = reorder(nivel_prioridad_fiscalizacion, -indice_riesgo))
    ggplot(s, aes(etiqueta, n_contratistas, fill = nivel)) +
      geom_col(show.legend = FALSE) +
      geom_text(aes(label = n_contratistas), vjust = -0.3, size = 4) +
      scale_fill_manual(values = COLOR_PRIORIDAD) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
      labs(x = "Prioridad de fiscalización", y = "N° de empresas") +
      theme_minimal(base_size = 12)
  })

  output$tabla_seg_contratistas <- renderDT({
    req(input$seg_sel)
    d <- datos_activos() %>%
      filter(!is.na(segmento_id), segmento_id == as.integer(input$seg_sel)) %>%
      transmute(RUC = ruc, `Razón social` = razon_social,
                Departamento = departamento,
                `N° actividades` = amplitud_actividad_actual)
    datatable(d, rownames = FALSE, options = list(pageLength = 6, scrollX = TRUE))
  })

  # ---------------- GRAFICOS ----------------
  output$plot_graficos <- renderPlot({
    if (input$graf_sel == "g1") {
      c5 <- consulta_c5()
      esc <- max(c5$nuevas_empresas) / max(c5$acumulado)
      ggplot(c5, aes(anio)) +
        geom_col(aes(y = nuevas_empresas), fill = "#0d6b73", alpha = 0.85) +
        geom_line(aes(y = acumulado * esc), color = "#a8412a", linewidth = 1.1) +
        scale_y_continuous("Nuevas empresas por año",
                           sec.axis = sec_axis(~ ./esc, name = "Padrón acumulado")) +
        scale_x_continuous(breaks = seq(min(c5$anio), max(c5$anio), by = 2)) +
        labs(title = "Ingreso de contratistas por año", x = NULL) +
        theme_minimal(base_size = 13)
    } else if (input$graf_sel == "g3") {
      c3 <- ejecutar_consulta("C3") %>%
        select(macrozona, con_telefono, sin_telefono) %>%
        pivot_longer(-macrozona, names_to = "estado", values_to = "n") %>%
        group_by(macrozona) %>% mutate(prop = n/sum(n)) %>% ungroup() %>%
        mutate(estado = recode(estado, con_telefono = "Con teléfono",
                               sin_telefono = "Sin teléfono"))
      ggplot(c3, aes(macrozona, prop, fill = estado)) +
        geom_col(width = 0.6) +
        geom_text(aes(label = percent(prop, 0.1)), position = position_stack(vjust = 0.5),
                  color = "white", size = 4.5) +
        scale_y_continuous(labels = percent) +
        scale_fill_manual(values = c("Con teléfono" = "#0d6b73", "Sin teléfono" = "#a8412a")) +
        labs(title = "Contactabilidad por zona", x = NULL, y = NULL, fill = NULL) +
        theme_minimal(base_size = 13) + theme(legend.position = "top")
    } else if (input$graf_sel == "g4") {
      c8 <- ejecutar_consulta("C8") %>% slice_max(n_contratistas, n = 10) %>%
        mutate(departamento = reorder(departamento, n_contratistas))
      ggplot(c8, aes(departamento)) +
        geom_col(aes(y = n_contratistas), fill = "#8795a1", alpha = 0.55) +
        geom_col(aes(y = n_alta_exposicion), fill = "#a8412a") +
        geom_text(aes(y = n_contratistas, label = n_contratistas), hjust = -0.2, size = 4) +
        coord_flip() + scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
        labs(title = "Concentración por departamento (gris: total · naranja: de alto alcance)",
             x = NULL, y = "N° de empresas") +
        theme_minimal(base_size = 13)
    } else {
      d <- datos_activos() %>%
        mutate(nivel = factor(prioridad, levels = names(COLOR_PRIORIDAD)))
      ggplot(d, aes(antiguedad_anios, amplitud_actividad_actual, color = nivel)) +
        geom_jitter(width = 0.15, height = 0.18, alpha = 0.4, size = 1.1) +
        scale_color_manual(values = COLOR_PRIORIDAD, name = "Prioridad") +
        scale_y_continuous(breaks = 1:4) +
        guides(color = guide_legend(override.aes = list(alpha = 1, size = 3))) +
        labs(title = "Antigüedad y alcance por grupo de riesgo",
             x = "Antigüedad (años)", y = "N° de actividades autorizadas") +
        theme_minimal(base_size = 13) + theme(legend.position = "top")
    }
  })

  output$graf_interpretacion <- renderUI({
    txt <- switch(input$graf_sel,
      g1 = "Muestra cuántas empresas nuevas ingresaron al padrón cada año. Permite ver si el sector crece o se desacelera y anticipar la carga de supervisión.",
      g3 = "Compara la contactabilidad por zona. La falta de teléfono dificulta coordinar inspecciones, y la brecha suele ser mayor en Regiones, donde la inspección presencial es más costosa.",
      g4 = "Muestra en qué departamentos se concentran las empresas (en gris) y cuántas son de alto alcance (en naranja). Ayuda a decidir dónde ubicar los equipos de supervisión.",
      g6 = "Cada punto es una empresa, coloreada por su prioridad de fiscalización. Permite ver cómo se separan los grupos según su antigüedad y su alcance de actividad.")
    tags$p(style = "margin-top:10px; color:#555;", tags$b("Qué significa: "), txt)
  })
}
