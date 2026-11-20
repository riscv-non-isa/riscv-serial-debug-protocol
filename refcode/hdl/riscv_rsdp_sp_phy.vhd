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

entity riscv_rsdp_sp_phy is
	port (
		-- free-running clock
		iRst:     in  std_logic;
		iClk:     in  std_logic;

		-- to/from ioregs
		iSpIn:  in  std_logic;
		oSpOe:  out std_logic;
		oSpOut: out std_logic;

		-- to riscv_rsdp_sp_act
		oDivider: out std_logic_vector(riscv_rsdp_sp_pkg.cDividerBits - 1 downto 0);
		oActive:  out std_logic;
		oValid:   out std_logic;
		oDataRx:  out std_logic;
		iDataEn:  in  std_logic;
		iDataTx:  in  std_logic
	);
end entity;

architecture behavioral of riscv_rsdp_sp_phy is
	type tMode is (
		cModeCalibrationFailed,
		cModeInactive,
		cModeCalibrate,
		cModeRx,
		cModeIdle,
		cModeTx
	);

	subtype tDivider       is unsigned(riscv_rsdp_sp_pkg.cDividerBits - 1 downto 0);
	subtype tDividerCnt    is unsigned(riscv_rsdp_sp_pkg.cDividerBits downto 0);
	subtype tCalibPulseCnt is unsigned(riscv_rsdp_sp_pkg.cLdCalibCnt - 1 downto 0);
	subtype tCalibCycleCnt is unsigned(riscv_rsdp_sp_pkg.cLdCalibCnt + riscv_rsdp_sp_pkg.cDividerBits + 2 - 1 downto 0);

	constant cCalibPulseMax: tCalibPulseCnt := (others => '1');

	function fCalibCycleInit return tCalibCycleCnt is
		variable vRet: tCalibCycleCnt;

	begin
		vRet := (others => '0');
		-- To calculate the divider, we divide the calibration cycle counter by
		-- 2 ** (1 + riscv_rsdp_sp_pkg.cLdCalibCnt). By starting at an offset, we
		-- essentially make this division round-to-nearest instead of
		-- round-to-minus-inifinity.
		vRet(riscv_rsdp_sp_pkg.cLdCalibCnt) := '1';
		return vRet;
	end function;

	type tState is record
		mode:            tMode;

		sp_prev:         std_logic;
		sp_out:          std_logic;

		rx_cnt:          unsigned(2 downto 0);
		tx_cnt:          unsigned(1 downto 0);
		divider_cnt:     tDividerCnt;
		calib_pulse_cnt: tCalibPulseCnt;

		valid:           std_logic;
		rx_data:         std_logic;
		tx_data:         std_logic;
		tx_oe:           std_logic;
	end record;

	constant cStateInitial: tState := (
		mode             => cModeCalibrationFailed,
		sp_prev          => '0',
		sp_out           => '0',
		rx_cnt           => (others => '0'),
		tx_cnt           => (others => '0'),
		divider_cnt      => (others => '0'),
		calib_pulse_cnt  => (others => '0'),
		valid            => '0',
		rx_data          => '0',
		tx_data          => '0',
		tx_oe            => '0'
	);

	signal rState: tState := cStateInitial;
	signal wState: tState;

	signal wCalibCycleEn:   std_logic;
	signal wCalibCycleLoad: std_logic;
	signal rCalibCycleCnt:  tCalibCycleCnt;

