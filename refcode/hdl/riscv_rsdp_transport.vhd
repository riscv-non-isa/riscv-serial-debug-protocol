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
use work.riscv_rsdp_pkg.all;

entity crc6_itu is
generic (
	gInit : STD_LOGIC_VECTOR(5 downto 0)
);
port (
	iClk         :  in STD_LOGIC;

	iClear       :  in STD_LOGIC;
	iValid       :  in STD_LOGIC;
	iData        :  in STD_LOGIC;
	oCrcBit      : out STD_LOGIC;
	oCrcNextBit  : out STD_LOGIC
);
end entity;

architecture rtl of crc6_itu is

-- ITU CRC-6 poly: x^6 + x^5 + 1
constant cPoly  : tCrc := "110000";
signal rCrc     : tCrc;
signal wNext    : tCrc;

begin
	pNextCrc: process(iData, iValid, rCrc)
		variable vXor     : STD_LOGIC;
		variable vShifted : STD_LOGIC_VECTOR(cPoly'high downto cPoly'low);
		variable vNext    : STD_LOGIC_VECTOR(cPoly'high downto cPoly'low);
	begin
		vXor := (iData xor rCrc(0)) and iValid;
		vShifted(cPoly'high-1 downto 0) := rCrc(cPoly'high downto 1);
		vShifted(cPoly'high)            := '0';
		for i in cPoly'range loop
			vNext(i) := vShifted(i) xor (vXor and cPoly(i));
		end loop;
		wNext <= vNext;
	end process;
	oCrcBit      <= not rCrc(0);
	oCrcNextBit  <= not rCrc(1);

	process(iClk)
	begin
		if rising_edge(iClk) then
			rCrc <= wNext;
			if iClear = '1' then
				rCrc <= gInit;
			end if;
		end if;
	end process;
end architecture;

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.riscv_rsdp_pkg.all;

entity riscv_rsdp_transport is
generic (
	-- gAddressWidth: Size of address bits required for DMI access.
	gAddressWidth : NATURAL;
	-- gCrcSupport: Support for ROBUST mode (with CRC6 checks)
	gCrcSupport : BOOLEAN;
	-- gStartInJtag: When set to true starts with oUseJtag set
	gStartInJtag: BOOLEAN
);
port (
	iRst : in STD_LOGIC;

	-- TwoWire interface
	-- Clock
	iRSDP_Clk     :  in STD_LOGIC;
	-- To from ** INPUT/OUTPUT REGISTER(s) ** (!)
	iFrIoreg_Data :  in STD_LOGIC;
	oToIoreg_Drv  : out STD_LOGIC; -- 1 => drive RSDP DATA pin
	oToIoreg_Data : out STD_LOGIC;

	-- potential multiplexer
	oUseJtag   : out STD_LOGIC;

	-- JTAG like output
	oJtag_Instr: out STD_LOGIC_VECTOR( 4 downto 0); -- Content IR register

	oJtag_CapDR: out STD_LOGIC;                                     -- Capture-DR state
	iJtag_Op   :  in STD_LOGIC_VECTOR( 1 downto 0);                 -- OP bits   (to TDO for DMI access)
	iJtag_Data :  in STD_LOGIC_VECTOR(31 downto 0);                 -- DATA bits (to TDO for DMI/DTMCS access)

	oJtag_UpdDR: out STD_LOGIC;                                     -- Update-DR state
	oJtag_Op   : out STD_LOGIC_VECTOR( 1 downto 0);                 -- OP bits   (from TDI for DMI access)
	oJtag_Addr : out STD_LOGIC_VECTOR(gAddressWidth-1 downto 0);    -- ADDR bits (from TDI for DMI access)
	oJtag_Data : out STD_LOGIC_VECTOR(31 downto 0);                 -- DATA bits (from TDI for DMI/DTMCS access)

	-- INTBUS
	oIntbusMOSI : out tIntbusMOSI;
	iIntbusData :  in tIntbusData
);
end entity;

architecture rtl of riscv_rsdp_transport is

-- IO registers; place close to DATA pin
signal rDataI : STD_LOGIC;
signal rDataO : STD_LOGIC;
signal rDataD : STD_LOGIC;

type tInput is record
	data     : STD_LOGIC; -- rDataI
	jtagOp   : STD_LOGIC_VECTOR(1 downto 0);
	jtagData : STD_LOGIC_VECTOR(31 downto 0);
	intData  : tIntbusData;

	crcBit      : STD_LOGIC;
	crcNextBit  : STD_LOGIC;

	frEsc    : tEscapeToRsdp;
end record;
signal wIn : tInput;

type tToOutReg is record
	data : STD_LOGIC;
	drv  : STD_LOGIC;
end record;
signal wToOutReg : tToOutReg;

type tToCrc is record
	clear: STD_LOGIC;
	valid: STD_LOGIC;
	data : STD_LOGIC;
end record;
signal wToCrc  : tToCrc;
constant cToCrcRst : tToCrc := (
	clear => '0',
	valid => '0',
	data  => '0'
);

-- State machine, read from LEFT to RIGHT:
-- Regular Transaction
--
-- Depending on ROBUST/FAST mode
--   recvCRC might be omitted
-- Depending on TT:
--   recvAddr / recvWrData might be omitted
--
-- rVerifyReq                                  | 1  |           | 1  |           |  1  |           | 1  |
-- vDataO                                                                                       Z  | 0  | 1 |    1 | 0 | s0 | s1  | R0 | ... | R31 | C0  | ... | C5  | 0       | Z  | 0/1
-- iData  0  | 1  | 1  | 0   | i0  | ... | i3  | A0 | ... | An  | W0 | ... | W31 | C0  | ... | C5  | 0  | 0 |    1 | 1 |  0 | s0  | s1 | R0  | ... | R31 | C0  | ... | C5      | 0  | Z | 0/1
-- rDataI      0  | 1  | 1   | 0   | i0  | ... | i3 | A0  | ... | An | W0  | ... | W31 | C0  | ... | C5 | 0 |    0 | 1 |  1 | 0   | s0 | s1  | R0  | ... | R31 | C0  | ...     | C5 | 0 | Z | 0/1
-- state               | recvStart |  recvTT        |   recvAddr     |  recvWrData     | recvCRC        | sendStart    | sendStat | sendRdData     | sendCRC         | sendEnd | gotoIdle   |
--                     [ CRC ONLY  ]                                                   [  CRC ONLY      ]   [ CRC ONLY][ sendShift                ][  CRC ONLY       ]
--                                                                                                      [ sendEna                                                              ]
--
-- Escape Sequence Response
--
-- WantResponse    0 | 1 | 0 | ...
-- vDataO          Z | 0 | 1 |    1 | 0 | s0   | s1   | R0 | ... | R31 | c0  | ... | c5  | rs0 | rs1 | rR0 | ... | rR31 | c0   | ... | c5  | 0       | Z | 0 |
-- iData           1 | 0 | 0 |    1 | 1 | 0    | s0   | s1 | R0  | ... | R31 | c0  | ... | c5  | rs0 | rs1 | rR0 | ...  | rR31 | c0  | ... | c5      | 0 | Z | 0 |
-- rDataI          1 | 1 | 0 | ...
-- state                 | sendStart    | sendEscStat | sendEscData    | sendCRC         | sendStat  | sendRdData       | sendCRC          | sendEnd | gotoIdle  |
--                           [ CRC ONLY ]                              [ CRC ONLY       ][ RETRANSMIT ONLY  (implies CRC)                  ]
--                                      [ sendEsc                      ]                 [ sendShift                    ]
--                       [ sendEna                                                                                                                   ]

type tState is record
	-- last three received bits, 0 oldest, 2 latest
	dataBits     : STD_LOGIC_VECTOR(2 downto 0);

	busy         : STD_LOGIC;
	-- one hot state machine, see comment above
	doRecvStart  : STD_LOGIC;
	doRecvTT     : STD_LOGIC;
	doRecvAddr   : STD_LOGIC;
	doRecvWrData : STD_LOGIC;
	doRecvCRC    : STD_LOGIC;
	doSendEna    : STD_LOGIC;  -- 1 if we must drive
	doSendStart  : STD_LOGIC;
	doSendEsc    : STD_LOGIC;  -- OR of doSendEscStat/doSendEscData
	doSendEscStat: STD_LOGIC;
	doSendEscData: STD_LOGIC;
	doSendShift  : STD_LOGIC;  -- OR of doSendStat/doSendRdData
	doSendStat   : STD_LOGIC;
	doSendRdData : STD_LOGIC;
	doSendCRC    : STD_LOGIC;
	doSendEnd    : STD_LOGIC;
	doGotoIdle   : STD_LOGIC;
	endDo        : STD_LOGIC;
	cntBits      : UNSIGNED(4 downto 0);
	withRtnsData : STD_LOGIC; -- at end of doSendCrc, go back to doSendStat

	verifyReq    : STD_LOGIC;
	verifyData   : STD_LOGIC; -- 1 => Need to check wIn.Data for specific value
	verifyRef    : STD_LOGIC; -- If verifyData == 1: Value against which wIn.Data is checked

	foundError   : STD_LOGIC_VECTOR(2 downto 0);
	backoff      : STD_LOGIC;

	-- Registers for oJtag_* outputs
	JtagIR      : STD_LOGIC_VECTOR(4 downto 0);
	JtagCap     : STD_LOGIC;
	JtagUpd     : STD_LOGIC;
	JtagOP      : STD_LOGIC_VECTOR(1 downto 0);
	JtagAddr    : STD_LOGIC_VECTOR(gAddressWidth-1 downto 0);
	JtagWrData  : STD_LOGIC_VECTOR(31 downto 0);

	-- Internal bus
	IntAddr       : tIntbusAddr;
	IntRdStrobe   : STD_LOGIC;
	IntWrStrobe   : STD_LOGIC;
	IntSetJtagIR  : STD_LOGIC;
	IntJtagAccess : STD_LOGIC;
	IntJtagAccessPre: STD_LOGIC;

	-- ACTIVE transaction type
	-- (transmitted TT for FAST mode, previous TT for ROBUST mode)
	activeTT     : tTTCode;
	isEscResp    : STD_LOGIC;  -- transmitting response to escape sequence
	hasRdData    : STD_LOGIC;  -- response has read data
	lastDmiWasRd : STD_LOGIC;  -- Last preceding DMI operation was a read
	curSeq       : UNSIGNED(1 downto 0); -- current sequence number

	curTT        : tTTCode;   -- received TT
	prevTT       : tTTCode;   -- received TT of previous transaction

	-- Control CRC generation
	crcClear     : STD_LOGIC;
	crcError     : STD_LOGIC;

	rdStatLatch  : STD_LOGIC;  -- strobe to latch STAT bits
	rdData       : STD_LOGIC_VECTOR(33 downto 0);

	-- Response to Escape Sequence:
	escHasRdData : STD_LOGIC;                      -- has read data
	escRdData    : STD_LOGIC_VECTOR(2 downto 0);   -- read data

	-- Retransmit data include previous read data
	rtnsHasRdData: STD_LOGIC;
end record;

constant cStateRst : tState := (
	dataBits => (others => '0'),
	busy     => '0',
	-- one hot state machine
	doRecvStart  => '0',
	doRecvTT     => '0',
	doRecvAddr   => '0',
	doRecvWrData => '0',
	doRecvCRC    => '0',
	doSendEna    => '0',
	doSendStart  => '0',
	doSendEsc    => '0',
	doSendEscStat=> '0',
	doSendEscData=> '0',
	doSendShift  => '0',
	doSendStat   => '0',
	doSendRdData => '0',
	doSendCRC    => '0',
	doSendEnd    => '0',
	doGotoIdle   => '0',
	endDo        => '0',
	cntBits      => (others => '0'),
	withRtnsData => '0',

	verifyReq    => '0',
	verifyData   => '0',
	verifyRef    => '0',

	-- after reset: start in backoff + DISABLED state
	-- cntBackoff  => "00000001",
	foundError  => (others => '0'),
	backoff     => '1',

	JtagIR     => (others => '0'),
	JtagCap    => '0',
	JtagUpd    => '0',
	JtagOP     => (others => '0'),
	JtagAddr   => (others => '0'),
	JtagWrData => (others => '0'),

	IntAddr       => (others => '0'),
	IntRdStrobe   => '0',
	IntWrStrobe   => '0',
	IntSetJtagIR  => '0',
	IntJtagAccess => '0',
	IntJtagAccessPre => '0',

	activeTT     => (others => '0'),
	isEscResp    => '0',
	hasRdData    => '0',
	lastDmiWasRd => '0',

	curTT        => (others => '0'),
	curSeq       => "00",
	prevTT       => (others => '0'),

	crcClear     => '0',
	crcError     => '0',

	rdStatLatch  => '0',
	rdData       => (others => '0'),

	escHasRdData => '0',
	escRdData    => (others => '0'),

	rtnsHasRdData => '0'
);
signal rS : tState := cStateRst;
signal wS : tState;

begin
	-- To/From IO registers
	wIn.data      <= iFrIoreg_Data;
	oToIoreg_Drv  <= wToOutReg.drv;
	oToIoreg_Data <= wToOutReg.data;

	yEscape: entity work.riscv_rsdp_escape
	generic map (
		gStartInJtag => gStartInJtag,
		gCrcSupport  => gCrcSupport
	)
	port map (
		iRst      => iRst,

		iClk      => iRSDP_Clk,
		iData     => wIn.data,

		oToRsdp   => wIn.frEsc
	);

	eCrc: if gCrcSupport generate
		yCrc: entity work.crc6_itu
		generic map (
			gInit => "111111"
		)
		port map (
			iClk       => iRSDP_Clk,

			iClear     => wToCrc.clear,
			iValid     => wToCrc.valid,
			iData      => wToCrc.data,

			oCrcBit      => wIn.crcBit,
			oCrcNextBit  => wIn.crcNextBit
		);
	end generate;
	eNoCrc: if not gCrcSupport generate
		wIn.crcBit     <= wToCrc.data;
		wIn.crcNextBit <= wToCrc.data;
	end generate;

	-- If you want to multiplex to JTAG back-end
	oUseJtag    <= wIn.frEsc.UseJtag;

	-- IOs to/from JTAG back-end
	oJtag_Instr <= rS.JtagIR;
	oJtag_CapDR <= rS.JtagCap;
	-- iJtag_Data
	-- iJtag_Op
	oJtag_UpdDR <= rS.JtagUpd;
	oJtag_Op    <= rS.JtagOP;
	oJtag_Addr  <= rS.JtagAddr;
	oJtag_Data  <= rS.JtagWrData;

	oIntbusMOSI.addr     <= rS.IntAddr;
	oIntbusMOSI.rdStrobe <= rS.IntRdStrobe;
	oIntbusMOSI.wrStrobe <= rS.IntWrStrobe;
	oIntbusMOSI.wrData   <= rS.JtagWrData;

	wIn.jtagOp   <= iJtag_Op;
	wIn.jtagData <= iJtag_Data;
	wIn.intData  <= iIntbusData;
	pComb: process(rS, wIn)
		variable vToOutReg : tToOutReg;
		variable vToCrc    : tToCrc;

		variable vDataIn : STD_LOGIC_VECTOR(3 downto 0);
		variable vActiveTTlsb : STD_LOGIC;
		variable vActiveTT : tTTCode;
		variable n : tState;
	begin
		-- Signals to output register
		vToOutReg.drv := '0';
		if
			-- JTAG_END at right position after escape sequence
			(wIn.frEsc.WantResponse = '1' and wIn.data = '1') or
			-- End of Transaction Request and right wIn.data value
			(rS.verifyReq = '1' and rS.crcError = '0' and (rS.verifyData = '0' or wIn.data=rS.verifyRef)) or
			-- Regular sending of response
			rS.doSendEna = '1'
		then
			vToOutReg.drv := '1';
		end if;
		vToOutReg.data := '0';
		vToOutReg.data := vToOutReg.data or (rS.doSendStart and (not rS.cntBits(1)));
		vToOutReg.data := vToOutReg.data or (rS.doSendShift and rS.rdData(0));
		vToOutReg.data := vToOutReg.data or (rS.doSendEsc   and rS.escRdData(0));
		if gCrcSupport then
			vToOutReg.data := vToOutReg.data or (rS.doSendCRC and wIn.crcBit);
		end if;
		wToOutReg <= vToOutReg;

		-- Signals to CRC generator/checker
		if gCrcSupport then
			vToCrc.clear := rS.crcClear;
			vToCrc.valid := not (rS.doSendCRC or rS.doRecvCRC);
			if rS.doSendEsc = '1' then
				vToCrc.data := rS.escRdData(0);
			elsif rS.doSendEna = '1' then
				vToCrc.data := rS.rdData(0);
			else
				vToCrc.data := wIn.data;
			end if;
		else
			vToCrc := cToCrcRst;
		end if;
		wToCrc <= vToCrc;

		-- main state machine
		n := rS;
		-- vDataIn: current input bit + last three input bits.
		vDataIn(3)             := wIn.data;
		vDataIn(2 downto 0)    := rS.dataBits(2 downto 0);
		n.dataBits(2 downto 0) := vDataIn(3 downto 1);

		-- error triggers; strobes so default is 0
		n.foundError := (others => '0');

		-- endDo: Mark end of multi-cycle states.
		-- Note: Single cycle states like doSendEnd and doSendStart (for non CRC mode) need special logic
		n.endDo := '0';
		if
			rS.endDo = '0' and (
				rS.doRecvStart = '1' or
				(rS.doRecvTT = '1'      and rS.cntBits =  2) or
				(rS.doRecvAddr = '1'    and (
					(rS.activeTT(0) = cTT_IS_DMI and rS.activeTT(2) = cTT_IS_SA) or    -- DMI_*_SA
					(rS.activeTT(0) = cTT_IS_DMI and rS.cntBits = gAddressWidth-2) or  -- DMI_*
					(rS.activeTT(0) /= cTT_IS_DMI and rS.cntBits = tIntbusAddr'length - 2) -- INTBUS_*
				)) or
				(rS.doRecvWrData = '1'  and rS.cntBits = 30) or
				(rS.doRecvCRC = '1'     and rS.cntBits =  4) or
				(rS.doSendStart = '1'   and rS.cntBits =  1) or -- ROBUST mode only
				rS.doSendStat = '1' or
				(rS.doSendRdData = '1'  and rS.cntBits = 30) or
				(rS.doSendCrc = '1'     and rS.cntBits =  4) or
				(rS.doGotoIdle = '1'    and rS.cntBits =  2) or -- Note: doSendEnd does NOT reset cntBits.
				rS.doSendEscStat = '1' or
				(rS.doSendEscData = '1' and rS.cntBits = 30)
			)
		then
			n.endDo := '1';
		end if;

		-- doSendStart, doSendEnd are handled by special logic
		-- because these might only be set for a single cycle.
		if rS.endDo = '1' then
			n.doRecvStart   := '0';
			n.doRecvTT      := '0';
			n.doRecvAddr    := '0';
			n.doRecvWrData  := '0';
			n.doRecvCRC     := '0';
			n.doSendStat    := '0';
			n.doSendRdData  := '0';
			n.doSendCRC     := '0';
			n.doGotoIdle    := '0';
			n.doSendEscStat := '0';
			n.doSendEscData := '0';
		end if;
		n.cntBits := rS.cntBits + 1;
		if rS.endDo = '1' or (rS.doSendStart = '1' and wIn.frEsc.RsdpWithCrc = '0') or rS.busy = '0' then
			-- Note: doSendEnd does NOT reset cntBits.
			n.cntBits := (others => '0');
		end if;

		if gCrcSupport then
			-- ROBUST mode: receive last two bits of START
			n.crcClear := '0';
			if rS.doRecvStart='1' and rS.endDo = '0' then
				n.crcClear := '1';
			end if;
			if rS.doRecvStart='1' and rS.endDo = '1' then
				n.doRecvTT := '1';
				if vDataIn(3 downto 2) /= "01" then
					-- error in received ROBUST start
					n.foundError(0) := '1';
				end if;
			end if;
		end if;

		-- ROBUST mode: Use previously transmitted  transaction type
		-- FAST   mode: Use currently  transmitted  transaction type
		if wIn.frEsc.RsdpWithCrc = '1' then
			vActiveTTlsb := rS.prevTT(0);
			vActiveTT    := rS.prevTT;
		else
			vActiveTTlsb := wIn.Data;
			vActiveTT    := vDataIn(3 downto 0);
		end if;
		-- PreDecode JtagIR by evaluation of TT[0]
		if rS.doRecvTT = '1' and rS.cntBits(1 downto 0) = 0 then
			n.JtagIR := cJtagBYPASS;
			if vActiveTTlsb = cTT_IS_DMI then
				n.JtagIR := cJtagDMI;
			end if;
		end if;

		-- Decide what to do next, based on ACTIVE transaction type, which is
		-- ROBUST mode: previously transmitted  transaction type
		-- FAST   mode: currently  transmitted  transaction type
		n.IntSetJtagIR := '0';
		if rS.doRecvTT = '1' and rS.endDo = '1' then
			n.curTT    := vDataIn(3 downto 0);
			n.activeTT := vActiveTT;
			case vActiveTT is
				when cTT_NOP | cTT_DMI_NOP =>
					if wIn.frEsc.RsdpWithCrc = '1' then
						n.doRecvCRC := '1';
					end if;
				when
					cTT_DMI_WR | cTT_DMI_RD |
					cTT_DMI_WR_SA | cTT_DMI_RD_SA
				=>
					n.doRecvAddr := '1';
				when cTT_INTBUS_WR | cTT_INTBUS_RD =>
					n.doRecvAddr := '1';
					n.IntSetJtagIR := '1';  -- decode LSB of address to set JTAG_IR
				when others =>
					-- Does not happen in ROBUST mode,
					-- because we do not accept illegal TT in robust mode at all.
					NULL;
			end case;
			-- We never accept a transaction if the transaction type is illegal.
			-- For ROBUST mode, check the received transaction type, not the previous one.
			-- The previous one is NEVER illegal (guaranteed by design here).
			case vDataIn(3 downto 0) is
				when
					cTT_NOP | cTT_DMI_NOP | cTT_DMI_WR | cTT_DMI_RD |
					cTT_DMI_WR_SA | cTT_DMI_RD_SA | cTT_INTBUS_RD | cTT_INTBUS_WR
				=>
					NULL;
				when others =>
					-- illegal transaction type
					n.foundError(1)   := '1';
			end case;
		end if;

		if rS.IntSetJtagIR = '1' then
			-- Access to INTBUS
			-- set Jtag IR based on least significant bit of address
			if wIn.data = cIntbus_IDCODE(0) then
				n.JtagIR := cJtagIDCODE;
			else
				n.JtagIR := cJtagDTMCS;
			end if;
		end if;

		if rS.doRecvAddr = '1' and rS.activeTT(0) = cTT_IS_DMI and rS.activeTT(2) /= cTT_IS_SA then
			-- Receive full dmi address
			n.JtagAddr(gAddressWidth-1) := wIn.data;
			n.JtagAddr(gAddressWidth-2 downto 0) := rS.JtagAddr(gAddressWidth-1 downto 1);
		end if;
		if rS.doRecvAddr = '1' and rS.activeTT(0) /= cTT_IS_DMI then
			-- 8 bit address for INTBUS
			n.IntAddr(tIntbusAddr'high) := wIn.data;
			n.IntAddr(tIntbusAddr'high - 1 downto 0) := rS.IntAddr(tIntbusAddr'high downto 1);
		end if;
		if rS.doRecvAddr = '1' and rS.activeTT(0) /= cTT_IS_DMI then
			n.IntJtagAccessPre := '0';
			if wIn.data = '0' and UNSIGNED(rS.IntAddr(tIntbusAddr'high downto 3)) = 0 then
				-- next cycle: rS.IntAddr(tIntbusAddr'high downto 2) = 0
				n.IntJtagAccessPre := '1';
			end if;
		end if;
		if rS.doRecvAddr = '1' and rS.endDo = '1' then
			if rS.activeTT(0) = cTT_IS_DMI and rS.activeTT(2) = cTT_IS_SA then
				-- short address (JtagAddr(gAddressWidth-1 downto 2) is unchanged)
				n.JtagAddr(1 downto 0) := vDataIn(3 downto 2);
			end if;
			if wIn.data = '0' and rS.IntJtagAccessPre = '1' then
				-- next cycle: rS.IntAddr(tIntbusAddr'high downto 1) = 0
				-- Address 0x00 or 0x01 go via DMI Bus Manager interface
				n.IntJtagAccess := '1';
			end if;
			if rS.activeTT(3)='0' then
				-- INTBUS_WR or DMI_WR or DMI_WR_SA
				n.doRecvWrData := '1';
			elsif wIn.frEsc.RsdpWithCrc = '1' then
				n.doRecvCRC := '1';
			end if;
		end if;

		-- Receive Write Data
		if rS.doRecvWrData = '1' then
			n.JtagWrData(31) := wIn.data;
			n.JtagWrData(30 downto 0) := rS.JtagWrData(31 downto 1);
		end if;
		if rS.doRecvWrData = '1' and rS.endDo = '1' then
			if wIn.frEsc.RsdpWithCrc = '1' then
				n.doRecvCRC := '1';
			end if;
		end if;

		if rS.doRecvCRC = '1' then
			if wIn.data/=wIn.crcBit  then
				n.crcError := '1';
			end if;
		else
			n.crcError := '0';
		end if;

		n.verifyReq := '0';
		n.verifyData:= '0';
		n.verifyRef := '0';
		if wIn.frEsc.RsdpWithCrc = '0' then
			-- FAST mode
			if
				-- Receiving last bit of TT
				rS.doRecvTT = '1' and rS.cntBits = 2 and (
					-- Might be cTT_DMI_NOP or cTT_NOP, need to check vDataIn(3) next
					vDataIn(3 downto 1) = cTT_DMI_NOP(2 downto 0) or
					vDataIn(3 downto 1) = cTT_NOP(2 downto 0)
				)
			then
				n.verifyReq  := '1';
				n.verifyData := '1';
				n.verifyRef  := '0'; -- wIn.data must be 0 next, otherwise that's an illegal TT.
			end if;
			if
				-- Receiving last bit of ADDR, WR-DATA is missing
				rS.doRecvAddr = '1' and rS.activeTT(3)='1' and (
					(rS.activeTT(0)  = cTT_IS_DMI and rS.activeTT(2) = cTT_IS_SA and rS.cntBits = 0) or  -- DMI_RD_SA
					(rS.activeTT(0)  = cTT_IS_DMI and rS.cntBits = gAddressWidth-2) or     -- DMI_RD
					(rS.activeTT(0) /= cTT_IS_DMI and rS.cntBits = tIntbusAddr'length - 2) -- INTBUS_RD
				)
			then
				n.verifyReq := '1';
			end if;
			if rS.doRecvWrData = '1'  and rS.cntBits = 30 then
				-- Receiving last bit of WR-DATA
				n.verifyReq := '1';
			end if;
		end if;
		if rS.doRecvCRC = '1' and rS.cntBits = 4 then
			-- ROBUST mode
			-- Receiving last bit of CRC
			n.verifyReq  := '1';
			n.verifyData := '1';
			n.verifyRef  := wIn.crcNextBit;
		end if;

		-- rS.verifyReq = '1' =>
		n.JtagCap := '0';
		n.rdStatLatch := '0';
		if rS.verifyReq = '1' then
			n.JtagOP := cDMI_OP_NOP;
			if rS.doRecvTT = '1' then
				-- only happens in FAST mode
				if vDataIn(0) = cTT_IS_DMI and rS.lastDmiWasRd='1' then
					-- TT == cTT_DMI_NOP
					-- Note check for TT == ILLEGAL is done below via
					--   rS.verifyData = '1' and wIn.data /= rS.verifyRef
					n.hasRdData := '1';
				end if;
			else
				-- We have at least ADDR or WR-DATA or CRC
				-- => rS.activeTT is valid
				case rS.activeTT is
					when cTT_DMI_WR|cTT_DMI_WR_SA =>
						n.JtagOP := cDMI_OP_WR;
					when cTT_DMI_RD|cTT_DMI_RD_SA =>
						n.JtagOP := cDMI_OP_RD;
					when others =>
						NULL;
				end case;
				if
					-- DMI access
					(rS.activeTT(0)  = cTT_IS_DMI and rS.lastDmiWasRd='1') or
					-- other Read
					(rS.activeTT(0) /= cTT_IS_DMI and rS.activeTT(3) = cTT_IS_RD)
				then
					n.hasRdData := '1';
				end if;
			end if;

			if rS.crcError = '0' and (rS.verifyData = '0' or wIn.data=rS.verifyRef) then
				n.doSendEna   := '1';
				n.doSendStart := '1';
				n.rdStatLatch := '1';
				if rS.doRecvTT = '1' then
					-- only happens in FAST mode
					if vDataIn(0) = cTT_IS_DMI then
						-- TT == cTT_DMI_NOP
						n.JtagCap := '1';
					end if;
				elsif
					-- DMI_*
					rS.activeTT(0) = cTT_IS_DMI or (
						-- INTBUS_RD and access to IDCODE/DTMCS
						rS.activeTT = cTT_INTBUS_RD and (
							-- FAST mode with ADDR, without WR-DATA and
							-- Access to IDCODE/DTMCS via DMI Bus Manager
							(rS.doRecvAddr = '1' and wIn.data='0' and rS.IntJtagAccessPre = '1') or
							-- Access to IDCODE/DTMCS via DMI Bus Manager
							rS.IntJtagAccess = '1'
						)
					)
				then
					n.JtagCap := '1';
				end if;
			else
				-- Wrong CRC or illegal TT
				n.foundError(2) := '1';
			end if;
		end if;
		if UNSIGNED(rS.foundError)/=0 then
			n.backoff := '1';
			n.busy    := '0';
		end if;

		n.IntRdStrobe := '0';
		if
			-- next cycle is last bit of doSendStat
			rS.isEscResp = '0' and rS.doSendStat = '1' and rS.endDo = '0' and
			-- RD request to INTBUS
			rS.activeTT = cTT_INTBUS_RD and rS.IntJtagAccess = '0'
		then
			n.IntRdStrobe := '1';
		end if;

		if rS.rdStatLatch='1' then
			-- Done at start of doSendStart:
			-- Latch STAT == OK/dmi.op
			n.rdData(1 downto 0) := (others => '0');
			if rS.activeTT(0) = cTT_IS_DMI then
				-- DMI access, latch iJtag_Op
				n.rdData(1 downto 0) := wIn.jtagOp;
			end if;
			-- Latch data from JTAG backend.
			-- Note: Might be unused (if rS.hasRdData = '0') or
			--       might be overwritten by wIn.intData two cycles later (see below).
			n.rdData(33 downto 2) := wIn.jtagData;
			n.rtnsHasRdData := rS.hasRdData;
		end if;
		if rS.doSendShift = '1' then
			-- Rotate data, so that rdData is unmodfied
			-- after sending data is finished.
			n.rdData(33) := rS.rdData(0);
			n.rdData(32 downto 0) := rS.rdData(33 downto 1);
			if rS.IntRdStrobe='1' then
				-- End of doSendStat and accessing INTBUS
				-- rS.rdData(33 downto 32) contain the STAT bits just shifted out
				-- Latch data from internal bus.
				n.rdData(31 downto 0) := wIn.intData;
			end if;
			if rS.hasRdData = '0' then
				-- Only shifting STAT bits =>
				-- Rotate STAT bits, so that these are unmodified,
				-- after sending STAT bits is finished.
				n.rdData(1) := rS.rdData(0);
			end if;
		end if;

		-- Send START pattern
		-- FAST   mode: 1
		-- ROBUST mode: 110
		if rS.doSendStart = '1' and rS.cntBits(0) = '1' then
			-- ROBUST mode
			n.crcClear := '1';
		end if;
		if rS.doSendStart = '1' and (wIn.frEsc.RsdpWithCrc = '0' or rS.endDo = '1') then
			n.doSendStart := '0';
			if rS.isEscResp = '1' then
				-- Escape Sequence Response
				n.doSendEsc     := '1';
				n.doSendEscStat := '1';
			else
				-- Regular Transaction
				n.doSendShift := '1';
				n.doSendStat  := '1';
			end if;
		end if;

		-- Escape Sequence Response Header: STAT
		if rS.doSendEscStat = '1' and rS.endDo = '1' then
			if rS.escHasRdData = '1' then
				n.doSendEscData := '1';
			else
				-- must be a RETRANSMIT response;
				-- all others have VERSION field
				n.doSendEsc := '0';
				n.doSendCRC := '1';
			end if;
		end if;
		-- Escape Sequence Response Header: VERSION
		if rS.doSendEscData = '1' and rS.endDo = '1' then
			n.doSendEsc := '0';
			if wIn.frEsc.RsdpWithCrc = '1' then
				n.doSendCRC := '1';
			else
				n.doSendEnd := '1';
			end if;
		end if;

		-- Regular Transaction or RETRANSMIT: STAT
		n.JtagUpd := '0';
		n.IntWrStrobe := '0';
		if rS.doSendStat = '1' and rS.endDo = '1' then
			if rS.isEscResp = '0' then
				if rS.activeTT(0) = cTT_IS_DMI then
					n.lastDmiWasRd := '0';
					if rS.activeTT(3) = cTT_IS_RD then
						-- DMI_RD or DMI_RD_SA
						n.lastDmiWasRd := '1';
					end if;
				end if;
				if
					rS.activeTT(0) = cTT_IS_DMI or
					(rS.activeTT = cTT_INTBUS_WR and rS.IntJtagAccess = '1')
				then
					-- DMI_* (all DMI accesses trigger an Update)
					-- INTBUS_WR and access to IDCODE/DTMCS
					n.JtagUpd := '1';
				end if;
				if rS.activeTT = cTT_INTBUS_WR and rS.IntJtagAccess = '0' then
					n.IntWrStrobe := '1';
				end if;
			end if;
			if rS.hasRdData='1' then
				n.doSendRdData := '1';
			elsif wIn.frEsc.RsdpWithCrc = '1' then
				n.doSendCRC := '1';
				n.doSendShift := '0';
			else
				n.doSendEnd := '1';
				n.doSendShift := '0';
			end if;
		end if;
		-- Regular Transaction or data of RETRANSMIT
		if rS.doSendRdData = '1' and rS.endDo = '1' then
			n.doSendShift := '0';
			if wIn.frEsc.RsdpWithCrc = '1' then
				n.doSendCRC := '1';
			else
				n.doSendEnd := '1';
			end if;
		end if;

		if gCrcSupport then
			-- CRC at end of Escape Sequence Response Header
			-- CRC at end of Escape Sequence Response RETRANSMIT Data
			-- CRC at end of Regular Transaction
			if rS.doSendCrc = '1' and rS.cntBits(2 downto 0) = 4 then
				n.crcClear := '1';
			end if;
			if rS.doSendCrc = '1' and rS.endDo = '1' then
				n.withRtnsData := '0';
				if rS.withRtnsData='1' then
					-- Now send RETRANSMIT data
					n.doSendShift:= '1';
					n.doSendStat := '1';
				else
					n.doSendEnd := '1';
				end if;
			end if;
		end if;

		if rS.doSendEnd = '1' then
			n.doSendEna := '0';
			n.doSendEnd := '0';
			n.doGotoIdle := '1';
			if gCrcSupport then
				if rS.isEscResp = '0' then
					n.prevTT := rS.curTT;
					n.curSeq := rS.curSeq + 1;
				end if;
			end if;
		end if;

		if rS.doGotoIdle = '1' and rS.endDo='1' then
			n.busy := '0';
		end if;

		if rS.busy = '0' then
			-- Idle, wait for start bit
			n.doRecvStart  := '0';
			n.doRecvTT     := '0';
			n.doRecvAddr   := '0';
			n.doRecvWrData := '0';
			n.doRecvCRC    := '0';
			n.doSendEna    := '0';
			n.doSendStart  := '0';
			n.doSendShift  := '0';
			n.doSendStat   := '0';
			n.doSendRdData := '0';
			n.doSendCRC    := '0';
			n.doSendEnd    := '0';
			n.doGotoIdle   := '0';
			n.doSendEsc    := '0';
			n.doSendEscStat:= '0';
			n.doSendEscData:= '0';
			n.endDo        := '0';
			n.withRtnsData := '0';
			n.hasRdData    := '0';
			n.IntJtagAccessPre := '0';
			n.IntJtagAccess:= '0';
			n.isEscResp    := '0';
			n.escHasRdData := '0';
			n.crcClear     := '1';

			if rS.backoff = '0' and wIn.frEsc.RsdpEnable = '1' and wIn.data='1' then
				n.busy := '1';
				if wIn.frEsc.RsdpWithCrc = '1' then
					n.doRecvStart := '1';
				else
					n.doRecvTT := '1';
				end if;
			end if;
		end if;

		if rS.doSendEsc = '1' then
			n.escRdData(2) := '0';
			n.escRdData(1 downto 0) := rS.escRdData(2 downto 1);
		end if;
		if wIn.frEsc.WantResponse = '1' and wIn.data='1' then
			-- Received a valid ENABLE-FAST, ENABLE-ROBUST or RETRANSMIT sequence,
			-- which all need a response
			-- n.cntBackoff  := TO_UNSIGNED(1, 8);
			n.backoff     := '0';
			n.busy        := '1';
			n.doSendEna   := '1';
			n.doSendStart := '1';

			n.isEscResp   := '1';
			if not gCrcSupport then
				-- Note: When gCrcSupport = false then
				-- ResponseType = "01" (ENABLE-FAST) always
				n.escHasRdData := '1';
				n.escRdData := "100";
			else
				-- ROBUST mode supported, check which response is needed.
				n.escRdData := "100";
				if wIn.frEsc.ResponseType(1) = '0' then
					-- ENABLE-FAST or ENABLE-ROBUST
					n.escHasRdData := '1';
					n.lastDmiWasRd := '0';
					if wIn.frEsc.ResponseType(0) = '0' then
						-- ENABLE-ROBUST, clear prevTT + sequence counter
						n.prevTT := cTT_NOP;
						n.curSeq := (others => '0');
					end if;
				else
					-- received RETRANSMIT
					n.withRtnsData := '1';
					n.escRdData(2) := '0';
					n.escRdData(1 downto 0) := STD_LOGIC_VECTOR(rS.curSeq(1 downto 0));
					if rS.rtnsHasRdData = '1' then
						n.hasRdData := '1';
					end if;
				end if;
			end if;
		end if;

		if not gCrcSupport then
			n.doRecvStart   := '0';
			n.doRecvCRC     := '0';
			n.doSendCRC     := '0';
			n.withRtnsData  := '0';
			n.crcClear      := '0';
			n.curTT         := (others => '0');
			n.curSeq        := "00";
			n.prevTT        := (others => '0');
			n.rtnsHasRdData := '0';
		end if;

		wS <= n;
	end process;

	pDFF: process(iRst, iRSDP_Clk)
	begin
		if iRst='1' then
			rS <= cStateRst;
		elsif rising_edge(iRSDP_Clk) then
			rS <= wS;
		end if;
	end process;
end architecture;
