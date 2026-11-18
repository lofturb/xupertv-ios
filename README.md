# XuperTV para iPad mini 1 (iOS 9, armv7)

Port de la app XuperTV a iPad mini 1 (`iPad2,5`, iOS 9.3.5, armv7, 512 MB).

## Estado

- Fase 0: proyecto Theos + CI + IPA instalable (build de prueba).
- Fase 1: WKWebView con la app web y servidor local (en curso).
- Fase 2: servicio real (magis en JavaScriptCore).
- Fase 3: reproducción H.264 vía HLS local.

## Compilar

El build lo hace GitHub Actions en Ubuntu con Theos + SDK 9.3 + toolchain armv7.
Cada push a `main` publica un `.ipa` en **Releases**.

Localmente (Linux/WSL) hace falta Theos y el SDK:

```bash
export THEOS=$HOME/theos
make clean
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

## Instalar en el iPad

Con jailbreak y **AppSync Unified**:

```powershell
ideviceinstaller -i .\com.webosflux.xupertv.ios_1.0.0_iphoneos-arm.ipa
```

O copiar el `.ipa` al iPad y abrirlo desde Filza.

## Estructura

- `Resources/` — Info.plist, iconos, LaunchImage y (fases siguientes) la app web.
- `vendor/GCDWebServer/` — servidor HTTP local (solo fuentes).
- `main.m`, `AppDelegate.*`, `RootViewController.*` — app UIKit.
- `.github/workflows/build-ipa.yml` — compilación y Release del IPA.

## Notas

- Solo landscape, H.264/720p (el A5 no decodifica HEVC).
- No se usa Node ni Electron en el dispositivo.
- La app web y `magis.js` se ejecutan en el dispositivo (WKWebView + JavaScriptCore).