begin
	pCalibCycleCnt: process(iRst, iClk)
	begin
		if iRst = '1' then
			rCalibCycleCnt <= (others => '0');
		elsif rising_edge(iClk) then
			if wCalibCycleLoad = '1' then
				rCalibCycleCnt <= fCalibCycleInit;
			elsif wCalibCycleEn = '1' then
				rCalibCycleCnt <= rCalibCycleCnt + 1;
			end if;
		end if;
	end process;

	pCombinatorial: process(rState, rCalibCycleCnt, iSpIn, iDataEn, iDataTx)
		type tEvent is (
			cEventNone,
			cEventIdle,
			cEventBreak,
			cEventBit
		);

		variable vEvent: tEvent;
		variable vBit: std_logic;

		variable vDivider: tDivider;
		variable vDividerDone: boolean;

	begin
		wState <= rState;

		wState.valid   <= '0';
		wState.rx_data <= '0';

		vEvent := cEventNone;
		vBit   := '0';

		vDivider := rCalibCycleCnt(riscv_rsdp_sp_pkg.cLdCalibCnt + riscv_rsdp_sp_pkg.cDividerBits + 1 - 1 downto riscv_rsdp_sp_pkg.cLdCalibCnt + 1);
		case rState.mode is
			when cModeCalibrationFailed | cModeInactive | cModeCalibrate =>
				vDividerDone := rState.divider_cnt(rState.divider_cnt'high) = '1';

			when others =>
				vDividerDone := rState.divider_cnt = vDivider;
		end case;

		-- Decision points assuming divider == 3.
		--
		--    nom => debugger sending '0' as exactly 2 quanta and '1' as 4
		--           quanta; This is what the target must always send.
		--    opt => debugger sending '0' as 1.5 quanta and '1' as 4.5 quanta,
		--           assuming the debugger has a much faster internal clock;
		--           This "optimization" centers the nominal edges within the
		--           target's decision region.
		--                        ____ _____ _____ _____ _____ _____ _____ _______
		-- rx_cnt                 ___0|6____|5____|4____|3____|2____|1____|0______
		--                             _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
		-- divider_cnt            ----|1|2|3|1|2|3|1|2|3|1|2|3|1|2|3|1|2|3|-------
		--                        ____             _______________________________
		-- iSpIn ('0') (nom)          |___________|
		--                        ____            .            ___________________
		-- iSpIn ('1') (nom)          |_______________________|
		--                        ____          __________________________________
		-- iSpIn ('0') (opt)          |________|  .           .
		--                        ____         :  .           .   ________________
		-- iSpIn ('1') (opt)          |__________________________|
		--                                     :  .           .  :
		-- detected as '0'             ^ ^ ^ ^ ^ ^ ^ ^ ^      .  :
		-- detected as '1'                               ^ ^ ^ ^ ^ ^ ^ ^ ^
		-- detected as idle/break                                          ^ ^ ^ ^

		wState.sp_prev <= iSpIn;
		if rState.mode = cModeTx then
			-- receiver is paused, divider_cnt is used by transmitter
			wState.rx_cnt <= (others => '0');
		elsif iSpIn /= rState.sp_prev then
			wState.divider_cnt <= to_unsigned(1, rState.divider_cnt'length);
			wState.rx_cnt      <= to_unsigned(6, rState.rx_cnt'length);
		elsif rState.rx_cnt = 0 then
			wState.divider_cnt <= to_unsigned(1, rState.divider_cnt'length);
			-- stop counting, we should enter cModeIdle or cModeCalibrate
		elsif vDividerDone then
			wState.divider_cnt <= to_unsigned(1, rState.divider_cnt'length);
			wState.rx_cnt      <= rState.rx_cnt - 1;
		else
			wState.divider_cnt <= rState.divider_cnt + 1;
		end if;

		if rState.mode = cModeTx then
		elsif rState.rx_cnt = 0 and rState.sp_prev = '0' then
			vEvent := cEventIdle;
		elsif rState.rx_cnt = 0 then
			vEvent := cEventBreak;
		elsif rState.rx_cnt > 3 and iSpIn /= rState.sp_prev then
			vEvent := cEventBit;
			vBit   := '0';
		elsif iSpIn /= rState.sp_prev then
			vEvent := cEventBit;
			vBit   := '1';
		end if;

		if rState.mode /= cModeTx then
			wState.tx_cnt <= (others => '0');
			wState.sp_out <= '0';
		elsif vDividerDone then
			wState.divider_cnt <= to_unsigned(1, rState.divider_cnt'length);
			wState.tx_cnt      <= rState.tx_cnt + 1;

			if ((rState.tx_oe = '0' or rState.tx_data = '0') and rState.tx_cnt = 1) or rState.tx_cnt = 3 then
				wState.tx_cnt <= (others => '0');
				wState.sp_out <= not rState.sp_out and rState.tx_oe;
				wState.valid <= '1';
			end if;
		else
			wState.divider_cnt <= rState.divider_cnt + 1;
		end if;

		if rState.valid = '1' then
			wState.tx_data <= iDataTx;
			wState.tx_oe   <= iDataEn;
		end if;

		case rState.mode is
			when cModeCalibrationFailed =>
				-- wait for the generic transition to cModeInactive to try again

			when cModeInactive =>
				if vEvent = cEventNone then
					wState.mode <= cModeCalibrate;
				end if;

			when cModeCalibrate =>
				if rCalibCycleCnt(rCalibCycleCnt'high) = '1' then
					-- counter overflowed, give up
					wState.mode <= cModeCalibrationFailed;
				elsif vEvent = cEventIdle then
					-- individual low pulse was too long, give up
					wState.mode <= cModeCalibrationFailed;
				elsif rState.calib_pulse_cnt = cCalibPulseMax and vEvent = cEventBit then
					wState.mode <= cModeRx;
				end if;

			when cModeRx =>
				if vEvent = cEventIdle then
					wState.valid   <= '1';
					wState.mode <= cModeIdle;
				elsif vEvent = cEventBit then
					wState.valid   <= '1';
					wState.rx_data <= vBit;
				end if;

			when cModeIdle =>
				if vEvent = cEventNone then
					wState.mode <= cModeRx;
				elsif iDataEn = '1' and iDataTx = '1' then
					wState.mode <= cModeTx;
				else
					wState.valid   <= '1';
					wState.rx_data <= '0';
				end if;

			when cModeTx =>
				if vDividerDone and rState.tx_cnt = 1 and rState.tx_oe = '0' and rState.sp_out = '0' then
					wState.mode <= cModeIdle;
				end if;
		end case;

		if vEvent = cEventBreak then
			wState.mode <= cModeInactive;
		end if;

		wCalibCycleEn <= '0';
		wCalibCycleLoad <= '0';
		if rState.mode = cModeInactive then
			wState.calib_pulse_cnt <= (others => '0');
			wCalibCycleLoad <= '1';
		elsif rState.mode = cModeCalibrate then
			wCalibCycleEn <= '1';
			if vEvent = cEventBit then
				wState.calib_pulse_cnt <= rState.calib_pulse_cnt + 1;
			end if;
		end if;

		oDivider <= std_logic_vector(vDivider);
	end process;

	-- These are registered in riscv_rsdp_sp_ioregs, so use the combinatorial signals!
	oSpOut   <= wState.sp_out;
	oSpOe    <= '1' when wState.mode = cModeTx else '0';

	oActive  <= '1' when rState.mode /= cModeInactive else '0';
	oValid   <= rState.valid;
	oDataRx  <= rState.rx_data;

	pSequential: process(iRst, iClk)
	begin
		if iRst = '1' then
			rState <= cStateInitial;
		elsif rising_edge(iClk) then
			rState <= wState;
		end if;
	end process;
end architecture;
