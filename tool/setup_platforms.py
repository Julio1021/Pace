#!/usr/bin/env python3
"""Aplica a configuração nativa do Android depois de `flutter create .`.

Uso (na raiz do projeto):
    flutter create --org br.com.julio --project-name pace --platforms=android .
    python3 tool/setup_platforms.py
"""
import os
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLAT = ROOT / "platform" / "android"

# Chave de assinatura fixa (vem dos Secrets do GitHub, nunca do repositório):
# todas as versões saem com a mesma assinatura, então as atualizações
# instalam por cima sem apagar as corridas.
STORE = os.environ.get("PACE_KEYSTORE_PATH", "")
STORE_PASS = os.environ.get("PACE_KEYSTORE_PASSWORD", "")
ALIAS = "pace"


def done(msg):
    print(f"  ✓ {msg}")


def main():
    app = ROOT / "android" / "app"
    if not app.exists():
        sys.exit("Pasta android/ não encontrada. Rode antes: flutter create --platforms=android .")
    shutil.copy(PLAT / "AndroidManifest.xml", app / "src" / "main" / "AndroidManifest.xml")
    done("AndroidManifest.xml (GPS, serviço em primeiro plano, notificações)")

    kts = app / "build.gradle.kts"
    groovy = app / "build.gradle"
    signing = bool(STORE and STORE_PASS and pathlib.Path(STORE).exists())
    if not signing:
        print("  ! Chave de assinatura não configurada: o APK sai com assinatura temporária.")
        print("    Atualizações não vão instalar por cima. Configure os Secrets (veja o README).")
    if kts.exists():
        s = kts.read_text()
        if signing and 'create("pace")' not in s:
            block = (
                "    signingConfigs {\n"
                '        create("pace") {\n'
                f'            storeFile = file("{STORE}")\n'
                f'            storePassword = "{STORE_PASS}"\n'
                f'            keyAlias = "{ALIAS}"\n'
                f'            keyPassword = "{STORE_PASS}"\n'
                "        }\n"
                "    }\n\n"
                "    buildTypes {"
            )
            s = s.replace("    buildTypes {", block, 1)
            s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                          'signingConfig = signingConfigs.getByName("pace")')
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", s)
        kts.write_text(s)
        if signing and 'getByName("pace")' not in s:
            sys.exit("Não consegui configurar a assinatura no build.gradle.kts")
        done("build.gradle.kts (minSdk 26" + (", assinatura fixa)" if signing else ")"))
    elif groovy.exists():
        s = groovy.read_text()
        if signing and "signingConfigs.pace" not in s:
            block = (
                "    signingConfigs {\n"
                "        pace {\n"
                f"            storeFile file('{STORE}')\n"
                f"            storePassword '{STORE_PASS}'\n"
                f"            keyAlias '{ALIAS}'\n"
                f"            keyPassword '{STORE_PASS}'\n"
                "        }\n"
                "    }\n\n"
                "    buildTypes {"
            )
            s = s.replace("    buildTypes {", block, 1)
            s = s.replace("signingConfig = signingConfigs.debug", "signingConfig = signingConfigs.pace")
            s = s.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.pace")
        s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 26", s)
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", s)
        groovy.write_text(s)
        if signing and "signingConfigs.pace" not in s:
            sys.exit("Não consegui configurar a assinatura no build.gradle")
        done("build.gradle (minSdk 26" + (", assinatura fixa)" if signing else ")"))
    else:
        sys.exit("build.gradle não encontrado")

    wt = ROOT / "test" / "widget_test.dart"
    if wt.exists() and "MyApp" in wt.read_text():
        wt.unlink()
        done("removido test/widget_test.dart do modelo")


if __name__ == "__main__":
    print("Configurando Android…")
    main()
    print("Pronto.")
