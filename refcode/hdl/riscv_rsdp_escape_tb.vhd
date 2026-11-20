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

library IEEE;
use IEEE.std_logic_1164.all;
use work.riscv_rsdp_pkg.all;

entity riscv_rsdp_escape_tb is
end entity;

architecture sim of riscv_rsdp_escape_tb is

constant cReportOK : boolean := false;
constant cClkCycle : time := 20 ns;
constant cOneBits: STD_LOGIC_VECTOR(127 downto 0) := (others => '1');

signal iRst  : STD_LOGIC;

signal iClk  : STD_LOGIC;
signal iData : STD_LOGIC;
signal oDut  : tEscapeToRsdp;

constant cErrRespStrMiss  : NATURAL := 1;
constant cErrRespStrExtra : NATURAL := 2;
constant cErrRsdpEna      : NATURAL := 3;
constant cErrCrcEna       : NATURAL := 4;
constant cErrUseJtag      : NATURAL := 5;

constant cErrLastNr       : NATURAL := cErrUseJtag;

type tErrCntArray is array(1 to cErrLastNr) of NATURAL;
type tErrNameArray is array(1 to cErrLastNr) of STRING(1 to 20);
constant cErrorNames : tErrNameArray := (
	"WantResponse missing",
	"WantResponse extra  ",
	"RsdpEnable wrong    ",
	"RsdpWithCrc wrong   ",
	"UseJtag wrong       "
);

type tSimState is record
	injectBitError : NATURAL;
	errCnt : tErrCntArray;
end record;
constant cSimStateRst : tSimState := (
	injectBitError => 0,
	errCnt => (others => 0)
);

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
end function;
function fToHexStr(
	iBit : in STD_LOGIC
) return string is
	variable vRes : STRING(1 to 3);
begin
	vRes(1 to 2):="0x";
	if iBit = '0' then
		vRes(3) := '0';
	elsif iBit = '1' then
		vRes(3) := '1';
	else
		vRes(3) := '-';
	end if;
	return vRes;
end function;

