# Guion de demostración — Aplicación Shiny (Fase III f)

**Proyecto:** Contratistas Mineros MINEM · Tópicos de Base de Datos (UNT)
**Duración estimada:** 8–10 minutos · **Sustentación repartida entre 3 expositores**
**Objetivo de la demo:** mostrar que la propuesta funciona de extremo a extremo — R conectado a MongoDB, reportes de negocio, grupos de riesgo por clustering, validación y una interfaz que **consulta y manipula** los datos en vivo.

**Cada expositor sigue el mismo hilo de explicación:**
1. **Qué hace** su parte del sistema.
2. **Cómo lo hace** (con la demostración en pantalla).
3. **Para qué lo hace** (el valor para la DGM).
4. **Qué objetivos, requerimientos (REQ) y reglas de negocio (RN) cumple.**

**Reparto:**
- **Expositor 1 — Datos e integración + exploración y edición en vivo** (pestañas *Resumen* y *Buscar contratistas*).
- **Expositor 2 — Reportes de negocio y tendencias del sector** (pestañas *Reportes* y *Tendencias*).
- **Expositor 3 — Grupos de riesgo, priorización y validación** (pestaña *Grupos de riesgo*).

> **Nota sobre las cifras:** los números concretos (p. ej. 1,023 empresas Muy Alta) son referenciales del corte actual; en la demo se leen en vivo en pantalla. Si algún día se recargan los datos, la app recalcula sola los reportes/KPIs/gráficos (los grupos de riesgo se refrescan re-ejecutando el agrupamiento).

> **Nota sobre el lenguaje de la interfaz:** la app está redactada para el **usuario final** (analista/funcionario de la DGM): no muestra códigos internos (RN, REQ, k-means…). Esa trazabilidad vive en el informe; en la demo se explica de viva voz al docente, pero la pantalla habla en lenguaje de gestión.

---

## 0. Preparación (antes de iniciar — cualquiera del equipo)

1. Verificar que el servicio de MongoDB está activo:
   ```powershell
   Get-Service MongoDB   # Status debe ser "Running"
   ```
2. (Opcional, si se modificó la base en pruebas) Reconstruir la base a su estado canónico:
   ```powershell
   $R = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
   & $R fase3\01_etl_seed.R
   & $R fase3\04_patrones_clustering.R
   ```
3. Lanzar la aplicación:
   ```powershell
   & "C:\Program Files\R\R-4.6.0\bin\Rscript.exe" fase3\lanzar_app.R
   ```
   Se abrirá el navegador en `http://127.0.0.1:8123`.

> **Apertura (la dice el Expositor 1):** «Esta aplicación en Shiny se conecta en vivo a nuestra base de datos MongoDB con las 2,521 empresas contratistas mineras del padrón del MINEM. La sustentación la dividimos en tres partes: primero el manejo de los datos, luego los reportes de negocio, y al final los grupos de riesgo para priorizar la fiscalización.»

---

# EXPOSITOR 1 — Datos e integración + exploración y edición en vivo
*(pestañas "Resumen" y "Buscar contratistas" · ~3.5 min)*

### 1. Qué hace
Almacena todo el padrón del MINEM (2,521 empresas, con su historial de autorizaciones) en una base de datos MongoDB, y permite el **CRUD completo en vivo** desde la interfaz —crear, consultar, editar y dar de baja contratistas— sin tocar el archivo original.

### 2. Cómo lo hace *(demostración)*
- **Pestaña "Resumen":** señalar los 4 indicadores (Contratistas ≈2,521 · Ubicaciones 216 · Sin teléfono ≈86.8% · Prioridad Muy Alta ≈1,023) y leer la nota "Qué significa" de los gráficos.
  - *Decir:* «Los datos vienen en vivo desde MongoDB, a través del paquete `mongolite` de R. El modelo es documental: cada empresa es un documento que lleva su historial embebido dentro.»
- **Pestaña "Buscar contratistas" (READ):** filtrar por **Departamento** (`CAJAMARCA`) y **Prioridad de fiscalización** (`Muy Alta`); buscar por razón social o RUC. *(Opcional: abrir el "Glosario de columnas".)*
  - *Decir:* «Cada filtro se traduce en una consulta real a MongoDB.»
- **Historial embebido:** clic en una fila → abajo aparece el historial (Resoluciones, fechas, representante, vigencia). *Sugerencia:* RUC **20100094135 (EXSA S.A.)**, con 2 autorizaciones (2009 y 2017).
  - *Decir:* «El historial se guarda embebido dentro del documento de la empresa; lo vemos sin ningún JOIN.»
- **Crear (CREATE):** botón **"Nuevo contratista"** → se abre un formulario (RUC, razón social, ubicación, teléfono, representante, la resolución inicial y sus actividades) → **Crear contratista**.
  - *Decir:* «Damos de alta una empresa nueva; el sistema calcula solo sus campos derivados —perfil de actividad, antigüedad, amplitud— y la guarda en MongoDB. Queda sin grupo de riesgo hasta recalcular.»
  - Para no alterar el padrón en la demo, se puede solo abrir el formulario y **Cancelar**.
