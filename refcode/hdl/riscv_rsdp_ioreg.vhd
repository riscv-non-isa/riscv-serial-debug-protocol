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

entity riscv_rsdp_ioreg is
	generic (
		-- gDrive: Which logic level indicates a drive on oRSDP_Data
		gDrive : STD_LOGIC
	);
	port (
		iRst          :  in STD_LOGIC;

		iRSDP_Clk     :  in STD_LOGIC;

		iRSDP_Data    :  in STD_LOGIC;
		oRSDP_DataDir : out STD_LOGIC; -- oRSDP_DataDir == gDrive => oRSDP_Data pin should drive
		oRSDP_Data    : out STD_LOGIC;

		oFrIoreg_Data : out STD_LOGIC;
		iToIoreg_Drv  :  in STD_LOGIC; -- 1 => drive oRSDP_Data pin
		iToIoreg_Data :  in STD_LOGIC
	);
end entity;

architecture rtl of riscv_rsdp_ioreg is

-- IO registers; place close to DATA pin
signal rDataI : STD_LOGIC := '0';
signal rDataO : STD_LOGIC := '0';
signal rDataD : STD_LOGIC := not gDrive;

begin
	pIoReg:
	process(iRSDP_Clk)
	begin
		if iRst = '1' then
			rDataD <= not gDrive;
			rDataO <= '0';
			rDataI <= '0';
		elsif rising_edge(iRSDP_Clk) then
			rDataD <= not gDrive;
			if iToIoreg_Drv='1' then
				rDataD <= gDrive;
			end if;
			rDataO <= iToIoreg_Data;
			rDataI <= iRSDP_Data;
		end if;
	end process;
	oRSDP_DataDir <= rDataD;
	oRSDP_Data    <= rDataO;
	oFrIoreg_Data <= rDataI;
end architecture;