procedure pSendBits(
	iData           : in STD_LOGIC_VECTOR;
	signal oClk     : out STD_LOGIC;
	signal oData    : out STD_LOGIC
) is
	constant cData : STD_LOGIC_VECTOR(iData'length-1 downto 0) := iData;
begin
	for i in cData'low to cData'high loop
		oClk  <= '0';
		oData <= cData(i);
		wait for cClkCycle/2;
		oClk  <= '1';
		wait for cClkCycle/2;
	end loop;
	oClk <= '0';
end procedure;

procedure pSendBits(
	iData           : in STD_LOGIC_VECTOR;
	iBitError       : in NATURAL;
	signal oClk     : out STD_LOGIC;
	signal oData    : out STD_LOGIC
) is
	constant cData : STD_LOGIC_VECTOR(iData'length-1 downto 0) := iData;
begin
	for i in cData'low to cData'high loop
		oClk  <= '0';
		if i = iBitError then
			oData <= not cData(i);
		else
			oData <= cData(i);
		end if;
		wait for cClkCycle/2;
		oClk  <= '1';
		wait for cClkCycle/2;
	end loop;
	oClk <= '0';
end procedure;

subtype tLfsr is STD_LOGIC_VECTOR(5 downto 0);
function fNextLfsr(
	iLfsr : in tLfsr;
	iBit  : in STD_LOGIC
) return tLfsr is
	variable ret: tLfsr;
begin
	ret(0) := iLfsr(1);
	ret(1) := iLfsr(2);
	ret(2) := iLfsr(3);
	ret(3) := iLfsr(4);
	ret(4) := iLfsr(5) xor iLfsr(0) xor iBit;
	ret(5) :=              iLfsr(0) xor iBit;
	return ret;
end function;

subtype tSelectData is STD_LOGIC_VECTOR(39 downto 0);
type tTmsSequence is record
	length: NATURAL;
	bits: STD_LOGIC_VECTOR(4 + 80*2 + 16 downto 0);
end record;

function fGenTmsSequence(
	iData: in STD_LOGIC_VECTOR
) return tTmsSequence is
	constant cData  : STD_LOGIC_VECTOR(iData'length-1 downto 0) := iData;
	variable ret    : tTmsSequence;
	variable l      : natural;
	variable lfsr   : tLfsr;
	variable lfsrToggle : STD_LOGIC;
begin
	ret.length := 0;
	ret.bits   := (others => '0');

	ret.bits(2 downto 0) := "010";
	l := 3;

	-- Generate RANDOM
	lfsr := "111000";
	for idx in 0 to 31 loop
		if lfsr(0) = '0' then
			ret.bits(l) := '0';
			l:=l+1;
		else
			ret.bits(l+1 downto l) := "01";
			l:=l+2;
		end if;
		lfsr := fNextLfsr(lfsr, '0');
	end loop;
	-- generate ST
	for idx in cData'low to cData'high loop
		if cData(idx) = '0' then
			ret.bits(l) := '0';
			l:=l+1;
		else
			ret.bits(l+1 downto l) := "01";
			l:=l+2;
		end if;
		lfsr := fNextLfsr(lfsr, cData(idx));
	end loop;
	-- generate CRC-6
	lfsr := not lfsr;
	for idx in 0 to 5 loop
		if lfsr(0) = '0' then
			ret.bits(l) := '0';
			l:=l+1;
		else
			ret.bits(l+1 downto l) := "01";
			l:=l+2;
		end if;
		lfsr := "0"&lfsr(5 downto 1);
	end loop;

	-- start JTAG_END without trailing "01"
	ret.bits(l) := '1';
	l:=l+1;
	ret.length := l;
	return ret;
end function;

function fGetSeqName(
	constant iCmd : in tRsdpEscST
) return STRING is
begin
	case iCmd is
		when cRSDP_ESC_ST_DISABLE =>
			return "Switching sequence: DISABLE      ";
		when cRSDP_ESC_ST_ROBUST =>
			return "Switching sequence: ENABLE-ROBUST";
		when cRSDP_ESC_ST_FAST =>
			return "Switching sequence: ENABLE-FAST  ";
		when cRSDP_ESC_ST_JTAG =>
			return "Switching sequence: ENABLE-JTAG  ";
		when cRSDP_ESC_ST_RTNS =>
			return "Switching sequence: RETRANSMIT   ";
		when others =>
			return "Switching sequence: UNKNOWN      ";
	end case;
end function;

procedure pCheckSequence(
	constant iCmd : in tRsdpEscST;
	ioSim : inout tSimState;

	signal oClk   : out STD_LOGIC;
	signal oData  : out STD_LOGIC;

	signal iDut   : in tEscapeToRsdp
) is
	variable vBitError : NATURAL;
	variable tmsSeq : tTmsSequence;
	variable vRpt : tReportString := cReportStringRst;
	variable vRsdpEnable   : STD_LOGIC := '0';
	variable vRsdpWithCrc  : STD_LOGIC := '0';
	variable vUseJtag      : STD_LOGIC := '0';
	variable vWantResponse : STD_LOGIC := '0';
	variable vResponseType : STD_LOGIC_VECTOR(1 downto 0) := "00";
	variable vHasError     : BOOLEAN;
	variable vIsWrong      : BOOLEAN;
begin
	case iCmd is
		when cRSDP_ESC_ST_DISABLE =>
			null;
		when cRSDP_ESC_ST_ROBUST =>
			vRsdpEnable     := '1';
			vRsdpWithCrc    := '1';
			vWantResponse   := '1';
			vResponseType   := "00";
		when cRSDP_ESC_ST_FAST =>
			vRsdpEnable     := '1';
			vRsdpWithCrc    := '0';
			vWantResponse   := '1';
			vResponseType   := "01";
		when cRSDP_ESC_ST_JTAG =>
			vUseJtag        := '1';
		when cRSDP_ESC_ST_RTNS =>
			vRsdpEnable     := '1';
			vRsdpWithCrc    := '1';
			vWantResponse   := '1';
			vResponseType   := "10";
		when others =>
			null;
	end case;
	vBitError := ioSim.injectBitError;
	ioSim.injectBitError := 0;

	vHasError := false;
	pSendBits(X"000", oClk, oData);
	if vBitError = 0 or vBitError > 80 then
		pSendBits(cOneBits(79 downto 0), oClk, oData);
	else
		vHasError := true;
		pSendBits(cOneBits(79 downto 0), vBitError - 1, oClk, oData);
	end if;

	tmsSeq := fGenTmsSequence(iCmd);

	pStrAppend(vRpt, LF & LF & "-----------------------------------------------------------------------------");
	pStrAppend(vRpt, LF & fGetSeqName(iCmd));
	if vBitError > 0 then
		pStrAppend(vRpt, LF & "injected bit error at bit " & integer'image(vBitError - 1));
	end if;
	if vBitError - 81 = tmsSeq.length then
		pStrAppend(vRpt, LF & "bit arror at LAST bit ");
	end if;
	pStrAppend(vRpt,
		LF & "tmsSeq.length: " & integer'image(tmsSeq.length + 80 + 1) &
		LF & "tmsSeq.bits: "   & fToHexStr("0" & tmsSeq.bits(tmsSeq.length-1 downto 0))
	);
	if vBitError <= 80 or vBitError > tmsSeq.length + 80 then
		pSendBits(tmsSeq.bits(tmsSeq.length-1 downto 0), oClk, oData);
	else
		vHasError := true;
		pSendBits(tmsSeq.bits(tmsSeq.length-1 downto 0), vBitError - 81 , oClk, oData);
	end if;
	if vHasError then
		vWantResponse := '0';
		vResponseType := "00";
		vRsdpEnable   := '0';
		vRsdpWithCrc  := '0';
		vUseJtag      := '0';
	end if;

	vIsWrong := false;
	if vWantResponse='1' then
		if iDut.WantResponse='0' then
			vIsWrong := true;
			ioSim.errCnt(cErrRespStrMiss) := ioSim.errCnt(cErrRespStrMiss) + 1;
			pStrAppend(vRpt, LF & "ERROR: WantResponse de-asserted!");
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : WantResponse asserted");
			if vResponseType /= iDut.ResponseType then
				pStrAppend(vRpt,
					LF & "ERROR: Wrong ResponseType" &
					LF & "is     : " & fToHexStr(iDut.ResponseType) &
					LF & "should : " & fToHexStr(vResponseType)
				);
			else
				pStrAppend(vRpt, LF & "OK   : ResponseType correct = " & fToHexStr(vResponseType));
			end if;
		end if;
	else
		if iDut.WantResponse='1' then
			vIsWrong := true;
			ioSim.errCnt(cErrRespStrExtra) := ioSim.errCnt(cErrRespStrExtra) + 1;
			pStrAppend(vRpt, LF & "ERROR: WantResponse asserted!");
		elsif cReportOK then
			pStrAppend(vRpt, LF & "OK   : WantResponse de-asserted");
		end if;
	end if;
	if vBitError - 81 = tmsSeq.length then
		-- Instead of sending JTAG_END, just send "0000".
		-- That's for simluation to see if the escape engine
		-- exits when too many bits are detected.
		pSendBits("000", oClk, oData);
		vRsdpEnable   := '0';
		vRsdpWithCrc  := '0';
		vUseJtag      := '0';
	else
		-- Send last '1' bit of JTAG_END
		pSendBits("1", oClk, oData);
	end if;

	if vRsdpEnable /= iDut.RsdpEnable then
		vIsWrong := true;
		ioSim.errCnt(cErrRsdpEna) := ioSim.errCnt(cErrRsdpEna) + 1;
		pStrAppend(vRpt,
			LF & "ERROR: Wrong RsdpEnable" &
			LF & "is     : " & fToHexStr(iDut.RsdpEnable) &
			LF & "should : " & fToHexStr(vRsdpEnable)
		);
	elsif cReportOK then
		pStrAppend(vRpt, LF & "OK   : RsdpEnable correct = " & fToHexStr(vRsdpEnable));
	end if;
	if vRsdpWithCrc /= iDut.RsdpWithCrc then
		vIsWrong := true;
		ioSim.errCnt(cErrCrcEna) := ioSim.errCnt(cErrCrcEna) + 1;
		pStrAppend(vRpt,
			LF & "ERROR: Wrong RsdpWithCrc" &
			LF & "is     : " & fToHexStr(iDut.RsdpWithCrc) &
			LF & "should : " & fToHexStr(vRsdpWithCrc)
		);
	elsif cReportOK then
		pStrAppend(vRpt, LF & "OK   : RsdpWithCrc correct = " & fToHexStr(vRsdpWithCrc));
	end if;
	if vUseJtag /= iDut.UseJtag then
		vIsWrong := true;
		ioSim.errCnt(cErrUseJtag) := ioSim.errCnt(cErrUseJtag) + 1;
		pStrAppend(vRpt,
			LF & "ERROR: Wrong UseJtag" &
			LF & "is     : " & fToHexStr(iDut.UseJtag) &
			LF & "should : " & fToHexStr(vUseJtag)
		);
	elsif cReportOK then
		pStrAppend(vRpt, LF & "OK   : UseJtag correct = " & fToHexStr(vUseJtag));
	end if;

	pStrAppend(vRpt, LF);

	if vIsWrong or cReportOK then
		report vRpt.s(1 to vRpt.l);
	end if;
	pSendBits(X"000", oClk, oData);
end procedure;

procedure pReportErrors(
	iSimState : in tSimState
) is
	variable vRpt : tReportString := cReportStringRst;
	variable vHaveErrors : boolean;
begin
	vHaveErrors := false;
	for i in iSimState.errCnt'range loop
		if iSimState.errCnt(i) > 0 then
			vHaveErrors := true;
		end if;
	end loop;
	if not vHaveErrors then
		pStrAppend(vRpt, LF &
			LF & "------------------------------------" &
			LF & "---- All OK                       --" &
			LF & "------------------------------------" &
			LF
		);
		report vRpt.s(1 to vRpt.l);
		return;
	end if;
	pStrAppend(vRpt, LF & LF & "Error Summary:");
	for i in iSimState.errCnt'range loop
		if iSimState.errCnt(i) > 0 then
			pStrAppend(vRpt, LF & cErrorNames(i) & " : " & integer'image(iSimState.errCnt(i)));
		end if;
	end loop;
	pStrAppend(vRpt, LF);
	report vRpt.s(1 to vRpt.l) severity error;
end procedure;

begin
	yDut: entity work.riscv_rsdp_escape
	generic map (
		gStartInJtag => false,
		gCrcSupport  => true
	)
	port map (

		iRst      => iRst,

		iClk      => iClk,
		iData     => iData,

		oToRsdp    => oDut
	);

	pData : process
		variable vSimState : tSimState := cSimStateRst;
	begin
		iRst  <= '1';
		iClk  <= '0';
		iData <= '0';
		wait for cClkCycle*3;
		iRst  <= '0';
		wait for cClkCycle;
		pCheckSequence(cRSDP_ESC_ST_DISABLE, vSimState, iClk, iData, oDut);
		pCheckSequence(cRSDP_ESC_ST_JTAG,    vSimState, iClk, iData, oDut);
		pCheckSequence(cRSDP_ESC_ST_FAST,    vSimState, iClk, iData, oDut);
		pCheckSequence(cRSDP_ESC_ST_ROBUST,  vSimState, iClk, iData, oDut);
		pCheckSequence(cRSDP_ESC_ST_RTNS,    vSimState, iClk, iData, oDut);

		-- UNKNOWN should go to DISABLED
		pCheckSequence(X"12",                vSimState, iClk, iData, oDut);

		-- Here: We should be in DISABLED state.
		-- To check bit error detection: Try to send ENABLE-ROBUST with a bit error
		-- None of these should succeed.
		-- Only 79 1 bits in a row (first 1 bit missing)
		vSimState.injectBitError := 1;
		pCheckSequence(cRSDP_ESC_ST_ROBUST, vSimState, iClk, iData, oDut);
		vSimState.injectBitError := 41;
		pCheckSequence(cRSDP_ESC_ST_ROBUST, vSimState, iClk, iData, oDut);
		-- Only 79 1 bits in a row (last 1 bit missing)
		-- and error in start of sequence
		for i in 80 to 84 loop
			vSimState.injectBitError := i;
			pCheckSequence(cRSDP_ESC_ST_ROBUST, vSimState, iClk, iData, oDut);
		end loop;

		for i in 1 to 9 loop
			-- i 1..9 : error in RANDOM/DATA or CRC
			vSimState.injectBitError := i*7 + 81;
			pCheckSequence(cRSDP_ESC_ST_ROBUST,  vSimState, iClk, iData, oDut);
		end loop;
		-- Instead of sending JTAG-END + 0 ("011"), send "010"
		vSimState.injectBitError := 68 + 81;
		pCheckSequence(cRSDP_ESC_ST_ROBUST,  vSimState, iClk, iData, oDut);

		-- Instead of sending JTAG-END + 0 ("011"), send "0001"
		vSimState.injectBitError := 69 + 81;
		pCheckSequence(cRSDP_ESC_ST_ROBUST,  vSimState, iClk, iData, oDut);

		pReportErrors(vSimState);
		wait;
	end process;

end architecture;
