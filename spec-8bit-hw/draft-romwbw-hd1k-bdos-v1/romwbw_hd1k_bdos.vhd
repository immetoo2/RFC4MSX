--------------------------------------------------------------------------------
-- Company: Open Hardware / Retrocomputing
-- Module Name: romwbw_hd1k_bdos
-- Description: Full Native VHDL Implementation of a CP/M BDOS Filesystem
-- Controller for RomWBW hd1k Micro-SD Images (SDHC SPI).
--
-- Features:
-- - Native SDv2/SDHC SPI Controller (400 kHz init -> 25 MHz data transfer)
-- - Automatic MBR Partition Discovery + Slice Offset Calculation
-- - Hardware 512-byte Sector Cache & 128-byte CP/M DMA Record Buffer
-- - Hardware Allocation Bitmap (2040 bits in BRAM/Registers for instant alloc)
-- - Full BDOS State Machine:
-- 0x0D (13): Reset Disk System & Mount Partition
-- 0x0E (14): Select Disk Slice (0..15)
-- 0x0F (15): Open File (FCB match + multi-extent support)
-- 0x10 (16): Close File (Flush dirty sector + update directory entry)
-- 0x11 (17): Search For First (Wildcard '?' matching)
-- 0x12 (18): Search For Next
-- 0x13 (19): Delete File (Marks 0xE5 & frees blocks in bitmap)
-- 0x14 (20): Read Sequential (128B DMA read + automatic extent chaining)
-- 0x15 (21): Write Sequential (128B DMA write + block/extent allocation)
-- 0x16 (22): Make File (Creates new 32B directory entry)
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

--------------------------------------------------------------------------------
-- ENTITY 1: SPI Micro-SD Block Controller (SDv2 / SDHC, 512-byte LBA)
--------------------------------------------------------------------------------
ENTITY sd_spi_master IS
	GENERIC (
		CLK_FREQ_HZ : INTEGER := 50_000_000 -- System clock frequency
	);
	PORT (
		clk : IN std_logic;
		rst : IN std_logic;

		-- Control Interface
		cmd_init : IN std_logic;
		cmd_read : IN std_logic;
		cmd_write : IN std_logic;
		lba_addr : IN std_logic_vector(31 DOWNTO 0);
		busy : OUT std_logic;
		ready : OUT std_logic;
		err : OUT std_logic;

		-- 512-Byte Internal Sector Buffer Access (Port B for Filesystem Engine)
		buf_addr : IN std_logic_vector(8 DOWNTO 0);
		buf_din : IN std_logic_vector(7 DOWNTO 0);
		buf_we : IN std_logic;
		buf_dout : OUT std_logic_vector(7 DOWNTO 0);

		-- Physical Micro-SD SPI Pins
		sd_cs_n : OUT std_logic;
		sd_sclk : OUT std_logic;
		sd_mosi : OUT std_logic;
		sd_miso : IN std_logic
	);
END ENTITY sd_spi_master;

