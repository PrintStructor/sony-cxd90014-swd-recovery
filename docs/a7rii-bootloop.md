# [ILCE-7RM2 / α7R II] Endless boot loop after installing a PMCA app with an XML launcher icon: diagnosed over SWD, fixed with a forced updater mode and `pmca updatershell`

**TL;DR**
- **Symptom.** An α7R II (FW 4.01) went into an endless boot loop right after a third-party app (`com.a7rii.focus`, "A7RII Focus") was installed with PMCA. It restarted every ~6.3 s, the screen and EVF stayed dark, and after a few cycles it switched itself off.
- **Diagnosis.** Over SWD (test points on the main board, read-only at first), I read the Linux kernel log and the Android logcat ring buffer straight out of RAM. Every warm boot (snapshot resume), Sony's launcher **`ScalarALauncher` crashes** with
  `ClassCastException: android.graphics.drawable.GradientDrawable cannot be cast to android.graphics.drawable.BitmapDrawable` at `IconCache.cacheLocked(IconCache.java:194)`.
  The app's launcher icon is an **XML drawable** instead of a PNG bitmap. About 4 s later the watchdog resets the camera.
- **Fix.**
  1. SWD: halt core 0 in Loader3 and force the `\updater\mode` check to "present" (`r0 := 0` at `0xc01f15a2`). The camera boots the Sony updater (USB `054c:03e2`).
  2. `pmca-console updatershell`: mount the Android data partition and delete the APK, its dalvik-cache entry and its lib folder.
  3. Power-cycle. The camera boots normally again (MTP mode, USB `054c:09e7`).

  Only CPU register `r0` was changed over SWD. Apart from deleting the three app files, nothing was written to flash.
- **For app developers.** On these cameras the launcher icon **must be a bitmap (PNG)**. XML shape, vector or adaptive drawables make `ScalarALauncher` crash on every boot, which bricks the camera into a loop with no USB.

