# MSX Expanded I/O Front Panel LED Indicator Specification (Device ID 168)

**Category:** Standards Track  
**Date:** November 13, 2026  
**Device ID:** `168` (`A8H`)  
**Status:** Draft / Experimental  

---

## Abstract

This document specifies an MSX Expansion I/O peripheral assigned to Device ID `168` (`A8H`), providing an 8-bit output register at I/O port `41H` (`0x41`) to drive an 8-LED mainframe-style front panel status array. It defines physical LED requirements, boot progress indicator conventions aligned with [RomWBW](https://smallcomputercentral.com/romwbw/romwbw-getting-started/ "RomWBW Getting Started diagnostic LEDs"), extensibility for alternative operating environments such as [Nextor](https://msx.org "Nextor MSX-DOS kernel"), and Z80 assembly detection routines.

---

## 1. Introduction

Traditional Z80 homebrew systems (such as RC2014 and RetroBrew platforms) frequently dedicate a fixed I/O port (commonly `00H`) to drive an 8-LED front panel diagnostic bar. On MSX computers, however, I/O port `00H` falls within the `00H`–`3FH` user-reserved space and cannot be safely claimed by standardized system peripherals.

To integrate a mainframe-style front panel status display into the MSX ecosystem without I/O collisions, this specification defines an MSX Expansion I/O device operating under the `40H`–`4FH` multiplexed I/O protocol. Front panel boot configuration switches are explicitly outside the scope of this document and are governed by a separate companion specification.

---

## 2. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

* **Device ID `168` (`A8H`):** The universal MSX Expansion I/O identifier assigned to this front panel LED controller (within the `128`–`254` universal peripheral range).
* **Output Register (`41H`):** The 8-bit write-only latch mapped to I/O port `41H` when Device ID `168` is active.
* **Active-High Bit Mapping:** A logical `1` written to bit $n$ (`D0`–`D7`) illuminates LED $n$, while a logical `0` extinguishes it.

---

## 3. Physical and Energy Compliance Requirements

### 3.1. Optical and Color Specification
* All eight status indicators (`LED0` through `LED7`) **MUST BE red** (peak wavelength ~625–635 nm) to satisfy classic mainframe front panel aesthetics and Energy Star–compliant low-power indicator guidelines.
* High-efficiency red LEDs driven at low forward current (≤ 2–5 mA per segment) **SHOULD** be used to minimize continuous standby and operational power draw across the MSX cartridge/expansion bus.

### 3.2. Physical Layout
* Indicators **SHOULD** be arranged linearly from left (`D7` / MSB) to right (`D0` / LSB) on the enclosure front panel to match binary progress bar conventions.

---

## 4. Protocol and Register Definition

This device adheres strictly to the **MSX Expansion I/O Port Specification**.

### 4.1. Device Selection and Identification (`40H`)
* **Power-On / Reset:** Upon `/RESET`, the device **MUST** disconnect from the CPU bus and clear its internal output latch to `00H` (all LEDs extinguished).
* **Selection:** Writing `168` (`A8H`) to I/O port `40H` selects the device and enables access to port `41H`. Writing any other byte deselects the device while preserving the current state of the LED output latch.
* **Identification Readback:** Reading port `40H` while Device `168` (`A8H`) is selected **MUST** return `~A8H` = **`57H` (`87` decimal)**.

### 4.2. LED Output Register (`41H`)
* **Address:** `41H` (`0x41`)
* **Access:** Write-Only (when Device `168` is selected)
* **Bit Assignment:**

| Bit | `D7` | `D6` | `D5` | `D4` | `D3` | `D2` | `D1` | `D0` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Indicator** | `LED7` | `LED6` | `LED5` | `LED4` | `LED3` | `LED2` | `LED1` | `LED0` |
| **Weight** | `80H` | `40H` | `20H` | `10H` | `08H` | `04H` | `02H` | `01H` |

---

## 5. Boot Progress and Runtime Indicator Conventions

### 5.1. Recommended Boot Progress Flags ([RomWBW](https://smallcomputercentral.com/romwbw/romwbw-getting-started/ "RomWBW Getting Started diagnostic LEDs") Profile)
Firmware and BIOS implementations targeting RomWBW-compatible diagnostics **SHOULD** use the progressive thermometer-code bitmasks defined by the [RomWBW](https://github.com/wwarthen/RomWBW "RomWBW GitHub repository") front panel specification during system initialization:

| Binary (`D7`..`D0`) | Hex | Recommended Boot Stage Milestone |
| :---: | :---: | :--- |
| `0000 0000` | `00H` | Hardware `/RESET` state; interrupts disabled |
| `0000 0001` | `01H` | Start of hardware initialization |
| `0000 0010` | `02H` | Memory mapper / bank controller setup |
| `0000 0011` | `03H` | System BIOS / HBIOS relocation to RAM |
| `0000 0111` | `07H` | Page zero and interrupt vector initialization |
| `0000 1111` | `0FH` | CPU type, clock speed, and slot detection |
| `0001 1111` | `1FH` | System heap and work area allocation |
| `0011 1111` | `3FH` | Pre-console and peripheral bus initialization |
| `0111 1111` | `7FH` | Console activation and firmware banner output |
| `1111 1111` | `FFH` | Boot complete; system ready / OS handoff |

### 5.2. Alternative Firmware and OS Profiles (e.g., [Nextor](https://msx.org "Nextor MSX-DOS kernel"))
Because MSX systems run diverse operating environments, firmware implementations **MAY** substitute alternative bit patterns suited to their boot architecture:
* **Nextor / MSX-DOS Profile:** Implementations **MAY** map individual bits to slot-search progress, drive letter assignments (`A:` through `H:`), or active storage LUN/device activity once the kernel has booted.
* **Post-Boot Runtime Mode:** After system initialization completes, the operating system or resident driver **MAY** repurpose the 8 bits as a real-time drive activity monitor (Units `0`–`7`), CPU load bar, or user-controlled status register.

---

## 6. Reference Z80 Assembly Implementation

The following Z80 assembly routine detects whether Device ID `168` (`A8H`) is present on the MSX Expansion I/O bus and, if detected, illuminates all eight red front panel LEDs (`FFH`) before restoring the previously active expansion device.

```z80
; ==============================================================================
; MSX Expanded I/O Front Panel LED Driver (Device ID 168 / 0xA8)
; ==============================================================================

EXP_IO_SEL  EQU     40H         ; MSX Expansion I/O selection port
EXP_IO_DATA EQU     41H         ; Front panel LED output register
LED_DEV_ID  EQU     168         ; Device ID 168 (0A8H)
LED_DEV_INV EQU     057H        ; Expected complement (~0A8H = 057H)

; ------------------------------------------------------------------------------
; Routine: DETECT_AND_ALL_ON
; Purpose: Detects Device ID 168 and turns on all 8 LEDs if present.
; Output:  Carry Flag (CF) = 0 if detected and updated; CF = 1 if not present.
; Clobbers: AF, B
; ------------------------------------------------------------------------------
DETECT_AND_ALL_ON:
        DI                      ; Prevent ISR bus contention during I/O switch

        IN      A, (EXP_IO_SEL) ; Read current complement ID
        CPL                     ; Invert to get previously active Device ID
        LD      B, A            ; Save previous Device ID in B

        LD      A, LED_DEV_ID   ; Select Device ID 168 (0A8H)
        OUT     (EXP_IO_SEL), A

        IN      A, (EXP_IO_SEL) ; Read back complement ID from port 40H
        CP      LED_DEV_INV     ; Does it match ~0A8H (057H)?
        JR      NZ, .NOT_FOUND  ; If not, hardware is absent

        ; Device detected: turn on all 8 red LEDs
        LD      A, 0FFH         ; Bitmask 11111111b (all LEDs ON)
        OUT     (EXP_IO_DATA), A

        ; Restore previous expansion device and return success
        LD      A, B
        OUT     (EXP_IO_SEL), A
        EI
        OR      A               ; Clear Carry Flag (success)
        RET

.NOT_FOUND:
        ; Restore previous expansion device and return failure
        LD      A, B
        OUT     (EXP_IO_SEL), A
        EI
        SCF                     ; Set Carry Flag (device not present)
        RET
```

---

## 7. Related Documents

* **MSX Expansion I/O Port Manual** (ASCII MS FE HQ, December 1985) — Defines the `40H`–`4FH` device multiplexing protocol.
* **MSX Expanded I/O Front Panel Switch Specification** *(Separate Document)* — Defines the companion input register for front panel boot configuration switches.
