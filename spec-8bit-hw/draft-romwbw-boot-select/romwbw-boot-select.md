# MSX Expanded I/O Front Panel Boot Switch Specification (Device ID 169)

**Category:** Standards Track  
**Date:** November 13, 2026  
**Device ID:** `169` (`A9H`)  
**Status:** Draft / Experimental  

---

## Abstract

This document specifies an MSX Expansion I/O peripheral assigned to Device ID `169` (`A9H`), providing an 8-bit input register at I/O port `41H` (`0x41`) to read manual front panel toggle or DIP switches. It addresses headless and embedded MSX controller deployments (such as systems operating without a Video Display Processor), defines safety requirements for commercial hardware implementations, outlines non-binding boot flag conventions derived from [RomWBW](https://github.com "RomWBW GitHub repository"), and provides Z80 assembly detection and readout code.

---

## 1. Introduction

In standard consumer MSX computers, boot configuration relies on keyboard hotkeys (such as holding `CTRL`, `SHIFT`, or `GRAPH`) and interactive on-screen menus rendered via the Video Display Processor (VDP). However, when an MSX architecture is deployed as a headless embedded controller, industrial rack unit, or VDP-less system, neither a keyboard nor a video monitor is available to the operator.

To provide reliable, non-volatile, physical boot-time control for end users and field technicians, this specification defines an MSX Expansion I/O input peripheral operating under the `40H`–`4FH` multiplexed I/O protocol. Front panel status LEDs are explicitly outside the scope of this document and are governed by a separate companion specification (Device ID `168`).

---

## 2. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

* **Device ID `169` (`A9H`):** The universal MSX Expansion I/O identifier assigned to this front panel switch reader (within the `128`–`254` universal peripheral range).
* **Input Register (`41H`):** The 8-bit read-only tri-state buffer mapped to I/O port `41H` when Device ID `169` is active.
* **Active-High Switch Logic:** A switch in the `ON` / `CLOSED` / `UP` position **MUST** read as a logical `1`, while a switch in the `OFF` / `OPEN` / `DOWN` position **MUST** read as a logical `0`.

---

## 3. Physical, Electrical, and Safety Requirements

### 3.1. Commercial Product Safety Color Coding
* When Dual In-line Package (DIP) switches are utilized in a commercial or retail hardware product to implement this interface, the DIP switch housing/case **MUST have a red color**.
* This red housing serves as a standardized visual warning to end users and service technicians that altering switch positions modifies low-level hardware boot behavior and carries potential operational hazards (e.g., bypassing safety checks, altering clock/bus modes, or wiping non-volatile storage).
* Open-frame mainframe toggle switches **SHOULD** include clear silkscreen legends indicating `ON` (`1`) and `OFF` (`0`) states.

### 3.2. Electrical Conditioning
* Input lines `SW0` through `SW7` **MUST** include pull-down (or pull-up with hardware inversion) resistors so that unasserted switches never float.
* Hardware implementations **SHOULD** incorporate basic RC or Schmitt-trigger debouncing if switches are intended to be polled dynamically during runtime rather than strictly at cold boot.

---

## 4. Protocol and Register Definition

This device adheres strictly to the **MSX Expansion I/O Port Specification**.

### 4.1. Device Selection and Identification (`40H`)
* **Power-On / Reset:** Upon `/RESET`, the device **MUST** disconnect its tri-state buffers from the CPU data bus (`D0`–`D7`).
* **Selection:** Writing `169` (`A9H`) to I/O port `40H` selects the device and enables read access on port `41H`. Writing any other byte deselects the device and places its bus buffers into high-impedance (`Hi-Z`) state.
* **Identification Readback:** Reading port `40H` while Device `169` (`A9H`) is selected **MUST** return `~A9H` = **`56H` (`86` decimal)**.

### 4.2. Switch Input Register (`41H`)
* **Address:** `41H` (`0x41`)
* **Access:** Read-Only (when Device `169` is selected; writes to `41H` **MUST** be ignored)
* **Bit Assignment:**

| Bit | `D7` | `D6` | `D5` | `D4` | `D3` | `D2` | `D1` | `D0` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Switch** | `SW7` | `SW6` | `SW5` | `SW4` | `SW3` | `SW2` | `SW1` | `SW0` |
| **Weight** | `80H` | `40H` | `20H` | `10H` | `08H` | `04H` | `02H` | `01H` |

---

## 5. Boot Configuration Flag Conventions

### 5.1. Suggested Mainframe Input Profile ([RomWBW](https://smallcomputercentral.com "RomWBW Getting Started front panel switches") Reference)
To promote ecosystem familiarity, system designers **MAY** adopt the 8-bit front panel switch layout used in [RomWBW](https://github.com "RomWBW GitHub repository") mainframe systems:

| Bit | Switch | Suggested Function | `0` (`OFF`) Behavior | `1` (`ON`) Behavior |
| :---: | :---: | :--- | :--- | :--- |
| `D0` | `SW0` | Console / Serial Mode | Default console | Force alternate serial baud/port |
| `D1` | `SW1` | Autoboot Control | Autoboot enabled | Halt at ROM monitor / prompt |
| `D2` | `SW2` | Boot Unit Select (Bit 0) | Unit bit 0 = `0` | Unit bit 0 = `1` |
| `D3` | `SW3` | Boot Unit Select (Bit 1) | Unit bit 1 = `0` | Unit bit 1 = `1` |
| `D4` | `SW4` | Memory / Cache Option | Standard RAM sizing | Safe mode / disable fast cache |
| `D5` | `SW5` | ROM / Extension Bypass | Normal slot scan | Skip external cartridge ROMs |
| `D6` | `SW6` | Diagnostic / Verbose | Quiet boot | Verbose POST / diagnostic loop |
| `D7` | `SW7` | Application / OEM Mode | Normal OS boot | Boot embedded controller firmware |

### 5.2. Non-Enforcement and Machine Runtime Specifications
* The bit assignments in Section 5.1 are **informational suggestions only** and **MUST NOT** be enforced as mandatory by generic MSX Expansion I/O BIOS extensions.
* Exact functional meanings for `SW0` through `SW7` remain implementation-defined until formally mandated by a separate, target-specific **Machine Runtime Specification** (for example, an industrial PLC controller runtime or headless Nextor appliance profile).

---

## 6. Reference Z80 Assembly Implementation

The following Z80 assembly routine probes for Device ID `169` (`A9H`) on the MSX Expansion I/O bus and, if present, reads the 8-bit switch register from port `41H` into register `C` while preserving the previously active expansion device.

```z80
; ==============================================================================
; MSX Expanded I/O Front Panel Switch Reader (Device ID 169 / 0xA9)
; ==============================================================================

EXP_IO_SEL  EQU     40H         ; MSX Expansion I/O selection port
EXP_IO_DATA EQU     41H         ; Front panel switch input register
SW_DEV_ID   EQU     169         ; Device ID 169 (0A9H)
SW_DEV_INV  EQU     056H        ; Expected complement (~0A9H = 056H)

; ------------------------------------------------------------------------------
; Routine: DETECT_AND_READ_SW
; Purpose: Detects Device ID 169 and reads switch states into C if present.
; Output:  Carry Flag (CF) = 0 if detected; C = 8-bit switch state (D7..D0).
;          Carry Flag (CF) = 1 if device is not present (C undefined).
; Clobbers: AF, BC
; ------------------------------------------------------------------------------
DETECT_AND_READ_SW:
        DI                      ; Prevent ISR bus contention during I/O switch

        IN      A, (EXP_IO_SEL) ; Read current complement ID
        CPL                     ; Invert to recover previously active Device ID
        LD      B, A            ; Save previous Device ID in B

        LD      A, SW_DEV_ID    ; Select Device ID 169 (0A9H)
        OUT     (EXP_IO_SEL), A

        IN      A, (EXP_IO_SEL) ; Read back complement ID from port 40H
        CP      SW_DEV_INV      ; Does it match ~0A9H (056H)?
        JR      NZ, .NOT_FOUND  ; If not, hardware is absent

        ; Device detected: read 8-bit boot toggle switches from port 41H
        IN      A, (EXP_IO_DATA)
        LD      C, A            ; Store switch bitmask in C

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
* **MSX Expanded I/O Front Panel LED Indicator Specification (Device ID 168)** — Defines the companion 8-bit red LED diagnostic indicator register.
* **Machine Runtime Specification** *(Target-Specific / External)* — Defines concrete runtime behavior for switch bitmasks on a given embedded MSX platform.
