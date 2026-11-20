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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv_rsdp_sp_pkg;

entity riscv_rsdp_sp_act is
	port (
		-- free-running clock
		iRst:     in  std_logic;
		iClk:     in  std_logic;

		-- from riscv_rsdp_sp_phy
		iActive:  in  std_logic;
		iValid:   in  std_logic;
		iDataRx:  in  std_logic;
		oDataEn:  out std_logic;
		oDataTx:  out std_logic;

		-- to riscv_rsdp_sp_conv
		oDone:    out std_logic
	);
end entity;

architecture behavioral of riscv_rsdp_sp_act is
	type tMode is (
		cModeFail,
		cModeZeros,
		cModeDone
	);

	subtype tCnt is signed(10 downto 0);

	type tState is record
		mode:            tMode;

		cnt:             tCnt;

		done:            std_logic;
	end record;

	constant cStateInitial: tState := (
		mode             => cModeFail,
		cnt              => (others => '0'),
		done             => '0'
	);

	signal rState: tState := cStateInitial;
	signal wState: tState;

begin
	pCombinatorial: process(rState, iActive, iValid, iDataRx)
	begin
		wState <= rState;

		case rState.mode is
			when cModeFail =>

			when cModeZeros =>
				if iValid = '1' then
					if rState.cnt >= 0 then
						wState.cnt <= rState.cnt - 1;
					end if;

					if iDataRx = '1' then
						wState.mode <= cModeFail;
					elsif rState.cnt < 0 then
						wState.mode <= cModeDone;
					end if;
				end if;

			when cModeDone =>
				if iValid = '1' then
					wState.done    <= '1';
				end if;
		end case;

		if iActive = '0' then
			wState.mode <= cModeZeros;
			wState.cnt  <= to_signed(riscv_rsdp_sp_pkg.cActZeroCnt - 2, rState.cnt'length);
			wState.done <= '0';
		end if;

		oDone   <= rState.done;
	end process;

	pSequential: process(iRst, iClk)
	begin
		if iRst = '1' then
			rState <= cStateInitial;
		elsif rising_edge(iClk) then
			rState <= wState;
		end if;
	end process;
end architecture;
