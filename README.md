# Segmentación de Contratistas Mineros del MINEM

Modelo de datos documental en **MongoDB** e integración analítica con **R** para priorizar la fiscalización de contratistas mineros de la Dirección General de Minería (MINEM, Perú).

Proyecto del curso **Tópicos de Base de Datos** — Universidad Nacional de Trujillo.

El proyecto cubre todo el recorrido desde el padrón administrativo publicado en datos abiertos hasta una herramienta de decisión:

1. **ETL** en R: el Excel original se limpia, se deduplica por RUC y se carga en MongoDB (contratistas con su historial de autorizaciones embebido, ubicaciones y segmentos de riesgo).
2. **Consultas de negocio** con el *aggregation framework* de MongoDB.
3. **Clustering k-means** (k = 4) para segmentar a los contratistas por prioridad de fiscalización, con su plan de **validación**.
4. **Gráficos** con `ggplot2`.
5. **Aplicación Shiny** conectada en vivo a MongoDB (tablero, reportes, grupos de riesgo y CRUD).

## Estructura del repositorio

```
.
├── Contratistas_Mineros_20_06_2026 ... .xlsx   # Dataset original (MINEM, corte 20/06/2026)
├── INFORME_FINAL.md                            # Informe técnico completo (Fases II y III)
├── INFORME_ACADEMICO_FINAL.md                  # Informe académico (redacción de tesis)
├── PRODUCT.md                                  # Contexto de usuarios y diseño de la app
└── fase3/
    ├── 01_etl_seed.R                 # ETL: extracción → 6 transformaciones → carga en MongoDB
    ├── 02_conexion_evidencias.R      # a) Conexión R–MongoDB
    ├── 03_consultas_negocio.R        # b) 8 consultas de negocio
    ├── 04_patrones_clustering.R      # c) Clustering k-means + poblado de segmentos_riesgo
    ├── 05_validacion_patrones.R      # d) Validación de los patrones (7 pruebas)
    ├── 06_graficos_ggplot2.R         # e) Gráficos G1–G6
    ├── 07_exportar_evidencia_etl.R   # Exporta la evidencia del ETL a .xlsx
    ├── agregar_contratista.R         # Alta de un contratista por código
    ├── lanzar_app.R                  # Lanza la app Shiny
    ├── app_shiny/                    # f) App Shiny (global.R, ui.R, server.R)
    ├── README.md                     # Informe técnico de la Fase III
    ├── CLUSTERING.md / .docx         # Referencia técnica del clustering
    ├── SHINY.md / .docx              # Guion de demostración de la app
    └── salidas/                      # Generado por los scripts (no versionado, salvo graficos/*.png)
```

## Datos

Solo se versiona el **dataset original** descargado del [Portal Nacional de Datos Abiertos](https://www.datosabiertos.gob.pe/) (Contratistas Mineros — MINEM/DGM, corte 20/06/2026; 2,625 resoluciones, 15 columnas).

Todo lo que producen los scripts (archivos `.rds` y `.csv` intermedios, evidencias `.txt`, el Excel transformado y el respaldo `mongodump`) **no se sube**: se regenera ejecutando el pipeline. La única excepción son los gráficos `fase3/salidas/graficos/*.png`, que se mantienen porque el informe los muestra.

## Requisitos

- **R** ≥ 4.6
- **MongoDB Community Server** ≥ 8.0 corriendo en `mongodb://localhost:27017`
- Paquetes de R:

```r
install.packages(c(
  "mongolite", "readxl", "dplyr", "tidyr", "lubridate", "stringr", "purrr",
  "jsonlite", "ggplot2", "scales", "cluster", "writexl",
  "shiny", "shinydashboard", "DT"
))
```

## Cómo ejecutar

Todos los scripts se ejecutan **desde la raíz del repositorio** (el ETL busca el `.xlsx` en el directorio actual). En Windows, si `Rscript` no está en el PATH, usar la ruta completa (p. ej. `"C:\Program Files\R\R-4.6.0\bin\Rscript.exe"`).

```bash
Rscript fase3/01_etl_seed.R              # Crea y puebla la BD contratistas_mineros_minem
Rscript fase3/02_conexion_evidencias.R   # a) Evidencias de conexión
Rscript fase3/03_consultas_negocio.R     # b) Consultas de negocio
Rscript fase3/04_patrones_clustering.R   # c) Clustering + segmentos de riesgo
Rscript fase3/05_validacion_patrones.R   # d) Validación
Rscript fase3/06_graficos_ggplot2.R      # e) Gráficos → fase3/salidas/graficos/
Rscript fase3/lanzar_app.R               # f) App Shiny → http://127.0.0.1:8123
```

El orden importa: 05 y 06 leen los resultados que dejan 03 y 04. El clustering usa `set.seed(2026)`, así que los resultados son reproducibles.

Para devolver la base de datos a su estado canónico (por ejemplo, después de probar el CRUD de la app), basta con volver a ejecutar `01_etl_seed.R` y `04_patrones_clustering.R`.

## Documentación

- [INFORME_FINAL.md](INFORME_FINAL.md): informe técnico completo (benchmark, caso de negocio, modelo ER, colecciones, ETL, consultas, clustering, validación, gráficos y app).
- [INFORME_ACADEMICO_FINAL.md](INFORME_ACADEMICO_FINAL.md): versión con redacción académica.
- [fase3/README.md](fase3/README.md): detalle técnico de la Fase III y sus evidencias.
# ETL-R-MINERIA
