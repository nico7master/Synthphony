# Client Setup Guide for Synthphony

This guide covers setting up your local PC, phone, and other devices to access Synthphony services securely over HTTPS.

---

## Table of Contents

1. [Copy the CA Certificate from Server](#1-copy-the-ca-certificate-from-server)
2. [Install CA on Linux (Local PC)](#2-install-ca-on-linux-local-pc)
3. [Install CA on macOS](#3-install-ca-on-macos)
4. [Install CA on Windows](#4-install-ca-on-windows)
5. [Install CA on Android](#5-install-ca-on-android)
6. [Install CA on iOS](#6-install-ca-on-ios)
7. [Verify Installation](#7-verify-installation)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Copy the CA Certificate from Server

The mkcert CA certificate is stored on your Synthphony server. Copy it to your local device:

```bash
# Replace 192.168.178.100 with your Synthphony server IP
scp home-server@192.168.178.100:/opt/Synthphony/BridgeCade/mkcert-ca/rootCA.pem ~/Downloads/synthphony-ca.pem
```

---

## 2. Install CA on Linux (Local PC)

### System-Wide Trust (for curl, wget, etc.)

```bash
# Copy to system CA store
sudo cp ~/Downloads/synthphony-ca.pem /usr/local/share/ca-certificates/synthphony-ca.crt
sudo update-ca-certificates
```

### Chrome/Chromium (uses NSS database)

```bash
# Install certutil if missing
sudo apt install libnss3-tools

# Install CA into Chrome's trust store
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "Synthphony mkcert CA" -i ~/Downloads/synthphony-ca.pem

# Verify installation
certutil -d sql:$HOME/.pki/nssdb -L | grep -i synth
```

**Remove old/conflicting CAs first:**

```bash
# List existing mkcert CAs
certutil -d sql:$HOME/.pki/nssdb -L | grep -i mkcert

# Delete old one (use exact name from list)
certutil -d sql:$HOME/.pki/nssdb -D -n "mkcert development CA"
```

### Firefox

**Option A: Command Line**

```bash
# Find Firefox profile
FIREFOX_PROFILE=$(find ~/.mozilla/firefox -name '*.default-release' -type d 2>/dev/null | head -1)

# Install CA
if [ -n "$FIREFOX_PROFILE" ]; then
    certutil -d sql:"$FIREFOX_PROFILE" -A -t "C,," -n "Synthphony mkcert CA" -i ~/Downloads/synthphony-ca.pem
fi
```

**Option B: Manual (GUI)**

1. Open Firefox → Settings → Privacy & Security
2. Scroll to Certificates → View Certificates
3. Authorities tab → Import
4. Select `~/Downloads/synthphony-ca.pem`
5. Check "Trust this CA to identify websites"
6. Click OK

**Restart browser completely after installation!**

---

## 3. Install CA on macOS

1. Copy `synthphony-ca.pem` to your Mac
2. Double-click the file → Keychain Access opens
3. Find "mkcert" certificate → Double-click
4. Expand "Trust" section
5. Set "When using this certificate" to "Always Trust"
6. Close and enter password to save

**Or via command line:**

```bash
# Add to system keychain
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/synthphony-ca.pem
```

---

## 4. Install CA on Windows

1. Copy `synthphony-ca.pem` to Windows
2. Rename to `synthphony-ca.crt` (change extension)
3. Double-click the file
4. Click "Install Certificate"
5. Select "Local Machine" → Next
6. Select "Place all certificates in the following store"
7. Click "Browse" → Select "Trusted Root Certification Authorities"
8. Click OK → Next → Finish
9. Click "Yes" on the security warning

**Or via PowerShell (Admin):**

```powershell
# Import certificate
Import-Certificate -FilePath "C:\Users\YourName\Downloads\synthphony-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

**Restart browsers after installation!**

---

## 5. Install CA on Android

### Method 1: Settings (Android 11+)

1. Copy `synthphony-ca.pem` to your phone (email, cloud, or USB)
2. Open Settings → Security → Encryption & credentials
3. Tap "Install a certificate" → "CA certificate"
4. Tap "Install anyway" on the warning
5. Select the `synthphony-ca.pem` file
6. Enter PIN/password if prompted

### Method 2: Certificate Installer

1. Open the file manager and tap `synthphony-ca.pem`
2. Select "Certificate Installer" if prompted
3. Enter a name: "Synthphony CA"
4. Tap OK

**Note:** Some Android versions require installing via Wi-Fi settings:
- Settings → Network & Internet → Wi-Fi → Wi-Fi preferences → Advanced → Install certificates

---

## 6. Install CA on iOS

1. Copy `synthphony-ca.pem` to your iPhone (AirDrop, email, or cloud)
2. Open the file → Tap "Allow" to download profile
3. Go to Settings → General → VPN & Device Management
4. Tap "Synthphony CA" under "Downloaded Profile"
5. Tap "Install" → Enter passcode → Tap "Install" again
6. Go to Settings → General → About → Certificate Trust Settings
7. Enable "Synthphony CA" under "Enable Full Trust for Root Certificates"
8. Tap "Continue" on the warning

**Restart Safari after installation!**

---

## 7. Verify Installation

### Test HTTPS Access

Open your browser and navigate to:
- https://agentzero.synth.home.arpa
- https://nextcloud.synth.home.arpa

You should see a **lock icon** (🔒) without any warnings.

### Command Line Test

```bash
# Test with curl (should show no certificate errors)
curl -I https://agentzero.synth.home.arpa

# Should return HTTP/2 200 without SSL errors
```

### Browser Test

1. Open https://agentzero.synth.home.arpa
2. Click the lock icon in the address bar
3. View certificate → Should show "Synthphony mkcert CA" as the issuer

---

## 8. Troubleshooting

### "Your connection is not private" / Certificate Error

**Cause:** CA not properly installed or browser using cached certificates.

**Fix:**
1. Verify CA is installed (check system certificate store)
2. Clear browser cache and restart browser
3. Try incognito/private mode
4. Check if multiple mkcert CAs exist and remove old ones

### curl: SSL certificate problem

**Cause:** System CA store doesn't include the mkcert CA.

**Fix:**
```bash
# Re-run system CA update
sudo update-ca-certificates

# Or use --cacert flag temporarily
curl --cacert ~/Downloads/synthphony-ca.pem https://agentzero.synth.home.arpa
```

### Firefox still shows warning after installation

**Cause:** Firefox uses its own certificate store.

**Fix:**
1. Go to about:config in Firefox
2. Search for `security.enterprise_roots.enabled`
3. Set to `true` (allows Firefox to use system CA store)
4. Restart Firefox

### Android: "Certificate not installed"

**Cause:** Some Android versions restrict CA installation.

**Fix:**
- Use a file manager app to open the .pem file
- Or install via Wi-Fi settings (see Section 5)

### iOS: Profile not appearing

**Cause:** Profile download didn't complete.

**Fix:**
1. Re-send the file via AirDrop or email
2. Open Settings → General → Profiles (should show pending profile)
3. Complete installation

### Works on WiFi but not on 5G/Cellular

**Cause:** Phone using carrier DNS which can't resolve `synth.home.arpa`.

**Fix:**
- Configure Tailscale DNS (see TAILSCALE-SETUP.md)
- Or use WireGuard VPN

---

## Quick Reference

| Platform | Location | Command/Path |
|----------|----------|--------------|
| Linux (system) | `/usr/local/share/ca-certificates/` | `sudo update-ca-certificates` |
| Linux (Chrome) | NSS database | `certutil -d sql:$HOME/.pki/nssdb -A ...` |
| macOS | Keychain | `security add-trusted-cert ...` |
| Windows | Certificate Store | `Import-Certificate ...` |
| Android | Settings → Security | Install from file |
| iOS | Settings → General | Profile installation |

---

**Next Steps:**
- [TAILSCALE-SETUP.md](TAILSCALE-SETUP.md) - For remote access from anywhere
- [FIRST-TIME-SETUP-GUIDE.txt](FIRST-TIME-SETUP-GUIDE.txt) - Complete server setup guide
