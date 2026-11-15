# 🎸 Bocchi Stickers

Aplicación **personal** hecha en **Flutter** para crear, organizar y exportar paquetes de stickers personalizados directamente a **WhatsApp**. Sin anuncios, sin cuentas, sin internet y sin restricciones comerciales: todo se guarda en el teléfono.

La interfaz tiene temas inspirados en las integrantes de Kessoku Band (*Bocchi the Rock!*): Bocchi, Kita, Ryo y Nijika.

> Proyecto de uso personal, no se publica en ninguna tienda. Se instala como APK.

---

## ✨ Funciones

- **Paquetes de stickers:** crear, renombrar, duplicar y eliminar paquetes.
- **Editor propio:** mover, hacer zoom y rotar la imagen sobre un lienzo de 512×512, con una guía del margen de 16 px y fondo de ajedrez para ver la transparencia.
- **Recorte a mano:** lazo, borrador, restaurar, y deshacer/rehacer.
- **Quitar fondo automático** con ML Kit (segmentación de sujeto).
- **Emojis por sticker** (de 1 a 3), requeridos por WhatsApp.
- **Reordenar** stickers y elegir el **ícono de bandeja** (tray icon).
- **Exportación automática** a WebP cumpliendo las reglas de WhatsApp (ver abajo).
- **Agregar a WhatsApp** con un botón, incluyendo WhatsApp Business.
- **Respaldo en `.zip`** de todos los paquetes.
- **Temas por personaje** (Bocchi, Kita, Ryo, Nijika), en modo claro y oscuro.

---

## 📱 Plataforma

| Plataforma | Estado |
|---|---|
| Android | ✅ Soportado |
| iOS | ❌ No soportado (el envío a WhatsApp y la conversión a WebP usan código nativo de Android) |

---

## 🛠️ Tecnologías

- **Flutter / Dart** (Material 3)
- **Riverpod** para el estado
- `path_provider` para archivos locales
- `image_picker` para elegir fotos de la galería
- **`google_mlkit_subject_segmentation`** para quitar el fondo
- **Kotlin** (código nativo de Android):
  - Codificación de PNG a **WebP** con control de peso.
  - **ContentProvider** propio que entrega los stickers a WhatsApp.
  - Intent `com.whatsapp.intent.action.ENABLE_STICKER_PACK`.

---

## ⚠️ Requisitos de WhatsApp que la app cumple automáticamente

**Cada sticker:**
- Formato **WebP**, exactamente **512 × 512 px**.
- Fondo transparente, peso máximo **100 KB**.
- Margen transparente de **16 px** alrededor.
- De **1 a 3 emojis**.

**Cada paquete:**
- Entre **3 y 30** stickers.
- **Tray icon** de **96 × 96 px**, máximo **50 KB**.
- Nombre, autor e identificador único.
- Al cambiar un paquete ya agregado, se incrementa la versión de las imágenes para que WhatsApp detecte la actualización.

---

## 📂 Estructura del código

```
lib/
  main.dart
  app.dart
  core/            # tema, constantes, límites de WhatsApp
  data/            # modelos (StickerPack, Sticker) y repositorio
  providers/       # estado con Riverpod
  services/        # exportación de imágenes y envío a WhatsApp
  features/
    home/          # pantalla principal
    editor/        # lienzo, herramientas y recorte
    pack/          # pantalla del paquete y selector de emojis
android/           # ContentProvider y canal nativo en Kotlin
assets/characters/ # imágenes de los temas
```

---

## 🚀 Cómo correrlo

**Requisitos:** Flutter instalado y un teléfono Android (o emulador) con depuración USB activada.

```bash
flutter pub get
flutter run
```

Para probar el envío a WhatsApp conviene un teléfono real con WhatsApp instalado.

---

## 📦 Generar el APK

```bash
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
```

Los archivos quedan en `build/app/outputs/flutter-apk/`. Para casi cualquier teléfono moderno se usa **`app-arm64-v8a-release.apk`**.

> La función de quitar fondo descarga el modelo de ML Kit la primera vez, así que esa primera vez necesita internet.

---

## 🗺️ Fases del proyecto

- [x] **Fase 0:** prueba de concepto de WhatsApp (provider propio)
- [x] **Fase 1:** base de la app, modelos y persistencia
- [x] **Fase 2:** importar foto y editor básico
- [x] **Fase 3:** lazo, borrador y transparencia
- [x] **Fase 4:** exportación a WebP y validaciones
- [x] **Fase 5:** integración completa con WhatsApp
- [x] **Fase 6:** extras (borde blanco, texto, stickers animados)

---

## ⚖️ Aviso

Proyecto personal y sin fines de lucro. Los personajes de *Bocchi the Rock!* y sus imágenes pertenecen a sus respectivos creadores y titulares de derechos; se usan aquí solo como decoración de una app de uso privado. Este repositorio debe mantenerse **privado**.

---

Hecho por **AxlGA25**.
