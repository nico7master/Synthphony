#!/bin/bash
set -euo pipefail

echo "═══ PHASE 1: INSPECT /dev/sda2 ═══"
echo ""

sudo apt-get install -y exfat-fuse exfatprogs 2>/dev/null || true
sudo mkdir -p /mnt/inspect
sudo mount -o ro /dev/sda2 /mnt/inspect 2>/dev/null || {
    echo "Could not mount as exfat — trying with fuse..."
    sudo mount.exfat-fuse /dev/sda2 /mnt/inspect 2>/dev/null || true
}

echo "--- Contents of /dev/sda2 ---"
ls -la /mnt/inspect/ 2>/dev/null || echo "(empty or cannot read)"
echo ""
echo "--- Size breakdown ---"
sudo du -sh /mnt/inspect/* 2>/dev/null || echo "(empty or cannot read)"
echo ""

ITEMS=$(ls -A /mnt/inspect/ 2>/dev/null | wc -l)
sudo umount /mnt/inspect 2>/dev/null || true

if [ "$ITEMS" -gt 0 ]; then
    echo "⚠️  /dev/sda2 has $ITEMS items. Review above before continuing."
    echo "   Copy anything you need off it, then re-run with: $0 --force"
    exit 1
fi

echo "✅ /dev/sda2 appears empty. Proceeding to Phase 2."
echo ""

echo "═══ PHASE 2: FORMAT /dev/sda2 → ext4 ═══"
read -p "This ERASES /dev/sda2. Type YES to continue: " confirm
[ "$confirm" = "YES" ] || { echo "Aborted."; exit 1; }

sudo umount /dev/sda2 2>/dev/null || true
sudo wipefs -a /dev/sda2
sudo mkfs.ext4 -L SYNTH-HDD /dev/sda2
echo "✅ Formatted as ext4"
echo ""

echo "═══ PHASE 3: MIGRATE /mnt/hdd ═══"
echo "Stopping Docker..."
sudo systemctl stop docker docker.socket
echo ""

echo "Moving current /mnt/hdd aside..."
sudo mv /mnt/hdd /mnt/hdd.onroot
sudo mkdir -p /mnt/hdd

UUID=$(sudo blkid -s UUID -o value /dev/sda2)
echo "UUID=${UUID}" > /tmp/sda2-uuid.txt
echo "Mounting /dev/sda2 (UUID=${UUID}) at /mnt/hdd..."
echo "UUID=${UUID}  /mnt/hdd  ext4  defaults,nofail,x-systemd.device-timeout=30  0  2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount /mnt/hdd
mountpoint /mnt/hdd && echo "✅ Mounted" || { echo "❌ Mount failed!"; exit 1; }
echo ""

echo "Copying 42GB of data (this takes a few minutes)..."
sudo rsync -aHAX --info=progress2 /mnt/hdd.onroot/ /mnt/hdd/
echo "✅ Data copied"
echo ""

echo "Verifying..."
ORIG_SIZE=$(sudo du -sb /mnt/hdd.onroot/ | cut -f1)
NEW_SIZE=$(sudo du -sb /mnt/hdd/ | cut -f1)
echo "Original: $(numfmt --to=iec $ORIG_SIZE)"
echo "Copied:   $(numfmt --to=iec $NEW_SIZE)"

if [ "$ORIG_SIZE" != "$NEW_SIZE" ]; then
    echo "⚠️  Size mismatch! Not removing old data. Check manually."
    exit 1
fi
echo "✅ Sizes match"
echo ""

echo "═══ PHASE 4: RESTART ═══"
echo "Starting Docker..."
sudo systemctl start docker
echo "Waiting 30s for containers..."
sleep 30
docker ps --format '{{.Names}}: {{.Status}}' | head -10
echo ""

echo "═══ PHASE 5: CLEANUP ═══"
read -p "Everything looks good? Remove old /mnt/hdd.onroot? (yes/no): " cleanup
if [ "$cleanup" = "yes" ]; then
    sudo rm -rf /mnt/hdd.onroot
    echo "✅ Old data removed"
else
    echo "Old data kept at /mnt/hdd.onroot — remove manually when ready"
fi

echo ""
echo "═══ DONE ═══"
df -h /mnt/hdd /
