# MSX Expansion I/O Port Specification

**Category:** Standards Track  
**Date:** December 27, 1985 (Original: December 5, 1985)  
**Author:** ASCII MS FE HQ  
**Status:** Historical / Informational  

---

## Abstract

This document specifies the MSX Expansion I/O Port standard, which enables multiple peripheral devices to share the I/O port address range `40H` through `4FH` via a dynamic device-selection protocol on port `40H`.

---

## 1. Introduction

In the baseline MSX standard, I/O ports `00H` through `3FH` are reserved for end-user applications, while ports `40H` through `FFH` are fixed for authorized peripheral devices. Due to the growing number of peripherals requiring port assignments in the `40H`–`FFH` range, fixed allocation is no longer sufficient for all hardware.

To resolve this limitation, the I/O address range `40H` through `4FH` is designated as a multiplexed expansion space. Multiple peripheral devices share this port range, and only one device is actively connected to the CPU bus at any given time.

---

## 2. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

* **Device ID:** An 8-bit identifier (`1` to `254`) assigned to a manufacturer or a specific peripheral device.
* **Maker ID:** A Device ID in the range `1` to `127` identifying a hardware manufacturer.
* **Peripheral Device ID:** A Device ID in the range `128` to `254` identifying a universal MSX peripheral.

---

## 3. Protocol Operation

### 3.1. Power-On and Reset State
Upon power-on or hardware `/RESET`, all expansion devices MUST default to the disconnected (shut) state, isolating their data buses from the MSX CPU bus.

### 3.2. Device Selection (`OUT (40H), A`)
* To select a peripheral, the CPU MUST write the target device's 8-bit Device ID to I/O port `40H`.
* When a byte written to port `40H` matches a peripheral's assigned Device ID, that peripheral MUST enable its bus buffer and connect to the CPU bus.
* When any value other than a peripheral's Device ID is written to port `40H`, that peripheral MUST disable its bus buffer and disconnect from the CPU bus.

### 3.3. Device Identification Readback (`IN A, (40H)`)
* When the CPU reads from I/O port `40H` while an expansion device is actively connected, the active device MUST return the one's complement (bitwise inversion) of its Device ID.
* If no expansion device is connected, reading port `40H` returns an open-bus value (typically `FFH`).
* This readback mechanism allows interrupt-driven software routines to save, switch, and restore the currently active expansion device.

### 3.4. Active Port Range (`40H`–`4FH`)
* Once selected, the active peripheral MAY utilize I/O ports `41H` through `4FH` for device-specific registers and data transfer.
* Port `40H` MUST remain dedicated to device selection (write) and active ID readback (read).

---

## 4. Hardware Reference Architecture

A compliant expansion peripheral implements address decoding and bus isolation logic as follows:

```text
   MSX CPU BUS                                       PERIPHERAL DEVICE
  -------------                                     -------------------
   A0 - A15  ----+-------------------------------+---> A0 - A15

                 |                               |
   D0 - D7   ----+---------------+---------------+---> D0 - D7

                 |               |               |
             +---+---+       +---+---+      +----+-----+

             | 40H?  |       |  ID?  |      |   Bus    |
             +---+---+       +---+---+      |  Buffer  |

                 |               |          +----+-----+
   /IORQ ----+---+               |               ^

             |   |               v               |
             |  AND ---> [Write] +---> [D   Q] --+ (Enable F/F)
   /WR   ----+---+                     [  R  ]
             |                           ^
             |  AND ---> [Read] ---------+---> [Access Control]
   /RD   ----+---+                                   |
                                                     v
   /RESET -------------------------------+---> [Buffer: ~ID] ---> D0-D7
```


1. **Address & Control Decoding:** The hardware decodes I/O address `40H` alongside `/IORQ` and `/WR` (write strobe) or `/RD` (read strobe).
2. **ID Comparator:** On a write to `40H`, an 8-bit comparator checks if `D0–D7` matches the peripheral's hardcoded Device ID.
3. **Enable Flip-Flop:** The comparator output latches into an Enable Flip-Flop (D-type). A match sets `Q=1` (enabling the bus buffer); a mismatch sets `Q=0` (isolating the bus). Asserting `/RESET` resets the flip-flop (`Q=0`).
4. **Complement Buffer:** On a read from `40H` while `Q=1`, access control logic enables a tri-state buffer driving the bitwise complement of the Device ID (`~ID`) onto `D0–D7`.

---

## 5. Device ID Allocation

Although an 8-bit field supports values `0` through `255`, values `0` (`00H`) and `255` (`FFH`) MUST NOT be assigned. Because port `40H` returns the bitwise complement on read, `255` (`FFH`) is reserved to represent the unallocated/open-bus state (`~0` = `FFH`), and `0` (`00H`) is excluded symmetrically.

### 5.1. Allocation Ranges

| ID Range | Category | Usage Rule |
| :--- | :--- | :--- |
| `0` | Reserved | MUST NOT be used. |
| `1` – `127` | Maker ID | Assigned to specific manufacturers (matching MSX expanded BIOS IDs). SHOULD be used for hardware designed specifically for a single vendor's machine. |
| `128` – `254` | Device ID | Assigned to universal peripherals usable across any MSX system. |
| `255` | Reserved | MUST NOT be used. |

### 5.2. 16-Bit I/O Address Expansion
Because the Z80 CPU places 16-bit addresses onto `A0–A15` during I/O cycles (with the `B` register output on `A8–A15` during `IN r,(C)` / `OUT (C),r` instructions), hardware designers are RECOMMENDED to decode the upper 8 address bits (`A8–A15`). Hardware connected via a Maker ID (`1`–`127`) can leverage `A8–A15` to expand its sub-device address space by a factor of 256 for future-proofing.

---

## 6. IANA / Registry Considerations (Initial Assignments)

### 6.1. Maker IDs (`1` – `127`)

| Maker ID | Manufacturer | Maker ID | Manufacturer |
| :--- | :--- | :--- | :--- |
| `1` | ASCII / Microsoft | `12` | JVC |
| `2` | Canon | `13` | Philips |
| `3` | Casio | `14` | Pioneer |
| `4` | Fujitsu | `15` | Sanyo |
| `5` | General | `16` | Sharp |
| `6` | Hitachi | `17` | SONY |
| `7` | Kyocera | `18` | Spectravideo |
| `8` | Matsushita | `19` | Toshiba |
| `9` | Mitsubishi | `20` | Mitsumi |
| `10` | NEC | `21` | *(Unassigned)* |
| `11` | Nippon Gakki (Yamaha) | `22`–`127` | *(Reserved)* |


### 6.2. Universal Device IDs (`128` – `254`)

| Device ID | Peripheral Description | Manufacturer |
| :--- | :--- | :--- |
| `128` | Image Scanner | Matsushita |
| `129`–`253` | *(Unassigned)* | — |
| `254` | MPS2 | ASCII |


---

## 7. Security and Bus Contention Considerations

* **Bus Contention:** Only one device ID may be active at any time. Assigning duplicate Device IDs to two installed peripherals will cause bus contention on `D0–D7` when both peripherals attempt to drive the bus simultaneously.
* **Interrupt Safety:** Interrupt service routines (ISRs) that access expansion I/O devices MUST read port `40H`, bitwise-invert the value to obtain the previously active Device ID, perform their I/O operations, and write the original Device ID back to port `40H` before returning.