- **Editar (UPDATE):** en el panel **"Editar contratista"**, escribir un teléfono (`044-555123`) → **Guardar cambios** → aparece «Cambios guardados.»
  - *Decir:* «Acabo de escribir en la base: actualicé el teléfono y el indicador de contactabilidad se recalculó solo.»
- **Reasignar grupo:** cambiar el **Grupo de riesgo** y guardar.
- **Baja lógica (no borrado físico):** mostrar el botón **"Marcar como inactivo"** (con confirmación). *Decir:* «En un padrón regulatorio no eliminamos empresas: las marcamos como inactivas, algo reversible. Queda oculta del listado pero no se pierde el registro, y puede reactivarse.» El filtro **"Estado"** (arriba) permite ver Activos, Inactivos o Todos. — Para no alterar el padrón, solo mostrar el modal y **cancelar**.

### 3. Para qué lo hace
Para que la DGM tenga una **única fuente viva y actualizable** del padrón: puede corregir datos (teléfonos), reclasificar empresas y mantener la información al día, en lugar de trabajar sobre un Excel plano y estático.

### 4. Objetivos, requerimientos y reglas que cumple
- **Objetivos:** 4 (modelo de colecciones MongoDB con embebido/referencia), 6 (proceso ETL que puebla la base), 7 (**integración/conexión R–MongoDB**), 12 (**frontend que consulta y manipula** los datos).
- **Requerimiento:** REQ2 (mantener/actualizar los datos de contacto).
- **Regla de negocio:** RN2 (contactabilidad: el teléfono editado alimenta el indicador).

---

# EXPOSITOR 2 — Reportes de negocio y tendencias del sector
*(pestañas "Reportes" y "Tendencias" · ~2.5 min)*

### 1. Qué hace
Responde **preguntas concretas de gestión** sobre el padrón (dónde están las empresas de alto alcance, quiénes no tienen teléfono, quiénes son prioritarias, cómo evoluciona el sector) y las comunica en tablas y gráficos interpretados.

### 2. Cómo lo hace *(demostración)*
- **Pestaña "Reportes":** en el selector "Elija un reporte", ejecutar 2–3:
  - **Contratistas prioritarios para fiscalizar** → 485 empresas de alto alcance, sin teléfono y en Regiones.
  - **Contactabilidad por zona (Lima/Callao y Regiones)** → la mayoría sin teléfono, brecha mayor en Regiones (≈90.9%).
  - **Ingreso de nuevas empresas por año** → crecimiento del sector y caída en 2020.
  - Señalar en cada uno el recuadro **"Qué responde"** y **"Decisión que informa"**.
  - *Decir:* «Cada reporte es una consulta de agregación de MongoDB (`aggregate`, `$group`, `$lookup`, `$match`) ejecutada desde R. En pantalla explica su utilidad; internamente —como está en el informe— cada uno responde a una regla de negocio y a un requerimiento de la DGM.»
- **Pestaña "Tendencias":** alternar entre los gráficos (Ingreso por año, Contactabilidad por zona, Concentración por departamento, **Antigüedad y alcance por grupo**) y leer la línea **"Qué significa"** de cada uno.
  - *Handoff:* «Este último gráfico ya muestra los grupos de riesgo, que explicará mi compañero.»

### 3. Para qué lo hace
Para convertir un padrón plano en **respuestas accionables**: dónde desplegar equipos, a quién contactar, a quién fiscalizar primero, y cómo se mueve el sector en el tiempo.

### 4. Objetivos, requerimientos y reglas que cumple
- **Objetivos:** 8 (**consultas de negocio** ligadas a reglas y requerimientos), 11 (**gráficos** que comunican los hallazgos).
- **Requerimientos:** REQ1 (priorización), REQ2 (contacto), REQ3 (distribución geográfica de equipos), REQ4 (monitoreo de la evolución), REQ5 (estrategias diferenciadas).
- **Reglas de negocio:** RN1 (exposición por alcance de actividad), RN2 (contactabilidad), RN3 (Regiones = mayor complejidad logística), RN5 (dinamismo/evolución del sector).

---

# EXPOSITOR 3 — Grupos de riesgo, priorización y validación
*(pestaña "Grupos de riesgo" · ~2.5 min + cierre)*

### 1. Qué hace
Agrupa a las 2,521 empresas en **4 grupos de riesgo**, le asigna a cada uno una **prioridad de fiscalización** y una **acción recomendada**, y **demuestra estadísticamente** que esos grupos son confiables.

