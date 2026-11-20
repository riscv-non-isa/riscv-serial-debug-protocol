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
use work.riscv_rsdp_sp_pkg;

entity riscv_rsdp_sp is
	port (
		-- free-running clock
		iRst:         in  std_logic;
		iClk:         in  std_logic;

		-- to/from SP input/output registers. Must be connected to a
		-- riscv_rsdp_ioreg instance or something similar.
		iSpIoregIn:   in  std_logic;
		oSpIoregOe:   out std_logic;
		oSpIoregOut:  out std_logic;

		-- to/from RSDP transport. There must be a riscv_rsdp_ioreg instance with
		-- gDrive => '1' between this entity and riscv_rsdp_transport.
		oRsdpClk:     out std_logic;
		oRsdpDataOut: out std_logic;
		iRsdpDataOe:  in  std_logic;
		iRsdpDataIn:  in  std_logic;

		-- for RSDP transport intbus register
		oDivider:     out std_logic_vector(31 downto 0)
	);
end entity;

architecture behavioral of riscv_rsdp_sp is
	signal wSpIn:       std_logic;
	signal wSpOe:       std_logic;
	signal wSpOut:      std_logic;

	signal wPhyDivider: std_logic_vector(riscv_rsdp_sp_pkg.cDividerBits - 1 downto 0);
	signal wPhyActive:  std_logic;
	signal wPhyValid:   std_logic;
	signal wPhyDataRx:  std_logic;
	signal wPhyDataEn:  std_logic;
	signal wPhyDataTx:  std_logic;

	signal wActDone:    std_logic;

begin
	sPhy: entity work.riscv_rsdp_sp_phy port map (
		iRst         => iRst,
		iClk         => iClk,

		iSpIn        => iSpIoregIn,
		oSpOe        => oSpIoregOe,
		oSpOut       => oSpIoregOut,

		oDivider     => wPhyDivider,
		oActive      => wPhyActive,
		oValid       => wPhyValid,
		oDataRx      => wPhyDataRx,
		iDataEn      => wPhyDataEn,
		iDataTx      => wPhyDataTx
	);

	sAct: entity work.riscv_rsdp_sp_act port map (
		iRst         => iRst,
		iClk         => iClk,

		iActive      => wPhyActive,
		iValid       => wPhyValid,
		iDataRx      => wPhyDataRx,

		oDone        => wActDone
	);

	sConv: entity work.riscv_rsdp_sp_conv port map (
		iRst         => iRst,
		iClk         => iClk,

		iActDone     => wActDone,

		iValid       => wPhyValid,
		iDataRx      => wPhyDataRx,
		oDataEn      => wPhyDataEn,
		oDataTx      => wPhyDataTx,

		oRsdpClk     => oRsdpClk,
		oRsdpDataOut => oRsdpDataOut,
		iRsdpDataOe  => iRsdpDataOe,
		iRsdpDataIn  => iRsdpDataIn
	);

	-- divider is a 32-bit register to hide choice of divider length
	oDivider(wPhyDivider'range) <= wPhyDivider;
	oDivider(31 downto wPhyDivider'length) <= (others => '0');
end architecture;
