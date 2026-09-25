# Product

## Register

product

## Users

Analistas y funcionarios de la Dirección General de Minería (DGM) del MINEM. Trabajan en escritorio, en un contexto de gestión pública con recursos de fiscalización limitados. Su tarea principal es **decidir a qué contratistas mineros fiscalizar primero**: consultar el padrón, entender los segmentos de riesgo y, ocasionalmente, corregir/actualizar datos de un contratista. Audiencia secundaria inmediata: el docente evaluador ante quien se sustenta la propuesta.

## Product Purpose

Aplicación web (Shiny/R) conectada en vivo a MongoDB que expone el padrón de 2,521 contratistas mineros del MINEM. Permite: ver indicadores globales, explorar y filtrar contratistas con su historial de autorizaciones embebido, ejecutar 8 consultas de negocio, revisar los 4 segmentos de riesgo generados por clustering, visualizar la evolución del sector, y **manipular los datos (CRUD)** sobre MongoDB. El éxito es que un analista pueda, en pocos clics, obtener la lista priorizada de fiscalización y actualizar un dato con confianza.

## Brand Personality

**Institucional sobrio.** Serio, confiable, denso en datos, con autoridad de organismo del Estado. Prioriza la legibilidad y la jerarquía sobre el adorno. Debe transmitir rigor técnico (es una herramienta de decisión regulatoria), no ser lúdico ni "marketing". Tres palabras: **riguroso, legible, confiable**.

## Anti-references

- **El look Bootstrap 3 genérico de `shinydashboard`** (azul `#3c8dbc` por defecto, cajas planas con cabecera de color, tipografía Source Sans por defecto). Es exactamente lo que hay que superar; hoy la app se ve "plantilla".
- **Slop de IA:** gradientes decorativos, glassmorphism, texto con gradiente, tarjetas idénticas repetidas, bordes laterales de color como acento.
- **Sobrecarga visual:** demasiados colores/sombras/adornos que compitan con los datos.
- **Exceso minimalista:** tan sobrio que quede vacío o sin identidad. Debe tener carácter institucional propio.

## Design Principles

1. **Los datos primero.** Cada elemento visual debe servir a la lectura del dato o retirarse. La densidad informativa es una virtud aquí, no un defecto.
2. **Identidad institucional propia, no Bootstrap.** Definir tokens de color/tipografía/espacio propios y aplicarlos consistentemente; superar el default del framework sin caer en el adorno.
3. **Jerarquía inequívoca.** El analista debe saber de un vistazo qué es prioritario (los segmentos de riesgo, los KPIs críticos) mediante escala, peso y color, no mediante decoración.
4. **Consistencia de sistema.** Un único conjunto de tokens (colores de prioridad, superficies, tinta, espaciado) reutilizado en KPIs, tablas, gráficos y segmentos.
5. **Confianza en la manipulación.** Las acciones de escritura (editar, eliminar) deben ser claras, reversibles y con feedback explícito.

## Accessibility & Inclusion

Nivel objetivo: **básico pero correcto**. Contraste de texto legible (evitar gris claro sobre fondos tintados), foco visible en controles, etiquetas en inputs. Atención especial a la **paleta de prioridad de riesgo** (Muy Alta / Alta / Media / Baja): hoy usa rojo/naranja/amarillo/verde, un esquema problemático para daltonismo; conviene reforzar con etiqueta de texto y/o intensidad además del color, aunque no se persiga certificación WCAG estricta.