### 2. Cómo lo hace *(demostración)*
- Abrir el box **"Cómo interpretar esta vista"** y leer la explicación del **puntaje de prioridad** (combina alcance de actividad, contactabilidad, ubicación en Regiones y antigüedad sin renovar).
- Mostrar la tabla **"Resumen de los grupos"** (4 grupos, su prioridad, puntaje, n° de empresas y rasgos promedio) y las fichas **"Qué hacer con cada grupo"** (acción por grupo: Muy Alta = fiscalizar primero … Baja = seguimiento rutinario).
- Mostrar el gráfico **"Tamaño y prioridad de cada grupo"** (ladrillo/rojo = Muy Alta · naranja = Alta · ocre = Media · **gris/pizarra = Baja**) y usar el selector **"Grupo"** para listar sus empresas.
  - *Decir:* «Estos 4 grupos no los definimos a mano: los descubrió el algoritmo **k-means** a partir de 6 variables estandarizadas. El 84% del padrón cae en prioridad Alta o Muy Alta. El grupo de prioridad **Alta**, por ejemplo, son empresas de alcance moderado, antiguas y sin renovación reciente —probables inactivas que conviene depurar—.»
  - *Sobre la validación (decir):* «Como el clustering es no supervisado, no basta con generarlo: lo validamos con **7 pruebas** en tres dimensiones (cohesión/silueta, ANOVA, coherencia con los reportes, convergencia con otro algoritmo y reproducibilidad). Las 7 cumplen.»
- *(Opcional)* mostrar el botón **"Recalcular grupos de riesgo"**. *Decir:* «Los reportes se actualizan solos al editar datos, pero los grupos son una foto del último cálculo. Con este botón el analista los vuelve a generar con los datos actuales, sin salir de la herramienta.» — No presionarlo en la demo salvo que se quiera mostrar (recalcula y mantiene los mismos grupos si los datos no cambiaron).

### 3. Para qué lo hace
Para que la DGM, con una capacidad de inspección limitada frente a 2,521 empresas, **concentre el esfuerzo en las de mayor riesgo primero**, con un criterio objetivo, trazable y respaldado estadísticamente, en lugar de reaccionar solo ante incidentes.

### 4. Objetivos, requerimientos y reglas que cumple
- **Objetivos:** 5 (fórmulas de los atributos derivados), 9 (**clustering** que genera los patrones de riesgo), 10 (**validación** de los patrones).
- **Requerimientos:** REQ1 (priorización de la fiscalización), REQ5 (estrategias diferenciadas por grupo).
- **Reglas de negocio:** RN1 (exposición), RN2 (contactabilidad), RN3 (Regiones), **RN4 (regla combinada de prioridad)**, RN5 (dinamismo).

> **Cierre (lo dice el Expositor 3):** «En resumen: partimos de un archivo plano del MINEM, lo normalizamos en un modelo documental en MongoDB, lo conectamos con R, generamos reportes y grupos de riesgo validados estadísticamente, y lo pusimos en una interfaz donde la DGM puede consultar y manipular los datos para decidir a quién fiscalizar primero. Todo el flujo Backend–Frontend funciona en vivo.»

---

## Preguntas frecuentes del docente (las responde quien corresponda al tema)

| Posible pregunta | Responde | Respuesta breve |
|---|---|---|
| ¿La app está conectada de verdad a MongoDB? | Exp. 1 | Sí; cada filtro, reporte y edición ejecuta operaciones reales (`find`, `aggregate`, `update`) vía `mongolite`. |
| ¿El historial no debería estar en otra tabla? | Exp. 1 | En el modelo documental se embebe dentro del contratista porque siempre se consulta junto a él; se ve sin JOINs. |
| Si edito o cargo datos, ¿se recalcula todo solo? | Exp. 1 / 3 | Reportes, KPIs, tablas y gráficos sí, en vivo. Los **grupos de riesgo** son una "foto" del último cálculo: se actualizan con el botón **"Recalcular grupos de riesgo"** (o re-ejecutando `04_patrones_clustering.R`). |
| ¿Cada reporte para qué sirve? | Exp. 2 | Cada uno responde a una regla de negocio (RN) y a un requerimiento (REQ) de la DGM; en pantalla se muestra "Qué responde / Decisión que informa". |
| ¿Por qué k = 4 grupos? | Exp. 3 | Se evaluó k = 2…8 con el método del codo y la silueta; k=4 equilibra cohesión estadística e interpretabilidad (4 niveles de prioridad). |
| ¿Cómo saben que los patrones sirven? | Exp. 3 | 7 pruebas en tres dimensiones (cobertura, silueta, ANOVA, coherencia con los reportes, convergencia con otro algoritmo y reproducibilidad ARI). Las 7 cumplen. |
| ¿Qué pasa si marco una empresa por error? | Exp. 1 | La baja es **lógica y reversible**: la empresa no se elimina, solo se marca inactiva; se reactiva con el botón **"Reactivar"** (filtrando por Estado = Inactivos). No se pierde el registro. |
| ¿Por qué la interfaz no muestra RN/REQ ni "k-means"? | Cualquiera | Porque la app es para el usuario operativo (analista/DGM), que decide con resultados; la trazabilidad técnica vive en el informe. |
