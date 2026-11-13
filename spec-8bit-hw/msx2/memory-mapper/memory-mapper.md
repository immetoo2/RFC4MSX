# MSX Memory Mapper Specification

**Category:** Standards Track  
**Date:** 1985 (MSX2 Standard Hardware Specification, Part 8)  
**Author:** ASCII / Microsoft  
**Status:** Historical / Informational  

---

## Abstract

This document specifies the MSX Memory Mapper hardware and system initialization standard, which enables the Z80 CPU to address up to 4 MB of RAM per slot by dynamically mapping 16 KB physical memory segments into the four 16 KB logical pages of the 64 KB Z80 address space via I/O ports `FCH` through `FFH`.

---

## 1. Introduction

The Zilog Z80 processor natively possesses a 16-bit address bus, limiting direct linear addressing to 64 KB (`0000H`–`FFFFH`). While the baseline MSX1 slot mechanism divides this 64 KB space into four 16 KB pages switchable across up to 16 slots/subslots, large applications and disk operating systems require contiguous, expandable RAM exceeding 64 KB within a single slot.

Introduced with the MSX2 standard, the Memory Mapper subdivides physical RAM into 16 KB blocks (segments) and maps any four segments simultaneously into the CPU's four 16 KB logical pages, providing up to 4 MB (256 × 16 KB) of addressable memory per mapper slot.

---

## 2. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

* **Page:** One of four fixed 16 KB logical address windows in the Z80 address space (`Page 0` through `Page 3`).
* **Segment (Physical Page):** A 16 KB (`16,384`-byte) block of physical RAM inside a Memory Mapper device, indexed from `0` to `255`.
* **Mapping Register:** An 8-bit hardware register associated with a specific logical page (`R0`–`R3`) that holds the active segment index for that page.

---

## 3. Logical Address Map and I/O Registers

A compliant Memory Mapper implements four 8-bit mapping registers mapped to I/O ports `FCH` through `FFH`. Each register controls which physical 16 KB segment appears in its corresponding Z80 memory page when that mapper's slot is selected.

| Register | I/O Port (Hex) | I/O Port (Dec) | Z80 Logical Page | CPU Address Range |
| :--- | :--- | :--- | :--- | :--- |
| `R0` | `FCH` | `252` | Page 0 | `0000H` – `3FFFH` |
| `R1` | `FDH` | `253` | Page 1 | `4000H` – `7FFFH` |
| `R2` | `FEH` | `254` | Page 2 | `8000H` – `BFFFH` |
| `R3` | `FFH` | `255` | Page 3 | `C000H` – `FFFFH` |

### 3.1. Capacity and Minimum Requirements
* The minimum mapped memory capacity for a compliant MSX2 Memory Mapper MUST be **64 KB** (4 segments).
* The maximum architectural capacity for a single Memory Mapper is **4 MB** (256 segments, indexed `00H` to `FFH`).
* Hardware implementations with fewer than 256 segments (e.g., 128 KB / 8 segments, or 256 KB / 16 segments) SHOULD ignore upper unused address bits when decoding the segment index, or mirror segments across the 8-bit index space.

---

## 4. Protocol Operation

### 4.1. Segment Selection (`OUT (port), A`)
* To map a physical segment into a logical page, the CPU writes the 8-bit segment number (`00H`–`FFH`) to the corresponding I/O port (`FCH`–`FFH`).
* Writing to a mapping register takes effect immediately for all subsequent memory read/write cycles targeting that 16 KB page while the mapper's slot is active.
* Writing to ports `FCH`–`FFH` affects the mapping registers of **all** installed Memory Mappers simultaneously, regardless of which primary or secondary slot is currently selected on the CPU bus.

### 4.2. Register Readback (`IN A, (port)`)
* External RAM expansion cartridges implementing the Memory Mapper specification MUST treat I/O ports `FCH`–`FFH` as **write-only** to prevent bus contention when multiple mappers are installed.
* Internal system Memory Mappers MAY support reading back the register contents on ports `FCH`–`FFH`. However, because readback is not guaranteed across hardware revisions—and unused upper bits on smaller mappers may read back as floating/undefined (`1`s)—portable software MUST NOT rely on reading ports `FCH`–`FFH` directly.

### 4.3. Interaction with MSX Slot Selection
* Memory Mapper ports `FCH`–`FFH` operate orthogonally to the MSX Primary Slot Register (`A8H`) and Secondary Slot Register (`FFFFH`).
* Selecting a segment via `FCH`–`FFH` does not alter which slot or subslot is visible to the CPU; the slot must still be selected via standard MSX slot-switching routines for the mapped RAM to be accessed.

