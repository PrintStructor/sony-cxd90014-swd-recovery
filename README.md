# Sony CXD90014 (BIONZ X) SWD recovery notes

Non-destructive debugging and recovery of boot-looping Sony cameras over **SWD**, using a cheap RP2040 probe (debugprobe/CMSIS-DAP), OpenOCD and PMCA's `updatershell`. No soldering on the camera (sewing needles on test points).

| Case | Status | Write-up |
|---|---|---|
| **ILCE-7RM2 (α7R II)**, FW 4.01: boot loop after installing a PMCA app with an XML launcher icon | ✅ **fixed** | [docs/a7rii-bootloop.md](docs/a7rii-bootloop.md) |
| **ILCE-5000 (a5000)**: boot loop after a bad firmware flash | 🔧 next on the operating table | (coming) |

## What's in here
- `tools/`: OpenOCD configs (read-only stages 1–2f, stage 3 = force the Sony updater by setting `r0` only), wrappers, log decoders (kernel `__log_buf`, persistent `klog`, Android logger), kallsyms parser, a FIFO-controlled PMCA updatershell session (macOS), an IOKit USB logger, and `check_apk.sh` (pre-install check for PMCA apps).
- `logs/a7rii/`: kernel log, klog, logcat and SWD/PMCA session logs (serials removed).
- `docs/`: write-ups and images.

## Key findings (short)
- α7R II SWD: **CL1100 = SWCLK, CL1101 = SWDIO** (SY-1058 side A, left of IC6000). `DPIDR 0x3ba02477`, 4× Cortex-A5.
- You can read the kernel `klog` (`PA 0x834e0000`) and the Android logger (`PA 0x8345ffc0`) over the AHB-AP **while the camera runs**. Both survive warm reboots.
- PMCA app developers: **use a PNG launcher icon.** Sony's `ScalarALauncher` casts icons to `BitmapDrawable`, and anything else boot-loops the camera.
- Loader3 addresses differ between models (α7R II vs. a5000/A6000). **Always verify by read-back.**

## Disclaimer
Everything here is at your own risk. Stage 3 changes a CPU register during boot (nothing persistent), but opening a camera and probing test points can damage it. Device dumps (BootROM/Loader/NAND) are intentionally **not** included.

## Credits
nicolvus (A6000 SWD updater approach), ma1co (Sony-PMCA-RE / OpenMemories), Raspberry Pi debugprobe, OpenOCD.
