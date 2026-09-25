# ============================================================
# FASE III — f) Frontend Shiny · Interfaz de usuario
# ============================================================

dashboardPage(
  skin = "blue",
  dashboardHeader(title = "Contratistas Mineros MINEM", titleWidth = 300),

  dashboardSidebar(
    width = 300,
    sidebarMenu(
      id = "menu",
      menuItem("Resumen", tabName = "resumen", icon = icon("gauge")),
      menuItem("Buscar contratistas", tabName = "explorador", icon = icon("table")),
      menuItem("Reportes", tabName = "consultas", icon = icon("magnifying-glass-chart")),
      menuItem("Grupos de riesgo", tabName = "segmentos", icon = icon("layer-group")),
      menuItem("Tendencias", tabName = "graficos", icon = icon("chart-line")),
      menuItem("Guía de uso", tabName = "acerca", icon = icon("circle-info"))
    ),
    tags$div(style = "padding:14px 16px; color:#9fb0b8; font-size:12px; line-height:1.5;
                      border-top:1px solid rgba(255,255,255,0.06); margin-top:8px;",
             "Priorización de fiscalización", tags$br(),
             "Padrón de contratistas mineros")
  ),

  dashboardBody(
    tags$head(
      tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
      tags$link(rel = "preconnect", href = "https://fonts.gstatic.com", crossorigin = ""),
      tags$link(rel = "stylesheet",
                href = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Source+Serif+4:opsz,wght@8..60,500;8..60,600&display=swap"),
      tags$style(HTML("
      /* ===========================================================
         Sistema de tokens — Contratistas Mineros MINEM
         Estrategia: neutrales fríos tintados + acento institucional
         (teal petróleo). OKLCH de referencia en comentarios.
         =========================================================== */
      :root {
        --bg:            #eceff3;  /* oklch(0.94 0.006 240) fondo app */
        --surface:       #ffffff;  /* superficie de caja */
        --surface-2:     #f6f8fa;  /* superficie sutil (cabeceras suaves) */
        --ink:           #17222e;  /* oklch(0.24 0.02 245) texto principal (~14:1 sobre blanco) */
        --ink-2:         #56636f;  /* texto secundario (~5.4:1 sobre blanco) */
        --border:        #d7dee5;
        --accent:        #0d6b73;  /* teal institucional (blanco encima ~5.9:1) */
        --accent-strong: #0a545b;  /* header/nav */
        --accent-soft:   #e3eeef;  /* relleno tenue del acento */
        --sidebar:       #16303a;  /* teal-pizarra profundo */
        /* Escala de prioridad: monótona en luminosidad (segura para daltonismo) */
        --prio-muyalta:  #8f2d1e;  /* ladrillo profundo */
        --prio-alta:     #c0562a;  /* naranja quemado */
        --prio-media:    #c98a3c;  /* ocre */
        --prio-baja:     #8795a1;  /* pizarra neutra (frío = menor preocupación) */
        --radius:        12px;
      }

      /* ---------- Tipografía ---------- */
      body, .content-wrapper, .main-sidebar, .box, .small-box, label,
      .form-control, table.dataTable, .selectize-input, .btn {
        font-family: 'Inter', system-ui, -apple-system, 'Segoe UI', sans-serif;
      }
      .content-wrapper { background-color: var(--bg); color: var(--ink); }
      .content-wrapper h2 {
        font-family: 'Source Serif 4', Georgia, serif;
        font-weight: 600; color: var(--ink);
        letter-spacing: -0.01em; margin: 4px 0 18px;
        text-wrap: balance;
      }
      .box-title { font-weight: 600; font-size: 15px; letter-spacing: -0.005em; }
      small, .small { color: var(--ink-2); }

      /* ---------- Header y sidebar (override del skin-blue) ---------- */
      .skin-blue .main-header .logo,
      .skin-blue .main-header .navbar { background-color: var(--accent-strong); }
      .skin-blue .main-header .logo {
        font-family: 'Source Serif 4', Georgia, serif; font-weight: 600;
        letter-spacing: -0.01em; border-bottom: 1px solid rgba(255,255,255,0.08);
      }
      .skin-blue .main-header .logo:hover { background-color: var(--accent); }
      .skin-blue .main-header .navbar .sidebar-toggle:hover { background-color: var(--accent); }
      .skin-blue .main-sidebar { background-color: var(--sidebar); }
      .skin-blue .sidebar-menu > li > a { border-left: 3px solid transparent; }
      .skin-blue .sidebar-menu > li.active > a,
      .skin-blue .sidebar-menu > li:hover > a {
        background-color: rgba(255,255,255,0.05);
        border-left-color: var(--accent);
        color: #ffffff;
      }
      .skin-blue .sidebar-menu > li > a { color: #cdd7dd; }

      /* ---------- Cajas ---------- */
      .box {
        border-radius: var(--radius); border-top: none;
        box-shadow: 0 1px 2px rgba(20,30,45,0.06);
        border: 1px solid var(--border);
      }
      .box-header { border-bottom: 1px solid var(--border); }
      .box.box-solid.box-primary > .box-header,
      .box.box-primary { border-color: var(--accent); }
      .box.box-solid.box-primary > .box-header {
        background-color: var(--accent); color: #fff;
      }
      .box.box-solid.box-info > .box-header,
      .box.box-info { border-color: #45596a; }
      .box.box-solid.box-info > .box-header {
        background-color: #45596a; color: #fff;
      }
      .box.box-solid.box-warning > .box-header,
      .box.box-warning { border-color: var(--prio-alta); }
      .box.box-solid.box-warning > .box-header {
        background-color: var(--prio-alta); color: #fff;
      }

      /* ---------- KPIs (small-box): superficie clara, tinta oscura ---------- */
      /* Arregla el contraste ilegible del blanco-sobre-color saturado. */
      .small-box {
        background: var(--surface) !important; color: var(--ink) !important;
        border: 1px solid var(--border); border-radius: var(--radius);
        box-shadow: 0 1px 2px rgba(20,30,45,0.06);
      }
      .small-box h3 { font-size: 30px; font-weight: 700; color: var(--ink) !important;
        letter-spacing: -0.02em; }
      .small-box p  { color: var(--ink-2) !important; font-weight: 500; }
      .small-box .icon { color: var(--accent); opacity: 0.28; font-size: 66px; }
      .small-box:hover { box-shadow: 0 4px 14px rgba(20,30,45,0.10); }
      /* Color semántico por KPI (solo el icono; el número queda en tinta legible) */
      .small-box.bg-blue .icon, .small-box.bg-aqua .icon { color: var(--accent); }
      .small-box.bg-orange .icon { color: var(--prio-media); opacity: 0.42; }
      .small-box.bg-red .icon    { color: var(--prio-muyalta); opacity: 0.42; }
      .small-box.bg-red h3       { color: var(--prio-muyalta) !important; }

      /* ---------- Tablas DT ---------- */
      table.dataTable thead th {
        background: var(--surface-2); color: var(--ink);
        border-bottom: 2px solid var(--border) !important; font-weight: 600;
      }
      table.dataTable tbody tr:hover { background: var(--accent-soft); }
      .dataTables_wrapper .dataTables_filter input:focus,
      .form-control:focus, .selectize-input.focus {
        border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft);
        outline: none;
      }

      /* ---------- Botones ---------- */
      .btn-primary {
        background-color: var(--accent); border-color: var(--accent); font-weight: 600;
      }
      .btn-primary:hover, .btn-primary:focus {
        background-color: var(--accent-strong); border-color: var(--accent-strong);
      }
      .btn-danger { background-color: var(--prio-muyalta); border-color: var(--prio-muyalta);
        font-weight: 600; }
      .btn-danger:hover { background-color: #74251a; border-color: #74251a; }
      .btn { border-radius: 8px; transition: background-color .15s ease-out; }

      /* ---------- Contenido interpretativo (glosas y ayudas) ---------- */
      .intro-tablero {
        font-size: 14px; color: var(--ink-2); max-width: 78ch;
        line-height: 1.55; margin: -6px 0 16px;
      }
      .nota-interpreta { color: var(--ink-2); font-size: 13px; line-height: 1.5; }
      .nota-interpreta b, .ayuda-lista b { color: var(--ink); }
      .ayuda-lista { margin: 6px 0 0; padding-left: 18px; }
      .ayuda-lista li { margin-bottom: 6px; color: var(--ink-2); line-height: 1.5; }
      .consulta-desc {
        background: var(--surface-2); border: 1px solid var(--border);
        border-left: 4px solid var(--accent); border-radius: 8px;
        padding: 10px 14px; margin-bottom: 14px; font-size: 13px;
        color: var(--ink-2); line-height: 1.5;
      }
      .consulta-desc b { color: var(--ink); }
      /* Fichas de segmento */
      .fichas-grid {
        display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
        gap: 12px;
      }
      .ficha-seg {
        border: 1px solid var(--border); border-left: 5px solid var(--border);
        border-radius: 10px; padding: 12px 14px; background: var(--surface);
      }
      .ficha-seg h4 { margin: 0 0 4px; font-size: 14px; font-weight: 600; color: var(--ink); }
      .ficha-seg p { margin: 5px 0; font-size: 13px; color: var(--ink-2); line-height: 1.45; }
      .ficha-seg .campo { color: var(--ink); font-weight: 600; }
      .badge-prio {
        display: inline-block; padding: 1px 9px; border-radius: 999px;
        font-size: 11px; font-weight: 600; color: #fff; vertical-align: middle;
      }

      @media (prefers-reduced-motion: reduce) {
        * { transition: none !important; animation: none !important; }
      }
      "))
    ),

    tabItems(
      # ---------------- RESUMEN ----------------
      tabItem(
        tabName = "resumen",
        h2("Resumen general del padrón"),
        tags$p(class = "intro-tablero",
          "Este tablero prioriza la fiscalización de los contratistas mineros del ",
          "padrón del MINEM. Ordena a las empresas en cuatro grupos de ",
          "riesgo para orientar dónde concentrar la limitada capacidad de inspección del ",
          "Estado: hacia las empresas de mayor exposición operativa y más difícil ",
          "seguimiento. Las cifras de abajo describen el universo a supervisar."),
        fluidRow(
          valueBoxOutput("kpi_contratistas", width = 3),
          valueBoxOutput("kpi_ubicaciones", width = 3),
          valueBoxOutput("kpi_sin_contacto", width = 3),
          valueBoxOutput("kpi_prioritarios", width = 3)
        ),
        tags$p(class = "nota-interpreta", style = "margin:-6px 0 14px;",
          tags$b("Cómo leer estos indicadores: "),
          "el porcentaje sin teléfono mide la dificultad para coordinar inspecciones; ",
          "los de prioridad Muy Alta son el foco inmediato de fiscalización. ",
          "Un padrón amplio y poco contactable justifica priorizar en lugar de ",
          "supervisar a todos por igual."),
        fluidRow(
          box(title = "Ingreso de contratistas por año",
              status = "primary", solidHeader = TRUE, width = 7,
              plotOutput("plot_evolucion", height = 300),
              footer = tags$span(class = "nota-interpreta",
                tags$b("Qué significa: "),
                "muestra cuántas empresas nuevas ingresaron al padrón cada año. ",
                "Permite ver si el sector crece o se desacelera y anticipar cuánta ",
                "carga de supervisión viene.")),
          box(title = "Empresas según su alcance de actividad",
              status = "primary", solidHeader = TRUE, width = 5,
              plotOutput("plot_perfil", height = 300),
              footer = tags$span(class = "nota-interpreta",
                tags$b("Qué significa: "),
                "las empresas con actividad integral (las 4 actividades autorizadas) ",
                "son las de mayor exposición y conviene fiscalizarlas primero. El ",
                "gráfico muestra cuántas hay en cada nivel de alcance."))
        )
      ),

      # ---------------- EXPLORADOR ----------------
      tabItem(
        tabName = "explorador",
        h2("Explorador de contratistas"),
        fluidRow(
          column(12, style = "margin-bottom:12px;",
            actionButton("btn_nuevo", "Nuevo contratista",
                         icon = icon("plus"), class = "btn-primary"))
        ),
        fluidRow(
          box(
            title = "Filtros", status = "info", solidHeader = TRUE, width = 12,
            collapsible = TRUE,
            column(3, selectInput("f_departamento", "Departamento",
                                  choices = NULL, selected = "Todos")),
            column(3, selectInput("f_prioridad", "Prioridad de fiscalización",
                                  choices = c("Todas"), selected = "Todas")),
            column(3, selectInput("f_perfil", "Perfil de actividad",
                                  choices = c("Todos"), selected = "Todos")),
            column(3, selectInput("f_estado", "Estado",
                                  choices = c("Activos", "Todos", "Inactivos"),
                                  selected = "Activos")),
            column(12, textInput("f_busqueda", "Buscar (razón social / RUC)", ""))
          )
        ),
        fluidRow(
          box(title = "Glosario de columnas", status = "info", solidHeader = TRUE,
              width = 12, collapsible = TRUE, collapsed = TRUE,
              tags$ul(class = "ayuda-lista",
                tags$li(tags$b("RUC / Razón social: "),
                        "identificador tributario y nombre legal de la empresa."),
                tags$li(tags$b("N° actividades (0 a 4): "),
                        "cuántas actividades mineras tiene autorizadas la empresa ",
                        "(exploración, explotación, desarrollo, beneficio). 4 = ",
                        "actividad integral = mayor exposición."),
                tags$li(tags$b("Alcance: "),
                        "resumen en palabras del número de actividades (de parcial a ",
                        "integral)."),
                tags$li(tags$b("Grupo de riesgo / Prioridad: "),
                        "grupo al que pertenece la empresa según su perfil de riesgo y ",
                        "qué tan urgente es fiscalizarla (Muy Alta a Baja)."),
                tags$li(tags$b("Teléfono: "),
                        "contacto de referencia; su ausencia dificulta coordinar una ",
                        "inspección."))),
          box(title = "Contratistas", status = "primary", solidHeader = TRUE, width = 12,
              DTOutput("tabla_contratistas"),
              tags$small("Seleccione una fila para ver su historial y editarla."))
        ),
        fluidRow(
          box(title = "Historial de autorizaciones del contratista seleccionado",
              status = "primary", solidHeader = TRUE, width = 7,
              DTOutput("tabla_historial")),
          box(title = "Editar contratista", status = "warning", solidHeader = TRUE,
              width = 5,
              uiOutput("panel_edicion"))
        )
      ),

      # ---------------- CONSULTAS ----------------
      tabItem(
        tabName = "consultas",
        h2("Reportes del padrón"),
        fluidRow(
          box(status = "info", solidHeader = TRUE, width = 12,
              selectInput("consulta_sel", "Elija un reporte",
                          choices = names(CONSULTAS), width = "100%"))
        ),
        fluidRow(
          box(title = "Resultado", status = "primary", solidHeader = TRUE, width = 12,
              uiOutput("consulta_desc"),
              DTOutput("tabla_consulta"))
        )
      ),

      # ---------------- SEGMENTOS ----------------
      tabItem(
        tabName = "segmentos",
        h2("Grupos de riesgo"),
        fluidRow(
          box(title = "Cómo interpretar esta vista", status = "info",
              solidHeader = TRUE, width = 12, collapsible = TRUE,
              tags$p(class = "nota-interpreta",
                "Las empresas del padrón se ordenaron en cuatro grupos según su perfil ",
                "de riesgo. Cada grupo tiene un nivel de prioridad de fiscalización (de ",
                "Muy Alta a Baja) y una acción recomendada. Las fichas de abajo indican ",
                "qué hacer con cada grupo; la tabla resume sus rasgos promedio."),
              tags$p(class = "nota-interpreta", style = "margin-top:8px;",
                tags$b("Puntaje de prioridad: "), TEXTO_INDICE_RIESGO),
              tags$hr(style = "margin:12px 0;"),
              tags$p(class = "nota-interpreta",
                tags$b("¿Editaste datos? "),
                "Los reportes y gráficos se actualizan solos, pero los grupos son una ",
                "\"foto\" del último cálculo. Usa este botón para volver a agruparlos con ",
                "los datos actuales."),
              actionButton("btn_recalcular", "Recalcular grupos de riesgo",
                           icon = icon("arrows-rotate"), class = "btn-primary"))
        ),
        fluidRow(
          box(title = "Resumen de los grupos", status = "primary",
              solidHeader = TRUE, width = 12, DTOutput("tabla_segmentos"))
        ),
        fluidRow(
          box(title = "Qué hacer con cada grupo", status = "primary",
              solidHeader = TRUE, width = 12, uiOutput("fichas_segmentos"))
        ),
        fluidRow(
          box(title = "Tamaño y prioridad de cada grupo", status = "primary",
              solidHeader = TRUE, width = 6, plotOutput("plot_segmentos", height = 320)),
          box(title = "Empresas del grupo seleccionado", status = "primary",
              solidHeader = TRUE, width = 6,
              selectInput("seg_sel", "Grupo", choices = NULL),
              DTOutput("tabla_seg_contratistas"))
        )
      ),

      # ---------------- GRAFICOS ----------------
      tabItem(
        tabName = "graficos",
        h2("Tendencias del sector"),
        fluidRow(
          box(status = "info", solidHeader = TRUE, width = 12,
              radioButtons("graf_sel", NULL, inline = TRUE,
                choices = c("Ingreso de empresas por año" = "g1",
                            "Contactabilidad por zona" = "g3",
                            "Concentración por departamento" = "g4",
                            "Antigüedad y alcance por grupo" = "g6")))
        ),
        fluidRow(
          box(status = "primary", solidHeader = TRUE, width = 12,
              plotOutput("plot_graficos", height = 460),
              uiOutput("graf_interpretacion"))
        )
      ),

      # ---------------- ACERCA ----------------
      tabItem(
        tabName = "acerca",
        box(title = "Para qué sirve esta herramienta", status = "primary",
            solidHeader = TRUE, width = 12,
            HTML("
            <p>Esta herramienta ayuda a <b>decidir a qué contratistas mineros fiscalizar
            primero</b>. Como no es posible inspeccionar a todas las empresas del padrón
            con la misma frecuencia, las ordena por su nivel de riesgo y sugiere hacia
            dónde dirigir la supervisión.</p>
            <p><b>Cómo usar cada sección:</b></p>
            <ul>
              <li><b>Resumen:</b> panorama general del padrón y las cifras clave.</li>
              <li><b>Buscar contratistas:</b> busque una empresa por nombre o RUC, vea su
              historial de autorizaciones y actualice sus datos (teléfono, grupo de riesgo).</li>
              <li><b>Reportes:</b> preguntas frecuentes ya resueltas (dónde se concentran las
              empresas de alto alcance, quiénes no tienen teléfono, etc.). Cada reporte
              explica qué responde y qué decisión ayuda a tomar.</li>
              <li><b>Grupos de riesgo:</b> los cuatro grupos de empresas ordenados por
              prioridad de fiscalización, con la acción recomendada para cada uno.</li>
              <li><b>Tendencias:</b> cómo ha evolucionado el sector a lo largo del tiempo.</li>
            </ul>
            <p>La información se actualiza en vivo: los cambios que guarde en una empresa se
            reflejan de inmediato en toda la herramienta.</p>"))
      )
    )
  )
)