---

## 5. Hardware Reference Architecture

A compliant Memory Mapper uses the upper two Z80 address lines (`A14`, `A15`) to select one of four 8-bit latches (`R0`–`R3`), substituting the 8-bit latch output for the upper physical address lines (`MA14`–`MA21`):

```text
   MSX CPU BUS                                   MAPPER RAM ARRAY
  -------------                                 ------------------
   A0 - A13  ------------------------------------> MA0 - MA13 (16 KB offset)

   A14 - A15 ----+----> [ 2-to-4 Multiplexer ] --> MA14 - MA21 (8-bit Segment)
                 |         ^   ^   ^   ^

                 |         |   |   |   |
   D0 - D7   ----+---> +---+---+---+---+

                 |     |R0 |R1 |R2 |R3 | (8-bit Latches)
                 |     +---+---+---+---+
                 |       ^   ^   ^   ^
             +---+---+   |   |   |   |
   A0 - A7 --+FC-FF? +---+   |   |   |
             +---+---+       |   |   |

                 |           |   |   |
   /IORQ --------+-----------+---+   |
   /WR   --------+-------------------+
```

1. **I/O Write Decode:** When `/IORQ` and `/WR` are asserted and `A0–A7` matches `FCH`, `FDH`, `FEH`, or `FFH`, the data bus `D0–D7` is latched into the corresponding 8-bit register (`R0`, `R1`, `R2`, or `R3`).
2. **Memory Address Translation:** During memory access cycles (`/MREQ` asserted when the mapper's slot is selected), `A14` and `A15` select the output of `R0` (`00`), `R1` (`01`), `R2` (`10`), or `R3` (`11`).
3. **Physical Address Output:** The selected 8-bit segment value drives physical RAM address lines `MA14` through `MA21` (up to 22 address lines = 4 MB), while `A0–A13` pass directly to `MA0–MA13`.

---

## 6. System Software Initialization

### 6.1. MSX2 / MSX2+ / MSX turbo R BIOS Behavior
During cold boot, prior to executing the standard slot ROM/RAM search, the MSX2 (and later) MAIN-ROM BIOS initializes the Memory Mapper registers to a deterministic descending order:

| I/O Port | Logical Page | Initial Segment Value |
| :--- | :--- | :--- |
| `FCH` | Page 0 (`0000H`–`3FFFH`) | `03H` (Segment 3) |
| `FDH` | Page 1 (`4000H`–`7FFFH`) | `02H` (Segment 2) |
| `FEH` | Page 2 (`8000H`–`BFFFH`) | `01H` (Segment 1) |
| `FFH` | Page 3 (`C000H`–`FFFFH`) | `00H` (Segment 0) |

* The BIOS performs these four `OUT` instructions unconditionally without probing for mapper hardware; systems lacking a Memory Mapper safely ignore the writes.
* Segment `0` (`00H`) is mapped to Page 3 (`C000H`–`FFFFH`) so that the system work area and stack reside in Segment `0`, ensuring compatibility with MSX-DOS and standard BIOS expectations.

### 6.2. MSX1 Compatibility
* The MSX1 BIOS does **not** initialize ports `FCH`–`FFH` at startup, leaving the latches in an undefined power-on state.
* External Memory Mapper cartridges intended for MSX1 systems SHOULD include hardware reset circuitry (or boot ROM code) to initialize `R0`–`R3` to `03H`, `02H`, `01H`, and `00H` upon `/RESET`.

---

## 7. Multi-Mapper and Software Management Considerations

* **Global Broadcast Writes:** Because all installed Memory Mappers listen to ports `FCH`–`FFH` simultaneously, writing a segment number updates every mapper in the system concurrently. When multiple mappers are installed (e.g., an internal mapper in Slot 3-2 and an external mapper in Slot 1), software isolates them via slot selection (`A8H` / `FFFFH`) rather than I/O port selection.
* **Extended BIOS / MSX-DOS 2 Arbiters:** Because mapping registers are write-only and shared globally, applications SHOULD NOT write directly to ports `FCH`–`FFH` when running under multi-tasking or resident environments (such as MSX-DOS 2 or MemMan). Instead, software SHOULD use the standardized Extended BIOS Mapper Support Routines (`ALL_SEG`, `FRE_SEG`, `PUT_Pn`, `GET_Pn`) to allocate segments and track active page mappings without corrupting resident system state.
