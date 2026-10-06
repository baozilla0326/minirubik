#!/bin/sh
# Build one reference ELF per distance-11 state (renderer-free, RV32I only).
# Usage: sh measure/all11_build.sh   (from the repository root)
set -e
./ida --list11 | sed -n 's/^\([0-9]\{14\}\) \([0-9]*\)$/\1 \2/p' > measure/dist11.txt
mkdir -p measure/all11
while read -r state nodes; do
    riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding \
        -nostdlib -nostartfiles -static -DINPUT="\"$state\"" \
        -o "measure/all11/$state.elf" rubik_ref.c
done < measure/dist11.txt
echo "built $(ls measure/all11 | wc -l) ELF files"
