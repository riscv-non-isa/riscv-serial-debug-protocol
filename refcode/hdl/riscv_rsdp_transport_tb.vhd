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

entity riscv_rsdp_transport_tb is
end riscv_rsdp_transport_tb;

architecture sim of riscv_rsdp_transport_tb is

-- Set cReportOK := tue if you want to get detailed output
-- about ALL transactions (even the ones without error).
constant cReportOK : boolean := false;
constant cClkCycle : time := 20 ns;
constant cDrive    : STD_LOGIC := '0';

signal iRst          : STD_LOGIC;
-- signal simTW
-- The external TwoWire signals to be stimulated by simulation.
type tTwoWire is record
	clk  : STD_LOGIC;
	data : STD_LOGIC;
end record;
constant cTwoWireRst : tTwoWire := (
	clk  => '0',
	data => '0'
);
signal simTW : tTwoWire;

signal wFrIoreg_Data : STD_LOGIC;
signal wToIoreg_Drv  : STD_LOGIC;
signal wToIoreg_Data : STD_LOGIC;

signal oRSDP_DataDir : STD_LOGIC;
signal oRSDP_Data    : STD_LOGIC;

signal oUseJtag    : STD_LOGIC;

signal oJtag_Instr : STD_LOGIC_VECTOR( 4 downto 0);

signal oJtag_CapDR : STD_LOGIC;
signal iJtag_Data  : STD_LOGIC_VECTOR(31 downto 0);
signal iJtag_Op    : STD_LOGIC_VECTOR( 1 downto 0);

signal oJtag_UpdDR : STD_LOGIC;
signal oJtag_Op    : STD_LOGIC_VECTOR( 1 downto 0);
signal oJtag_Addr  : STD_LOGIC_VECTOR( 6 downto 0);
signal oJtag_Data  : STD_LOGIC_VECTOR(31 downto 0);

signal oIntbusMOSI : tIntbusMOSI;
signal iIntbusData : tIntbusData;
signal rIntbusData : tIntbusData;



signal wTW_DutData      : STD_LOGIC; -- combine oRSDP_DataDir/oRSDP_Data
signal wTW_DataResolved : STD_LOGIC; -- combine simTW.data/wTW_DutData
signal wTW_Data         : STD_LOGIC; -- simulate pull down.
-- sample wTW_Data to evaluate responses
signal rTwData          : STD_LOGIC_VECTOR(255 downto 0);

type tShiftData is record
	l    : NATURAL;
	bits : STD_LOGIC_VECTOR(255 downto 0);
end record;
constant cShiftDataRst : tShiftData := (
	l    => 0,
	bits => (others => '0')
);

subtype tSimAddr   is STD_LOGIC_VECTOR( 7 downto 0);
subtype tSimData   is STD_LOGIC_VECTOR(31 downto 0);

-- tTwReqProp describes the expected properties of one transaction
type tTwReqProp is record
	reqLen     : NATURAL;
	twInst     : tTTCode;

	jtagIR     : tJtagInst;

	capCurCnt  : NATURAL;
	updCurCnt  : NATURAL;

	reqHasAddr : boolean;
	reqAddr    : STD_LOGIC_VECTOR(7 downto 0);

	capExec    : boolean;
	capHasData : boolean;
	capHasOp   : boolean;

	updExec    : boolean;
	updHasOp   : boolean;
	updHasAddr : boolean;
	updHasSA   : boolean;
	updHasData : boolean;
	updOP      : tDmiOp;
	updData    : tSimData;

	intWrCnt   : NATURAL;
	intRdCnt   : NATURAL;
	intWr      : boolean;
	intRd      : boolean;
end record;
constant cTwReqPropRst : tTwReqProp := (
	reqLen     => 0,
	twInst     => (others => '0'),

	jtagIR     => (others => '0'),

	capCurCnt  => 0,
	updCurCnt  => 0,

	reqHasAddr => false,
	reqAddr    => (others => '0'),

	capExec    => false,
	capHasData => false,
	capHasOp   => false,

	updExec    => false,
	updHasOp   => false,
	updHasAddr => false,
	updHasSA   => false,
	updHasData => false,
	updOP      => (others => '0'),
	updData    => (others => '0'),

	intWrCnt   => 0,
	intRdCnt   => 0,
	intWr      => false,
	intRd      => false
);

-- Count errors for summary
type tErrorCounters is array(natural range<>) of NATURAL;
constant cErr_CapMiss  : NATURAL := 0;   -- transaction did NOT produce expected oJtag_CapDR strobe
constant cErr_CapExtra : NATURAL := 1;   -- transaction produced an unexpected oJtag_CapDR strobe
constant cErr_CapIR    : NATURAL := 2;   -- transaction produced wrong oJtag_Instr at oJtag_CapDR strobe
constant cErr_UpdMiss  : NATURAL := 3;   -- transaction did NOT produce expected oJtag_UpdDR strobe
constant cErr_UpdExtra : NATURAL := 4;   -- transaction produced an unexpected oJtag_UpdDR strobe
constant cErr_UpdIR    : NATURAL := 5;   -- transaction produced wrong oJtag_Instr at oJtag_UpdDR strobe
constant cErr_UpdOP    : NATURAL := 6;   -- transaction produced wrong oJtag_Op at oJtag_UpdDR strobe
constant cErr_UpdAddr  : NATURAL := 7;   -- transaction produced wrong oJtag_Addr at oJtag_UpdDR strobe
constant cErr_UpdData  : NATURAL := 8;   -- transaction produced wrong oJtag_Data at oJtag_UpdDR strobe
constant cErr_TrnReq   : NATURAL := 9;   -- TRN after request was not TriStated
constant cErr_RspRstart: NATURAL := 10;  -- ROBUST mode: Wrong response START field
constant cErr_RspFstart: NATURAL := 11;  -- FAST mode: Wrong response START field
constant cErr_RspLen   : NATURAL := 12;  -- should not happen: Means Testbench calculates inconsistent response lengths
constant cErr_RspOp    : NATURAL := 13;  -- Response has wrong dmi.op
constant cErr_RspStat  : NATURAL := 14;  -- Response has STAT /= OK (for non DMI access)
constant cErr_RspData  : NATURAL := 15;  -- Response has wrong data
constant cErr_TrnRsp   : NATURAL := 16;  -- Response doesn't end with 0Z
constant cErr_RspCRC   : NATURAL := 17;  -- ROBUST mode: CRC of response is wrong
constant cErr_EscSTART : NATURAL := 18;  -- START field of Escape Response is wrong
constant cErr_EscSTAT  : NATURAL := 19;  -- STAT field of Escape Response is wrong
constant cErr_EscVERS  : NATURAL := 20;  -- VERSION field of Escape Response is wrong
constant cErr_EscCRC   : NATURAL := 21;  -- CRC field of Escape Response is wrong
constant cErr_RtnsSeq  : NATURAL := 22;  -- SEQ field of RETRANSMIT Response is wrong
constant cErr_RtnsCRC1 : NATURAL := 23;  -- CRC over SEQ field of RETRANSMIT Response is wrong
constant cErr_RtnsOp   : NATURAL := 24;  -- Retransmitted OP   field is inconsistent
constant cErr_RtnsData : NATURAL := 25;  -- Retransmitted DATA field is inconsistent
constant cErr_RtnsCRC2 : NATURAL := 26;  -- Retransmitted CRC of retransmitted response is wrong
constant cErr_EscTRN   : NATURAL := 27;  -- End of Escape Response is not 0Z
constant cErr_RspErrTri: NATURAL := 28;  -- After injected bit error, did NOT get ZZZZ as response START
constant cErr_WrMiss   : NATURAL := 29;  -- transaction did NOT produce an expected intbus.wrStrobe
constant cErr_RdMiss   : NATURAL := 30;  -- transaction did NOT produce an expected intbus.rdStrobe
constant cErr_IntAddr  : NATURAL := 31;  -- Wrong intbus.addr
constant cErr_IntWrData: NATURAL := 32;  -- Wrong intbus.wrData
constant cErr_WrExtra  : NATURAL := 33;  -- transaction did produce an EXTRA intbus.wrStrobe
constant cErr_RdExtra  : NATURAL := 34;  -- transaction did produce an EXTRA intbus.rdStrobe

constant cErr_LastCode : NATURAL := 34;

subtype tErrorFlags is BIT_VECTOR(0 to cErr_LastCode);
type tErrorNames is array(0 to cErr_LastCode) of STRING(1 to 12);
constant cErrorNames : tErrorNames := (
	"Cap Missing ",
	"Cap Extra   ",
	"Cap IR      ",
	"Upd Missing ",
	"Upd Extra   ",
	"Upd IR      ",
	"Upd OP      ",
	"Upd Addr    ",
	"Upd Data    ",
	"TRN (req)   ",
	"Rsp R Start ",
	"Rsp F Start ",
	"Rsp Len     ",
	"Rsp Op      ",
	"Rsp Stat    ",
	"Rsp Data    ",
	"TRN (rsp)   ",
	"Rsp CRC     ",
	"Escape Start",
	"Escape STAT ",
	"Escape VERS ",
	"Escape CRC  ",
	"RTNS SEQ    ",
	"RTNS CRC SEQ",
	"RTNS OP     ",
	"RTNS DATA   ",
	"RTNS CRCRTNS",
	"Escape TRN  ",
	"BitErr TRI  ",
	"Wr Missing  ",
	"Rd Missing  ",
	"Int Addr    ",
	"Int WrData  ",
	"Wr Extra    ",
	"Rd Extra    "
);

-- state to track what has happened
type tTwState is record
	errCnt      : tErrorCounters(0 to cErr_LastCode);
	withGap     : boolean;
	withCRC     : boolean;
	lastDmiWasRd : boolean;
	rtnsHasRdData: boolean;
	activeInst  : tTTCode;
	prevInst    : tTTCode;
	prevDmiAddr : STD_LOGIC_VECTOR(6 downto 0);
	seq         : UNSIGNED(1 downto 0);
	lastRsp     : tShiftData;

	rqp         : tTwReqProp;
	bitError    : NATURAL;
