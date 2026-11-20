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


-- This module is only for simulation and verification.
-- It simulates a DMI bus manager for the riscv_rsdp_transport_tb testbench.
-- Its main purpose is to provide pseudo random data on
--    oJtag_Data, oJtag_Op
-- below.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.riscv_rsdp_pkg.all;

entity riscv_jtag_backend_sim is
generic (
	-- Size of address bits required for DMI access.
	gAddressWidth : NATURAL
);
port (
	iRst        :  in STD_LOGIC;

	iRSDP_Clk   :  in STD_LOGIC;
	iJtag_Instr :  in STD_LOGIC_VECTOR( 4 downto 0); -- Content IR register

	iJtag_CapDR :  in STD_LOGIC;                                     -- Capture-DR state
	oJtag_Data  : out STD_LOGIC_VECTOR(31 downto 0);                 -- DATA bits (TDI for DMI/DTMCS access)
	oJtag_Op    : out STD_LOGIC_VECTOR( 1 downto 0);                 -- OP bits (TDI for DMI access)

	iJtag_UpdDR :  in STD_LOGIC;                                     -- Update-DR state
	iJtag_Op    :  in STD_LOGIC_VECTOR( 1 downto 0);                 -- OP bits (for DMI access)
	iJtag_Data  :  in STD_LOGIC_VECTOR(31 downto 0);                 -- DATA bits (for DMI/DTMCS access)
	iJtag_Addr  :  in STD_LOGIC_VECTOR(gAddressWidth-1 downto 0)     -- ADDR bits (for DMI access)
);
end entity;

architecture rtl of riscv_jtag_backend_sim is

subtype tLfsrReg is STD_LOGIC_VECTOR(31 downto 0);
function fLfsrNext(iLfsr : in tLfsrReg) return tLfsrReg is
	variable vResult : tLfsrReg;
begin
	-- sequence in C code:
	-- r1 = (((r1<<6) ^ (r1<<4))&0xFFFFFFC0)|((r1 ^ (r1>>1) ^ (r1>>26))&0x3F);
	for i in 0 to 5 loop
		vResult(i) := iLfsr(i) xor iLfsr(i+1) xor iLfsr(i+26);
	end loop;
	for i in 6 to 31 loop
		vResult(i) := iLfsr(i-6) xor iLfsr(i-4);
	end loop;
	return vResult;
end function;

type tState is record
	idcode  : STD_LOGIC_VECTOR(31 downto 0);
	dtmcs   : STD_LOGIC_VECTOR(31 downto 0);
	dmi     : STD_LOGIC_VECTOR(31 downto 0);
	stat    : STD_LOGIC_VECTOR(31 downto 0);
end record;
constant cStateRst : tState := (
	idcode  => X"12345678",
	dtmcs   => X"23456789",
	dmi     => X"3456789A",
	stat    => X"456789AB"
);

type tInput is record
	instr : STD_LOGIC_VECTOR( 4 downto 0);
	capDR : STD_LOGIC;
	updDR : STD_LOGIC;
	op    : STD_LOGIC_VECTOR( 1 downto 0);
	data  : STD_LOGIC_VECTOR(31 downto 0);
	addr  : STD_LOGIC_VECTOR(gAddressWidth-1 downto 0);
end record;
signal ii : tInput;

signal rs, wNext: tState;
signal roJtagData : STD_LOGIC_VECTOR(31 downto 0);
signal roJtagOp   : STD_LOGIC_VECTOR(1 downto 0);

begin
	ii.instr <= iJtag_Instr;
	ii.capDR <= iJtag_CapDR;
	ii.updDR <= iJtag_UpdDR;
	ii.op    <= iJtag_Op;
	ii.data  <= iJtag_Data;
	ii.addr  <= iJtag_Addr;

	oJtag_Data <= roJtagData;
	oJtag_op   <= roJtagOp;
	process(iRSDP_Clk)
	begin
		if rising_edge(iRSDP_Clk) then
			case ii.instr is
				when cJtagDMI =>
					roJtagOp   <= rs.stat(1 downto 0);
					roJtagData <= rs.dmi;
				when cJtagDTMCS =>
					roJtagOp   <= "00";
					roJtagData <= rs.dtmcs;
				when cJtagIDCODE =>
					roJtagOp   <= "00";
					roJtagData <= rs.idcode;
				when others =>
					roJtagOp   <= (others => '0');
					roJtagData <= (others => '0');
			end case;
		end if;
	end process;

	pComb: process(rs, ii)
		variable n : tState;
	begin
		n := rs;

		-- read from dtmcs (CaptureDR)
		if ii.instr = cJtagDTMCS and ii.capDR = '1' then
			n.dtmcs := fLfsrNext(rs.dtmcs);
		end if;

		-- write to dtmcs (UpdateDR)
		if ii.instr = cJtagDTMCS and ii.updDR = '1' then
			n.dtmcs := rS.dtmcs xor fLfsrNext(ii.data);
		end if;

		-- read from dmi (CaptureDR)
		if ii.instr = cJtagDMI and ii.capDR = '1' then
			n.stat:= fLfsrNext(rs.stat);
		end if;

		-- write to dmi (UpdateDR)
		if ii.instr = cJtagDMI and ii.updDR = '1' then
			if ii.op = cDMI_OP_WR then
				n.dmi := rS.dmi xor fLfsrNext(ii.data);
			elsif ii.op = cDMI_OP_RD then
				n.dmi := fLfsrNext(rS.dmi);
			end if;
		end if;

		-- read from idcode (CaptureDR)
		if ii.instr = cJtagIDCODE and ii.capDR = '1' then
			n.idcode := fLfsrNext(rs.idcode);
		end if;
		wNext <= n;
	end process;

	pReg: process(iRst, iRSDP_Clk)
	begin
		if iRst = '1' then
			rs <= cStateRst;
		elsif rising_edge(iRSDP_Clk) then
			rs <= wNext;
		end if;
	end process;
end architecture;
