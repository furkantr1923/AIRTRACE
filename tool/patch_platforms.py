#!/usr/bin/env python3
"""`flutter create` ile üretilen Android/Windows dosyalarını AIRTRACE için yapılandırır.

Bir kez (bootstrap iş akışında) çalışır; sonuç depoya commit edilir.
İdempotenttir: tekrar çalıştırılırsa aynı sonucu verir.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.')


def edit(rel, fn):
    p = ROOT / rel
    s = p.read_text(encoding='utf-8')
    n = fn(s)
    if n != s:
        p.write_text(n, encoding='utf-8')
        print('patched', rel)


# ---------------- Android ----------------
def manifest(s):
    s = re.sub(r'android:label="[^"]*"', 'android:label="AIRTRACE"', s, count=1)
    perms = (
        '    <uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n'
        '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n'
        '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
    )
    if 'android.permission.INTERNET' not in s:
        s = re.sub(r'(<manifest[^>]*>\n)', r'\1' + perms, s, count=1)
    return s


edit('android/app/src/main/AndroidManifest.xml', manifest)

SIGNING_KTS = '''
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
'''


def gradle(s):
    if 'keystoreProperties' in s:
        return s
    s = re.sub(r'(plugins \{.*?\n\}\n)', r'\1' + SIGNING_KTS, s, count=1, flags=re.S)
    s = re.sub(r'(\n    defaultConfig \{)', '''
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
\\1''', s, count=1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                  'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") '
                  'else signingConfigs.getByName("debug")')
    return s


edit('android/app/build.gradle.kts', gradle)

# ---------------- Windows ----------------
edit('windows/CMakeLists.txt', lambda s: re.sub(r'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "AIRTRACE")', s))
edit('windows/runner/main.cpp', lambda s: s
     .replace('window.Create(L"airtrace", origin, size)', 'window.Create(L"AIRTRACE", origin, size)')
     .replace('Win32Window::Size size(1280, 720);', 'Win32Window::Size size(1360, 820);')
     .replace('Win32Window::Point origin(10, 10);', 'Win32Window::Point origin(60, 40);'))


def rc(s):
    s = re.sub(r'VALUE "CompanyName", "[^"]*"', 'VALUE "CompanyName", "Furkan Baykal"', s)
    s = re.sub(r'VALUE "FileDescription", "[^"]*"', 'VALUE "FileDescription", "AIRTRACE - Canli Ucak Takibi"', s)
    s = re.sub(r'VALUE "InternalName", "[^"]*"', 'VALUE "InternalName", "AIRTRACE"', s)
    s = re.sub(r'VALUE "LegalCopyright", "[^"]*"', 'VALUE "LegalCopyright", "Copyright (C) 2026 Furkan Baykal"', s)
    s = re.sub(r'VALUE "OriginalFilename", "[^"]*"', 'VALUE "OriginalFilename", "AIRTRACE.exe"', s)
    s = re.sub(r'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "AIRTRACE"', s)
    return s


edit('windows/runner/Runner.rc', rc)
print('ok')
