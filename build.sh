#!/bin/bash

virt-install --connect=qemu:///system \
    --network=default \
    --initrd-inject=./fedora-qiot.ks \
    --extra-args="ks=file:/fedora-qiot.ks" \
    --name=fedora-33-qiot.aarch64 \
    --disk ./fedora-33-qiot.aarch64.raw,format=raw,size=4,bus=virtio \
    --ram 4096 \
    --vcpus=4 \
    --check-cpu \
    --accelerate \
    --virt-type qemu \
    --hvm \
    --arch aarch64 \
    --machine virt-5.1 \
    --cpu cortex-a57 \
    --location=https://fedora.mirror.garr.it/fedora/linux/releases/33/Everything/aarch64/os/ \
    --nographics --noreboot --debug

    #--extra-args="ks=file:/fedora-qiot.ks no_timer_check console=tty0 console=ttyS0,115200 net.ifnames=0 biosdevname=0" \
