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

entity riscv_rsdp_sp_conv is
	port (
		-- free-running clock
		iRst:         in  std_logic;
		iClk:         in  std_logic;

		-- from riscv_rsdp_sp_phy
		iValid:       in  std_logic;
		iDataRx:      in  std_logic;
		oDataEn:      out std_logic;
		oDataTx:      out std_logic;

		-- from riscv_rsdp_sp_act
		iActDone:     in  std_logic;

		-- to RSDP transport
		oRsdpClk:     out std_logic;
		oRsdpDataOut: out std_logic;
		iRsdpDataOe:  in  std_logic;
		iRsdpDataIn:  in  std_logic
	);
end entity;

architecture behavioral of riscv_rsdp_sp_conv is
	type tState is record
		clk:             std_logic;
		data_rx:         std_logic;
		data_en:         std_logic;
		data_tx:         std_logic;
	end record;

	constant cStateInitial: tState := (
		clk              => '0',
		data_rx          => '0',
		data_en          => '0',
		data_tx          => '0'
	);

	signal rState: tState := cStateInitial;
	signal wState: tState;

begin
	pCombinatorial: process(rState, iValid, iDataRx, iActDone, iRsdpDataOe, iRsdpDataIn)
	begin
		wState <= rState;

		if iActDone = '0' then
			wState <= cStateInitial;
		else
			wState.clk <= '0';

			if iValid = '1' and rState.clk = '0' then
				wState.data_rx <= iDataRx;
				wState.clk <= '1';
			end if;
			if rState.clk = '1' then
				wState.data_en <= iRsdpDataOe;
				wState.data_tx <= iRsdpDataIn;
			end if;
		end if;

		oDataEn      <= rState.data_en;
		oDataTx      <= rState.data_tx;
		oRsdpClk     <= rState.clk;
		oRsdpDataOut <= iDataRx;
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
