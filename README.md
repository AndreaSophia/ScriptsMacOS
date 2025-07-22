# 🎧 Audio Watchdog para macOS (by Safiye)

**Versión:** 1.0  
**Identificador:** `com.safiye.audio.watchdog`  
**Compatibilidad:** macOS 12+  
**Tipo:** LaunchDaemon (nivel sistema)

---

## 🔥 ¿Qué es esto?

Este paquete instala un servicio de sistema que **verifica automáticamente si el audio del Mac está funcional**. En caso de que no haya dispositivos de salida de audio detectados (bug común en macOS 15.5), reinicia el proceso `coreaudiod` de manera automática y silenciosa.

---

## 🛠 ¿Qué incluye?

- 🧠 `audio_watchdog.sh`: un script inteligente que detecta fallos de audio y los soluciona.
- 🧩 `com.safiye.audio.watchdog.plist`: un `LaunchDaemon` que se ejecuta:
  - al arrancar el sistema,
  - y cada 5 minutos (configurable).

---

## 🚀 ¿Qué hace?

| Evento                            | Acción                                                      |
|----------------------------------|-------------------------------------------------------------|
| Arranque del sistema             | Espera 10s, revisa si hay salida de audio.                 |
| No hay audio                     | Reinicia `coreaudiod` y verifica nuevamente.               |
| Segundo intento falla            | Logea que el problema persiste.                            |
| Audio está OK                    | No hace nada, todo fluye.                                  |

---

## 📂 Instalación

1. Descarga o genera el paquete `.pkg`.
2. Ejecuta el instalador.
3. Listo, el servicio queda funcionando de forma silenciosa en segundo plano.

---

## 🧼 Desinstalación manual

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.safiye.audio.watchdog.plist
sudo rm /Library/LaunchDaemons/com.safiye.audio.watchdog.plist
sudo rm /usr/local/bin/audio_watchdog.sh
