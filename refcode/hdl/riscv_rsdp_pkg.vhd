-- The MIT License
--
-- Copyright (c) 2026 Lauterbach GmbH, Ingo Rohloff
--
-- Permission is hereby granted, free of charge,
-- to any person obtaining a copy of this software and
-- associated documentation files (the "Software"), to
-- deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify,
-- merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom
-- the Software is furnished to do so,
-- subject to the following conditions:
--
-- The above copyright notice and this permission notice
-- shall be included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
-- ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--


-- !WARNING! !WARNING! !WARNING! !WARNING! !WARNING!
--
-- This source code implements the **work-in-progress** RISC-V RSDP
-- specification (v0.1.5, 20th Oct 2026).
-- Please note that this specification is **preliminary** and
-- subject to future changes.


library IEEE;
use IEEE.std_logic_1164.all;

package riscv_rsdp_pkg is
	subtype tCrc is STD_LOGIC_VECTOR( 5 downto 0);

	subtype tJtagInst is STD_LOGIC_VECTOR(4 downto 0);
	constant cJtagBYPASS : tJtagInst := "11111";
	constant cJtagIDCODE : tJtagInst := "00001";
	constant cJtagDTMCS  : tJtagInst := "10000";
	constant cJtagDMI    : tJtagInst := "10001";

	subtype tTTCode is STD_LOGIC_VECTOR(3 downto 0);

	-- For all: Bit 0: 0 - DMI access  , 1 - Other Access (or illegal)
	-- For all: Bit 3: 0 - WR operation, 1 - RD operation (or illegal)

	-- For DMI access. Bit 1: 0 - NOP, 1 - Read or Write
	-- For DMI access. Bit 2: 0 - Normal Address, 1 - Short Address
	constant cTT_IS_DMI    : STD_LOGIC := '0';
	constant cTT_IS_SA     : STD_LOGIC := '1';
	constant cTT_IS_RD     : STD_LOGIC := '1';

	constant cTT_DMI_NOP   : tTTCode := "0100";

	constant cTT_DMI_WR    : tTTCode := "0010";
	constant cTT_DMI_RD    : tTTCode := "1010";
	constant cTT_DMI_WR_SA : tTTCode := "0110";
	constant cTT_DMI_RD_SA : tTTCode := "1110";

	-- For non DMI access. Bit[2..1] sub-type
	constant cTT_INTBUS_WR : tTTCode := "0001";
	constant cTT_INTBUS_RD : tTTCode := "1001";

	-- Free Codes, easy encoding, beacuse bit 0 set (no DMI access)
	--  0011   -- subtype 01
	--  1011
	--  0101   -- subtype 10
	--  1101
	-- Free codes, not so easy, because bit 0 cleared (indicate DMI access)
	--  0000
	--  1000
	--  1100
	constant cTT_NOP       : tTTCode := "0111"; -- Bit 0 set => No DMI access
	constant cTT_ILLEGAL   : tTTCode := "1111";

	subtype tDmiOp is STD_LOGIC_VECTOR(1 downto 0);
	constant cDMI_OP_NOP : tDmiOp := "00";
	constant cDMI_OP_RD  : tDmiOp := "01";
	constant cDMI_OP_WR  : tDmiOp := "10";

	subtype tRsdpEscST is STD_LOGIC_VECTOR(7 downto 0);
	constant cRSDP_ESC_ST_DISABLE : tRsdpEscST := X"00";
	constant cRSDP_ESC_ST_ROBUST  : tRsdpEscST := X"01";
	constant cRSDP_ESC_ST_FAST    : tRsdpEscST := X"02";
	constant cRSDP_ESC_ST_JTAG    : tRsdpEscST := X"03";
	constant cRSDP_ESC_ST_RTNS    : tRsdpEscST := X"04";

	type tEscapeToRsdp is record
		RsdpEnable   : STD_LOGIC;
		RsdpWithCrc  : STD_LOGIC;
		UseJtag      : STD_LOGIC;
		-- Strobe asserted for one cycle
		-- React if additionally iData == '1'
		WantResponse : STD_LOGIC;
			-- ResponseType
			--  "00"  ROBUST mode response
			--  "01"  FAST mode response
			--  "10"  RETRANSMIT response
		ResponseType : STD_LOGIC_VECTOR(1 downto 0);
	end record;
	constant cEscapeToRsdpRst : tEscapeToRsdp := (
		RsdpEnable   => '0',
		RsdpWithCrc  => '0',
		UseJtag      => '0',
		WantResponse => '0',
		ResponseType => (others => '0')
	);

	subtype tIntbusAddr is STD_LOGIC_VECTOR( 7 downto 0);
	subtype tIntbusData is STD_LOGIC_VECTOR(31 downto 0);
	type tIntbusMOSI is record
		addr     : tIntbusAddr;
		rdStrobe : STD_LOGIC;
		wrStrobe : STD_LOGIC;
		wrdata   : tIntbusData;
	end record;
	constant cIntbusMOSIRst : tIntbusMOSI := (
		addr     => (others => '0'),
		rdStrobe => '0',
		wrStrobe => '0',
		wrData   => (others => '0')
	);
	constant cIntbus_IDCODE : tIntbusAddr := X"00";
	constant cIntbus_DTMCS  : tIntbusAddr := X"01";
	constant cIntbus_SPDIV  : tIntbusAddr := X"02";
end package;

package body riscv_rsdp_pkg is
end package body;