end record;
constant cTwStateRst : tTwState := (
	errCnt      => (others => 0),
	withGap     => true,
	withCRC     => false,
	lastDmiWasRd => false,
	rtnsHasRdData=> false,
	activeInst  => cTT_NOP,
	prevInst    => cTT_NOP,
	prevDmiAddr => (others => '0'),
	seq         => "00",
	lastRsp     => cShiftDataRst,

	rqp         => cTwReqPropRst,
	bitError    => 0
);

-- type to hold data for a simulated request (bits driven to iRSDP_Data)
type tReqData is record
	rspLen: NATURAL;
	l     : NATURAL;
	bits  : STD_LOGIC_VECTOR(255 downto 0);
end record;
constant cReqDataRst : tReqData := (
	rspLen => 0,
	l    => 0,
	bits => (others => '0')
);

-- Observed JTAG signals to JTAG backend
type tJtagData is record
	capCnt  : NATURAL;
	capIR   : STD_LOGIC_VECTOR(4 downto 0);
	capOp   : STD_LOGIC_VECTOR( 1 downto 0);
	capData : tSimData;

	updCnt  : NATURAL;
	updIR   : STD_LOGIC_VECTOR(4 downto 0);
	updOp   : STD_LOGIC_VECTOR( 1 downto 0);
	updAddr : STD_LOGIC_VECTOR( 7 downto 0);
	updData : tSimData;

	intWrCnt : NATURAL;
	intRdCnt : NATURAL;
end record;
constant cJtagDataRst : tJtagData := (
	capCnt  => 0,
	capIR   => (others => '0'),
	capOp   => "00",
	capData => (others => '0'),
	updCnt  => 0,
	updIR   => (others => '0'),
	updOp   => "00",
	updAddr => (others => '0'),
	updData => (others => '0'),
	intWrCnt=> 0,
	intRdCnt=> 0
);
signal rJtagData : tJtagData;

-- Constants to drive variable number of 0,1,Z bits
constant cTriBits : STD_LOGIC_VECTOR(255 downto 0) := (others => 'Z');
constant cOneBits : STD_LOGIC_VECTOR(255 downto 0) := (others => '1');
constant cZeroBits: STD_LOGIC_VECTOR(255 downto 0) := (others => '0');

-- helpers to produce multi-line report strings
type tReportString is record
	l : NATURAL;
	s : STRING(1 to 1024);
end record;
constant cReportStringRst : tReportString := (
	l => 0,
	s => (others => ' ')
);
procedure pStrAppend(
	dst : inout tReportString;
	constant src : in STRING
) is
	variable vNewL : NATURAL;
begin
	vNewL := dst.l + src'length;
	if vNewL > 1024 then
		vNewL := 1024;
	end if;
	dst.s(dst.l+1 to vNewL) := src(1 to (vNewL - dst.l));
	dst.l := vNewL;
end procedure;
procedure pStrAppend(
	dst : inout tReportString;
	constant src : in CHARACTER
) is
	variable vNewL : NATURAL;
begin
	if vNewL >= 1024 then
		return;
	end if;
	vNewL := dst.l + 1;
	dst.s(dst.l+1) := src;
	dst.l := vNewL;
end procedure;


