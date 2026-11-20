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
use IEEE.numeric_std.all;
use work.riscv_rsdp_pkg.all;

entity riscv_rsdp_escape is
	generic (
		gStartInJtag : BOOLEAN;
		gCrcSupport  : BOOLEAN
	);
	port (
		iRst      : in STD_LOGIC;

		iClk      : in STD_LOGIC;
		iData     : in STD_LOGIC; -- that's from an input FLIP-FLOP!

		oToRsdp   : out tEscapeToRsdp
	);
end entity;

architecture rtl of riscv_rsdp_escape is

function fInitUseJtag return STD_LOGIC is
begin
	if gStartInJtag then
		return '1';
	else
		return '0';
	end if;
end function;

constant cToRsdpInit : tEscapeToRsdp := (
	RsdpEnable   => '0',
	RsdpWithCrc  => '0',
	UseJtag      => fInitUseJtag,
	WantResponse => '0',
	ResponseType => (others => '0')
);

type tReg is record
	Bits      : STD_LOGIC_VECTOR(1 downto 0);
	OnesDetected: STD_LOGIC;
	Shifting  : STD_LOGIC;
	BitCnt    : UNSIGNED(6 downto 0);
	ShiftCrc  : STD_LOGIC;
	ShiftST   : STD_LOGIC;
	Finished  : STD_LOGIC;
	ST        : STD_LOGIC_VECTOR(7 downto 0);
	Crc       : STD_LOGIC_VECTOR(5 downto 0);
	CrcError  : STD_LOGIC;

	SwitchToST : STD_LOGIC;
	SwitchToCrc : STD_LOGIC;

	pre       : tEscapeToRsdp;
	toRsdp    : tEscapeToRsdp;
end record;
constant cRegRst : tReg := (
	Bits         => (others => '0'),
	OnesDetected => '0',
	Shifting     => '0',
	BitCnt       => (others => '0'),
	ShiftCrc     => '0',
	ShiftST      => '0',
	Finished     => '0',
	ST           => (others => '0'),
	Crc          => (others => '0'),
	CrcError     => '0',

	SwitchToST   => '0',
	SwitchToCrc  => '0',

	pre          => cEscapeToRsdpRst,
	toRsdp       => cToRsdpInit
);
signal rS : tReg := cRegRst;
signal wS : tReg;

