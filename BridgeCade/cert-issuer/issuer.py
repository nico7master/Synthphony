#!/usr/bin/env python3
"""
Cert Issuer - Listens to Docker events and generates mkcert certificates
for services with caddy labels.
"""
import os
import subprocess
import json
import time
import re
from pathlib import Path

# Configuration from environment
CAROOT = os.environ.get('CAROOT', '/mkcert-ca')
CERT_DIR = os.environ.get('CERT_DIR', '/certs')
DOMAIN_SUFFIX = os.environ.get('DOMAIN_SUFFIX', 'synth.home.arpa')

def get_hostnames_from_labels():
    """Extract hostnames from running containers' caddy labels."""
    hostnames = set()
    try:
        result = subprocess.run(
            ['docker', 'ps', '--format', '{{.Labels}}'],
            capture_output=True, text=True, check=True
        )
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            # Look for caddy=<hostname> pattern
            match = re.search(r'caddy=([^,\s]+)', line)
            if match:
                hostname = match.group(1)
                if hostname and not hostname.startswith('{'):
                    hostnames.add(hostname)
    except subprocess.CalledProcessError as e:
        print(f"Error getting container labels: {e}")
    return hostnames

def ensure_certificate(hostname):
    """Ensure a certificate exists for the given hostname."""
    cert_path = Path(CERT_DIR) / f"{hostname}.crt"
    key_path = Path(CERT_DIR) / f"{hostname}.key"
    
    if cert_path.exists() and key_path.exists():
        return True
    
    print(f"Generating certificate for {hostname}...")
    try:
        # Set CAROOT for mkcert
        env = os.environ.copy()
        env['CAROOT'] = CAROOT
        
        # Generate certificate
        subprocess.run(
            ['mkcert', '-cert-file', str(cert_path), '-key-file', str(key_path), hostname],
            env=env, check=True, capture_output=True
        )
        print(f"✓ Certificate generated: {hostname}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ Failed to generate certificate for {hostname}: {e}")
        return False

def main():
    """Main loop - watch for Docker events and generate certificates."""
    print("Cert Issuer starting...")
    print(f"CAROOT: {CAROOT}")
    print(f"CERT_DIR: {CERT_DIR}")
    print(f"DOMAIN_SUFFIX: {DOMAIN_SUFFIX}")
    
    # Ensure directories exist
    Path(CAROOT).mkdir(parents=True, exist_ok=True)
    Path(CERT_DIR).mkdir(parents=True, exist_ok=True)
    
    # Install mkcert CA if not already done
    try:
        subprocess.run(['mkcert', '-install'], check=True, capture_output=True)
        print("✓ mkcert CA installed")
    except subprocess.CalledProcessError as e:
        print(f"Warning: mkcert -install failed: {e}")
    
    # Initial scan
    print("Scanning existing containers...")
    hostnames = get_hostnames_from_labels()
    for hostname in hostnames:
        ensure_certificate(hostname)
    
    # Watch for events
    print("Watching for Docker events...")
    try:
        process = subprocess.Popen(
            ['docker', 'events', '--filter', 'event=start', '--filter', 'event=create', '--format', '{{json .}}'],
            stdout=subprocess.PIPE, text=True
        )
        
        for line in process.stdout:
            try:
                event = json.loads(line)
                # Re-scan all hostnames on any container event
                hostnames = get_hostnames_from_labels()
                for hostname in hostnames:
                    ensure_certificate(hostname)
            except json.JSONDecodeError:
                continue
            except Exception as e:
                print(f"Error processing event: {e}")
                
    except KeyboardInterrupt:
        print("\nShutting down...")
    except Exception as e:
        print(f"Error: {e}")
        # Fallback: periodic scan
        while True:
            time.sleep(30)
            hostnames = get_hostnames_from_labels()
            for hostname in hostnames:
                ensure_certificate(hostname)

if __name__ == '__main__':
    main()
