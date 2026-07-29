#!/usr/bin/env bash
# Gate local del Cert Lab. No toca el Sync Engine.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== Cert Lab protocolo (GREEN obligatorio) =="
flutter test test/cert/lab/cert_lab_protocol_test.dart test/cert/lab/cert_lab_oracle_test.dart
echo "== Cert Lab full (informe; P0-99 puede ser ROJO) =="
flutter test test/cert/lab/cert_lab_battery_test.dart
echo "OK — laboratorio ejecutado."
