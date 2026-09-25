# ============================================================
# FASE III — f) Lanzador de la aplicación Shiny
# Ejecutar desde la raíz del proyecto:
#   & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" fase3\lanzar_app.R
# Luego abrir en el navegador: http://127.0.0.1:8123
# ============================================================
shiny::runApp("fase3/app_shiny", port = 8123,
              host = "127.0.0.1", launch.browser = TRUE)
