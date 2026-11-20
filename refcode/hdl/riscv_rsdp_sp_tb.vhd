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
use ieee.math_real.all;
use work.riscv_rsdp_sp_pkg;
use work.riscv_rsdp_pkg;

entity riscv_rsdp_sp_tb is
	generic (
		gDrive:        std_logic := '1';
		gAddressWidth: positive := 7;
		gClkPer:       time := 10 ns
	);
end entity;

architecture behavioral of riscv_rsdp_sp_tb is
	signal wRst:          std_logic := '1';
	signal wClk:          std_logic := '1';
	signal wSpIn:         std_logic;
	signal wSpDir:        std_logic;
	signal wSpOut:        std_logic;

	signal wSpIoregIn:    std_logic;
	signal wSpIoregOe:    std_logic;
	signal wSpIoregOut:   std_logic;

	signal wRsdpIoregDataIn:  std_logic;
	signal wRsdpIoregDataOe:  std_logic;
	signal wRsdpIoregDataOut: std_logic;

	signal wRsdpClk:      std_logic;
	signal wRsdpDataIn:   std_logic;
	signal wRsdpDataOe:   std_logic;
	signal wRsdpDataOut:  std_logic;

	signal wDivider:      std_logic_vector(31 downto 0);

	signal wUseJtag:      std_logic;
	signal wJtag_Instr:   std_logic_vector( 4 downto 0);
	signal wJtag_CapDr:   std_logic;
	signal wJtag_CapOp:   std_logic_vector( 1 downto 0);
	signal wJtag_CapData: std_logic_vector(31 downto 0);
	signal wJtag_UpdDr:   std_logic;
	signal wJtag_UpdOp:   std_logic_vector( 1 downto 0);
	signal wJtag_UpdAddr: std_logic_vector(gAddressWidth - 1 downto 0);
	signal wJtag_UpdData: std_logic_vector(31 downto 0);

	signal wIntbusMosi:   riscv_rsdp_pkg.tIntbusMOSI;
	signal wIntbusMiso:   riscv_rsdp_pkg.tIntbusData;

	signal wSpOutDelta:   std_logic;

	signal wDone:         std_logic := '0';

	subtype tLfsr is std_logic_vector(5 downto 0);
	function fNextLfsr(cLfsr: tLfsr; cBit: std_logic) return tLfsr;
	constant cLfsrInit: tLfsr := "111111";

	function fNextLfsr(cLfsr: tLfsr; cBit: std_logic) return tLfsr is
		variable vRet: tLfsr;

	begin
		vRet(0) := cLfsr(1);
		vRet(1) := cLfsr(2);
		vRet(2) := cLfsr(3);
		vRet(3) := cLfsr(4);
		vRet(4) := cLfsr(5) xor cLfsr(0) xor cBit;
		vRet(5) :=              cLfsr(0) xor cBit;
		return vRet;
	end function;

	function fCrc(cData: std_logic_vector) return std_logic_vector is
		constant cDataNorm: std_logic_vector(cData'length - 1 downto 0) := cData;
		variable vLfsr: tLfsr;

	begin
		vLfsr := cLfsrInit;
		for i in 0 to cData'length - 1 loop
			vLfsr := fNextLfsr(vLfsr, cDataNorm(i));
		end loop;
		return not vLfsr;
	end function;

begin
	wRst <= '0' after 1 ns;
	wClk <= wClk xnor wDone after gClkPer / 2;

	sSpIoreg: entity work.riscv_rsdp_ioreg generic map (
		gDrive        => gDrive
	)
	port map (
		iRst          => wRst,
		iRSDP_Clk     => wClk,

		iRSDP_data    => wSpIn,
		oRSDP_DataDir => wSpDir,
		oRSDP_Data    => wSpOut,

		oFrIoreg_Data => wSpIoregIn,
		iToIoreg_Drv  => wSpIoregOe,
		iToIoreg_Data => wSpIoregOut
	);

	sUut: entity work.riscv_rsdp_sp port map (
		iRst          => wRst,
		iClk          => wClk,

		iSpIoregIn    => wSpIoregIn,
		oSpIoregOe    => wSpIoregOe,
		oSpIoregOut   => wSpIoregOut,

		oRsdpClk      => wRsdpClk,
		oRsdpDataOut  => wRsdpDataIn,
		iRsdpDataOe   => wRsdpDataOe,
		iRsdpDataIn   => wRsdpDataOut,

		oDivider      => wDivider
	);

	sRsdpIoreg: entity work.riscv_rsdp_ioreg generic map (
		gDrive        => '1'
	)
	port map (
		iRst          => wRst,
		iRSDP_Clk     => wRsdpClk,

		iRSDP_data    => wRsdpDataIn,
		oRSDP_DataDir => wRsdpDataOe,
		oRSDP_Data    => wRsdpDataOut,

		oFrIoreg_Data => wRsdpIoregDataIn,
		iToIoreg_Drv  => wRsdpIoregDataOe,
		iToIoreg_Data => wRsdpIoregDataOut
	);

	sTransport: entity work.riscv_rsdp_transport generic map (
		gAddressWidth => gAddressWidth,
		gCrcSupport   => true,
		gStartInJtag  => false
	) port map (
		iRst          => wRst,

		iRSDP_Clk     => wRsdpClk,
		iFrIoreg_Data => wRsdpIoregDataIn,
		oToIoreg_Drv  => wRsdpIoregDataOe,
		oToIoreg_Data => wRsdpIoregDataOut,

		oUseJtag      => wUseJtag,
		oJtag_Instr   => wJtag_Instr,
		oJtag_CapDR   => wJtag_CapDr,
		iJtag_Op      => wJtag_CapOp,
		iJtag_Data    => wJtag_CapData,
		oJtag_UpdDR   => wJtag_UpdDr,
		oJtag_Op      => wJtag_UpdOp,
		oJtag_Addr    => wJtag_UpdAddr,
		oJtag_Data    => wJtag_UpdData,

		oIntbusMOSI   => wIntbusMosi,
		iIntbusData   => wIntbusMiso
	);
	wJtag_CapOp   <= (others => '0');
	wJtag_CapData <= (others => '0');

	wIntbusMiso <= wDivider when wIntbusMosi.addr = riscv_rsdp_pkg.cIntbus_SPDIV else (others => '0');

	wSpOutDelta <= wSpOut;

	pStimuli: process
		variable vSpPer: time;

		procedure fSendBit(cBit: std_logic) is
		begin
			wSpIn <= not wSpIn;
			if cBit = '0' then
				wait for 2 * vSpPer;
			else
				wait for 4 * vSpPer;
			end if;
		end procedure;

		procedure fSendBits(cBits: std_logic_vector) is
			constant cBitsNorm: std_logic_vector(cBits'length - 1 downto 0) := cBits;

		begin
			for i in 0 to cBits'length - 1 loop
				fSendBit(cBitsNorm(i));
			end loop;
		end procedure;

		procedure fSendIdle is
		begin
			-- complete previous bit
			fSendBit('0');

			-- go to idle if necessary
			if wSpIn = '1' then
				fSendBit('0');
			end if;

			-- fSendBit (either above or in fSendTransaction) waited for 2 quanta.
			-- 8 quanta after this transition, the target detects the idle
			-- condition and drives '0' for 4 more quanta.
			-- Drive SP line for 10 quanta (including the 2 we've already been
			-- driving it) so we release it while the target is already driving it.

			wait for 8 * vSpPer;
		end procedure;

		procedure fSendTransaction(cTt: riscv_rsdp_pkg.tTTCode; cWdata: std_logic_vector) is
			constant cLength: natural := 3 + 4 + cWdata'length + 6;
			variable vData: std_logic_vector(cLength - 1 downto 0);

		begin
			vData(cLength - 6 - 1 downto 0) := cWdata & cTt & "011";
			vData(cLength - 1 downto cLength - 6) := fCrc(vData(cLength - 6 - 1 downto 3));
			fSendBits(vData);
			fSendIdle;
		end procedure;

		procedure fReceiveResponse(vOut: out std_logic_vector; vLen: out natural) is
			alias vOutNorm: std_logic_vector(vOut'length - 1 downto 0) is vOut;

		begin
			vLen := 0;
			wait on wSpOut for 10 * vSpPer;
			assert wSpOut'event report "Missing reply from target";
			if not wSpOut'event then
				return;
			end if;

			for i in 0 to vOut'length - 1 loop
				wait on wSpOut for 6 * vSpPer;
				if not wSpOut'event then
					return;
				elsif wSpOutDelta'last_event < 3 * vSpPer then
					vOut(i) := '0';
				else
					vOut(i) := '1';
				end if;
				vLen := i;
			end loop;
		end procedure;

		procedure fExpectResponse(cStat: std_logic_vector(1 downto 0); cRdata: std_logic_vector) is
			variable vResp: std_logic_vector(63 downto 0);
			variable vLen: natural;
			variable vExpLen: natural;

		begin
			fReceiveResponse(vResp, vLen);
			vExpLen := 2 + 2 + cRdata'length + 6;

			assert vLen = vExpLen or vLen = vExpLen + 1 report "Response length " & integer'image(vLen) & ", expcected " & integer'image(vExpLen) & " or one more";
			assert vResp(1 downto 0) = "01" report "start mismatch";
			assert vResp(3 downto 2) = cStat report "stat mismatch";
			assert vResp(cRdata'length + 4 - 1 downto 4) = cRdata report "rdata mismatch";
			assert vResp(cRdata'length + 10 - 1 downto cRdata'length + 4) = fCrc(vResp(cRdata'length + 4 - 1 downto 2)) report "crc mismatch";
			assert vResp(cRdata'length + 11 - 1) = '0' report "park mismatch";
		end procedure;

		procedure fDoTransaction(cTt: riscv_rsdp_pkg.tTTCode; cWdata: std_logic_vector; cStat: std_logic_vector(1 downto 0); cRdata: std_logic_vector) is
		begin
			fSendTransaction(cTt, cWdata);
			fExpectResponse(cStat, cRdata);
		end procedure;

		procedure fTest(cFactor: real) is
			variable vDivActual: natural;
			variable vDivExpect: natural;

		begin
			vSpPer := cFactor * gClkPer;

			wSpIn <= '1';
			wait for ((2 ** riscv_rsdp_sp_pkg.cDividerBits) * 6 + 100) * gClkPer;

			fSendBits(std_logic_vector(to_unsigned(0, 2 ** riscv_rsdp_sp_pkg.cLdCalibCnt)));
			fSendBits(std_logic_vector(to_unsigned(0, riscv_rsdp_sp_pkg.cActZeroCnt)));
			-- more zeros would also be ok here...
			fSendIdle;
			wait until rising_edge(wClk);

			vDivExpect := integer(round(cFactor));
			vDivActual := to_integer(unsigned(wDivider));

			assert vDivExpect = vDivActual report "Unexpected divider " & integer'image(vDivActual) & ", expected " & integer'image(vDivExpect);

			wait for 100 * vSpPer;

			-- send canned ENABLE-ROBUST sequence without park bit
			fSendBits("11" & x"4AA014928A54A44542FFFFFFFFFFFFFFFFFFFF");

			fSendIdle;
			fExpectResponse("00", x"00000001");

			fDoTransaction(riscv_rsdp_pkg.cTT_INTBUS_RD, "", "00", "");
			fDoTransaction(riscv_rsdp_pkg.cTT_NOP, riscv_rsdp_pkg.cIntbus_SPDIV, "00", wDivider);
		end procedure;

	begin
		wSpIn <= '0';
		wait until wRst = '0' and rising_edge(wClk);

		fTest(9.7);

		fTest(3.0);

		fTest(1.9);
		fTest(2.0);
		fTest(2.1);

		wDone <= '1';
		wait;
	end process;
end architecture;