All OpenOCD configs, scripts and log excerpts are attached (see [Files](#files); paths below are relative to the repo: `tools/`, `logs/a7rii/`). Comments in the scripts are partly in German.

---

## 1. Background and symptoms

| | |
|---|---|
| Camera | Sony ILCE-7RM2 (α7R II), firmware 4.01, platform CXD90014 ("Musashi"), ~97.6k shutter actuations |
| What happened | A third-party PMCA app `com.a7rii.focus` ("A7RII Focus", unreleased, still in development by its author) was installed, as well as OpenMemories: Tweak. The camera was used normally the week before. The boot loop started right after the install. |
| Symptom | Restarts every **6.34 s on average**, no picture on screen or EVF. After roughly 7 cycles the camera switches off completely. Occasional clicking (aperture/shutter init) on every cycle. |
| USB during the loop | Only `054c:0994` ("USB Charger") blips of ~50 ms per cycle. No MTP, no mass storage, no updater, so PMCA/`updatershell` can't reach it. |
| UART (multi terminal pad 8 = `DEBUG_UART0_TXD`, 115200) | Exactly **one `0x00` byte per reboot**, otherwise silent (`console=ttynull`). |
| 56 kΩ between `AD_JACK_IN` and `AV_GND` on the multi terminal | The camera leaves the loop and stays on. This is the "adjust"/factory boot, a **cold boot without snapshot**. No USB device, and UART silent at any baud rate up to ~1 Mbaud. |

## 2. Hardware access: SWD with sewing needles, no soldering

The α7R II exposes SWD of the CXD90014 on test points on the main board **SY-1058, side A, left of IC6000** (under the heat sink). Per the Level-3 service manual:

| Test point | Signal | IC6000 ball | Probe |
|---|---|---|---|
| **CL1100** | SWCLK | W25 (the lower of the pair) | RP2040 **GP2** via 100 Ω in series |
| **CL1101** | SWDIO | W26 (the upper one, next to R6127) | RP2040 **GP3** via 100 Ω in series |
| CL1102 | FIQ | – | **do not connect** |
| GND | – | – | chassis or main-board screw |

- **IO voltage** `D_3.15V_MSS`. **Never connect 3V3/5V of the probe.**
- **Probe:** Waveshare RP2040-Zero with Raspberry Pi **debugprobe** firmware (CMSIS-DAPv2, `2e8a:000c`, FW 2.0.0). One 100 Ω series resistor per signal, soldered directly to the RP2040 pins GP2 and GP3.
- **Contact:** two sewing needles held in a helping hand, with thin stranded wire clipped to them. Nothing soldered on the camera. With the needles placed carefully, **1 MHz was bit-exact** (43 KiB/s via AHB-AP), the same as 100 kHz.
- **Minimum to power the board:** battery connector (BT-2008 to CN4909) and power switch (RL-1048 to CN4911). Display, EVF and the rear cover are not needed. For the 56 kΩ factory boot, use a multi-terminal breakout.
- Tooling: OpenOCD 0.12.0 on macOS.

> Pitfall in OpenOCD 0.12: `catch {mdw …}` / `catch {dap info …}` **swallows the command output**. Use `catch {cmd} r; echo $r`.

## 3. Stage 1, identification (read-only)

```
SWD DPIDR 0x3ba02477
AP0: AP ID 0x44770001  MEM-AP AHB3, BASE 0xffffffff (no ROM table)
AP1: AP ID 0x24770002  MEM-AP APB, BASE 0x80000000, ROM table (Fujitsu)
  0x80002000 CTI, 0x80003000 TPIU, 0x80004000 Funnel
  0x80100000 ROM table:
    0x80110000 / 0x80112000 / 0x80114000 / 0x80116000  Cortex-A5 Debug (4 cores)
    0x80111000 …  PMU, 0x80118000 … CTI, 0x8011c000 … ETM
```
This is identical to the A6000/a5000 layout (CXD90014 family). Full log: `logs/10_swd_stage1_dap_romtable.log`.

## 4. Stage 2, registers, BootROM, Loader3 (read-only)

- `MIDR 0x410fc051` (Cortex-A5 r0p1). `DBGDIDR 0x1203f001`.
- **BootROM** (`0xffff0000`, 24 KB): sha256 `81a17e039a2debfe589b127e12384ed4d7c2ba0d0c819238d0b021b466246026`. This is **byte-identical to an a5000's BootROM** ("Musashi Loader1 Ver.01.00").
- **Loader3** in RAM at `0xc01f0000` (0x21000 bytes) is intact, but it is **a different build than the a5000's Loader3**: only ~3 % identical bytes, and the strings are at other offsets. **Don't reuse A6000/a5000 Loader3 addresses on the α7R II.** See §7.
- PC samples (DBGPCSR) of core 0 in factory mode: `0x40049f40` = `wfi` in `cpu_v7_do_idle` + 8. Linux is idle and healthy.

(Dumps are not attached because they may contain device-specific data. Hashes and addresses are given instead.)

## 5. Reading the logs out of RAM

### 5.1 Kernel facts (from FW 4.01 `nflasha3/vmlinux.bin`)
- `Linux version 3.0.27_nl-rt106 … Sony CE Linux 8.2.1.9 … Wed Feb 18 2015`
- `vmlinux.bin` starts at **VA `0x40038000`**: `PAGE_OFFSET 0x40000000` (1G/3G split), `TEXT_OFFSET 0x38000`. The header words are `e321f0d3 eb005a0d`.
- **PHYS_OFFSET = `0x80000000`**. It is set by Loader3 at runtime from `\boot\loadaddr.txt`. I found it by reading the header words at candidate bases over AHB-AP.
- kallsyms is present (no `KALLSYMS_ALL`). Quirk: in this build the address table sits **12 entries before** `kallsyms_num_syms - 4*N`. My minimal parser is `tools/kallsyms30.py`.
- `emit_log_char` (`0x4006190c`) gives `log_buf_len/log_buf` at VA `0x403ed8c0/4` (default 8 KB buffer at `0x4041ff9d`) and `log_end/log_start/con_start/logged_chars` at `0x4041fad0`.
- Relevant cmdline parts: `exception.reboot=1 softlockup_panic=0 wdt.timeout=500 wdt.mode=1 warm.mode=2 warm.tmo=50000 console=ttynull exception.console_option=115200n8 initrd=0x80628000,8M tmonitor.addr=0x82000000`

### 5.2 Persistent buffers, found in the kernel log
- **`klog`**: `0x00020000 @ PA 0x834e0000`. The header is `"klog"` + length, followed by a copy of the kernel log with a magic check (`magic wrong` after a cold start, `keep logging buffer` after a warm boot). **It survives warm reboots**, so every boot cycle appends to it.
- **Android logger (`alog`)**: `PA 0x8345ffc0`, `log_main` 256 KB (trailer at `0x8349ffc0`, magic `MAIN`), `log_events` 128 KB (trailer at `0x834bffe0`), `log_radio` 64 KB. Entry format: standard `logger_entry` v1 (`u16 len, u16 pad, s32 pid, tid, sec, nsec`, then `prio, tag\0, msg\0`). Decoder: `tools/alog_lesen.py`.

### 5.3 Factory/adjust mode (56 kΩ) is a clean cold boot
Full Linux boot up to `6.018 s: MMC:Failed mcmnd_api_checkmediapower` (no card inserted, harmless). Logs `01_…`, `02_…`.

### 5.4 Normal mode is the boot loop, and every cycle is a WARMBOOT
I read the `klog` 99 times over 45 s at 1 MHz. Every cycle looks the same (`logs/03_bootloop_klog_7_warmboot_cycles.txt`):
```
[ 2.49] WARMBOOT
[ 2.54] klog: keep logging buffer: 0x00020000@0x834e0000, magic wrong nbit: 0
[ 2.54] Enabling non-boot CPUs ... CPU1..3 is up
[ 2.55] UDIF: resume start: unified drivers   (gpio … liro … usb_darwin … buspwr)
[ 2.61] UDIF: resume end:   unified drivers
[ 2.62] Restarting tasks ... done.
          <- then nothing in the kernel log; ~4 s later a silent reset
```
So the kernel, the drivers and LIRO all resume fine. There is no oops, no panic and no `Restarting system`. Something in user space dies, and the watchdog resets the camera.

### 5.5 The culprit, from the Android logcat in RAM
Reading 256 KB in one piece fails during the loop, because a reset in the middle of an AHB transfer leaves the AP stalled (`Connecting DP: stalled AP operation`). Re-plugging the probe recovers it. So I read **16 KB chunks with retries** (`tools/stufe2f_alog_stueckweise.cfg`, wrapper `tools/normalmodus_alog.sh`).

Interesting detail: **the snapshot image contains the alog buffer**. Every warm boot therefore restores the log of the original cold boot (up to `create SSBI` at 34.9 s) and appends only its own cycle. The last part of the buffer is always the cycle that was running when it was read. Two independent reads gave the same result (`logs/04_…`, full `05_…`):

```
 3.597  D/PackageManager: New apk found! name:com.github.ma1co.openmemories.tweak
 3.608  I/PackageManager: /data/app/com.a7rii.focus-1.apk changed; collecting certs
 4.242  D/PackageManager: New apk found! name:com.a7rii.focus
 4.288  D/PackageManager: broadcasting ACTION_PACKAGE_ADDED continueously for: com.a7rii.focus
 4.649  D/ScalarALauncher: onSSBCompleted
 4.697  W/System.err: android.content.res.Resources$NotFoundException: String resource ID #0x0
           at com.sony.scalar.dlsys.scalaralauncher.IconCache.cacheLocked(IconCache.java:149)   <- caught (missing label)
 4.789  D/IconCahce: entry.title = OpenMemories: Tweak                                            <- fine
 5.191  W/System.err: android.content.res.Resources$NotFoundException: String resource ID #0x0   <- caught
 5.207  D/IconCahce: entry.title = A7RII Focus
 5.250  W/dalvikvm: threadid=10: thread exiting with uncaught exception (group=0x54c7330)
 5.277  E/AndroidRuntime: FATAL EXCEPTION: ScalarALauncher-loader
java.lang.ClassCastException: android.graphics.drawable.GradientDrawable cannot be cast to android.graphics.drawable.BitmapDrawable
	at com.sony.scalar.dlsys.scalaralauncher.IconCache.cacheLocked(IconCache.java:194)
	at com.sony.scalar.dlsys.scalaralauncher.IconCache.getTitleAndIcon(IconCache.java:92)
	at com.sony.scalar.dlsys.scalaralauncher.ApplicationInfo.<init>(ApplicationInfo.java:62)
	at com.sony.scalar.dlsys.scalaralauncher.ScalarALauncherModel$LoaderTask.loadApplicationInfo(ScalarALauncherModel.java:544)
	at ...LoaderTask.loadAllAppsByBatch(ScalarALauncherModel.java:509)
	at ...LoaderTask.loadAndBindAllApps(ScalarALauncherModel.java:431)
	at ...LoaderTask.run(ScalarALauncherModel.java:346)
```
A look at the installed APK confirms it: its launcher icon is an **XML drawable**, and the package contains **no PNG bitmap at all**. The app is unreleased work in progress by its developer, so neither the APK nor any of its contents are attached here.

## 6. Why the camera can't recover on its own
- The launcher is a system component. Its loader thread dies, the UI never comes up, and a watchdog resets the board.
- The warm boot resumes the same snapshot each time, so the same package sync runs and the same crash follows, again and again.
- No USB function comes up before the crash, so PMCA can't reach the camera. The 56 kΩ factory boot is stable but has no USB either.
- So the only way in was a debug port: SWD.

## 7. Stage 3: forcing the Sony updater over SWD (α7R II addresses)

Same idea as the A6000 SWD recovery by **nicolvus** (force the `\updater\mode` check), but with the α7R II's own Loader3 addresses. **They differ from A6000/a5000.**

| What | α7R II (FW 4.01) | a5000/A6000 (for comparison) |
|---|---|---|
| `chk_updater()` function | `0xc01f1584` (mount part. 2, `\updater\mode` at `0xc01f1978`, `bl 0xc01f40d2`) | `0xc01f159a` |
| **`cmp r0,#0` after file check** (bge → return 1) | **`0xc01f15a2`** | `0xc01f15c0` |
| callers of `chk_updater` | 7 (`c01f1186 c01f1702 c01f170e c01f731c c01f74ce c01f8d54 c01f8da6`) | 8 |
| boot-mode selection ("BOM") | `0xc01f16f4`, calls `set_bootmode(r0)` `0xc01f152c` from `0xc01f1732` (lr `0xc01f1737`) | `movs r0,#3` at `0xc01f1e16` |
| mode name table | `none, cold, hot, updater, cipa, adjust, usbchrg, off, reboot, ontimer, …` | – |
| main switch → mode 3 | `0xc01f11fe` → `0xc01f12fc` → **updater loader `0xc01f1362`** | `0xc01f1378` |

**Procedure** (`tools/stufe3_updater_erzwingen.cfg`, started by `tools/stufe3_starten.sh JA`):
1. Camera in **normal mode** (boot loop), USB cable to the computer. Wait until the DP answers.
2. Poll core-0 `DBGPCSR` over the APB-AP until the PC is inside Loader3 (`0xc01f0000–0xc0211000`), then **halt**.
3. **Read-back check:** compare 5 code blocks in RAM with my earlier Loader3 dump. **Abort on any difference.**
4. Set hardware breakpoints (Thumb, 2 bytes):
   - `0xc01f15a2`: set `r0 := 0` (file "exists"), step, re-arm.
   - `0xc01f152c` (`set_bootmode`): set `r0 := 3` only when `lr == 0xc01f1737`. This was a safety net, and it turned out not to be needed.
   - `0xc01f1362`: success marker. Then remove all breakpoints and resume.
5. If a cycle is missed, retry on the next loop restart.

**Result** (`logs/20_swd_stage3_force_updater.txt`):
```
   1 ms  core 0 in Loader3 (PCSR c01f4ced) -> halt;  code check OK
2056 ms  chk_updater hit: r0 fffffed2 (-302, file not found) -> 0
         (cycle lost, retry)
6573 ms  halted again; code check OK
6746 ms  chk_updater hit: r0 fffffed2 -> 0
6840 ms  chk_updater hit: r0 fffffed2 -> 0
6931 ms  set_bootmode from BOM: mode 3 -> 3        <- forcing the file check alone already yields mode 3
7025 ms  updater loader 0xc01f1362 reached -> SUCCESS
```
About 35 s later, **`054c:03e2` (Sony updater)** enumerated on the Mac, and the camera's LED stayed solid red. The boot loop had stopped. Notes: Loader3 runs with the MMU on, but VA == PA for its region, so the AHB-AP read-back matches. Cortex-A5 has 3 BRPs, which are exactly enough.

## 8. Removing the app with `pmca updatershell`

- PMCA (`ma1co/Sony-PMCA-RE`), `updatershell` with fdat `CXD90014` / model `ILCE-7RM2`. It sends the custom updater body (runs from RAM) through the regular update protocol. **No firmware is written.**
- **On macOS, `updatershell` needs root.** The updater is a USB mass storage device and `IOUSBMassStorageDriver` grabs the interface. libusb can only detach it as root, otherwise you get `USBError: [Errno 13] Access denied`. So run it with `sudo`.
- **Keep the session open.** When `updatershell` exits, the update is "completed". I wanted backup and deletion in one session, so I drove PMCA's `UsbPlatformBackend` through a FIFO (`tools/updatershell_steuerung.py`, `tools/updatershell_starten.sh`). Supported commands: `info`, `mount` (`AMNT`), `pull`, `sh <cmd>` (busybox), `umount`, `quit`.

Session (`logs/30_pmca_updatershell_session.log`, serial removed):
```
Model: ILCE-7RM2   Firmware version: 4.01   Android platform version: 2.14
mount -> Android data mounted at /mnt          (nflasha17, vfat)
/mnt/app: com.a7rii.focus-1.apk   com.github.ma1co.openmemories.tweak-1.apk
pull  -> local backup of the affected files and system/packages.xml, packages.list (not attached)
rm /mnt/app/com.a7rii.focus-1.apk
rm /mnt/dalvik-cache/data@app@com.a7rii.focus-1.apk@classes.dex
rm -r /mnt/lib/com.a7rii.focus
sync; umount (commitBackup=0); quit -> "Done"
```
`packages.xml` was left untouched, because Android drops packages whose APK is gone. OpenMemories: Tweak was kept, since its icon is a proper bitmap.

After `quit` the camera **stayed in updater mode** (red LED, `03e2`), because the mode had been forced. A **manual power cycle** then booted it normally. The display showed **"MTP Mode"**, it enumerated as **`054c:09e7 ILCE-7RM2`**, it was stable, and the loop was gone.

## 9. Lessons / recommendations

**For PMCA app developers**
- Use a **PNG launcher icon** (`res/drawable*/ic_launcher.png`, so a `BitmapDrawable`). `ScalarALauncher`'s `IconCache.cacheLocked()` casts the icon to `BitmapDrawable` without checking. A shape, vector or layer XML drawable crashes the launcher on every boot.
- Provide an `android:label` string resource as well. A missing one throws `Resources$NotFoundException` in the same code path. That one is caught, but it's a bad sign.
- Maybe PMCA's installer could **reject or warn** about APKs whose launcher icon isn't a bitmap.

**For people with a boot-looping Sony camera after installing an app**
- If the camera still reaches any USB mode, uninstall via PMCA/updatershell. If it loops without USB, as here, SWD on CL1100/CL1101 (α7R II) is a non-destructive way in.
- The kernel `klog` (`0x834e0000`) and the Android logger (`0x8345ffc0`) persist across warm reboots, and you can read them over the AHB-AP **without halting the CPU**. They tell you exactly what crashes.
- **Verify Loader3 addresses on your own camera.** Even within CXD90014, the builds differ (α7R II vs. a5000/A6000).

## Files

`tools/` (OpenOCD 0.12 configs and scripts; comments partly German):

| File | Purpose |
|---|---|
| `stufe1_identifizieren.cfg` | DPIDR, AP info, ROM table (read-only) |
| `stufe2_nur_lesen.cfg` | core-0 regs, PC samples, BootROM and Loader3 dump (read-only) |
| `stufe2b_kernel_log.cfg` | PHYS_OFFSET probe and kernel `__log_buf` dump |
| `stufe2c_klog_alog.cfg` | dump klog and alog |
| `stufe2d_normal_schleife.cfg` | 45 s klog snapshot loop during the boot loop |
| `stufe2e_pc_verlauf.cfg` | PCSR/DSCR history of all 4 cores |
| `stufe2f_alog_stueckweise.cfg` | alog in 16 KB chunks with retries (survives resets) |
| `stufe3_updater_erzwingen.cfg` | **writes r0 only**: force updater mode (α7R II FW 4.01 addresses, read-back verified) |
| `start_stufe.sh`, `stufe3_starten.sh`, `normalmodus_alog.sh` | wrappers (stage 3 requires the argument `JA`) |
| `kernel_log_lesen.py`, `alog_lesen.py`, `kallsyms30.py` | decoders/parsers |
| `updatershell_steuerung.py`, `updatershell_starten.sh` | FIFO-controlled PMCA updatershell session (macOS, sudo) |
| `usb_lauscher.swift` | macOS IOKit USB arrival/removal logger (catches the 50 ms `0994` blips) |

`logs/`: factory-mode kernel log and klog, boot-loop klog (7 cycles), boot-loop logcat (crash excerpt and full), SWD stage logs 1/2/2b/3, PC samples, the PMCA session.

## What's next: the a5000 goes on the operating table
This α7R II was the dry run. Next up is my **a5000 (ILCE-5000)**. It is stuck in a boot loop after a bad firmware flash (no USB at all, see #752). It's the same CXD90014 platform, so the same toolchain applies: SWD with the RP2040 probe, the read-only stages first, and then stage 3 to force the updater. Its Loader3 was already analysed offline from a donor camera: the `cmp r0,#0` after the `\updater\mode` check is at `0xc01f15c0`, the same as the A6000. Unlike the α7R II, those addresses will again be verified on the camera by read-back before anything is changed. Once in the updater, the stock firmware can be flashed back. I'll report the result here.

## Credits
- **nicolvus**: the A6000 SWD "force updater" approach this builds on.
- **ma1co**: Sony-PMCA-RE / OpenMemories (updatershell made the fix possible).
- Raspberry Pi **debugprobe**, **OpenOCD**.

---

<details>
<summary><b>Kurzfassung (Deutsch)</b></summary>

- **Problem:** Eine α7R II (FW 4.01) startete nach der Installation der PMCA-App `com.a7rii.focus` alle ~6,3 s neu.
- **Diagnose:** Per SWD (CL1100/CL1101, Nähnadeln, RP2040-debugprobe) habe ich Kernel-Log und Android-Logcat aus dem RAM gelesen. Sonys `ScalarALauncher` stürzt an der App ab, weil ihr Symbol eine XML-Form statt eines PNG ist (`ClassCastException GradientDrawable → BitmapDrawable`). Danach setzt der Watchdog die Kamera zurück.
- **Lösung:**
  1. Per SWD im Loader3 `r0` an `0xc01f15a2` auf 0 setzen. Die Kamera startet dann im Sony-Updater-Modus.
  2. Mit `pmca updatershell` (unter macOS mit `sudo`) die APK, den Dalvik-Cache-Eintrag und den lib-Ordner löschen.
  3. Kamera aus- und wieder einschalten. Sie läuft wieder normal.
- Im Flash wurde außer den App-Dateien nichts verändert.
</details>
