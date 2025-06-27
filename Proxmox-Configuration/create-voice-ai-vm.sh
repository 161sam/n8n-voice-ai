#!/bin/bash
# create-voice-ai-vm.sh

VM_ID=200
VM_NAME="n8n-voice-ai"
MEMORY=32768  # 32GB RAM
CORES=16      # 16 CPU cores
DISK_SIZE=200G
ISO_PATH="local:iso/ubuntu-22.04.3-live-server-amd64.iso"

# Create VM
qm create $VM_ID \
  --name $VM_NAME \
  --numa 0 \
  --ostype l26 \
  --cpu host \
  --cores $CORES \
  --memory $MEMORY \
  --balloon 16384 \
  --agent enabled=1 \
  --net0 virtio,bridge=vmbr0,firewall=1 \
  --scsi0 local-lvm:$DISK_SIZE,cache=writeback,discard=on \
  --ide2 $ISO_PATH,media=cdrom \
  --boot order=scsi0;ide2 \
  --vga serial0 \
  --serial0 socket

# Add GPU passthrough (optional)
# qm set $VM_ID --hostpci0 01:00,pcie=1

# Start VM
qm start $VM_ID

echo "VM $VM_NAME (ID: $VM_ID) created and started"
echo "Access console with: qm terminal $VM_ID"