-- Convert STD_LOGIC_VECTOR to hex string
function fToHexStr(
	ivVector : in STD_LOGIC_VECTOR
) return string is
	constant cNibbles : integer := (ivVector'LENGTH+3)/4;
	variable vRes : STRING(1 to cNibbles + 2);
	variable vVec : STD_LOGIC_VECTOR(cNibbles*4-1 downto 0);
	variable vNibble : STD_LOGIC_VECTOR(3 downto 0);
begin
	vVec:=(others => '0');
	vVec(ivVector'LENGTH-1 downto 0):=ivVector;
	vRes(1 to 2):="0x";
	for i in 1 to cNibbles loop
		vNibble:=vVec((cNibbles-i)*4+3 downto (cNibbles-i)*4+0);
		case vNibble is
			when "0000" => vRes(i+2) := '0';
			when "0001" => vRes(i+2) := '1';
			when "0010" => vRes(i+2) := '2';
			when "0011" => vRes(i+2) := '3';
			when "0100" => vRes(i+2) := '4';
			when "0101" => vRes(i+2) := '5';
			when "0110" => vRes(i+2) := '6';
			when "0111" => vRes(i+2) := '7';
			when "1000" => vRes(i+2) := '8';
			when "1001" => vRes(i+2) := '9';
			when "1010" => vRes(i+2) := 'A';
			when "1011" => vRes(i+2) := 'B';
			when "1100" => vRes(i+2) := 'C';
			when "1101" => vRes(i+2) := 'D';
			when "1110" => vRes(i+2) := 'E';
			when "1111" => vRes(i+2) := 'F';
			when others => vRes(i+2) := 'X';
		end case;
	end loop;
	return vRes;
end fToHexStr;

-- helper to convert STD_LOGIC_VECTOR to string bit by bit
function fToBitStr(
	iData: in STD_LOGIC_VECTOR
) return string is
	constant cVec : STD_LOGIC_VECTOR(iData'length - 1 downto 0) := iData;
	variable vRes : STRING(1 to iData'length + 2);
begin
	vRes(1 to 2) := "0b";
	for i in 1 to iData'length loop
		case cVec(iData'length - i) is
			when 'Z'    => vRes(i+2) := 'Z';
			when '0'    => vRes(i+2) := '0';
			when '1'    => vRes(i+2) := '1';
			when others => vRes(i+2) := '-';
		end case;
	end loop;
	return vRes;
end function;

-- helper to output single bit
function fToBitStr(
	iData: in STD_LOGIC
) return string is
	variable vRes : STRING(1 to 3);
begin
	vRes(1 to 2) := "0b";
	case iData is
		when 'Z'    => vRes(3) := 'Z';
		when '0'    => vRes(3) := '0';
		when '1'    => vRes(3) := '1';
		when others => vRes(3) := '-';
	end case;
	return vRes;
end function;

-- Calculate CRC6-ITU
constant cCrcInit  : tCrc := "111111";
	-- Might be used to check output XOR:
constant cCrcChk   : tCrc := "010000";
function fCrcUpd(
	iCrc:  in tCrc;
	iData: in STD_LOGIC_VECTOR
) return STD_LOGIC_VECTOR is
	variable vCRC : tCrc;
	variable vXOR : STD_LOGIC;
begin
	vCRC := iCrc;
	for i in iData'low to iData'high loop
		vXOR := iData(i) xor vCRC(0);
		vCRC := "0" & vCRC(5 downto 1);
		if vXOR='1' then
			vCRC := vCRC xor "110000";
		end if;
	end loop;
	return vCRC;
end function;
function fCrcFinal(
	iCrc:  in tCrc
) return STD_LOGIC_VECTOR is
	variable vCRC : tCrc;
begin
	-- might be used to implement output XOR
	vCRC := not iCrc;
	return vCRC;
end function;


-- Put bits onto "signal simTW"
procedure pSendBits(
	constant iData : in STD_LOGIC_VECTOR;
	signal oTW : out tTwoWire
) is
	constant cData : STD_LOGIC_VECTOR(iData'high downto iData'low) := iData;
begin
	-- drive data co-incident to falling edge of clock.
	for i in cData'low to cData'high loop
		oTW.clk  <= '0';
		oTW.data <= cData(i);
		wait for cClkCycle/2;
		oTW.clk  <= '1';
		wait for cClkCycle/2;
	end loop;
	oTW.clk <= '0';
end procedure;

-- Put bits onto "signal simTW" and inject a single bit error
procedure pSendBitsWithError(
	constant iData      : in STD_LOGIC_VECTOR;
	constant iBitError  : in NATURAL;
	signal oTW          : out tTwoWire
) is
	constant cData : STD_LOGIC_VECTOR(iData'high downto iData'low) := iData;
begin
	-- drive data co-incident to falling edge of clock.
	for i in cData'low to cData'high loop
		oTW.clk  <= '0';
		if i = iBitError then
			oTW.data <= not cData(i);
		else
			oTW.data <= cData(i);
		end if;
		wait for cClkCycle/2;
		oTW.clk  <= '1';
		wait for cClkCycle/2;
	end loop;
	oTW.clk <= '0';
end procedure;

-- Analyse TT/ADDR/DATA and generate expected properties of this transaction
-- Note: This specifies IN DETAIL how a particular transaction should behave
procedure pGenReqProp(
	constant cInst    : in tTTCode;
	constant cAddr    : in tSimAddr;
	constant cData    : in tSimData;
	ioTwState : inout tTwState
) is
	variable reqLen: NATURAL;
begin
	if ioTwState.withCRC then
		ioTwState.activeInst := ioTwState.prevInst;
	else
		ioTwState.activeInst := cInst;
	end if;

	ioTwState.rqp := cTwReqPropRst;
	ioTwState.rqp.reqAddr(6 downto 0) := ioTwState.prevDmiAddr;
	ioTwState.rqp.twInst    := cInst;
	ioTwState.rqp.capCurCnt := rJtagData.capCnt;
	ioTwState.rqp.updCurCnt := rJtagData.updCnt;
	ioTwState.rqp.intWrCnt  := rJtagData.intWrCnt;
	ioTwState.rqp.intRdCnt  := rJtagData.intRdCnt;
	case ioTwState.activeInst is
		when cTT_NOP =>
			NULL;

		when cTT_DMI_WR =>
			ioTwState.rqp.jtagIR     := cJtagDMI;
			ioTwState.rqp.reqHasAddr := true;
			ioTwState.rqp.reqAddr    := cAddr;
			ioTwState.rqp.reqAddr(7) := '0';

			ioTwState.rqp.capExec    := true;
			ioTwState.rqp.capHasOp   := true;
			ioTwState.rqp.capHasData := ioTwState.lastDmiWasRd;

			ioTwState.rqp.updExec    := true;
			ioTwState.rqp.updHasOp   := true;
			ioTwState.rqp.updHasAddr := true;
			ioTwState.rqp.updHasData := true;
			ioTwState.rqp.updOP      := cDMI_OP_WR;
			ioTwState.rqp.updData    := cData;

		when cTT_DMI_RD =>
			ioTwState.rqp.jtagIR     := cJtagDMI;
			ioTwState.rqp.reqHasAddr := true;
			ioTwState.rqp.reqAddr    := cAddr;
			ioTwState.rqp.reqAddr(7) := '0';

			ioTwState.rqp.capExec    := true;
			ioTwState.rqp.capHasOp   := true;
			ioTwState.rqp.capHasData := ioTwState.lastDmiWasRd;

			ioTwState.rqp.updExec    := true;
			ioTwState.rqp.updHasOp   := true;
			ioTwState.rqp.updHasAddr := true;
			ioTwState.rqp.updOP      := cDMI_OP_RD;

		when cTT_DMI_WR_SA =>
			ioTwState.rqp.jtagIR     := cJtagDMI;
			ioTwState.rqp.reqHasAddr := true;
			ioTwState.rqp.reqAddr(1 downto 0) := cAddr(1 downto 0);

			ioTwState.rqp.capExec    := true;
			ioTwState.rqp.capHasOp   := true;
			ioTwState.rqp.capHasData := ioTwState.lastDmiWasRd;

			ioTwState.rqp.updExec    := true;
			ioTwState.rqp.updHasOp   := true;
			ioTwState.rqp.updHasAddr := true;
			ioTwState.rqp.updHasSA   := true;
			ioTwState.rqp.updHasData := true;
			ioTwState.rqp.updOP      := cDMI_OP_WR;
			ioTwState.rqp.updData    := cData;

		when cTT_DMI_RD_SA =>
			ioTwState.rqp.jtagIR     := cJtagDMI;
			ioTwState.rqp.reqHasAddr := true;
			ioTwState.rqp.reqAddr(1 downto 0) := cAddr(1 downto 0);

			ioTwState.rqp.capExec    := true;
			ioTwState.rqp.capHasOp   := true;
			ioTwState.rqp.capHasData := ioTwState.lastDmiWasRd;

			ioTwState.rqp.updExec    := true;
			ioTwState.rqp.updHasOp   := true;
			ioTwState.rqp.updHasAddr := true;
			ioTwState.rqp.updHasSA   := true;
			ioTwState.rqp.updOP      := cDMI_OP_RD;

		when cTT_DMI_NOP =>
			ioTwState.rqp.jtagIR     := cJtagDMI;
			ioTwState.rqp.capExec    := true;
			ioTwState.rqp.capHasOp   := true;
			ioTwState.rqp.capHasData := ioTwState.lastDmiWasRd;

			ioTwState.rqp.updExec    := true;
			ioTwState.rqp.updHasOp   := true;
			ioTwState.rqp.updOP      := cDMI_OP_NOP;

		when cTT_INTBUS_WR =>
			ioTwState.rqp.reqHasAddr := true;
			ioTwState.rqp.reqAddr    := cAddr;

			ioTwState.rqp.updHasData := true;
			ioTwState.rqp.updData    := cData;
			if UNSIGNED(cAddr(7 downto 1)) = 0 then
				ioTwState.rqp.updExec := true;
				if cAddr(0) = cIntbus_IDCODE(0) then
					ioTwState.rqp.jtagIR := cJtagIDCODE;
				else
					ioTwState.rqp.jtagIR := cJtagDTMCS;
				end if;
			else
				ioTwState.rqp.intWr      := true;
				ioTwState.rqp.jtagIR     := cJtagBYPASS;
			end if;

		when cTT_INTBUS_RD =>
			ioTwState.rqp.reqHasAddr := true;
			ioTwState.rqp.reqAddr    := cAddr;

			ioTwState.rqp.capHasData := true;
			if UNSIGNED(cAddr(7 downto 1)) = 0 then
				ioTwState.rqp.capExec := true;
				if cAddr(0) = cIntbus_IDCODE(0) then
					ioTwState.rqp.jtagIR := cJtagIDCODE;
				else
					ioTwState.rqp.jtagIR := cJtagDTMCS;
				end if;
			else
				ioTwState.rqp.intRd      := true;
				ioTwState.rqp.jtagIR     := cJtagBYPASS;
			end if;

		when others =>
			null;
	end case;

end procedure;


-- Convert tTwState.rqp into tReqData
function fGenReq(
	constant cTwState : in tTwState
) return tReqData is
	constant withAddr      : boolean  := cTwState.rqp.reqHasAddr;
	constant withShortAddr : boolean  := cTwState.rqp.updHasSA;
	constant withWrData    : boolean  := cTwState.rqp.updHasData;
	variable ret           : tReqData := cReqDataRst;
	variable vCrcReq       : tCrc;
	variable l : NATURAL := 0;
begin
	-- START
	if cTwState.withCRC then
		ret.bits(2 downto 0) := "011";
		l := 3;
	else
		ret.bits(0) := '1';
		l := 1;
	end if;
	-- TT
	ret.bits(l+3 downto l) := cTwState.rqp.twInst;
	l := l + 4;
	-- ADDR
	if withAddr then
		if withShortAddr then
			ret.bits(l+1 downto l) := cTwState.rqp.reqAddr(1 downto 0);
			l := l + 2;
		elsif cTwState.activeInst = cTT_INTBUS_WR or cTwState.activeInst = cTT_INTBUS_RD then
			ret.bits(l+tIntbusAddr'high downto l) := cTwState.rqp.reqAddr(tIntbusAddr'high downto 0);
			l := l + tIntbusAddr'length;
		else
			ret.bits(l+6 downto l) := cTwState.rqp.reqAddr(6 downto 0);
			l := l + 7;
		end if;
	end if;
	-- WR-DATA
	if withWrData then
		ret.bits(l+31 downto l) := cTwState.rqp.updData;
		l := l + 32;
	end if;
	-- CRC
	if cTwState.withCRC then
		vCrcReq := cCrcInit;
		vCrcReq := fCrcUpd(vCrcReq, ret.bits(l-1 downto 3));
		ret.bits(l+5 downto l) := fCrcFinal(vCrcReq);
		l := l + 6;
	end if;
	ret.bits(l) := '0';
	l := l + 1;
	ret.l := l;

	-- calculate response length
	l := 5; --  / 0 / STAT[1..0] / START[0] / 0 /
	if cTwState.withCRC then
		l := l + 2; -- / START[2..1] /
		l := l + 6; -- / CRC /
	end if;
	case cTwState.activeInst is
		when cTT_INTBUS_RD =>
			l := l + 32;
		when
			cTT_DMI_NOP | cTT_DMI_WR | cTT_DMI_RD |
			cTT_DMI_WR_SA | cTT_DMI_RD_SA
		=>
			if cTwState.lastDmiWasRd then
				l := l + 32;
			end if;
		when others =>
			null;
	end case;
	ret.rspLen := l;
	return ret;
end function;

-- Extract response from rTwData into returned tShiftData
function fGetRsp(
	signal    iTwData : in STD_LOGIC_VECTOR;
	constant  cReq    : in tReqData
) return tShiftData is
	variable ret : tShiftData;
begin
	-- +2 : Sample leading and trailing 'Z'
	ret.l := cReq.rspLen + 2;
	ret.bits(ret.l - 1  downto 0) := iTwData(iTwData'high downto iTwData'high + 1 - ret.l);
	return ret;
end function;

-- Helper convert TT field into string
function fGetTTName(
	constant cTwInst: in tTTCode
) return string is
	variable vRet : STRING(1 to 9);
begin
	case cTwInst is
		when cTT_NOP =>
			return "NOP";
		when cTT_INTBUS_WR =>
			return "IBUS_WR";
		when cTT_INTBUS_RD =>
			return "IBUS_RD";
		when cTT_DMI_WR =>
			return "DMI_WR";
		when cTT_DMI_RD =>
			return "DMI_RD";
		when cTT_DMI_WR_SA =>
			return "DMI_WR_SA";
		when cTT_DMI_RD_SA =>
			return "DMI_RD_SA";
		when cTT_DMI_NOP =>
			return "DMI_NOP";
		when others =>
			return "!UNKNOWN!";
	end case;
end function;


-- Check transaction has the expected properties.
-- Produce report.
-- Return error flags what was wrong.
function fCheckTransaction(
	constant cTwState : in tTwState;
	constant cJtagData: in tJtagData;
	constant cRsp     : in tShiftData;
	constant cBitError: in NATURAL
) return tErrorFlags is
	variable ret      : tErrorFlags := (others => '0');
	variable vRspLen  : natural;
	variable vRspStart: STD_LOGIC_VECTOR( 3 downto 0);
	variable vRspOp   : STD_LOGIC_VECTOR( 1 downto 0);
	variable vRspData : STD_LOGIC_VECTOR(31 downto 0);
	variable vRspCrc  : tCrc;
	variable vRpt : tReportString := cReportStringRst;
begin
	pStrAppend(vRpt, LF & LF & "-----------------------------------------------------------------------------");
	if cTwState.withCrc then
		pStrAppend(vRpt, LF & "transmit TT = " & fGetTTName(cTwState.rqp.twInst));
	end if;
	pStrAppend(vRpt, LF & "active   TT = " & fGetTTName(cTwState.activeInst));
	if cBitError > 0 then
		pStrAppend(vRpt, LF & "injected bit error at bit " & integer'image(cBitError-1));
	end if;
	pStrAppend(vRpt, LF & "INFO : Request Length = " & integer'image(cTwState.rqp.reqLen));
	if cTwState.rqp.capExec and cBitError = 0 then
		if cTwState.rqp.capCurCnt + 1 /= cJtagData.capCnt then
			ret(cErr_CapMiss) := '1';
			pStrAppend(vRpt, LF & "ERROR: missing CaptureDR strobe");
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : CaptureDR strobe");
		end if;
		if cTwState.rqp.capCurCnt + 1 = cJtagData.capCnt then
			if cTwState.rqp.jtagIR /= cJtagData.capIR then
			ret(cErr_CapIR) := '1';
				pStrAppend(vRpt,
					LF & "ERROR: JTAG IR (at CaptureDR)" &
					LF & "    is     : " & fToHexStr(cJtagData.capIR) &
					LF & "    should : " & fToHexStr(cTwState.rqp.jtagIR)
				);
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : JTAG IR (at CaptureDR) = " & fToHexStr(cJtagData.capIR));
			end if;
		end if;
	else
		if cTwState.rqp.capCurCnt /= cJtagData.capCnt then
			ret(cErr_CapExtra) := '1';
			pStrAppend(vRpt, LF &
				"ERROR: extra CaptureDR strobe"
			);
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		elsif cReportOK then
			pStrAppend(vRpt, LF &
				"OK   : no CaptureDR strobe"
			);
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		end if;
	end if;
	if cTwState.rqp.updExec and cBitError = 0 then
		if cTwState.rqp.updCurCnt + 1 /= cJtagData.updCnt then
			ret(cErr_UpdMiss) := '1';
			pStrAppend(vRpt, LF & "ERROR: missing UpdateDR strobe");
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : UpdateDR strobe");
		end if;
		if cTwState.rqp.updCurCnt + 1 = cJtagData.updCnt then
			if cTwState.rqp.jtagIR /= cJtagData.updIR then
				ret(cErr_UpdIR) := '1';
				pStrAppend(vRpt,
					LF & "ERROR: JTAG IR (at UpdateDR)" &
					LF & "    is     : " & fToHexStr(cJtagData.updIR) &
					LF & "    should : " & fToHexStr(cTwState.rqp.jtagIR)
				);
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : JTAG IR (at UpdateDR) = " & fToHexStr(cJtagData.updIR));
			end if;

			if cTwState.rqp.updHasOp then
				if cTwState.rqp.updOP /= cJtagData.updOP then
					ret(cErr_UpdOP) := '1';
					pStrAppend(vRpt,
						LF & "ERROR: OP (at UpdateDR)" &
						LF & "    is     :" & fToBitStr(cJtagData.updOP) &
						LF & "    should :" & fToBitStr(cTwState.rqp.updOP)
					);
				elsif cReportOK then
					pStrAppend(vRpt, LF & "OK   : OP      (at UpdateDR) = " & fToBitStr(cJtagData.updOP));
				end if;
			end if;

			if cTwState.rqp.updHasAddr then
				if cTwState.rqp.reqAddr /= cJtagData.updAddr then
					ret(cErr_UpdAddr) := '1';
					pStrAppend(vRpt,
						LF & "ERROR: addr (at UpdateDR)" &
						LF & "    is     :" & fToHexStr(cJtagData.updAddr) &
						LF & "    should :" & fToHexStr(cTwState.rqp.reqAddr)
					);
				elsif cReportOK then
					pStrAppend(vRpt, LF & "OK   : addr    (at UpdateDR) = " & fToHexStr(cJtagData.updAddr));
				end if;
			end if;

			if cTwState.rqp.updHasData then
				if cTwState.rqp.updData /= cJtagData.updData then
					ret(cErr_UpdData) := '1';
					pStrAppend(vRpt,
						LF & "ERROR: data (at UpdateDR)" &
						LF & "    is     :" & fToHexStr(cJtagData.updData) &
						LF & "    should :" & fToHexStr(cTwState.rqp.updData)
					);
				elsif cReportOK then
					pStrAppend(vRpt, LF & "OK   : data    (at UpdateDR) = " & fToHexStr(cJtagData.updData));
				end if;
			end if;

		end if;
	else
		if cTwState.rqp.updCurCnt /= cJtagData.updCnt then
			ret(cErr_UpdExtra) := '1';
			pStrAppend(vRpt, LF & "ERROR: extra UpdateDR strobe");
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : no UpdateDR strobe");
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		end if;
	end if;
	if cTwState.rqp.intRd and cBitError = 0 then
		if cTwState.rqp.intRdCnt + 1 /= cJtagData.intRdCnt then
			ret(cErr_RdMiss) := '1';
			pStrAppend(vRpt, LF & "ERROR: missing Intbus.rdStrobe");
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : Intbus.rdStrobe");
		end if;
		if cTwState.rqp.intRdCnt + 1 = cJtagData.intRdCnt then
			if cTwState.rqp.reqAddr /= cJtagData.updAddr then
				ret(cErr_IntAddr) := '1';
				pStrAppend(vRpt,
					LF & "ERROR: Intbus.Addr (at rdStrobe)" &
					LF & "    is     : " & fToHexStr(cJtagData.updAddr) &
					LF & "    should : " & fToHexStr(cTwState.rqp.reqAddr)
				);
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : Intbus.Addr (at rdStrobe) = " & fToHexStr(cJtagData.updAddr));
			end if;
		end if;
	else
		if cTwState.rqp.intRdCnt /= cJtagData.intRdCnt then
			ret(cErr_RdExtra) := '1';
			pStrAppend(vRpt, LF & "ERROR: extra Intbus.rdStrobe");
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : no Intbus.rdStrobe");
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		end if;
	end if;
	if cTwState.rqp.intWr and cBitError = 0 then
		if cTwState.rqp.intWrCnt + 1 /= cJtagData.intWrCnt then
			ret(cErr_WrMiss) := '1';
			pStrAppend(vRpt, LF & "ERROR: missing Intbus.wrStrobe");
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : Intbus.wrStrobe");
		end if;
		if cTwState.rqp.intWrCnt + 1 = cJtagData.intWrCnt then
			if cTwState.rqp.reqAddr /= cJtagData.updAddr then
				ret(cErr_IntAddr) := '1';
				pStrAppend(vRpt,
					LF & "ERROR: Intbus.Addr (at wrStrobe)" &
					LF & "    is     : " & fToHexStr(cJtagData.updAddr) &
					LF & "    should : " & fToHexStr(cTwState.rqp.reqAddr)
				);
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : Intbus.Addr (at wrStrobe) = " & fToHexStr(cJtagData.updAddr));
			end if;
			if cTwState.rqp.updData /= cJtagData.updData then
				ret(cErr_IntWrData) := '1';
				pStrAppend(vRpt,
					LF & "ERROR: data (at wrStrobe)" &
					LF & "    is     :" & fToHexStr(cJtagData.updData) &
					LF & "    should :" & fToHexStr(cTwState.rqp.updData)
				);
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : data        (at wrStrobe) = " & fToHexStr(cJtagData.updData));
			end if;
		end if;
	else
		if cTwState.rqp.intWrCnt /= cJtagData.intWrCnt then
			ret(cErr_RdExtra) := '1';
			pStrAppend(vRpt, LF & "ERROR: extra Intbus.wrStrobe");
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : no Intbus.wrStrobe");
			if cBitError > 0 then
				pStrAppend(vRpt, " (injectedt bit error)");
			end if;
		end if;
	end if;

	vRspLen   := 0;
	if cTwState.withCRC then
		vRspLen := 1 + 4 + 2 + 6 + 2; --  / Z 0 / CRC[5..0] / ... / STAT[1..0] / START[3..0] / Z /
		if  cBitError > 0 then
			-- had a bit error, target should not answer...
			if cRsp.bits(4 downto 0) /= "ZZZZZ" then
				ret(cErr_RspErrTri) := '1';
				pStrAppend(vRpt, LF & "ERROR: robust = " & fToBitStr(cRsp.bits(4 downto 0)) & " (injected bit error)");
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : robust = ZZZZZ (injected bit error)");
			end if;
		elsif cRsp.bits(4 downto 0) /= "0110Z" then
			ret(cErr_RspRstart) := '1';
			pStrAppend(vRpt, LF & "ERROR: robust START = " & fToBitStr(cRsp.bits(4 downto 0)));
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : robust START");
		end if;
		vRspOp   := cRsp.bits( 6 downto 5);
		vRspData := cRsp.bits(38 downto 7);
	else
		vRspLen := 1 + 2 + 2 + 2; -- / Z 0 / ... / STAT[1..0] / START[1..0] / Z /
		if cRsp.bits(2 downto 0) /= "10Z" then
			ret(cErr_RspFstart) := '1';
			pStrAppend(vRpt, LF & "ERROR: fast START = " & fToBitStr(cRsp.bits(2 downto 0)));
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : fast START");
		end if;
		vRspOp   := cRsp.bits( 4 downto 3);
		vRspData := cRsp.bits(36 downto 5);
	end if;

	if cBitError = 0 then
		if cTwState.rqp.capHasData then
			vRspLen := vRspLen + 32;
		end if;

		if cRsp.l /= vRspLen then
			ret(cErr_RspLen) := '1';
			pStrAppend(vRpt, LF & "ERROR: Reponse Length" &
				LF & "    is    : " & integer'image(cRsp.l - 2) &
				LF & "    should: " & integer'image(vRspLen - 2)
			);
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : Reponse Length = " & integer'image(cRsp.l - 2));
		end if;
		if cRsp.l = vRspLen then
			if cTwState.rqp.capHasOp then
				if vRspOp /= cJtagData.capOp then
					ret(cErr_RspOp) := '1';
					pStrAppend(vRpt, LF & "ERROR: Op DMI (at CaptureDR)" &
						LF & "    is    : " & fToBitStr(vRspOp) &
						LF & "    should: " & fToBitStr(cJtagData.capOp)
					);
				elsif cReportOK then
					pStrAppend(vRpt, LF & "OK   : Op DMI (at CaptureDR) = " & fToBitStr(vRspOp));
				end if;
			else
				if vRspOp /= "00" then
					ret(cErr_RspStat) := '1';
					pStrAppend(vRpt, LF & "ERROR: STAT" &
						LF & "    is    : " & fToBitStr(vRspOp) &
						LF & "    should: 0b00"
					);
				elsif cReportOK then
					pStrAppend(vRpt, LF & "OK   : STAT");
				end if;
			end if;
			if cTwState.rqp.capHasData then
				if vRspData /= cJtagData.capData then
					ret(cErr_RspData) := '1';
					pStrAppend(vRpt, LF & "ERROR: data   (at CaptureDR)" &
						LF & "    is    : " & fToHexStr(vRspData) &
						LF & "    should: " & fToHexStr(cJtagData.capData)
					);
				elsif cReportOK then
					pStrAppend(vRpt, LF & "OK   : data   (at CaptureDR) = " & fToHexStr(vRspData));
				end if;
			end if;
		end if;

		vRspCrc := cCrcInit;
		if cTwState.withCRC then
			-- cRsp.bits(4..0)                     = / START[3..0] / Z /
			-- cRsp.bits(cRsp.l-1 downto cRsp.l-2) = / Z 0 /
			vRspCrc := fCrcUpd(vRspCrc, cRsp.bits(cRsp.l-3 downto 5));
			if vRspCrc /= cCrcChk then
				ret(cErr_RspCRC) := '1';
				pStrAppend(vRpt,
					LF & "ERROR: CRC = " & fToBitStr(vRspCrc) &
					LF & "   rsp.len  = " & integer'image(cRsp.l - 2)  &
					LF & "   rsp.bits = " & fToHexStr(cRsp.bits(cRsp.l-2 downto 1))
				);
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : CRC");
			end if;
		end if;

		if cRsp.bits(cRsp.l-1 downto cRsp.l-2) /= "Z0" then
			ret(cErr_TrnRsp) := '1';
			pStrAppend(vRpt, LF & "ERROR: TRN (rsp) = " & fToBitStr(cRsp.bits(cRsp.l-1 downto cRsp.l-2)));
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : TRN (rsp)");
		end if;
	end if; -- if cBitError = 0 then

	pStrAppend(vRpt, LF);
	if ret /= tErrorFlags'(others => '0') then
		report vRpt.s(1 to vRpt.l) severity warning;
	elsif cReportOK then
		report vRpt.s(1 to vRpt.l);
	end if;
	return ret;
end function;

-- Produce one transaction and compare expected properties to observed properties
procedure pDoTransaction(
	constant cInst : in tTTCode;
	constant cAddr : in tSimAddr;
	constant cData : in tSimData;
	ioTwState      : inout tTwState;
	signal oTW     : out tTwoWire
) is
	variable vReq    : tReqData;
	variable vRsp    : tShiftData;
	variable errFlags: tErrorFlags;
	variable vBitError: NATURAL;
begin
	if ioTwState.withGap then
		pSendBits(X"00", oTW);
	end if;


	-- Analyse transaction and calculate expected properties
	pGenReqProp(cInst, cAddr, cData, ioTwState);

	-- Send Request
	vReq   := fGenReq(ioTwState);
	ioTwState.rqp.reqLen := vReq.l;
	vBitError := ioTwState.bitError;
	if vBitError > 0 then
		pSendBitsWithError(vReq.bits(vReq.l - 1 downto 0), vBitError - 1, oTW);
		ioTwState.bitError := 0;
	else
		pSendBits(vReq.bits(vReq.l - 1 downto 0), oTW);
	end if;
	-- Receive Response
	pSendBits(cTriBits(vReq.rspLen - 1 downto 0), oTW);
	pSendBits(cZeroBits(0 downto 0), oTW);
	vRsp := fGetRsp(rTwData, vReq);

	-- check observed properties against expected properties
	errFlags := fCheckTransaction(ioTwState,rJtagData,vRsp,vBitError);

	if vBitError = 0 then
		for i in errFlags'range loop
			if errFlags(i) = '1' then
				ioTwState.errCnt(i) := ioTwState.errCnt(i) + 1;
			end if;
		end loop;

		-- For simulation only:
		-- If we intentionally injected a bit error,
		-- do NOT increment ioTwState.seq, do NOT update ioTwState.lastRsp
		-- This way it's easy to check if the retransmitted response is correct.
		ioTwState.seq := ioTwState.seq + 1;
		ioTwState.lastRsp := vRsp;
		if errFlags = tErrorFlags'(others => '0') then
			if ioTwState.activeInst(0) = cTT_IS_DMI then
				ioTwState.lastDmiWasRd := false;
				if ioTwState.activeInst = cTT_DMI_RD or ioTwState.activeInst = cTT_DMI_RD_SA then
					ioTwState.lastDmiWasRd := true;
				end if;
			end if;
			if
				ioTwState.activeInst = cTT_DMI_RD or ioTwState.activeInst = cTT_DMI_RD_SA or
				ioTwState.activeInst = cTT_DMI_WR or ioTwState.activeInst = cTT_DMI_WR_SA
			then
				ioTwState.prevDmiAddr := ioTwState.rqp.reqAddr(6 downto 0);
			end if;
			ioTwState.prevInst := cInst;
			ioTwState.rtnsHasRdData := ioTwState.rqp.capHasData;
		end if;
	elsif errFlags(cErr_RspErrTri) = '1' then
		-- If we injected a bit error, only useful check is that target produced no answer
		ioTwState.errCnt(cErr_RspErrTri) := ioTwState.errCnt(cErr_RspErrTri) + 1;
	end if;

end procedure;

-- Helper to leave out Addr/Data if not needed
procedure pDoTransaction(
	constant cInst  : in tTTCode;
	constant cValue : in STD_LOGIC_VECTOR;
	ioTwState      : inout tTwState;
	signal oTW     : out tTwoWire
) is
	variable vAddr : tSimAddr := (others => '0');
	variable vData : tSimData := (others => '0');
begin
	if cValue'length = 32 then
		vData := cValue;
	elsif cValue'length = 8 then
		vAddr := cValue;
	end if;
	pDoTransaction(cInst, vAddr, vData, ioTwState, oTW);
end procedure;

-- Helper to only provide TT field and nothing else
procedure pDoTransaction(
	constant cInst : in tTTCode;
	ioTwState      : inout tTwState;
	signal oTW     : out tTwoWire
) is
begin
	pDoTransaction(cInst, tSimAddr'(others => '0'), tSimData'(others => '0'), ioTwState, oTW);
end procedure;


-- Generate an Escape Sequence
function fGenEscapeSequence(
	iData: in STD_LOGIC_VECTOR;
	constant cTwState: tTwState
) return tReqData is
	constant cData : STD_LOGIC_VECTOR(iData'length-1 downto 0) := iData;
	variable ret   : tReqData := cReqDataRst;
	variable l     : natural;
	variable crc   : tCrc;
begin
	ret.bits(2 downto 0) := "010";
	l := 3;

	-- Send fixed code "/RANDOM/" to mark escape sequence.
	-- Init value: After sending 32-bit "/RANDOM/"
	-- "crc" should have the cCrcInit value
	crc := "111000";
	for idx in 0 to 31 loop
		if crc(0) = '0' then
			ret.bits(l) := '0';
			l:=l+1;
		else
			ret.bits(l+1 downto l) := "01";
			l:=l+2;
		end if;
		crc := fCrcUpd(crc, "0");
	end loop;

	-- Check that "crc" now has the cCrcInit value
	assert crc = cCrcInit report "message" severity error;
	for idx in cData'low to cData'high loop
		if cData(idx) = '0' then
			ret.bits(l) := '0';
			l:=l+1;
		else
			ret.bits(l+1 downto l) := "01";
			l:=l+2;
		end if;
	end loop;
	crc := fCrcUpd(crc, cData);
	crc := fCrcFinal(crc);
	for idx in 0 to 5 loop
		if crc(idx) = '0' then
			ret.bits(l) := '0';
			l:=l+1;
		else
			ret.bits(l+1 downto l) := "01";
			l:=l+2;
		end if;
	end loop;

	ret.bits(l+2 downto l) := "011";
	l:=l+3;
	ret.l := l;
	case cData(7 downto 0) is
		when cRSDP_ESC_ST_DISABLE =>
			ret.rspLen := 0;
		when cRSDP_ESC_ST_ROBUST =>
			ret.rspLen := 4 + 2 + 32 + 6 + 1;
		when cRSDP_ESC_ST_FAST =>
			ret.rspLen := 2 + 2 + 32 + 1;
		when cRSDP_ESC_ST_JTAG =>
			ret.rspLen := 0;
		when cRSDP_ESC_ST_RTNS =>
			ret.rspLen := 4 + 2 + 6 + 2 + 6 + 1;
			if cTwState.rtnsHasRdData then
				ret.rspLen := ret.rspLen + 32;
			end if;
		when others =>
			ret.rspLen := 80;
	end case;
	return ret;
end function;

-- Send an Escape Sequence and check response.
procedure pSendEscapeSequence(
	iData: in STD_LOGIC_VECTOR;
	ioTwState  : inout tTwState;
	signal oTW : out tTwoWire
) is
	constant cEscapeSequence : tReqData := fGenEscapeSequence(iData, ioTwState);
	variable vRsp : tShiftData;
	variable vRspCrc : tCrc;
	variable vRspSeq : STD_LOGIC_VECTOR( 1 downto 0);
	variable vRspData: STD_LOGIC_VECTOR(33 downto 0); -- / R-DATA / STAT /
	variable vRpt : tReportString := cReportStringRst;
	variable errCnt : tErrorCounters(0 to cErr_LastCode);
	variable vErrFlags : tErrorFlags := (others => '0');
begin
	pSendBits(cOneBits, oTW);
	pSendBits(cEscapeSequence.bits(cEscapeSequence.l - 1 downto 0), oTW);
	if cEscapeSequence.rspLen > 0 then
		pSendBits(cTriBits(cEscapeSequence.rspLen - 1 downto 0), oTW);
		pSendBits(cZeroBits(0 downto 0), oTW);
		vRsp := fGetRsp(rTwData, cEscapeSequence);
	end if;
	pStrAppend(vRpt, LF &
		LF & "-----------------------------------------------------------------------------" &
		LF & "Escape Sequence = "
	);

	pSendBits(X"00", oTW);
	vRspCrc := (others => '0');
	errCnt := ioTwState.errCnt;
	case iData(7 downto 0) is
		when cRSDP_ESC_ST_DISABLE =>
			pStrAppend(vRpt, "DISABLE");
		when cRSDP_ESC_ST_ROBUST =>
			pStrAppend(vRpt, "ENABLE-ROBUST");
			ioTwState := cTwStateRst;
			ioTwState.errCnt := errCnt;
			ioTwState.withCRC := true;
			if vRsp.bits( 4 downto 0) /= "0110Z" then
				vErrFlags(cErr_EscSTART) := '1';
				pStrAppend(vRpt, LF & "ERROR: START = " & fToBitStr(vRsp.bits( 4 downto 0)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : START");
			end if;
			if vRsp.bits( 6 downto 5) /= "00" then
				vErrFlags(cErr_EscSTAT) := '1';
				pStrAppend(vRpt, LF & "ERROR: STAT = " & fToBitStr(vRsp.bits( 6 downto 5)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : STAT");
			end if;
			if vRsp.bits(38 downto 7) /= X"00000001" then
				vErrFlags(cErr_EscVERS) := '1';
				pStrAppend(vRpt, LF & "ERROR: VERSION = " & fToHexStr(vRsp.bits(38 downto 7)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : VERSION");
			end if;
			vRspCrc := cCrcInit;
			vRspCrc := fCrcUpd(vRspCrc, vRsp.bits(6 + 38 downto 5));
			if vRspCrc /= cCrcChk then
				vErrFlags(cErr_EscCRC) := '1';
				pStrAppend(vRpt, LF & "ERROR: CRC = " & fToBitStr(vRspCrc));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : CRC");
			end if;
			if vRsp.bits(46 downto 45) /= "Z0" then
				vErrFlags(cErr_EscTRN) := '1';
				pStrAppend(vRpt, LF & "ERROR: TRN = " & fToBitStr(vRsp.bits(46 downto 45)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : TRN");
			end if;
		when cRSDP_ESC_ST_FAST =>
			pStrAppend(vRpt, "ENABLE-FAST");
			ioTwState := cTwStateRst;
			ioTwState.errCnt := errCnt;
			ioTwState.withCRC := false;
			if vRsp.bits( 2 downto 0) /= "10Z" then
				vErrFlags(cErr_EscSTART) := '1';
				pStrAppend(vRpt, LF & "ERROR: START = " & fToBitStr(vRsp.bits( 2 downto 0)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : START");
			end if;
			if vRsp.bits( 4 downto 3) /= "00" then
				vErrFlags(cErr_EscSTAT) := '1';
				pStrAppend(vRpt, LF & "ERROR: STAT = " & fToBitStr(vRsp.bits( 4 downto 3)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : STAT");
			end if;
			if vRsp.bits(36 downto 5) /= X"00000001" then
				vErrFlags(cErr_EscVERS) := '1';
				pStrAppend(vRpt, LF & "ERROR: VERSION = " & fToHexStr(vRsp.bits(36 downto 5)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : VERSION");
			end if;
			if vRsp.bits(38 downto 37) /= "Z0" then
				vErrFlags(cErr_EscTRN) := '1';
				pStrAppend(vRpt, LF & "ERROR: TRN = " & fToBitStr(vRsp.bits(38 downto 37)));
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : TRN");
			end if;

		when cRSDP_ESC_ST_JTAG =>
			pStrAppend(vRpt, "ENABLE-JTAG");
		when others =>
			-- RETRANSMIT check done below
			null;
	end case;
	if iData(7 downto 0) = cRSDP_ESC_ST_RTNS then
		-- RETRANSMIT, more to check here
		pStrAppend(vRpt, "RETRANSMIT");
		pStrAppend(vRpt, LF & "INFO : rsp.len = " & integer'image(vRsp.l));
		vRspSeq := STD_LOGIC_VECTOR(ioTwState.seq);
		if vRsp.bits(6 downto 5) /= vRspSeq then
			vErrFlags(cErr_RtnsSeq) := '1';
			pStrAppend(vRpt,
				LF & "ERROR: SEQ" &
				LF & "    is     :" & fToHexStr(vRsp.bits(6 downto 5)) &
				LF & "    should :" & fToHexStr(vRspSeq)
			);
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : SEQ = " & fToHexStr(vRsp.bits(6 downto 5)));
		end if;
		vRspCrc := cCrcInit;
		vRspCrc := fCrcUpd(vRspCrc, vRsp.bits(6 + 6 downto 5));
		if vRspCrc /= cCrcChk then
			vErrFlags(cErr_RtnsCRC1) := '1';
			pStrAppend(vRpt, LF & "ERROR: CRC (seq) = " & fToBitStr(vRspCrc));
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : CRC (seq)");
		end if;
		vRspData := ioTwState.lastRsp.bits(38 downto 5); -- op + data
		if vRspData(1 downto 0) /= vRsp.bits(14 downto 13) then
			vErrFlags(cErr_RtnsOp) := '1';
			pStrAppend(vRpt, LF & "ERROR: op   (rtns)" &
				LF & "    is     :" & fToBitStr(vRsp.bits(14 downto 13)) &
				LF & "    should :" & fToBitStr(vRspData(1 downto 0))
			);
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : op   (rtns) = " & fToBitStr(vRsp.bits(14 downto 13)));
		end if;
		if vRsp.l > 50 then
			if vRspData(33 downto 2) /= vRsp.bits(46 downto 15) then
				vErrFlags(cErr_RtnsData) := '1';
				pStrAppend(vRpt,
					LF & "ERROR: data (rtns)" &
					LF & "    is     :" & fToHexStr(vRsp.bits(46 downto 15)) &
					LF & "    should :" & fToHexStr(vRspData(33 downto 2))
				);
			elsif cReportOK then
				pStrAppend(vRpt, LF & "OK   : data (rtns) = " & fToHexStr(vRsp.bits(46 downto 15)));
			end if;
		end if;
		vRspCrc := cCrcInit;
		vRspCrc := fCrcUpd(vRspCrc, vRsp.bits(vRsp.l-3 downto 13));
		if vRspCrc /= cCrcChk then
			vErrFlags(cErr_RtnsCRC2) := '1';
			pStrAppend(vRpt, LF & "ERROR: CRC  (rtns) = " & fToBitStr(vRspCrc));
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : CRC  (rtns)");
		end if;
		if vRsp.bits(vRsp.l-1 downto vRsp.l-2) /= "Z0" then
			vErrFlags(cErr_EscTRN) := '1';
			pStrAppend(vRpt, LF & "ERROR: TRN  (rtns) = " & fToBitStr(vRsp.bits(vRsp.l-1 downto vRsp.l-2)));
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : TRN  (rtns)");
		end if;
	end if;
	pStrAppend(vRpt, LF);
	if vErrFlags /= tErrorFlags'(others => '0') then
		for i in vErrFlags'range loop
			if vErrFlags(i) = '1' then
				ioTwState.errCnt(i) := ioTwState.errCnt(i) + 1;
			end if;
		end loop;
		report vRpt.s(1 to vRpt.l) severity warning;
	elsif cReportOK then
		report vRpt.s(1 to vRpt.l);
	end if;
end procedure;

-- pseudo number generator for fuzzy testing
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

-- run fuzzy test
procedure pFuzzyTest(
	constant cCnt:  in natural;
	ioTwState    : inout tTwState;
	signal oTW   : out tTwoWire
) is
	variable vInstRnd : tLfsrReg;
	variable vAddrRnd : tLfsrReg;
	variable vDataRnd : tLfsrReg;
	variable vIsDmi : boolean;

	variable vInst : tTTCode;
	variable vAddr : tSimAddr;
	variable vData : tSimData;

begin
	vInstRnd := X"99887766";
	vAddrRnd := X"88776655";
	vDataRnd := X"77665544";

	for l in 1 to cCnt loop
		if l = cCnt/2 then
			ioTwState.withGap := false;
		end if;
		vInstRnd := fLfsrNext(vInstRnd);
		vAddrRnd := fLfsrNext(vAddrRnd);
		vDataRnd := fLfsrNext(vDataRnd);
		case vInstRnd(11 downto 8) is
			when X"0"|X"1" =>
				vInst := cTT_INTBUS_WR;
			when X"2" =>
				vInst := cTT_INTBUS_RD;
			when X"3"|X"4" =>
				vInst := cTT_DMI_WR;
			when X"5"|X"6" =>
				vInst := cTT_DMI_RD;
			when X"7"|X"8" =>
				vInst := cTT_DMI_WR_SA;
			when X"9"|X"A" =>
				vInst := cTT_DMI_RD_SA;
			when X"B"|X"C" =>
				vInst := cTT_DMI_NOP;
			when others =>
				vInst := cTT_NOP;
		end case;
		vAddr := vAddrRnd(7 downto 0);
		if vInst = cTT_INTBUS_RD then
			if vInstRnd(7 downto 6) = "11" then
				if vInstRnd(5) = cIntbus_IDCODE(0) then
					vAddr := cIntbus_IDCODE;
				else
					vAddr := cIntbus_DTMCS;
				end if;
			end if;
		elsif vInst = cTT_INTBUS_WR then
			if vInstRnd(7 downto 6) = "11" then
				vAddr := cIntbus_DTMCS;
			end if;
		else
			vAddr(7) := '0';
		end if;
		vData :=vDataRnd;
		pDoTransaction(vInst, vAddr, vData, ioTwState, oTW);
	end loop;
	vInstRnd := fLfsrNext(vInstRnd);
	vAddrRnd := fLfsrNext(vAddrRnd);
	vDataRnd := fLfsrNext(vDataRnd);
	ioTwState.withGap := true;
	pDoTransaction(cTT_NOP, vAddr, vData, ioTwState, oTW);
	pDoTransaction(cTT_NOP, vAddr, vData, ioTwState, oTW);
end procedure;

-- Report summary at end of test
procedure pReportErrorCnt(
	constant cTwState : in tTwState
) is
	variable totalErrors : NATURAL;
	variable vRpt : tReportString := cReportStringRst;
begin
	totalErrors := 0;
	for i in cTwState.errCnt'range loop
		totalErrors := totalErrors + cTwState.errCnt(i);
	end loop;
	if totalErrors = 0 then
		report LF & LF &
			LF & "------------------------------------------------------" &
			LF & "------------------------------------------------------" &
			LF & "OK: no errors detected" &
			LF & "------------------------------------------------------" &
			LF & "------------------------------------------------------" &
			LF & LF;
		return;
	end if;
	pStrAppend(vRpt, LF & LF &
		LF & "------------------------------------------------------" &
		LF & "------------------------------------------------------" &
		LF & "ERROR: found " & integer'image(totalErrors) & " errors. Details"
	);
	for i in cTwState.errCnt'range loop
		if cTwState.errCnt(i) /= 0 then
			pStrAppend(vRpt, LF &
				"    " & cErrorNames(i) & ": " &
				integer'image(cTwState.errCnt(i))
			);
		end if;
	end loop;
	pStrAppend(vRpt,
		LF & "------------------------------------------------------" &
		LF & "------------------------------------------------------"
	);
	report vRpt.s(1 to vRpt.l) severity error;
end procedure;

begin
	-- IO registers
	yIoreg: entity work.riscv_rsdp_ioreg
	generic map (
		gDrive        => cDrive
	)
	port map (
		iRst          => iRst,
		iRSDP_Clk     => simTW.clk,

		iRSDP_data    => wTW_Data,
		oRSDP_DataDir => oRSDP_DataDir,
		oRSDP_Data    => oRSDP_Data,

		oFrIoreg_Data => wFrIoreg_Data,
		iToIoreg_Drv  => wToIoreg_Drv,
		iToIoreg_Data => wToIoreg_Data
	);

	-- Combine oRSDP_Data/oRSDP_DataDir, use clock to output time of cClkCycle/4
	wTW_DutData <= oRSDP_Data after cClkCycle/4 when oRSDP_DataDir=cDrive else 'Z' after cClkCycle/4;
	-- Combine simulated drive to DATA line
	wTW_DataResolved <= wTW_DutData;
	wTW_DataResolved <= simTW.data;
	-- Simulate pull down
	wTW_Data <=
		'0' when wTW_DataResolved='0' or wTW_DataResolved='Z' else
		'1' when wTW_DataResolved='1' else
		'X';

	-- Sample wTW_DutData to check responses
	pTwSample: process(iRst, simTW.clk)
	begin
		if iRst='1' then
			rTwData <= (others => '0');
		elsif rising_edge(simTW.clk) then
			-- Here we take the data produced by work.riscv_rsdp_transport
			-- WITHOUT considering what the simulation sends.
			rTwData(rTwData'high) <= wTW_DutData;
			rTwData(rTwData'high-1 downto 0) <= rTwData(rTwData'high downto 1);
		end if;
	end process;

	yDut: entity work.riscv_rsdp_transport
	generic map (
		gAddressWidth => 7,
		gCrcSupport   => true,
		gStartInJtag  => false
	)
	port map (
		iRst        => iRst,

		iRSDP_Clk     => simTW.clk,
		iFrIoreg_Data => wFrIoreg_Data,
		oToIoreg_Drv  => wToIoreg_Drv,
		oToIoreg_Data => wToIoreg_Data,

		oUseJtag    => oUseJtag,

		oJtag_Instr => oJtag_Instr,

		oJtag_CapDR => oJtag_CapDR,
		iJtag_Op    => iJtag_Op,
		iJtag_Data  => iJtag_Data,

		oJtag_UpdDR => oJtag_UpdDR,
		oJtag_Op    => oJtag_Op,
		oJtag_Addr  => oJtag_Addr,
		oJtag_Data  => oJtag_Data,

		oIntbusMOSI => oIntbusMOSI,
		iIntbusData => iIntbusData
	);
	-- Demonstrate problem with non-inverted CRC6
	-- for INTBUS_RD from address 0xFF
	iIntbusData <=
		X"00000027" when oIntbusMOSI.addr=X"FF" else
		rIntbusData;

	-- simulate backend. Produce random data on iJtag_Data/iJtag_Op
	yDmiSim: entity work.riscv_jtag_backend_sim
	generic map (
		gAddressWidth => 7
	)
	port map (
		iRst        => iRst,

		iRSDP_Clk   => simTW.clk,

		iJtag_Instr => oJtag_Instr,
		iJtag_CapDR => oJtag_CapDR,
		oJtag_Data  => iJtag_Data,
		oJtag_Op    => iJtag_Op,

		iJtag_UpdDR => oJtag_UpdDR,
		iJtag_Op    => oJtag_Op,
		iJtag_Data  => oJtag_Data,
		iJtag_Addr  => oJtag_Addr
	);

	-- Sample signals to/from yDmiSim to observe behavior of DUT
	pJtagSample: process(iRst, simTW.clk)
	begin
		if iRst='1' then
			rJtagData   <= cJtagDataRst;
			rIntbusData <= X"DEADDEAD";
		elsif rising_edge(simTW.clk) then
			if oJtag_CapDR='1' then
				rJtagData.capCnt  <= rJtagData.capCnt + 1;
				rJtagData.capIR   <= oJtag_Instr;
				rJtagData.capOp   <= iJtag_Op;
				rJtagData.capData <= iJtag_Data;
			end if;
			if oIntbusMOSI.rdStrobe = '1' then
				rJtagData.intRdCnt <= rJtagData.intRdCnt + 1;
				rJtagData.updAddr  <= oIntbusMOSI.addr;
				rJtagData.capData  <= iIntbusData;
				rIntbusData        <= fLfsrNext(rIntbusData);
			end if;
			if oJtag_UpdDR='1' then
				rJtagData.updCnt  <= rJtagData.updCnt + 1;
				rJtagData.updIR   <= oJtag_Instr;
				rJtagData.updOp   <= oJtag_Op;
				rJtagData.updAddr(7) <= '0';
				rJtagData.updAddr(6 downto 0) <= oJtag_Addr;
				rJtagData.updData <= oJtag_Data;
			end if;
			if oIntbusMOSI.wrStrobe = '1' then
				rJtagData.intWrCnt <= rJtagData.intWrCnt + 1;
				rJtagData.updAddr  <= oIntbusMOSI.addr;
				rJtagData.updData  <= oIntbusMOSI.wrData;
			end if;
		end if;
	end process;

	pSimTwoWire: process
		variable vTwState : tTwState := cTwStateRst;
		variable vRndAddr : tLfsrReg := X"A7D6FE20";
		variable vRndData : tLfsrReg := X"8AF3E8CD";
	begin
		simTW  <= cTwoWireRst;
		iRst   <= '1';
		wait for 20 ns;
		iRst   <= '0';
		wait for 40 ns;
		pSendBits(cZeroBits(11 downto 0), simTW);

		-------------------------------------------------
		-- FAST mode
		pSendEscapeSequence(cRSDP_ESC_ST_FAST, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);
		-- Check that back-to-back transactions work
		vTwState.withGap := false;
		pDoTransaction(cTT_NOP, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);
		vTwState.withGap := true;
		pDoTransaction(cTT_NOP, vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_IDCODE, vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_IDCODE, vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_IDCODE, vTwState, simTW);
		pDoTransaction(cTT_INTBUS_WR, cIntbus_DTMCS,  tSimData'(X"99112233"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_DTMCS,  vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_DTMCS,  vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_DTMCS,  vTwState, simTW);

		pDoTransaction(cTT_INTBUS_WR, tSimAddr'(X"AA"), tSimData'(X"4440CCAA"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_WR, tSimAddr'(X"BB"), tSimData'(X"4440CCBB"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_WR, tSimAddr'(X"CC"), tSimData'(X"4440CCCC"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, tSimAddr'(X"DD"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, tSimAddr'(X"EE"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, tSimAddr'(X"FF"), vTwState, simTW);

		-- test change of oJtagIR -> oJtagCap delay
		pDoTransaction(cTT_DMI_NOP, vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"40"), tSimData'(X"11103341"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"41"), tSimData'(X"11113342"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"42"), tSimData'(X"11123343"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"43"), tSimData'(X"11133344"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"50"), tSimData'(X"11143345"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR_SA,  tSimAddr'(X"01"), tSimData'(X"11153346"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR_SA,  tSimAddr'(X"02"), tSimData'(X"11163347"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR_SA,  tSimAddr'(X"02"), tSimData'(X"11173348"), vTwState, simTW);
		pDoTransaction(cTT_DMI_NOP, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);

		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"60"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"61"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"62"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"63"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"70"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD_SA,  tSimAddr'(X"01"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD_SA,  tSimAddr'(X"02"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD_SA,  tSimAddr'(X"03"), vTwState, simTW);
		-- maximum length transaction:
		-- trigger DMI_WR with addr/wr-data, receive rd-data (from pevious DMI_RD_SA)
		pDoTransaction(cTT_DMI_WR,  tSimAddr'(X"30"), tSimData'(X"11173349"), vTwState, simTW);
		pDoTransaction(cTT_DMI_NOP, vTwState, simTW); -- get status from preceding DMI_WR request
		pDoTransaction(cTT_DMI_NOP, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);

		-- Check that INTBUS accesses do not disturb DMI_RD logic:
		pDoTransaction(cTT_DMI_RD,   tSimAddr'(X"10"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,   tSimAddr'(X"11"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD,tSimAddr'(X"A2"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD,tSimAddr'(X"A3"), vTwState, simTW);
		pDoTransaction(cTT_DMI_NOP,  vTwState, simTW); -- get status + read data from preceding DMI_RD request

		-------------------------------------------------
		-- ROBUST mode
		-- NOTE: ROBUST means PIPELINED OPERATION!
		pSendEscapeSequence(cRSDP_ESC_ST_ROBUST, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_IDCODE, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW); -- trigger IDCODE_RD, receive IDCODE
		pDoTransaction(cTT_NOP, vTwState, simTW);

		pDoTransaction(cTT_INTBUS_RD, vTwState, simTW);
		pDoTransaction(cTT_INTBUS_WR, cIntbus_IDCODE, vTwState, simTW); -- trigger IDCODE_RD, receive IDCODE
		pDoTransaction(cTT_INTBUS_WR, cIntbus_DTMCS,  tSimData'(X"99112233"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_WR, cIntbus_DTMCS,  tSimData'(X"99445566"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_WR, cIntbus_DTMCS,  tSimData'(X"9977AACC"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_DTMCS,  tSimData'(X"99CC7733"), vTwState, simTW); -- trigger DTMCS_WR with data
		pDoTransaction(cTT_INTBUS_RD, cIntbus_DTMCS,  vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_DTMCS,  vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, cIntbus_DTMCS,  vTwState, simTW);
		pDoTransaction(cTT_NOP, cIntbus_DTMCS, vTwState, simTW); -- Trigger last DTMCS_RD, receive DATA
		pDoTransaction(cTT_NOP, vTwState, simTW);

		--- True INTBUS accesses
		pDoTransaction(cTT_INTBUS_WR, vTwState, simTW);
		pDoTransaction(cTT_INTBUS_WR, tSimAddr'(X"AA"), tSimData'(X"4440CCAA"), vTwState, simTW); -- Trigger INTBUS_WR
		pDoTransaction(cTT_INTBUS_WR, tSimAddr'(X"BB"), tSimData'(X"4440CCBB"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, tSimAddr'(X"CC"), tSimData'(X"4440CCCC"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, tSimAddr'(X"DD"), vTwState, simTW);
		pDoTransaction(cTT_INTBUS_RD, tSimAddr'(X"EE"), vTwState, simTW);
		pDoTransaction(cTT_NOP, tSimAddr'(X"FF"), vTwState, simTW); -- Trigger last INTBUS_RD, receive DATA
		pDoTransaction(cTT_NOP, vTwState, simTW);

		-- DMI request even more pipelined:
		pDoTransaction(cTT_DMI_WR, vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"40"), tSimData'(X"11103341"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"41"), tSimData'(X"11113342"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"42"), tSimData'(X"11123343"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"43"), tSimData'(X"11133344"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR_SA,  tSimAddr'(X"50"), tSimData'(X"11143345"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR_SA,  tSimAddr'(X"01"), tSimData'(X"11153346"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR_SA,  tSimAddr'(X"02"), tSimData'(X"11163347"), vTwState, simTW);
		pDoTransaction(cTT_DMI_NOP,    tSimAddr'(X"03"), tSimData'(X"11173348"), vTwState, simTW); -- trigger last DMI_WR_SA with addr/data
		pDoTransaction(cTT_NOP, vTwState, simTW); -- Trigger DMI_NOP, receive STAT == DMI.op
		pDoTransaction(cTT_NOP, vTwState, simTW);

		pDoTransaction(cTT_DMI_RD, vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"60"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"61"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"62"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"63"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD_SA,  tSimAddr'(X"70"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD_SA,  tSimAddr'(X"01"), vTwState, simTW);
		pDoTransaction(cTT_DMI_RD_SA,  tSimAddr'(X"02"), vTwState, simTW);
		pDoTransaction(cTT_DMI_WR,     tSimAddr'(X"03"), vTwState, simTW); -- Trigger last DMI_RD_SA with addr
		-- maximum length transaction:
		-- Trigger DMI_WR with addr/wr-data, receive dmi.op/dmi.data from last DMI_RD_SA
		pDoTransaction(cTT_DMI_RD,     tSimAddr'(X"30"), tSimData'(X"11183349"), vTwState, simTW);
		pDoTransaction(cTT_DMI_NOP,    tSimAddr'(X"55"), vTwState, simTW); -- Trigger DMI_RD
		pDoTransaction(cTT_NOP, vTwState, simTW); -- Trigger DMI_NOP, receive STAT == DMI.op and DMI.data (from last DMI_RD)

		-- Check that INTBUS accesses do not disturb DMI_RD logic:
		pDoTransaction(cTT_DMI_RD,   vTwState, simTW);                    -- schedule first DMI_RD
		pDoTransaction(cTT_DMI_RD,   tSimAddr'(X"20"), vTwState, simTW);  -- trigger preceding DMI_RD
		pDoTransaction(cTT_INTBUS_RD,tSimAddr'(X"21"), vTwState, simTW);  -- trigger preceding DMI_RD
		pDoTransaction(cTT_INTBUS_RD,tSimAddr'(X"B2"), vTwState, simTW);  -- trigger preceding INTBUS_RD
		pDoTransaction(cTT_DMI_NOP,  tSimAddr'(X"B3"), vTwState, simTW);  -- trigger preceding INTBUS_RD
		-- trigger preceding DMI_NOP, get status + read data from preceding DMI_RD request
		pDoTransaction(cTT_NOP,      vTwState, simTW);

		------------------------------------
		-- Checks RETRANSMIT seq counter + retransmit with data
		------------------------------------
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW); -- should retransmit DMI.data from above
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- should be able to do RETRANSMIT more than once:
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW); -- should retransmit DMI.data from above
		pSendBits(cZeroBits(11 downto 0), simTW);

		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW); -- should retransmit DMI.data from above
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- Check reset of seq counter by ENABLE-ROBUST:
		-- 1) increase sequence counter to 2
		while vTwState.seq /= 2 loop
			pDoTransaction(cTT_NOP, vTwState, simTW);
		end loop;
		-- 2) check that sequence counter is 2
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW); -- incremented SEQ by one
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- 3) ENABLE-ROBUST should reset sequence counter to 0
		pSendEscapeSequence(cRSDP_ESC_ST_ROBUST, vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW); -- increment SEQ by one == 1
		-- 4) and check that sequence counter is now 1
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW); -- incremented SEQ by one
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- Check sequence counter increment
		pDoTransaction(cTT_NOP, vTwState, simTW); -- increment SEQ by one == 2
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
		pSendBits(cZeroBits(11 downto 0), simTW);

		pDoTransaction(cTT_NOP, vTwState, simTW); -- increment SEQ by one == 3
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
		pSendBits(cZeroBits(11 downto 0), simTW);

		pDoTransaction(cTT_NOP, vTwState, simTW); -- increment SEQ by one == 0 (wrap around)
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
		pSendBits(cZeroBits(11 downto 0), simTW);

		pDoTransaction(cTT_NOP, vTwState, simTW);

		-- Read data from INTBUS and check correct re-transmit data
		-- IDCODE
		pDoTransaction(cTT_INTBUS_RD, vTwState, simTW);
		pDoTransaction(cTT_NOP, cIntbus_IDCODE, vTwState, simTW);
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- DTMCS
		pDoTransaction(cTT_INTBUS_RD, vTwState, simTW);
		pDoTransaction(cTT_NOP, cIntbus_DTMCS, vTwState, simTW);
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- INTBUS ADDR 0xAA
		pDoTransaction(cTT_INTBUS_RD, vTwState, simTW);
		pDoTransaction(cTT_NOP, tSimAddr'(X"AA"), vTwState, simTW);
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- INTBUS ADDR 0xBB
		pDoTransaction(cTT_INTBUS_RD, vTwState, simTW);
		pDoTransaction(cTT_NOP, tSimAddr'(X"BB"), vTwState, simTW);
		pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
		pSendBits(cZeroBits(11 downto 0), simTW);

		-- Check that enable sequence forgets about preceding DMI operations
		pDoTransaction(cTT_DMI_RD,  vTwState, simTW);                   -- schedule first DMI_RD
		pDoTransaction(cTT_DMI_NOP, tSimAddr'(X"20"), vTwState, simTW); -- trigger preceding DMI_RD
		pSendEscapeSequence(cRSDP_ESC_ST_ROBUST, vTwState, simTW);
		-- schedule DMI_WR, SHOULD NOT receive DMI_RD data here (because of ENABLE-ROBUST sequence).
		pDoTransaction(cTT_DMI_WR,  vTwState, simTW);
		pDoTransaction(cTT_DMI_NOP, tSimAddr'(X"40"), tSimData'(X"11103341"), vTwState, simTW); -- trigger preceding DMI_WR, schedule DMI_NOP
		pDoTransaction(cTT_NOP,     vTwState, simTW); -- trigger preceding DMI_NOP, receive STAT
		pDoTransaction(cTT_NOP,     vTwState, simTW);

		----------------------------------------
		-- Check transmit bit error
		----------------------------------------
		pDoTransaction(cTT_DMI_RD, vTwState, simTW);
		vRndAddr := fLfsrNext(vRndAddr);
		pDoTransaction(cTT_DMI_NOP, tSimAddr'(vRndAddr(7 downto 0)), vTwState, simTW); -- Trigger cTT_DMI_RD
		pDoTransaction(cTT_DMI_WR, vTwState, simTW); -- Trigger cTT_DMI_NOP, receive DMI.op and DMI.data

		if cReportOK then
			report LF &
				LF & "-------------------------------------" &
				LF & "Now generating transmit bit errors" &
				LF & "-------------------------------------" & LF;
		end if;
		for cnt in 0 to 22 loop
			vRndData := fLfsrNext(vRndData);
			vRndAddr := fLfsrNext(vRndAddr);
			if cnt <= 7 then
				-- Test start bit + TT
				vTwState.bitError := cnt+1;
			else
				-- Test CRC + /0/ bit
				vTwState.bitError := cnt*3 - 16;
			end if;
			pDoTransaction(cTT_DMI_RD, tSimAddr'(vRndAddr(7 downto 0)), tSimData'(vRndData), vTwState, simTW);

			-- This retransmit checks if target did receive the request or not
			-- This will retransmit the answer to "cTT_DMI_WR" (so DMI.op and DMI.data)
			-- because last cTT_DMI_RD request had a bit error
			pSendEscapeSequence(cRSDP_ESC_ST_RTNS, vTwState, simTW);
			pSendBits(cZeroBits(11 downto 0), simTW);

			-- Resend our cTT_DMI_RD, this will  trigger the previously scheduled cTT_DMI_WR
			pDoTransaction(cTT_DMI_RD, tSimAddr'(vRndAddr(7 downto 0)), tSimData'(vRndData), vTwState, simTW);
			vRndAddr := fLfsrNext(vRndAddr);
			pDoTransaction(cTT_DMI_NOP, tSimAddr'(vRndAddr(7 downto 0)), vTwState, simTW); -- Trigger cTT_DMI_RD
			pDoTransaction(cTT_DMI_WR, vTwState, simTW); -- Trigger cTT_DMI_NOP, receive DMI.op and DMI.data
		end loop;

		vRndData := fLfsrNext(vRndData);
		vRndAddr := fLfsrNext(vRndAddr);
		pDoTransaction(cTT_DMI_NOP, tSimAddr'(vRndAddr(7 downto 0)), tSimData'(vRndData), vTwState, simTW);
		pDoTransaction(cTT_NOP, vTwState, simTW); -- Trigger cTT_DMI_NOP, receive DMI.op
		pDoTransaction(cTT_NOP, vTwState, simTW);
		if not cReportOK then
			-- fuzzy test ROBUST mode
			pFuzzyTest(1000, vTwState, simTW);

			pSendEscapeSequence(cRSDP_ESC_ST_FAST, vTwState, simTW);

			-- fuzzy test FAST mode
			pFuzzyTest(1000, vTwState, simTW);
		end if;

		pReportErrorCnt(vTwState);
		wait;
	end process;

end architecture;