begin
	oToRsdp <= rS.toRsdp;
	pDFF: process(iRst, iClk)
	begin
		if iRst= '1' then
			rS <= cRegRst;
		elsif rising_edge(iClk) then
			rS <= wS;
		end if;
	end process;

	pComb: process(rS, iData)
		variable n : tReg;
		variable vCrcXor : STD_LOGIC;
	begin
		n := rS;
		n.bits(1) := iData;
		n.bits(0) := rS.bits(1);

		vCrcXor := (rS.Crc(0) and (not rS.ShiftCrc)) xor (rS.Bits(1) and rS.ShiftST);
		if rS.Shifting = '0' then
			-- waiting for 80 x 1 + 010
			if iData='0' then
				n.BitCnt := (others => '0');
			elsif rS.OnesDetected = '0' then
				n.BitCnt := rS.BitCnt + 1;
			end if;
			if iData='1' and rS.BitCnt=79 then
				n.OnesDetected := '1';
			end if;
			if rS.OnesDetected = '1' and rS.Bits(0)='0' then
				n.OnesDetected := '0';
				if iData='0' and rS.Bits(1)='1' then
					n.Shifting := '1';
				end if;
			end if;
			n.Crc := "111000";
			n.ST  := (others => '0');
			n.ShiftST := '0';
			n.ShiftCrc := '0';
			n.SwitchToST := '0';
			n.SwitchToCrc := '0';
			n.CrcError := '0';
		elsif iData = '0' then
			-- We are shifting bits. iData = '0' => Receive one encoded bit.
			-- Bit value is in rS.Bits(1).

			-- CRC-6 ITU G.704, polynomial 0x30:
			n.Crc(3 downto 0) := rS.Crc(4 downto 1);
			n.Crc(4) := rS.Crc(5) xor vCrcXor;
			n.Crc(5) := vCrcXor;

			-- States
			-- rS.ShiftST='0' and rS.ShiftCrc='0'
			--      Receiving 32 bit RANDOM field
			-- rS.ShiftST='1' and rS.ShiftCrc='0'
			--      Receiving 8 bit ST field
			-- rS.ShiftST='0' and rS.ShiftCrc='1'
			--      Receiving CRC field (until JTAG_END is received)
			if rS.ShiftST='0' and rS.ShiftCrc='0' then
				-- Shifting RANDOM sequence
				if rS.Crc(0) /= rS.Bits(1) then
					n.Shifting := '0';
				end if;
			end if;
			if rS.ShiftST='1' then
				-- Shifting 8 Bit ST
				n.ST(7)          := rS.Bits(1);
				n.ST(6 downto 0) := rS.ST(7 downto 1);
			end if;

			-- rS.ShiftST='0' and rS.ShiftCrc='1'
			-- Shifting CRC until iData='1' rS.Bits(1)='1' is received.
			-- Stop incrementing rS.BitCnt after receiving 8 CRC bits (illegal).
			-- Prevents to activate SwitchToST a 2nd time.
			if rS.ShiftCrc = '0' or rS.BitCnt(3) = '0' then
				n.BitCnt := rS.BitCnt + 1;
			end if;

			n.SwitchToST := '0';
			if rS.ShiftST = '0' and rS.BitCnt(4 downto 0) = 30 then
				n.SwitchToST := '1';
			end if;
			if rS.SwitchToST='1' then
				-- Switch from receiving RANDOM to receiving ST bits.
				n.BitCnt   := (others => '0');
				n.ShiftST := '1';
			end if;

			n.SwitchToCrc := '0';
			if rS.ShiftST = '1' and rS.BitCnt(2 downto 0) = 6 then
				n.SwitchToCrc := '1';
			end if;
			if rS.SwitchToCrc='1' then
				-- Switch from receiving ST to receiving CRC bits.
				n.BitCnt   := (others => '0');
				n.ShiftST := '0';
				n.ShiftCrc := '1';
			end if;

			if rS.ShiftCrc = '1' and rS.Bits(1)/=(not rS.Crc(0)) then
				n.CrcError := '1';
			end if;
		end if;

		-- Predecode ST(7..0)
		-- Default: Treat everything as DISABLE
		n.pre.RsdpEnable   := '0';
		n.pre.RsdpWithCrc  := '0';
		n.pre.UseJtag      := '0';
		n.pre.WantResponse := '0';
		n.pre.ResponseType := "00";
		case rS.ST is
			when cRSDP_ESC_ST_ROBUST =>
				if gCrcSupport then
					n.pre.RsdpEnable   := '1';
					n.pre.RsdpWithCrc  := '1';
					n.pre.WantResponse := '1';
					n.pre.ResponseType := "00";
				end if;
				-- ROBUST not supported, treat like DISABLE
			when cRSDP_ESC_ST_FAST   =>
				n.pre.RsdpEnable   := '1';
				n.pre.WantResponse := '1';
				n.pre.ResponseType := "01";
			when cRSDP_ESC_ST_RTNS   =>
				if gCrcSupport then
					if rS.toRsdp.RsdpEnable = '1' and rS.toRsdp.RsdpWithCrc='1' then
						-- ROBUST mode, send answer
						n.pre.RsdpEnable   := '1';
						n.pre.RsdpWithCrc  := '1';
						n.pre.WantResponse := '1';
						n.pre.ResponseType := "10";
					end if;
				end if;
				-- ROBUST not supported or in FAST mode, treat like DISABLE
			when cRSDP_ESC_ST_JTAG =>
				n.pre.UseJtag      := '1';
			when others =>
				null;
		end case;

		if rS.Shifting = '1' and iData='1' and rS.Bits(1) = '1' then
			-- JTAG_END received
			n.Shifting := '0';
		end if;

		n.Finished := '0';
		n.toRsdp.WantResponse := '0';
		n.toRsdp.ResponseType := "00";
		if rS.ShiftCrc = '1' and rS.BitCnt(2 downto 0) = 6 then
			-- SHOULD receive JTAG_END next
			n.Shifting := '0';
			n.ShiftCrc := '0';
			if iData='1' and rS.CrcError='0' then
				-- MIGHT be JTAG_END (first '1' received of JTAG_END)
				n.Finished := '1';
				n.toRsdp.WantResponse := rS.pre.WantResponse;
				n.toRsdp.ResponseType := rS.pre.ResponseType;
			end if;
		end if;

		if rS.Finished = '1' and iData='1' then
			-- Received JTAG_END at right position
			n.toRsdp.RsdpEnable  := rS.pre.RsdpEnable;
			n.toRsdp.RsdpWithCrc := rS.pre.RsdpWithCrc;
			n.toRsdp.UseJtag     := rS.pre.UseJtag;
		end if;

		if not gCrcSupport then
			n.pre.RsdpWithCrc    := '0';
			n.toRsdp.RsdpWithCrc := '0';
		end if;

		wS <= n;
	end process;
end architecture;
