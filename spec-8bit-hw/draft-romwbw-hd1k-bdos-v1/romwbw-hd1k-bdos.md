# romWBW hd1k BDOS

Below is a complete, synthesizable VHDL implementation of a `hardware-accelerated CP/M BDOS filesystem engine` coupled with an SPI Micro-SD block controller tailored specifically to the RomWBW hd1k disk geometry.  
Rather than forcing a Z80/CPU to execute software BIOS/BDOS routines and do software sector deblocking, this core acts as a memory-mapped or I/O-mapped peripheral.  
Your host CPU writes an FCB (File Control Block) or filename into the peripheral's registers and triggers high-level BDOS commands (OPEN, READ_SEQ, WRITE_SEQ, MAKE, DELETE, SEARCH_FIRST, SEARCH_NEXT).  
The hardware state machine resolves the hd1k MBR/partition prefix, parses the 1,024-entry directory, allocates/traverses 4 KB blocks, and streams 128-byte CP/M records directly over SPI to/from an SDHC micro-SD card.

NOTE: V2 needs idx of 16 mounts out of all 256 usable slices

## RomWBW hd1k Geometry & Hardware Parameters

Per the RomWBW cpmtools diskdefs specification, the hardware constants baked into this design are:
* Prefix Offset. Standard hd1k images begin after a 1 MB prefix (hd1k_prefix.dat = 128 tracks \(\times \) 16 sectors = 2,048 LBA sectors), though the core also dynamically reads the MBR partition table at LBA 0 (partition type 0x2E / 0x52 or standard LBA start at offset 0x1C6) to find the exact starting LBA.
* Slice Geometry. Each slice is 8 MB (16,384 sectors of 512 bytes = 1,024 tracks \(\times \) 16 sectors/track). Slice \(N\) starts at BASE_LBA + (N * 16384).
* Reserved System Tracks. boottrk = 2 (2 tracks \(\times \) 16 sectors = 32 sectors = 16 KB reserved at the start of each slice).
* Directory Area. maxdir = 1024 entries \(\times \) 32 bytes = 32 KB (64 sectors, or 8 allocation blocks 0..7 of 4,096 bytes each), starting immediately after the 32 reserved sectors.
* Allocation Block Size. 4,096 bytes (8 physical 512-byte SD sectors per block; 32 CP/M 128-byte records per block).
* Total Blocks (DSM). 2039 (0..2039, so 16-bit block pointers are used in the FCB AL array—8 pointers per 32-byte directory extent, covering 8 * 4 KB = 32 KB per extent, meaning EXM = 1).

## Complete VHDL Implementation

Save the following code as romwbw_hd1k_bdos.vhd. It is self-contained (zero external IP cores required) and includes:
* sd_spi_master: Full SD v2 / SDHC SPI initializer (CMD0, CMD8, ACMD41, CMD58) and 512-byte single-block reader/writer (CMD17, CMD24) with a dual-port 512-byte sector BRAM buffer.
* hd1k_bdos_engine: Native hardware state machine implementing CP/M 2.2 BDOS Functions 13 (Reset Disk), 14 (Select Slice), 15 (Open File), 16 (Close File), 17 (Search First), 18 (Search Next), 19 (Delete File), 20 (Read Sequential), 21 (Write Sequential), and 22 (Make File).
* bdos_bus_wrapper: Clean synchronous 8-bit CPU bus interface (addr[5:0], din[7:0], dout[7:0], cs, we, re) containing a 32-byte hardware FCB register file and a 128-byte DMA record buffer.

[romwbw_hd1k_bdos.vhd](romwbw_hd1k_bdos.vhd) (none valid incomplete dream code)

### Host Register Map & Usage Sequence

Connect `bus_addr(5:0)`, `bus_din`, `bus_dout`, `bus_cs`, `bus_we`, and `bus_re` to your Z80/soft-CPU I/O decoder (e.g., mapped to I/O ports `0x40..0x7F`):

| Offset | Name | R/W | Description |
| :--- | :--- | :--- | :--- |
| **`0x00`** | `CMD_STAT` | R/W | **Write:** Triggers BDOS opcode (`0x0D`–`0x16`). **Read:** Bit `7`=Busy, Bit `6`=SD Ready, Bit `5`=SD Error, Bit `4`=Dirty Cache. |
| **`0x01`** | `SLICE` | R/W | Selects active 8 MB RomWBW `hd1k` slice (`0` to `15`). |
| **`0x02`** | `RET_CODE` | R | Standard CP/M BDOS return code (`0x00`–`0x03` = Dir code/Success, `0x01` = EOF on Read, `0xFF` = Not Found/Error). |
| **`0x03`** | `DMA_PTR` | R/W | Sets or reads the 7-bit index (`0`–`127`) into the internal 128-byte CP/M DMA buffer. |
| **`0x04`** | `DMA_DATA` | R/W | Reads or writes a byte at `DMA_PTR` and automatically increments `DMA_PTR` (`0` $\rightarrow$ `127` $\rightarrow$ `0`). |
| **`0x05`** | `FCB_CR` | R/W | Current Record counter (`0`–`255`) within the active 32 KB `hd1k` extent. |
| **`0x20..0x3F`** | `FCB[0..31]` | R/W | Direct access to the 32-byte CP/M File Control Block (`0x20`=User, `0x21..0x2B`=8.3 Name, `0x2C`=EX, `0x2F`=RC, `0x30..0x3F`=AL0..15). |

#### Typical Host Flow

1. **Mount Card:** Write `0x0D` (`CMD_RESET_DISK`) to `0x00`. Poll bit `7` of `0x00` until `0`. The core initializes the micro-SD card, reads the MBR partition offset (`2048`), and builds the 2,040-bit allocation map in hardware.
2. **Select Slice:** Write `0x02` to `0x01`, then write `0x0E` (`CMD_SELECT_DISK`) to `0x00` and wait for `Busy = 0`.
3. **Load FCB:** Write `0x00` (User 0) to `0x20`, ASCII `"ZORK1   COM"` to `0x21..0x2B`, and `0x00` to `0x2C` (`EX`).
4. **Open File:** Write `0x0F` (`CMD_OPEN_FILE`) to `0x00`. Wait for `Busy = 0`, check `0x02` (`RET_CODE /= 0xFF`).
5. **Stream Records:** Write `0x14` (`CMD_READ_SEQ`) to `0x00`. When `Busy = 0`, if `RET_CODE = 0x00`, write `0x00` to `0x03` (`DMA_PTR`) and read 128 bytes sequentially from `0x04` (`DMA_DATA`). Repeat until `RET_CODE = 0x01` (EOF).

