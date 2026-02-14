#!/usr/bin/env python3
"""
DNS Registrar - Registers hostnames from caddy labels in Pi-hole v6 DNS.
"""
import os
import subprocess
import json
import re
import time

# Configuration from environment
PIHOLE_CONTAINER = os.environ.get('PIHOLE_CONTAINER', 'bridgecade-pihole')
DOMAIN_SUFFIX = os.environ.get('DOMAIN_SUFFIX', 'synth.home.arpa')
INGRESS_IP = os.environ.get('INGRESS_IP', '127.0.0.1')

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
            match = re.search(r'caddy=([^,\s]+)', line)
            if match:
                hostname = match.group(1)
                if hostname and not hostname.startswith('{'):
                    hostnames.add(hostname)
    except subprocess.CalledProcessError as e:
        print(f"Error getting container labels: {e}")
    return hostnames

def update_pihole_dns(hostnames):
    """Update Pi-hole v6 DNS with hostnames pointing to ingress IP."""
    if not hostnames:
        return
    
    # Pi-hole v6: use JSON array format for misc.dnsmasq_lines
    lines = []
    for hostname in sorted(hostnames):
        lines.append(f"address=/{hostname}/{INGRESS_IP}")
    
    # Convert to JSON array
    config_value = json.dumps(lines)
    
    try:
        # Update Pi-hole v6 config
        result = subprocess.run(
            ['docker', 'exec', PIHOLE_CONTAINER, 'pihole-FTL', '--config', 'misc.dnsmasq_lines', config_value],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            # Reload DNS (v6 uses reloaddns, not restartdns)
            subprocess.run(
                ['docker', 'exec', PIHOLE_CONTAINER, 'pihole', 'reloaddns'],
                capture_output=True
            )
            print(f"✓ DNS updated with {len(hostnames)} hostnames")
        else:
            print(f"✗ Failed to update Pi-hole config: {result.stderr}")
    except subprocess.CalledProcessError as e:
        print(f"✗ Failed to update Pi-hole DNS: {e}")

def main():
    """Main loop - watch for Docker events and update DNS."""
    print("DNS Registrar starting...")
    print(f"PIHOLE_CONTAINER: {PIHOLE_CONTAINER}")
    print(f"DOMAIN_SUFFIX: {DOMAIN_SUFFIX}")
    print(f"INGRESS_IP: {INGRESS_IP}")
    
    # Initial scan
    print("Scanning existing containers...")
    hostnames = get_hostnames_from_labels()
    update_pihole_dns(hostnames)
    
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
                update_pihole_dns(hostnames)
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
            update_pihole_dns(hostnames)

if __name__ == '__main__':
    main()