ARCHITECTURE rtl OF sd_spi_master IS
	-- Clock dividers: 400 kHz for init, CLK_FREQ/2 (up to 25 MHz) for data
	CONSTANT DIV_SLOW : INTEGER := (CLK_FREQ_HZ / (2 * 400_000)) - 1;
	CONSTANT DIV_FAST : INTEGER := 0; -- CLK / 2

	TYPE state_t IS (
	ST_IDLE, ST_INIT_DUMMY, ST_SEND_CMD, ST_WAIT_R1, ST_GET_R7, 
	ST_WAIT_DATA_TOK, ST_READ_BYTES, ST_READ_CRC, 
	ST_WRITE_TOK, ST_WRITE_BYTES, ST_WRITE_CRC, ST_WRITE_RESP, ST_WRITE_BUSY, 
	ST_DONE, ST_ERROR
	);
	SIGNAL state : state_t := ST_IDLE;
	SIGNAL next_state : state_t := ST_IDLE;

	-- 512-byte Dual-Port Sector Buffer
	TYPE sector_ram_t IS ARRAY (0 TO 511) OF std_logic_vector(7 DOWNTO 0);
	SIGNAL sector_ram : sector_ram_t := (OTHERS => (OTHERS => '0'));
	SIGNAL sd_buf_addr : unsigned(8 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sd_buf_din : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sd_buf_we : std_logic := '0';
	SIGNAL sd_buf_dout : std_logic_vector(7 DOWNTO 0);

	-- SPI Byte Shifter Signals
	SIGNAL spi_start : std_logic := '0';
	SIGNAL spi_busy : std_logic := '0';
	SIGNAL spi_tx : std_logic_vector(7 DOWNTO 0) := x"FF";
	SIGNAL spi_rx : std_logic_vector(7 DOWNTO 0) := x"FF";
	SIGNAL slow_clk : std_logic := '1';

	SIGNAL clk_cnt : INTEGER RANGE 0 TO 255 := 0;
	SIGNAL bit_cnt : INTEGER RANGE 0 TO 7 := 0;
	SIGNAL sclk_reg : std_logic := '0';
	SIGNAL shift_reg : std_logic_vector(7 DOWNTO 0) := x"FF";

	-- Command framing
	TYPE cmd_buf_t IS ARRAY (0 TO 5) OF std_logic_vector(7 DOWNTO 0);
	SIGNAL cmd_bytes : cmd_buf_t;
	SIGNAL byte_idx : INTEGER RANGE 0 TO 520 := 0;
	SIGNAL r1_resp : std_logic_vector(7 DOWNTO 0) := x"FF";
	SIGNAL r7_resp : std_logic_vector(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL init_step : INTEGER RANGE 0 TO 7 := 0;
	SIGNAL retry_cnt : INTEGER RANGE 0 TO 65535 := 0;
	SIGNAL card_ready : std_logic := '0';
	SIGNAL err_reg : std_logic := '0';

BEGIN
	ready <= card_ready;
	err <= err_reg;
	busy <= '0' WHEN state = ST_IDLE ELSE '1';

	-- Dual-Port Sector RAM Process
	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			-- Port A: SD Controller
			IF sd_buf_we = '1' THEN
				sector_ram(to_integer(sd_buf_addr)) <= sd_buf_din;
			END IF;
			sd_buf_dout <= sector_ram(to_integer(sd_buf_addr));

			-- Port B: BDOS Engine
			IF buf_we = '1' THEN
				sector_ram(to_integer(unsigned(buf_addr))) <= buf_din;
			END IF;
			buf_dout <= sector_ram(to_integer(unsigned(buf_addr)));
		END IF;
	END PROCESS;

	-- Low-level SPI Byte Transfer Engine (Mode 0: CPOL=0, CPHA=0)
	sd_sclk <= sclk_reg;
	sd_mosi <= shift_reg(7);

	PROCESS (clk)
	VARIABLE div_limit : INTEGER;
		BEGIN
			IF rising_edge(clk) THEN
				IF rst = '1' THEN
					spi_busy <= '0';
					sclk_reg <= '0';
					clk_cnt <= 0;
					bit_cnt <= 0;
					shift_reg <= x"FF";
				ELSE
					IF slow_clk = '1' THEN
						div_limit := DIV_SLOW;
					ELSE
						div_limit := DIV_FAST;
					END IF;

					IF spi_busy = '0' THEN
						sclk_reg <= '0';
						IF spi_start = '1' THEN
							spi_busy <= '1';
							shift_reg <= spi_tx;
							bit_cnt <= 7;
							clk_cnt <= 0;
						END IF;
					ELSE
						IF clk_cnt = div_limit THEN
							clk_cnt <= 0;
							IF sclk_reg = '0' THEN
								-- Rising edge: sample MISO
								sclk_reg <= '1';
								spi_rx <= spi_rx(6 DOWNTO 0) & sd_miso;
							ELSE
								-- Falling edge: shift out next bit
								sclk_reg <= '0';
								IF bit_cnt = 0 THEN
									spi_busy <= '0';
								ELSE
									bit_cnt <= bit_cnt - 1;
									shift_reg <= shift_reg(6 DOWNTO 0) & '1';
								END IF;
							END IF;
						ELSE
							clk_cnt <= clk_cnt + 1;
						END IF;
					END IF;
				END IF;
			END IF;
		END PROCESS;

		-- High-Level SD Protocol FSM
		PROCESS (clk)
			BEGIN
				IF rising_edge(clk) THEN
					spi_start <= '0';
					sd_buf_we <= '0';

					IF rst = '1' THEN
						state <= ST_IDLE;
						sd_cs_n <= '1';
						card_ready <= '0';
						err_reg <= '0';
						slow_clk <= '1';
					ELSE
						CASE state IS
							WHEN ST_IDLE => 
								sd_cs_n <= '1';
								IF cmd_init = '1' THEN
									card_ready <= '0';
									err_reg <= '0';
									slow_clk <= '1';
									init_step <= 0;
									byte_idx <= 0;
									state <= ST_INIT_DUMMY;
								ELSIF cmd_read = '1' AND card_ready = '1' THEN
									err_reg <= '0';
									sd_cs_n <= '0';
									cmd_bytes(0) <= x"51"; -- CMD17 (READ_SINGLE_BLOCK)
									cmd_bytes(1) <= lba_addr(31 DOWNTO 24);
									cmd_bytes(2) <= lba_addr(23 DOWNTO 16);
									cmd_bytes(3) <= lba_addr(15 DOWNTO 8);
									cmd_bytes(4) <= lba_addr(7 DOWNTO 0);
									cmd_bytes(5) <= x"FF";
									byte_idx <= 0;
									next_state <= ST_WAIT_DATA_TOK;
									state <= ST_SEND_CMD;
								ELSIF cmd_write = '1' AND card_ready = '1' THEN
									err_reg <= '0';
									sd_cs_n <= '0';
									cmd_bytes(0) <= x"58"; -- CMD24 (WRITE_BLOCK)
									cmd_bytes(1) <= lba_addr(31 DOWNTO 24);
									cmd_bytes(2) <= lba_addr(23 DOWNTO 16);
									cmd_bytes(3) <= lba_addr(15 DOWNTO 8);
									cmd_bytes(4) <= lba_addr(7 DOWNTO 0);
									cmd_bytes(5) <= x"FF";
									byte_idx <= 0;
									next_state <= ST_WRITE_TOK;
									state <= ST_SEND_CMD;
								END IF;

								-- 80 dummy clocks with CS high
							WHEN ST_INIT_DUMMY => 
								sd_cs_n <= '1';
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF byte_idx < 10 THEN
										spi_tx <= x"FF";
										spi_start <= '1';
										byte_idx <= byte_idx + 1;
									ELSE
										-- Issue CMD0
										sd_cs_n <= '0';
										cmd_bytes(0) <= x"40"; -- CMD0
										cmd_bytes(1) <= x"00";
										cmd_bytes(2) <= x"00";
										cmd_bytes(3) <= x"00";
										cmd_bytes(4) <= x"00";
										cmd_bytes(5) <= x"95"; -- Valid CRC for CMD0
										byte_idx <= 0;
										init_step <= 1;
										state <= ST_SEND_CMD;
									END IF;
								END IF;
							WHEN ST_SEND_CMD => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF byte_idx < 6 THEN
										spi_tx <= cmd_bytes(byte_idx);
										spi_start <= '1';
										byte_idx <= byte_idx + 1;
									ELSE
										retry_cnt <= 0;
										state <= ST_WAIT_R1;
									END IF;
								END IF;
							WHEN ST_WAIT_R1 => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF spi_rx(7) = '0' AND retry_cnt > 0 THEN
										r1_resp <= spi_rx;
										IF init_step = 1 THEN
											-- CMD0 complete, send CMD8
											cmd_bytes(0) <= x"48"; -- CMD8
											cmd_bytes(1) <= x"00";
											cmd_bytes(2) <= x"00";
											cmd_bytes(3) <= x"01";
											cmd_bytes(4) <= x"AA";
											cmd_bytes(5) <= x"87"; -- Valid CRC for CMD8
											byte_idx <= 0;
											init_step <= 2;
											state <= ST_SEND_CMD;
										ELSIF init_step = 2 THEN
											-- Read 4-byte R7 response
											byte_idx <= 0;
											state <= ST_GET_R7;
										ELSIF init_step = 3 THEN
											-- CMD55 complete, send ACMD41 (HCS=1)
											cmd_bytes(0) <= x"69"; -- CMD41
											cmd_bytes(1) <= x"40";
											cmd_bytes(2) <= x"00";
											cmd_bytes(3) <= x"00";
											cmd_bytes(4) <= x"00";
											cmd_bytes(5) <= x"FF";
											byte_idx <= 0;
											init_step <= 4;
											state <= ST_SEND_CMD;
										ELSIF init_step = 4 THEN
											-- Check if ACMD41 returned 0x00 (ready)
											IF spi_rx = x"00" THEN
												slow_clk <= '0'; -- Switch to full speed
												card_ready <= '1';
												state <= ST_DONE;
											ELSE
												-- Repeat CMD55 + ACMD41
												cmd_bytes(0) <= x"77"; -- CMD55
												cmd_bytes(1) <= x"00";
												cmd_bytes(2) <= x"00";
												cmd_bytes(3) <= x"00";
												cmd_bytes(4) <= x"00";
												cmd_bytes(5) <= x"FF";
												byte_idx <= 0;
												init_step <= 3;
												state <= ST_SEND_CMD;
											END IF;
										ELSE
											-- Normal Read/Write command R1 received
											IF spi_rx = x"00" THEN
												byte_idx <= 0;
												state <= next_state;
											ELSE
												state <= ST_ERROR;
											END IF;
										END IF;
									ELSIF retry_cnt = 1000 THEN
										state <= ST_ERROR;
									ELSE
										spi_tx <= x"FF";
										spi_start <= '1';
										retry_cnt <= retry_cnt + 1;
									END IF;
								END IF;
							WHEN ST_GET_R7 => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF byte_idx < 4 THEN
										IF byte_idx > 0 THEN
											r7_resp <= r7_resp(23 DOWNTO 0) & spi_rx;
										END IF;
										spi_tx <= x"FF";
										spi_start <= '1';
										byte_idx <= byte_idx + 1;
									ELSE
										r7_resp <= r7_resp(23 DOWNTO 0) & spi_rx;
										-- Issue CMD55
										cmd_bytes(0) <= x"77";
										cmd_bytes(1) <= x"00";
										cmd_bytes(2) <= x"00";
										cmd_bytes(3) <= x"00";
										cmd_bytes(4) <= x"00";
										cmd_bytes(5) <= x"FF";
										byte_idx <= 0;
										init_step <= 3;
										state <= ST_SEND_CMD;
									END IF;
								END IF;
								-- Sector Read States
							WHEN ST_WAIT_DATA_TOK => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF spi_rx = x"FE" AND retry_cnt > 0 THEN
										byte_idx <= 0;
										state <= ST_READ_BYTES;
									ELSIF retry_cnt = 50000 THEN
										state <= ST_ERROR;
									ELSE
										spi_tx <= x"FF";
										spi_start <= '1';
										retry_cnt <= retry_cnt + 1;
									END IF;
								END IF;
							WHEN ST_READ_BYTES => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF byte_idx > 0 THEN
										sd_buf_addr <= to_unsigned(byte_idx - 1, 9);
										sd_buf_din <= spi_rx;
										sd_buf_we <= '1';
									END IF;
									IF byte_idx < 512 THEN
										spi_tx <= x"FF";
										spi_start <= '1';
										byte_idx <= byte_idx + 1;
									ELSE
										byte_idx <= 0;
										state <= ST_READ_CRC;
									END IF;
								END IF;
							WHEN ST_READ_CRC => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF byte_idx < 2 THEN
										spi_tx <= x"FF";
										spi_start <= '1';
										byte_idx <= byte_idx + 1;
									ELSE
										state <= ST_DONE;
									END IF;
								END IF;
								-- Sector Write States
							WHEN ST_WRITE_TOK => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									spi_tx <= x"FE"; -- Start Block Token
									spi_start <= '1';
									byte_idx <= 0;
									sd_buf_addr <= (OTHERS => '0');
									state <= ST_WRITE_BYTES;
								END IF;
							WHEN ST_WRITE_BYTES => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF byte_idx < 512 THEN
										spi_tx <= sd_buf_dout;
										spi_start <= '1';
										byte_idx <= byte_idx + 1;
										sd_buf_addr <= to_unsigned(byte_idx + 1, 9);
									ELSE
										byte_idx <= 0;
										state <= ST_WRITE_CRC;
									END IF;
								END IF;
							WHEN ST_WRITE_CRC => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF byte_idx < 2 THEN
										spi_tx <= x"FF";
										spi_start <= '1';
										byte_idx <= byte_idx + 1;
									ELSE
										state <= ST_WRITE_RESP;
									END IF;
								END IF;
							WHEN ST_WRITE_RESP => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									spi_tx <= x"FF";
									spi_start <= '1';
									state <= ST_WRITE_BUSY;
								END IF;
							WHEN ST_WRITE_BUSY => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									IF spi_rx = x"FF" THEN
										state <= ST_DONE;
									ELSE
										spi_tx <= x"FF";
										spi_start <= '1';
									END IF;
								END IF;
							WHEN ST_DONE => 
								IF spi_busy = '0' AND spi_start = '0' THEN
									sd_cs_n <= '1';
									spi_tx <= x"FF";
									state <= ST_IDLE;
								END IF;
							WHEN ST_ERROR => 
								sd_cs_n <= '1';
								err_reg <= '1';
								state <= ST_IDLE;
						END CASE;
					END IF;
				END IF;
			END PROCESS;
			END ARCHITECTURE rtl;

			-- ENTITY 2: Native RomWBW hd1k BDOS Filesystem Controller + CPU Bus Wrapper

			LIBRARY ieee;
			USE ieee.std_logic_1164.ALL;
			USE ieee.numeric_std.ALL;
			ENTITY romwbw_hd1k_bdos IS
				GENERIC (
				CLK_FREQ_HZ : INTEGER := 50_000_000
				);
				PORT (
				clk : IN std_logic;
				rst : IN std_logic;
				-- 8-Bit CPU Memory/IO Bus Interface
				-- Addr 0x00: Command / Status Register
				-- Addr 0x01: Slice Select Register (0..15)
				-- Addr 0x02: BDOS Return Code (0x00..0x03 = Dir Index/Success, 0xFF = Error/EOF)
				-- Addr 0x03: DMA Buffer Pointer (0..127, auto-increments on 0x04 R/W)
				-- Addr 0x04: DMA Data Port (128-byte CP/M record window)
				-- Addr 0x20..0x3F: Active 32-byte File Control Block (FCB)
				bus_addr : IN std_logic_vector(5 DOWNTO 0);
				bus_din : IN std_logic_vector(7 DOWNTO 0);
				bus_dout : OUT std_logic_vector(7 DOWNTO 0);
				bus_cs : IN std_logic;
				bus_we : IN std_logic;
				bus_re : IN std_logic;
				-- Physical Micro-SD SPI Interface
				sd_cs_n : OUT std_logic;
				sd_sclk : OUT std_logic;
				sd_mosi : OUT std_logic;
				sd_miso : IN std_logic
				);
			END ENTITY romwbw_hd1k_bdos;
			ARCHITECTURE rtl OF romwbw_hd1k_bdos IS
				-- RomWBW hd1k Geometry Constants
				CONSTANT DEFAULT_PREFIX_LBA : unsigned(31 DOWNTO 0) := to_unsigned(2048, 32); -- 1MB prefix
				CONSTANT SLICE_SECTORS : unsigned(31 DOWNTO 0) := to_unsigned(16384, 32); -- 8MB slice
				CONSTANT RESERVED_SECTORS : unsigned(31 DOWNTO 0) := to_unsigned(32, 32); -- 2 boot tracks
				CONSTANT DIR_SECTORS : INTEGER := 64; -- 1024 entries * 32B = 32KB = 64 sectors
				CONSTANT TOTAL_BLOCKS : INTEGER := 2040; -- DSM = 2039 (Blocks 0..2039)
				-- BDOS Function Opcodes
				CONSTANT CMD_RESET_DISK : std_logic_vector(7 DOWNTO 0) := x"0D"; -- 13
				CONSTANT CMD_SELECT_DISK : std_logic_vector(7 DOWNTO 0) := x"0E"; -- 14
				CONSTANT CMD_OPEN_FILE : std_logic_vector(7 DOWNTO 0) := x"0F"; -- 15
				CONSTANT CMD_CLOSE_FILE : std_logic_vector(7 DOWNTO 0) := x"10"; -- 16
				CONSTANT CMD_SEARCH_FIRST : std_logic_vector(7 DOWNTO 0) := x"11"; -- 17
				CONSTANT CMD_SEARCH_NEXT : std_logic_vector(7 DOWNTO 0) := x"12"; -- 18
				CONSTANT CMD_DELETE_FILE : std_logic_vector(7 DOWNTO 0) := x"13"; -- 19
				CONSTANT CMD_READ_SEQ : std_logic_vector(7 DOWNTO 0) := x"14"; -- 20
				CONSTANT CMD_WRITE_SEQ : std_logic_vector(7 DOWNTO 0) := x"15"; -- 21
				CONSTANT CMD_MAKE_FILE : std_logic_vector(7 DOWNTO 0) := x"16"; -- 22
				-- SD Controller Interconnect
				SIGNAL sd_cmd_init : std_logic := '0';
				SIGNAL sd_cmd_read : std_logic := '0';
				SIGNAL sd_cmd_write : std_logic := '0';
				SIGNAL sd_lba_addr : std_logic_vector(31 DOWNTO 0) := (OTHERS => '0');
				SIGNAL sd_busy : std_logic;
				SIGNAL sd_ready : std_logic;
				SIGNAL sd_err : std_logic;
				SIGNAL sd_buf_addr : std_logic_vector(8 DOWNTO 0) := (OTHERS => '0');
				SIGNAL sd_buf_din : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
				SIGNAL sd_buf_we : std_logic := '0';
				SIGNAL sd_buf_dout : std_logic_vector(7 DOWNTO 0);
				-- 32-Byte Hardware FCB Register File
				-- [0]=DR, [1..8]=F1..F8, [9..11]=T1..T3, [12]=EX, [13]=S1, [14]=S2, [15]=RC,
				-- [16..31]=AL0..AL15 (8 x 16-bit block numbers), [32]=CR (Current Record, stored separately)
				TYPE fcb_t IS ARRAY (0 TO 31) OF std_logic_vector(7 DOWNTO 0);
				SIGNAL fcb : fcb_t := (OTHERS => (OTHERS => '0'));
				SIGNAL fcb_cr : unsigned(7 DOWNTO 0) := (OTHERS => '0');
				SIGNAL active_dir_idx : unsigned(9 DOWNTO 0) := (OTHERS => '0'); -- 0..1023
				-- 128-Byte CP/M DMA Record Buffer
				TYPE dma_t IS ARRAY (0 TO 127) OF std_logic_vector(7 DOWNTO 0);
				SIGNAL dma_buf : dma_t := (OTHERS => (OTHERS => '0'));
				SIGNAL dma_ptr : unsigned(6 DOWNTO 0) := (OTHERS => '0');
				-- Hardware Block Allocation Bitmap (2040 bits: 1 = allocated, 0 = free)
				SIGNAL alloc_map : std_logic_vector(2039 DOWNTO 0) := (OTHERS => '0');
				-- Filesystem State & Cache Tracking
				SIGNAL part_base_lba : unsigned(31 DOWNTO 0) := DEFAULT_PREFIX_LBA;
				SIGNAL current_slice : unsigned(3 DOWNTO 0) := (OTHERS => '0');
				SIGNAL cached_lba : unsigned(31 DOWNTO 0) := x"FFFFFFFF";
				SIGNAL cache_dirty : std_logic := '0';
				SIGNAL search_idx : unsigned(9 DOWNTO 0) := (OTHERS => '0');
				SIGNAL search_mode : std_logic := '0'; -- '0' = exact open/delete, '1' = wildcard search
				-- CPU Registers
				SIGNAL bdos_busy : std_logic := '0';
				SIGNAL bdos_ret : std_logic_vector(7 DOWNTO 0) := x"00";
				SIGNAL pending_cmd : std_logic_vector(7 DOWNTO 0) := x"00";
				SIGNAL cmd_trigger : std_logic := '0';
				-- Main BDOS FSM
				TYPE bdos_state_t IS (B_IDLE, 
				-- Reset / Mount Sequence
				B_INIT_SD, B_WAIT_SD_INIT, B_READ_MBR, B_WAIT_MBR, B_PARSE_MBR, 
				-- Bitmap Scan Sequence
				B_SCAN_INIT, B_SCAN_READ_SEC, B_SCAN_WAIT_SEC, B_SCAN_ENTRY, B_SCAN_NEXT, 
				-- Directory Search / Open / Delete / Make
				B_DIR_START, B_DIR_READ_SEC, B_DIR_WAIT_SEC, B_DIR_CHECK_ENTRY, B_DIR_LOAD_FCB, B_DIR_DEL_WRITE, B_DIR_MAKE_WRITE, 
				-- Sequential Read / Write
				B_RW_CALC_LBA, B_RW_FLUSH_OLD, B_RW_WAIT_FLUSH, B_RW_FETCH_SEC, B_RW_WAIT_FETCH, B_RW_COPY_DATA, 
				-- Close / Commit Directory Entry
				B_CLOSE_FLUSH_DATA, B_CLOSE_WAIT_DATA, B_CLOSE_READ_DIR, B_CLOSE_WAIT_DIR, B_CLOSE_WRITE_DIR, B_CLOSE_WAIT_WDIR, 
				B_FINISH);
				SIGNAL bstate : bdos_state_t := B_IDLE;
				SIGNAL after_dir_write : bdos_state_t := B_FINISH;
				-- Working Variables
				SIGNAL dir_sec_idx : INTEGER RANGE 0 TO 64 := 0;
				SIGNAL dir_ent_in_sec : INTEGER RANGE 0 TO 15 := 0;
				SIGNAL byte_cnt : INTEGER RANGE 0 TO 128 := 0;
				SIGNAL target_lba : unsigned(31 DOWNTO 0) := (OTHERS => '0');
				SIGNAL rec_offset_in_sec : unsigned(1 DOWNTO 0) := "00";
				SIGNAL cur_block_num : unsigned(15 DOWNTO 0) := (OTHERS => '0');
				SIGNAL free_block_found : unsigned(15 DOWNTO 0) := (OTHERS => '0');
				SIGNAL match_ok : std_logic := '0';
				-- Helper function: Compute LBA of start of current slice's data area (after 32 boot sectors)
				FUNCTION slice_data_base(base : unsigned(31 DOWNTO 0);
					slc : unsigned(3 DOWNTO 0)) RETURN unsigned ISBEGIN
					RETURN base + (resize(slc, 32) SLL 14) + RESERVED_SECTORS;
				END FUNCTION;
				BEGIN
				-- Instantiate SPI Micro-SD Controller
				u_sd : ENTITY work.sd_spi_master
						GENERIC MAP(CLK_FREQ_HZ => CLK_FREQ_HZ)
					PORT MAP(
						clk => clk, 
						rst => rst, 
						cmd_init => sd_cmd_init, 
						cmd_read => sd_cmd_read, 
						cmd_write => sd_cmd_write, 
						lba_addr => sd_lba_addr, 
						busy => sd_busy, 
						ready => sd_ready, 
						err => sd_err, 
						buf_addr => sd_buf_addr, 
						buf_din => sd_buf_din, 
						buf_we => sd_buf_we, 
						buf_dout => sd_buf_dout, 
						sd_cs_n => sd_cs_n, 
						sd_sclk => sd_sclk, 
						sd_mosi => sd_mosi, 
						sd_miso => sd_miso
					);
						----------------------------------------------------------------------------
						-- CPU Bus Read Multiplexer & Write Handler
						----------------------------------------------------------------------------
						PROCESS (clk)
				BEGIN
					IF rising_edge(clk) THEN
						cmd_trigger <= '0';
						IF rst = '1' THEN
							bus_dout <= x"00";
							current_slice <= (OTHERS => '0');
							dma_ptr <= (OTHERS => '0');
							fcb_cr <= (OTHERS => '0');
						ELSE
							IF bus_cs = '1' THEN
								-- CPU Read Access
								IF bus_re = '1' THEN
									CASE bus_addr IS
										WHEN "000000" => -- 0x00: Status [7]=Busy, [6]=SD_Ready, [5]=SD_Err, [4]=Dirty
											bus_dout <= bdos_busy & sd_ready & sd_err & cache_dirty & "0000";
										WHEN "000001" => -- 0x01: Current Slice
											bus_dout <= "0000" & std_logic_vector(current_slice);
										WHEN "000010" => -- 0x02: BDOS Return Code
											bus_dout <= bdos_ret;
										WHEN "000011" => -- 0x03: DMA Pointer
											bus_dout <= '0' & std_logic_vector(dma_ptr);
										WHEN "000100" => -- 0x04: DMA Data Auto-Increment Read
											bus_dout <= dma_buf(to_integer(dma_ptr));
											dma_ptr <= dma_ptr + 1;
										WHEN "000101" => -- 0x05: FCB Current Record (CR)
											bus_dout <= std_logic_vector(fcb_cr);
										WHEN OTHERS => 
											IF bus_addr(5) = '1' THEN -- 0x20..0x3F: FCB Bytes
												bus_dout <= fcb(to_integer(unsigned(bus_addr(4 DOWNTO 0))));
											ELSE
												bus_dout <= x"FF";
											END IF;
									END CASE;
								END IF;
								-- CPU Write Access (Only permitted when BDOS engine is idle)
								IF bus_we = '1' AND bdos_busy = '0' THEN
									CASE bus_addr IS
										WHEN "000000" => -- 0x00: Issue BDOS Command
											pending_cmd <= bus_din;
											cmd_trigger <= '1';
										WHEN "000001" => -- 0x01: Set Slice
											current_slice <= unsigned(bus_din(3 DOWNTO 0));
										WHEN "000011" => -- 0x03: Set DMA Pointer
											dma_ptr <= unsigned(bus_din(6 DOWNTO 0));
										WHEN "000100" => -- 0x04: DMA Data Auto-Increment Write
											dma_buf(to_integer(dma_ptr)) <= bus_din;
											dma_ptr <= dma_ptr + 1;
										WHEN "000101" => -- 0x05: FCB Current Record (CR)
											fcb_cr <= unsigned(bus_din);
										WHEN OTHERS => 
											IF bus_addr(5) = '1' THEN -- 0x20..0x3F: Write FCB
												fcb(to_integer(unsigned(bus_addr(4 DOWNTO 0)))) <= bus_din;
											END IF;
									END CASE;
								END IF;
							END IF;
						END IF;
					END IF;
				END PROCESS;
				----------------------------------------------------------------------------
				-- Native BDOS Filesystem Finite State Machine
				----------------------------------------------------------------------------
				PROCESS (clk)
				VARIABLE v_ent_base : INTEGER;
				VARIABLE v_fcb_char : std_logic_vector(6 DOWNTO 0);
				VARIABLE v_dir_char : std_logic_vector(6 DOWNTO 0);
				VARIABLE v_ext_num : unsigned(7 DOWNTO 0);
				VARIABLE v_blk_idx : INTEGER RANGE 0 TO 7;
				VARIABLE v_blk_num : unsigned(15 DOWNTO 0);
				VARIABLE v_sec_in_blk : unsigned(2 DOWNTO 0);
				VARIABLE v_found_free : BOOLEAN;
				BEGIN
					IF rising_edge(clk) THEN
						sd_cmd_init <= '0';
						sd_cmd_read <= '0';
						sd_cmd_write <= '0';
						sd_buf_we <= '0';
						IF rst = '1' THEN
							bstate <= B_IDLE;
							bdos_busy <= '0';
							bdos_ret <= x"00";
							cached_lba <= x"FFFFFFFF";
							cache_dirty <= '0';
							part_base_lba <= DEFAULT_PREFIX_LBA;
						ELSE
							CASE bstate IS
								WHEN B_IDLE => 
									bdos_busy <= '0';
									IF cmd_trigger = '1' THEN
										bdos_busy <= '1';
										bdos_ret <= x"00";
										CASE pending_cmd IS
											WHEN CMD_RESET_DISK => 
												bstate <= B_INIT_SD;
											WHEN CMD_SELECT_DISK => 
												-- Rebuild allocation bitmap for newly selected slice
												cached_lba <= x"FFFFFFFF";
												cache_dirty <= '0';
												bstate <= B_SCAN_INIT;
											WHEN CMD_OPEN_FILE => 
												search_idx <= (OTHERS => '0');
												search_mode <= '0';
												bstate <= B_DIR_START;
											WHEN CMD_SEARCH_FIRST => 
												search_idx <= (OTHERS => '0');
												search_mode <= '1';
												bstate <= B_DIR_START;
											WHEN CMD_SEARCH_NEXT => 
												search_idx <= search_idx + 1;
												search_mode <= '1';
												bstate <= B_DIR_START;
											WHEN CMD_DELETE_FILE => 
												search_idx <= (OTHERS => '0');
												search_mode <= '0';
												bstate <= B_DIR_START;
											WHEN CMD_MAKE_FILE => 
												search_idx <= (OTHERS => '0');
												search_mode <= '0';
												bstate <= B_DIR_START;
											WHEN CMD_READ_SEQ | CMD_WRITE_SEQ => 
												bstate <= B_RW_CALC_LBA;
											WHEN CMD_CLOSE_FILE => 
												bstate <= B_CLOSE_FLUSH_DATA;
											WHEN OTHERS => 
												bdos_ret <= x"FF";
												bstate <= B_FINISH;
										END CASE;
									END IF;
									------------------------------------------------------------
									-- 1. Initialize Micro-SD & Parse RomWBW MBR Partition
									------------------------------------------------------------
								WHEN B_INIT_SD => 
									sd_cmd_init <= '1';
									bstate <= B_WAIT_SD_INIT;
								WHEN B_WAIT_SD_INIT => 
									IF sd_cmd_init = '0' AND sd_busy = '0' THEN
										IF sd_err = '1' THEN
											bdos_ret <= x"FF";
											bstate <= B_FINISH;
										ELSE
											bstate <= B_READ_MBR;
										END IF;
									END IF;
								WHEN B_READ_MBR => 
									sd_lba_addr <= (OTHERS => '0'); -- Read LBA 0 (MBR)
									sd_cmd_read <= '1';
									bstate <= B_WAIT_MBR;
								WHEN B_WAIT_MBR => 
									IF sd_cmd_read = '0' AND sd_busy = '0' THEN
										IF sd_err = '1' THEN
											bdos_ret <= x"FF";
											bstate <= B_FINISH;
										ELSE
											-- Read MBR Partition 1 Start LBA at offset 0x1C6..0x1C9 (454..457)
											sd_buf_addr <= to_unsigned(454, 9);
											byte_cnt <= 0;
											bstate <= B_PARSE_MBR;
										END IF;
									END IF;
								WHEN B_PARSE_MBR => 
									IF byte_cnt < 4 THEN
										IF byte_cnt > 0 THEN
											part_base_lba <= unsigned(sd_buf_dout) & part_base_lba(31 DOWNTO 8);
										END IF;
										sd_buf_addr <= to_unsigned(454 + byte_cnt + 1, 9);
										byte_cnt <= byte_cnt + 1;
									ELSE
										part_base_lba <= unsigned(sd_buf_dout) & part_base_lba(31 DOWNTO 8);
										-- If MBR has no partition (0), fall back to 2048 (hd1k_prefix)
										IF (unsigned(sd_buf_dout) & part_base_lba(31 DOWNTO 8)) = 0 THEN
											part_base_lba <= DEFAULT_PREFIX_LBA;
										END IF;
										bstate <= B_SCAN_INIT;
									END IF;
									------------------------------------------------------------
									-- 2. Scan 64 Directory Sectors to Build Allocation Bitmap
									------------------------------------------------------------
								WHEN B_SCAN_INIT => 
									-- Blocks 0..7 belong to the 32KB Directory itself
									alloc_map <= (OTHERS => '0');
									alloc_map(7 DOWNTO 0) <= x"FF";
									dir_sec_idx <= 0;
									bstate <= B_SCAN_READ_SEC;
								WHEN B_SCAN_READ_SEC => 
									IF dir_sec_idx < DIR_SECTORS THEN
										sd_lba_addr <= std_logic_vector(slice_data_base(part_base_lba, current_slice) + to_unsigned(dir_sec_idx, 32));
										sd_cmd_read <= '1';
										bstate <= B_SCAN_WAIT_SEC;
									ELSE
										bdos_ret <= x"00";
										bstate <= B_FINISH;
									END IF;
								WHEN B_SCAN_WAIT_SEC => 
									IF sd_cmd_read = '0' AND sd_busy = '0' THEN
										dir_ent_in_sec <= 0;
										byte_cnt <= 0;
										sd_buf_addr <= (OTHERS => '0');
										bstate <= B_SCAN_ENTRY;
									END IF;
								WHEN B_SCAN_ENTRY => 
									v_ent_base := dir_ent_in_sec * 32;
									IF byte_cnt = 0 THEN
										-- Read status byte (0xE5 = deleted/unused)
										sd_buf_addr <= to_unsigned(v_ent_base + 16, 9);
										byte_cnt <= 1;
									ELSIF byte_cnt = 1 THEN
										IF sd_buf_dout = x"E5" THEN
											-- Skip deleted entry
											bstate <= B_SCAN_NEXT;
										ELSE
											-- Read 16-bit block pointers at offsets 16..31
											byte_cnt <= 2;
											sd_buf_addr <= to_unsigned(v_ent_base + 17, 9);
										END IF;
									ELSIF byte_cnt <= 17 THEN
										IF (byte_cnt MOD 2) = 0 THEN
											cur_block_num(7 DOWNTO 0) <= unsigned(sd_buf_dout);
										ELSE
											v_blk_num := unsigned(sd_buf_dout) & cur_block_num(7 DOWNTO 0);
											IF v_blk_num > 0 AND v_blk_num < TOTAL_BLOCKS THEN
												alloc_map(to_integer(v_blk_num)) <= '1';
											END IF;
										END IF;
										sd_buf_addr <= to_unsigned(v_ent_base + 16 + byte_cnt, 9);
										byte_cnt <= byte_cnt + 1;
									ELSE
										bstate <= B_SCAN_NEXT;
									END IF;
								WHEN B_SCAN_NEXT => 
									IF dir_ent_in_sec < 15 THEN
										dir_ent_in_sec <= dir_ent_in_sec + 1;
										byte_cnt <= 0;
										sd_buf_addr <= to_unsigned((dir_ent_in_sec + 1) * 32, 9);
										bstate <= B_SCAN_ENTRY;
									ELSE
										dir_sec_idx <= dir_sec_idx + 1;
										bstate <= B_SCAN_READ_SEC;
									END IF;
									------------------------------------------------------------
									-- 3. Directory Lookup / Open / Search / Delete / Make
									------------------------------------------------------------
								WHEN B_DIR_START => 
									IF search_idx >= 1024 THEN
										bdos_ret <= x"FF"; -- Not found / Directory full
										bstate <= B_FINISH;
									ELSE
										target_lba <= slice_data_base(part_base_lba, current_slice) + resize(search_idx(9 DOWNTO 4), 32);
										IF target_lba = cached_lba THEN
											byte_cnt <= 0;
											sd_buf_addr <= search_idx(3 DOWNTO 0) & "00000";
											match_ok <= '1';
											bstate <= B_DIR_CHECK_ENTRY;
										ELSE
											bstate <= B_DIR_READ_SEC;
										END IF;
									END IF;
								WHEN B_DIR_READ_SEC => 
									sd_lba_addr <= std_logic_vector(target_lba);
									sd_cmd_read <= '1';
									bstate <= B_DIR_WAIT_SEC;
								WHEN B_DIR_WAIT_SEC => 
									IF sd_cmd_read = '0' AND sd_busy = '0' THEN
										cached_lba <= target_lba;
										cache_dirty <= '0';
										byte_cnt <= 0;
										sd_buf_addr <= search_idx(3 DOWNTO 0) & "00000";
										match_ok <= '1';
										bstate <= B_DIR_CHECK_ENTRY;
									END IF;
								WHEN B_DIR_CHECK_ENTRY => 
									v_ent_base := to_integer(search_idx(3 DOWNTO 0)) * 32;
									IF byte_cnt <= 12 THEN
										IF byte_cnt > 0 THEN
											-- Byte 0: User code; Bytes 1..11: 8.3 Filename; Byte 12: Extent EX
											IF pending_cmd = CMD_MAKE_FILE THEN
												-- Looking for first free (0xE5) slot
												IF byte_cnt = 1 THEN
													IF sd_buf_dout = x"E5" THEN
														match_ok <= '1';
													ELSE
														match_ok <= '0';
													END IF;
												END IF;
											ELSE
												IF byte_cnt = 1 THEN
													-- Match User Code (unless FCB[0] = '?' wildcard)
													IF sd_buf_dout = x"E5" THEN
														match_ok <= '0';
													ELSIF fcb(0) /= x"3F" AND sd_buf_dout /= fcb(0) THEN
														match_ok <= '0';
													END IF;
												ELSIF byte_cnt <= 12 THEN
													-- Compare 7-bit ASCII (ignore CP/M high-bit R/O & SYS flags)
													v_fcb_char := fcb(byte_cnt - 1)(6 DOWNTO 0);
													v_dir_char := sd_buf_dout(6 DOWNTO 0);
													IF v_fcb_char /= "0111111" AND v_fcb_char /= v_dir_char THEN
														match_ok <= '0';
													END IF;
												END IF;
											END IF;
										END IF;
										sd_buf_addr <= to_unsigned(v_ent_base + byte_cnt, 9);
										byte_cnt <= byte_cnt + 1;
									ELSE
										-- Check Extent byte (byte 12) for Open/Delete
										IF pending_cmd /= CMD_MAKE_FILE AND search_mode = '0' THEN
											-- For hd1k (EXM=1), compare EX(7 downto 1)
											IF sd_buf_dout(7 DOWNTO 1) /= fcb(12)(7 DOWNTO 1) THEN
												match_ok <= '0';
											END IF;
										END IF;
										IF match_ok = '1' THEN
											active_dir_idx <= search_idx;
											bdos_ret <= "000000" & std_logic_vector(search_idx(1 DOWNTO 0));
											IF pending_cmd = CMD_OPEN_FILE OR pending_cmd = CMD_SEARCH_FIRST OR pending_cmd = CMD_SEARCH_NEXT THEN
												byte_cnt <= 0;
												sd_buf_addr <= to_unsigned(v_ent_base, 9);
												bstate <= B_DIR_LOAD_FCB;
											ELSIF pending_cmd = CMD_DELETE_FILE THEN
												-- Mark directory entry as 0xE5
												sd_buf_addr <= to_unsigned(v_ent_base, 9);
												sd_buf_din <= x"E5";
												sd_buf_we <= '1';
												bstate <= B_DIR_DEL_WRITE;
											ELSIF pending_cmd = CMD_MAKE_FILE THEN
												-- Clear FCB allocation pointers and write new entry
												FOR i IN 12 TO 31 LOOP
													fcb(i) <= x"00";
												END LOOP;
												fcb_cr <= x"00";
												byte_cnt <= 0;
												bstate <= B_DIR_MAKE_WRITE;
											END IF;
										ELSE
											search_idx <= search_idx + 1;
											bstate <= B_DIR_START;
										END IF;
									END IF;
								WHEN B_DIR_LOAD_FCB => 
									v_ent_base := to_integer(active_dir_idx(3 DOWNTO 0)) * 32;
									IF byte_cnt <= 32 THEN
										IF byte_cnt > 0 THEN
											IF search_mode = '1' THEN
												-- Copy raw 32B entry into DMA buffer for Search First/Next
												dma_buf(byte_cnt - 1) <= sd_buf_dout;
											ELSE
												-- Copy into active FCB
												fcb(byte_cnt - 1) <= sd_buf_dout;
											END IF;
										END IF;
										sd_buf_addr <= to_unsigned(v_ent_base + byte_cnt, 9);
										byte_cnt <= byte_cnt + 1;
									ELSE
										fcb_cr <= (OTHERS => '0');
										bstate <= B_FINISH;
									END IF;
								WHEN B_DIR_DEL_WRITE => 
									sd_lba_addr <= std_logic_vector(cached_lba);
									sd_cmd_write <= '1';
									after_dir_write <= B_SCAN_INIT; -- Refresh allocation bitmap after delete
									bstate <= B_CLOSE_WAIT_WDIR;
								WHEN B_DIR_MAKE_WRITE => 
									v_ent_base := to_integer(active_dir_idx(3 DOWNTO 0)) * 32;
									IF byte_cnt < 32 THEN
										sd_buf_addr <= to_unsigned(v_ent_base + byte_cnt, 9);
										sd_buf_din <= fcb(byte_cnt);
										sd_buf_we <= '1';
										byte_cnt <= byte_cnt + 1;
									ELSE
										sd_lba_addr <= std_logic_vector(cached_lba);
										sd_cmd_write <= '1';
										after_dir_write <= B_FINISH;
										bstate <= B_CLOSE_WAIT_WDIR;
									END IF;
									------------------------------------------------------------
									-- 4. Sequential 128-Byte Record Read / Write (with Extent & Block Alloc)
									------------------------------------------------------------
								WHEN B_RW_CALC_LBA => 
									-- In hd1k (EXM=1), each directory extent holds 256 records (32 KB)
									-- Bit 7 of fcb_cr selects upper/lower 16KB half-extent
									v_blk_idx := to_integer(fcb_cr(7 DOWNTO 5)); -- 0..7 (8 blocks * 32 recs = 256)
									v_sec_in_blk := fcb_cr(4 DOWNTO 2); -- 0..7 (8 sectors * 4 recs = 32)
									rec_offset_in_sec <= fcb_cr(1 DOWNTO 0); -- 0..3 (4 x 128B records per 512B sector)
									v_blk_num := unsigned(fcb(16 + (v_blk_idx * 2) + 1)) & unsigned(fcb(16 + (v_blk_idx * 2)));
									IF pending_cmd = CMD_READ_SEQ THEN
										-- Check EOF against Record Count (RC) and EX parity
										IF v_blk_num = 0 OR (fcb(12)(0) = '0' AND fcb_cr >= unsigned(fcb(15))) OR (fcb(12)(0) = '1' AND fcb_cr(6 DOWNTO 0) >= unsigned(fcb(15)(6 DOWNTO 0))) THEN
											bdos_ret <= x"01"; -- CP/M EOF
											bstate <= B_FINISH;
										ELSE
											target_lba <= slice_data_base(part_base_lba, current_slice) + (resize(v_blk_num, 32) SLL 3) + resize(v_sec_in_blk, 32);
											bstate <= B_RW_FLUSH_OLD;
										END IF;
									ELSE
										-- CMD_WRITE_SEQ: Allocate new 4KB block if v_blk_num = 0
										IF v_blk_num = 0 THEN
											v_found_free := false;
											FOR b IN 8 TO 2039 LOOP
												IF alloc_map(b) = '0' AND NOT v_found_free THEN
													v_blk_num := to_unsigned(b, 16);
													alloc_map(b) <= '1';
													v_found_free := true;
												END IF;
											END LOOP;
											IF NOT v_found_free THEN
												bdos_ret <= x"02"; -- Disk Full
												bstate <= B_FINISH;
											ELSE
												fcb(16 + (v_blk_idx * 2)) <= std_logic_vector(v_blk_num(7 DOWNTO 0));
												fcb(16 + (v_blk_idx * 2) + 1) <= std_logic_vector(v_blk_num(15 DOWNTO 8));
												target_lba <= slice_data_base(part_base_lba, current_slice) + (resize(v_blk_num, 32) SLL 3) + resize(v_sec_in_blk, 32);
												bstate <= B_RW_FLUSH_OLD;
											END IF;
										ELSE
											target_lba <= slice_data_base(part_base_lba, current_slice) + (resize(v_blk_num, 32) SLL 3) + resize(v_sec_in_blk, 32);
											bstate <= B_RW_FLUSH_OLD;
										END IF;
									END IF;
								WHEN B_RW_FLUSH_OLD => 
									IF target_lba = cached_lba THEN
										-- Sector Cache Hit!
										byte_cnt <= 0;
										sd_buf_addr <= rec_offset_in_sec & "0000000";
										bstate <= B_RW_COPY_DATA;
									ELSIF cache_dirty = '1' THEN
										-- Write back dirty 512B sector before loading new one
										sd_lba_addr <= std_logic_vector(cached_lba);
										sd_cmd_write <= '1';
										bstate <= B_RW_WAIT_FLUSH;
									ELSE
										bstate <= B_RW_FETCH_SEC;
									END IF;
								WHEN B_RW_WAIT_FLUSH => 
									IF sd_cmd_write = '0' AND sd_busy = '0' THEN
										cache_dirty <= '0';
										bstate <= B_RW_FETCH_SEC;
									END IF;
								WHEN B_RW_FETCH_SEC => 
									sd_lba_addr <= std_logic_vector(target_lba);
									sd_cmd_read <= '1';
									bstate <= B_RW_WAIT_FETCH;
								WHEN B_RW_WAIT_FETCH => 
									IF sd_cmd_read = '0' AND sd_busy = '0' THEN
										cached_lba <= target_lba;
										cache_dirty <= '0';
										byte_cnt <= 0;
										sd_buf_addr <= rec_offset_in_sec & "0000000";
										bstate <= B_RW_COPY_DATA;
									END IF;
								WHEN B_RW_COPY_DATA => 
									IF pending_cmd = CMD_READ_SEQ THEN
										IF byte_cnt <= 128 THEN
											IF byte_cnt > 0 THEN
												dma_buf(byte_cnt - 1) <= sd_buf_dout;
											END IF;
											sd_buf_addr <= (rec_offset_in_sec & "0000000") + to_unsigned(byte_cnt, 9);
											byte_cnt <= byte_cnt + 1;
										ELSE
											-- Advance Current Record (CR) & chain to next extent if CR wraps 255->0
											IF fcb_cr = x"FF" THEN
												fcb_cr <= x"00";
												fcb(12) <= std_logic_vector(unsigned(fcb(12)) + 2);
												search_idx <= (OTHERS => '0');
												search_mode <= '0';
												pending_cmd <= CMD_OPEN_FILE;
												bstate <= B_DIR_START;
											ELSE
												fcb_cr <= fcb_cr + 1;
												bdos_ret <= x"00";
												bstate <= B_FINISH;
											END IF;
										END IF;
									ELSE
										-- CMD_WRITE_SEQ: Copy 128B from DMA buffer into 512B sector cache
										IF byte_cnt < 128 THEN
											sd_buf_addr <= (rec_offset_in_sec & "0000000") + to_unsigned(byte_cnt, 9);
											sd_buf_din <= dma_buf(byte_cnt);
											sd_buf_we <= '1';
											byte_cnt <= byte_cnt + 1;
										ELSE
											cache_dirty <= '1';
											-- Update FCB Record Count (RC) and EX parity bit
											IF fcb_cr >= 128 THEN
												fcb(12)(0) <= '1';
												IF unsigned(fcb(15)) <= fcb_cr(6 DOWNTO 0) THEN
													fcb(15) <= '0' & std_logic_vector(fcb_cr(6 DOWNTO 0) + 1);
												END IF;
											ELSE
												IF unsigned(fcb(15)) <= fcb_cr(6 DOWNTO 0) THEN
													fcb(15) <= std_logic_vector(fcb_cr + 1);
												END IF;
											END IF;
											IF fcb_cr = x"FF" THEN
												-- Close full extent and make next extent
												fcb_cr <= x"00";
												pending_cmd <= CMD_CLOSE_FILE;
												bstate <= B_CLOSE_FLUSH_DATA;
											ELSE
												fcb_cr <= fcb_cr + 1;
												bdos_ret <= x"00";
												bstate <= B_FINISH;
											END IF;
										END IF;
									END IF;
									------------------------------------------------------------
									-- 5. Close File (Flush Dirty Cache + Update Directory Entry)
									------------------------------------------------------------
								WHEN B_CLOSE_FLUSH_DATA => 
									IF cache_dirty = '1' THEN
										sd_lba_addr <= std_logic_vector(cached_lba);
										sd_cmd_write <= '1';
										bstate <= B_CLOSE_WAIT_DATA;
									ELSE
										bstate <= B_CLOSE_READ_DIR;
									END IF;
								WHEN B_CLOSE_WAIT_DATA => 
									IF sd_cmd_write = '0' AND sd_busy = '0' THEN
										cache_dirty <= '0';
										bstate <= B_CLOSE_READ_DIR;
									END IF;
								WHEN B_CLOSE_READ_DIR => 
									target_lba <= slice_data_base(part_base_lba, current_slice) + resize(active_dir_idx(9 DOWNTO 4), 32);
									sd_lba_addr <= std_logic_vector(slice_data_base(part_base_lba, current_slice) + resize(active_dir_idx(9 DOWNTO 4), 32));
									sd_cmd_read <= '1';
									bstate <= B_CLOSE_WAIT_DIR;
								WHEN B_CLOSE_WAIT_DIR => 
									IF sd_cmd_read = '0' AND sd_busy = '0' THEN
										cached_lba <= target_lba;
										byte_cnt <= 0;
										bstate <= B_CLOSE_WRITE_DIR;
									END IF;
								WHEN B_CLOSE_WRITE_DIR => 
									v_ent_base := to_integer(active_dir_idx(3 DOWNTO 0)) * 32;
									IF byte_cnt < 32 THEN
										sd_buf_addr <= to_unsigned(v_ent_base + byte_cnt, 9);
										sd_buf_din <= fcb(byte_cnt);
										sd_buf_we <= 
											'1';
											byte_cnt <= byte_cnt + 1;
									ELSE
										sd_lba_addr <= std_logic_vector(target_lba);
										sd_cmd_write <= '1';
										after_dir_write <= B_FINISH;
										bstate <= B_CLOSE_WAIT_WDIR;
									END IF;
								WHEN B_CLOSE_WAIT_WDIR => 
									IF sd_cmd_write = '0' AND sd_busy = '0' THEN
										cache_dirty <= '0';
										bdos_ret <= "000000" & std_logic_vector(active_dir_idx(1 DOWNTO 0));
										bstate <= after_dir_write;
									END IF;
								WHEN B_FINISH => 
									bdos_busy <= '0';
									bstate <= B_IDLE;
							END CASE;
						END IF;
					END IF;
				END PROCESS;
END ARCHITECTURE rtl;
