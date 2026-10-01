# lars13 TLS cert maker (Windows port of server/scripts/make-certs.sh)
# Run in PowerShell: create self-signed cert, export pem pair, trust via certutil.
# Browser mic requires TLS (secure origin). Trust step needs a normal (non-admin)
# certutil -user addstore.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot        # repo root
$certDir = Join-Path $root "server\certs"
New-Item -ItemType Directory -Force -Path $certDir | Out-Null

$cert = New-SelfSignedCertificate -Type SSLServerAuthentication `
    -DnsName "localhost", "127.0.0.1", "lars13.local" `
    -FriendlyName "lars13 HUD dev" `
    -NotAfter (Get-Date).AddYears(5) `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable

# export to pem pair the server expects
$pwd_ = ConvertTo-SecureString -String "lars13" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath (Join-Path $certDir "cert.pfx") -Password $pwd_ | Out-Null
$cerPath = Join-Path $certDir "jarvis.cer"
Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null

# convert to pem key/cert using dotnet-free approach: openssl if present else python cryptography
$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if ($openssl) {
    openssl pkcs12 -in (Join-Path $certDir "cert.pfx") -passin pass:lars13 -passout pass:lars13 -out (Join-Path $certDir "key.pem") -nodes
    openssl pkcs12 -in (Join-Path $certDir "cert.pfx") -passin pass:lars13 -nokeys -out (Join-Path $certDir "cert.pem")
    "openssl conversion done"
} else {
    "openssl not found - install Git Bash available openssl or run: winget install openssl"
    "will use python cryptography fallback"
    & (Join-Path $root ".venv\Scripts\python.exe") -c @"
from cryptography.hazmat.primitives.serialization import pkcs12, BestAvailableEncryption, Encoding, PrivateFormat
data = open(r'$certDir\cert.pfx','rb').read()
key, cert, additional = pkcs12.load_key_and_certificates(data, b'lars13')
open(r'$certDir\key.pem','wb').write(key.private_bytes(Encoding.PEM, PrivateFormat.TraditionalOpenSSL, BestAvailableEncryption(b'lars13')))
open(r'$certDir\cert.pem','wb').write(cert.public_bytes(Encoding.PEM))
print('python cryptography conversion done')
"@
    uv pip install --python (Join-Path $root ".venv\Scripts\python.exe") cryptography | Out-Null
}

# trust (user store, no admin needed)
certutil -user -addstore Root $cerPath

Write-Host "TLS ready: server\certs\cert.pem + key.pem; trusted in CurrentUser Root store."
