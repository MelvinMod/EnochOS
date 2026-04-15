#!/bin/bash
set -e

echo "Building EnochOS..."
cd "$(dirname "$0")"

zig build iso

if [ -f "EnochOS.iso" ]; then
    echo "EnochOS.iso created successfully!"
    echo "You can run it with:"
    echo "  qemu-system-i386 -cdrom EnochOS.iso"
    echo "  # Or load in VirtualBox"
else
    echo "Error: ISO file not created"
    exit 1
fi
