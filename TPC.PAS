{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/turbopascal6-0)
  @abstract(Target: Free Pascal)
  @description: Clone du compilateur Turbo Pascal 6.0
}

Program TPC;

{ Portage partiel, et NON un remplacement integral de Turbo Pascal 6.
  Reference: N:\IBMPC\CODER\TurboPascalSource\COMPILER (VER60 / TPU9).
  Les tokens, NeedToken, CalcHash et les structures TPU ci-dessous suivent
  COMPILER.INC et LEX.ASM. Le parseur et le runtime sont nouveaux: le code
  produit n'est pas identique a celui de Borland. Aucun backend FPC externe.
  Hote valide: Free Pascal 3.2, mode TP, strings courts uniquement.
  Cible: DOS MZ, instructions 8086, un segment CS/DS et pile separee.
  Restrictions explicites: ABI Borland partielle (ordinaux 8/16 bits), pas d'OBJ, real, tableaux, objets,
  types utilisateurs, procedures a parametres, routines imbriquees, ASM.
  /B recompile les sources et produit des fichiers TPU. Unites de code:
  profil TPU9/TPC1 marque, ABI locale near, incompatible ABI Borland.
  Unites autonomes de constantes seules: layout TPU9 sans extension.
  TURBO.TPL: index TPU9 concatene, lecture directe par tranche, import des
  constantes et routines Borland. Ponts far, donnees DS separees, fixups MZ;
  initialisation/finalisation SYSTEM et initialisations des unites liees.
  La compatibilite avec le linker Borland n'a pas ete validee.
  Les fonctionnalites manquantes ont un diagnostic propre sans faux numero TP.
  Numeros verifies dans le source et dans la table du TPC.EXE original DISK1.
  Les messages anglais ci-dessous couvrent les erreurs utilisees ici; les
  details supplementaires sont locaux, les positions ne sont pas garanties
  identiques a Borland. }
{$A-}
{$IFDEF FPC}
{$MODE TP}
{$H-}
{$ENDIF}
{$R-}{$Q-}

Uses Dos;

Const
  MaxSource = 60000;
  MaxImage = 60000;
  MaxSymbols = 512;
  MaxFixups = 4096;
  MaxDefines = 128;
  MaxUnits = 64;
  MaxLibraryUnits = 256;
  tkEOF=0; tkIdent=1; tkConstant=2;
  tkPlus=3; tkMinus=4; tkTimes=5; tkSlash=6; tkEqual=7;
  tkNE=8; tkGreater=9; tkLess=10; tkGE=11; tkLE=12;
  tkLP=13; tkRP=14; tkLB=15; tkRB=16; tkDot=17; tkComma=18;
  tkColon=19; tkSemi=20; tkCaret=21; tkAssign=22; tkRange=23; tkAt=24;
  tkAnd=28; tkArray=29; tkBegin=30; tkCase=31; tkConst=32;
  tkConstructor=33; tkDestructor=34; tkDiv=35; tkDo=36;
  tkDownto=37; tkElse=38; tkEnd=39; tkAsm=40; tkFile=41; tkFor=42;
  tkFunction=44; tkGoto=45; tkIf=46; tkImplementation=47;
  tkIn=48; tkInline=49; tkInterface=50; tkLabel=52; tkMod=53;
  tkNil=54; tkNot=55; tkObject=56; tkOf=57; tkOr=58;
  tkPacked=59; tkProcedure=60; tkProgram=61; tkRecord=62;
  tkRepeat=63; tkSet=64; tkShl=65; tkShr=66; tkString=67;
  tkThen=68; tkType=69; tkTo=70; tkUnit=71; tkUntil=72;
  tkUses=73; tkVar=74; tkWhile=76; tkWith=77; tkXor=78;
  ttVoid=0; ttArray=1; ttRecord=2; ttObject=3; ttFile=4; ttText=5;
  ttProc=6; ttSet=7; ttPointer=8; ttString=9; tt8087=10;
  ttReal=11; ttInteger=12; ttBoolean=13; ttChar=14; ttEnum=15;
  skVar=1; skConst=2; skProc=3; skForeign=4;
  MaxNativeParams = 8;
  MaxNativeRefs = 4096;

type
  TShortString = string[255];
  { Packed + Word: jamais de pointeurs natifs 32/64 bits dans une TPU. }
  TUnitHeader = packed record
    Signature: array[0..3] of Char;
    Next, Link, Name, Interf, ProcMap, CodeMap, ConstMap, DataMap: Word;
    EndMaps, Units, Sources, Trace, EndTrace: Word;
    CodeSize, ConstSize, CodeFixupSize, DataFixupSize, DataSize: Word;
    DebugHash, Flags, CodeStart, CodeLength, OverlayLength: Word;
    TpuName, CodeSeg, ConstSeg, CodeFixupSeg, ConstFixupSeg: Word;
    Reserved: array[0..9] of Word;
  end;
  TTypeDescriptor = packed record
    Typ, Modifier: Byte;
    SizeOfType, Next: Word;
  end;
  TSymbolPrefix = packed record
    Prev: Word;
    Typ, NameLength: Byte;
  end;
  TFarAddress = packed record Offs, Segm: Word end;
  TTPUFixup = packed record UnitRef, Map, Target, Offs: Word end;
  TSegMap = packed record Addr, Len, FixupLength, Owner: Word end;
  TProcMap = packed record Stub, Flags, CodeMap, EntryPoint: Word end;
  TSymbol = record
    Name: string[63];
    Kind, Typ, Width: Byte;
    Capacity: Byte;
    Addr: Word;
    Owner: Byte;
    Exported, HasBody: Boolean;
    ForwardJump: Word;
    Value: Longint;
    StrValue: TShortString;
    Native: Boolean;
    NativeMap: Word;
    NativeConst: Boolean;
    ParamCount: Byte;
    ParamTypes, ParamWidths, ParamFlags: array[1..MaxNativeParams] of Byte;
    SignedByte: Boolean;
    ParamSigned: array[1..MaxNativeParams] of Boolean;
  end;
  TAddressFixup = record Position, DataOffset: Word end;
  TRelativeFixup = record Position, Target: Word end;
  TCondition = record ParentActive, Test, SeenElse: Boolean end;
  TUnitSet = set of 0..MaxUnits;
  TBuildUnit = record
    Name: string[63];
    State: Byte; { 1 = compilation en cours; 2 = compilee }
    InterfaceReady, HasInit: Boolean;
    InitAddress: Word;
    FromSource: Boolean;
    Path: TShortString;
    Dependencies: TUnitSet;
    DependencyChecks: array[1..MaxUnits] of Word;
    Checksum: Word;
    CodeBase, DataBase: Word;
    LibraryEntry: Word;
  end;
  TLibraryEntry = record
    Name: string[63];
    Offset, Size: Longint;
    Header: TUnitHeader;
  end;
  TBinaryBuffer = array[0..262143] of Byte;
  PBinaryBuffer = ^TBinaryBuffer;
  TNativeRef = record Position, Map, Target: Word; U, Kind: Byte end;
  TMZRelocation = packed record Offs, Segm: Word end;
  TSourceBuffer = array[1..MaxSource] of Char;
  PSourceBuffer = ^TSourceBuffer;
  PParserState = ^TParserState;
  TParserState = record
    Buffer: PSourceBuffer;
    SourceName: TShortString;
    SourceSize, SourcePos: Longint;
    Line, Column, TokenLine, TokenColumn: Word;
    Token: Byte;
    TokenText: TShortString;
    TokenValue: Longint;
    TokenIsString, Active, InProcedure, InInterface: Boolean;
    CondDepth, CurrentUnit: Byte;
    Imports: TUnitSet;
    ImportOrder: array[1..MaxUnits] of Byte;
    ImportCount: Byte;
    Conditions: array[1..32] of TCondition;
    Defines: array[1..MaxDefines] of string[63];
    DefineCount, OptionBits, StackSize, MinHeap, MaxHeap: Word;
  end;

var
  Source: array[1..MaxSource] of Char;
  Image, Data: array[0..MaxImage-1] of Byte;
  Symbols: array[1..MaxSymbols] of TSymbol;
  Fixups: array[1..MaxFixups] of TAddressFixup;
  RelativeFixups: array[1..MaxFixups] of TRelativeFixup;
  RelativeCount: Word;
  CodeOwners, DataOwners: array[0..MaxImage-1] of Byte;
  Defines: array[1..MaxDefines] of string[63];
  Conditions: array[1..32] of TCondition;
  SourceSize, SourcePos: Longint;
  Line, Column, TokenLine, TokenColumn: Word;
  Token: Byte;
  TokenText: TShortString;
  TokenValue: Longint;
  TokenIsString, Active: Boolean;
  CodeSize, DataSize, SymbolCount, FixupCount, DefineCount: Word;
  CondDepth: Byte;
  SourceName, OutputDir, UnitDirs, InputName, InspectName: TShortString;
  TurboDirs, LibraryName, InspectLibraryName: TShortString;
  LibraryUnits: array[1..MaxLibraryUnits] of TLibraryEntry;
  LibraryCount: Word;
  OptionBits, StackSize, MinHeap, MaxHeap: Word;
  BuildMode, MakeMode, Quiet, InProcedure: Boolean;
  EntryFixup, RuntimeString, RuntimeInteger, RuntimeChar: Word;
  RuntimeBoolean, RuntimeCopy: Word;
  NumberBuffer, TrueText, FalseText: Word;
  Units: array[1..MaxUnits] of TBuildUnit;
  InitOrder: array[1..MaxUnits] of Byte;
  UnitCount, InitCount, CurrentUnit: Byte;
  Imports: TUnitSet;
  ImportOrder: array[1..MaxUnits] of Byte;
  ImportCount: Byte;
  InInterface: Boolean;
  MainSourceName: TShortString;
  InitialDefines: array[1..MaxDefines] of string[63];
  InitialDefineCount, InitialOptions: Word;
  UnitOutput: Boolean;
  NativeBuffers: array[1..MaxUnits] of PBinaryBuffer;
  NativeHeaders: array[1..MaxUnits] of TUnitHeader;
  NativeCodeBases, NativeConstBases, NativeVarBases: array[1..MaxUnits] of Word;
  NativeActive: array[1..MaxUnits] of Boolean;
  NativeData: array[0..MaxImage-1] of Byte;
  NativeDataSize: Word;
  NativeRefs: array[1..MaxNativeRefs] of TNativeRef;
  NativeRefCount: Word;
  Relocations: array[1..MaxNativeRefs] of TMZRelocation;
  RelocationKinds: array[1..MaxNativeRefs] of Byte;
  RelocationCount: Word;
  NativeNeeded: Boolean;
  RuntimeHalt, MainEntry: Word;
  NativeInitOrder: array[1..MaxUnits] of Byte;
  NativeInitCount: Byte;

procedure ActivateNative(U: Byte); forward;

function Upper(S: TShortString): TShortString;
var I: Integer;
begin
  for I:=1 to Length(S) do S[I]:=UpCase(S[I]);
  Upper:=S;
end;

function HashIdent(S: TShortString): Byte;
var I: Integer; H: Word;
begin
  H:=0;
  for I:=1 to Length(S) do H:=(H+Ord(UpCase(S[I]))-1) and 255;
  HashIdent:=(H*2) and 255;
end;

function ErrorMessage(N: Word): TShortString;
begin
  case N of
    2:ErrorMessage:='Identifier expected';
    3:ErrorMessage:='Unknown identifier';
    4:ErrorMessage:='Duplicate identifier';
    5:ErrorMessage:='Syntax error';
    7:ErrorMessage:='Error in integer constant';
    8:ErrorMessage:='String constant exceeds line';
    10:ErrorMessage:='Unexpected end of file';
    15:ErrorMessage:='File not found';
    16:ErrorMessage:='Disk full';
    17:ErrorMessage:='Invalid compiler directive';
    20:ErrorMessage:='Variable identifier expected';
    25:ErrorMessage:='Invalid string length';
    26:ErrorMessage:='Type mismatch';
    36:ErrorMessage:='BEGIN expected';
    37:ErrorMessage:='END expected';
    38:ErrorMessage:='Integer expression expected';
    40:ErrorMessage:='Boolean expression expected';
    42:ErrorMessage:='Error in expression';
    43:ErrorMessage:='Illegal assignment';
    48:ErrorMessage:='Code segment too large';
    49:ErrorMessage:='Data segment too large';
    50:ErrorMessage:='DO expected';
    54:ErrorMessage:='OF expected';
    55:ErrorMessage:='INTERFACE expected';
    57:ErrorMessage:='THEN expected';
    58:ErrorMessage:='TO or DOWNTO expected';
    59:ErrorMessage:='Undefined forward';
    66:ErrorMessage:='String expression expected';
    68:ErrorMessage:='Circular unit reference';
    69:ErrorMessage:='Unit name mismatch';
    70:ErrorMessage:='Unit version mismatch';
    72:ErrorMessage:='Unit file format error';
    73:ErrorMessage:='IMPLEMENTATION expected';
    76:ErrorMessage:='Constant out of range';
    84:ErrorMessage:='UNIT expected';
    85:ErrorMessage:='";" expected';
    86:ErrorMessage:='":" expected';
    87:ErrorMessage:='"," expected';
    88:ErrorMessage:='"(" expected';
    89:ErrorMessage:='")" expected';
    90:ErrorMessage:='"=" expected';
    91:ErrorMessage:='":=" expected';
    92:ErrorMessage:='"[" or "(." expected';
    93:ErrorMessage:='"]" or ".)" expected';
    94:ErrorMessage:='"." expected';
    95:ErrorMessage:='".." expected';
    106:ErrorMessage:='Character expression expected';
    120:ErrorMessage:='NIL expected';
    123:ErrorMessage:='Too many symbols';
    127:ErrorMessage:='Misplaced conditional directive';
    128:ErrorMessage:='ENDIF directive missing';
  else ErrorMessage:='Compiler error';
  end;
end;

procedure Fail(N: Word; S: TShortString);
begin
  WriteLn(SourceName,'(',TokenLine,',',TokenColumn,'): Error ',N,': ',ErrorMessage(N),
    ' (',S,')');
  Halt(1);
end;

procedure Unsupported(S: TShortString);
begin
  WriteLn(SourceName,'(',TokenLine,',',TokenColumn,
    '): TPC: fonctionnalite non implementee: ',S);
  Halt(2);
end;

procedure CLIError(S: TShortString);
begin
  WriteLn('TPC: ',S);
  Halt(2);
end;

function Peek: Char;
begin
  if SourcePos>SourceSize then Peek:=#0 else Peek:=Source[SourcePos];
end;

function PeekNext: Char;
begin
  if SourcePos>=SourceSize then PeekNext:=#0 else PeekNext:=Source[SourcePos+1];
end;

procedure Advance;
begin
  if Peek=#10 then begin Inc(Line); Column:=1 end
  else Inc(Column);
  Inc(SourcePos);
end;

procedure AppendChar(var S: TShortString; C: Char);
begin
  if Length(S)=255 then Unsupported('chaine ou lexeme > 255 octets');
  S:=S+C;
end;

function IsDefined(S: TShortString): Boolean;
var I: Word;
begin
  S:=Upper(S);
  IsDefined:=False;
  for I:=1 to DefineCount do if Defines[I]=S then IsDefined:=True;
end;

procedure Define(S: TShortString);
begin
  S:=Upper(S);
  if (S='') or (Length(S)>63) then Fail(2,'Identificateur de define attendu');
  if not IsDefined(S) then begin
    if DefineCount=MaxDefines then Unsupported('trop de defines');
    Inc(DefineCount); Defines[DefineCount]:=S;
  end;
end;

procedure Undefine(S: TShortString);
var I: Word;
begin
  S:=Upper(S);
  for I:=1 to DefineCount do if Defines[I]=S then Defines[I]:='';
end;

function Trim(S: TShortString): TShortString;
begin
  while (Length(S)>0) and (S[1]<=' ') do Delete(S,1,1);
  while (Length(S)>0) and (S[Length(S)]<=' ') do Delete(S,Length(S),1);
  Trim:=S;
end;

function SwitchBit(C: Char): Word;
begin
  case UpCase(C) of
    'I':SwitchBit:=$0001; 'R':SwitchBit:=$0002; 'S':SwitchBit:=$0004;
    'X':SwitchBit:=$0008; 'V':SwitchBit:=$0010; 'F':SwitchBit:=$0020;
    'B':SwitchBit:=$0040; 'N':SwitchBit:=$0080; 'D':SwitchBit:=$0100;
    'L':SwitchBit:=$0200; 'E':SwitchBit:=$0400; 'O':SwitchBit:=$0800;
    'A':SwitchBit:=$1000; 'G':SwitchBit:=$2000;
  else SwitchBit:=0;
  end;
end;

procedure SetSwitch(S: TShortString);
var B: Word;
begin
  if (Length(S)<>2) or not (S[2] in ['+','-']) then
    CLIError('Option attendue sous la forme $X+ ou $X-');
  B:=SwitchBit(S[1]);
  if B=0 then CLIError('Option inconnue: $'+S);
  { Accepter une option sans en respecter l'effet serait trompeur. }
  if S[2]='+' then begin
    if UpCase(S[1]) in ['R','S','B','N','G','D','L','F','O','X'] then
      Unsupported('option $'+Upper(S));
    OptionBits:=OptionBits or B;
  end else OptionBits:=OptionBits and not B;
end;

procedure MemoryDirective(S: TShortString);
var A: array[1..3] of Longint; I, P, E: Integer; Part: TShortString;
begin
  for I:=1 to 3 do begin
    P:=Pos(',',S);
    if P=0 then begin Part:=Trim(S); S:='' end
    else begin Part:=Trim(Copy(S,1,P-1)); Delete(S,1,P) end;
    Val(Part,A[I],E);
    if E<>0 then Fail(17,'Directive $M incorrecte');
  end;
  if (S<>'') or (A[1]<1024) or (A[1]>65520) or
    (A[2]<0) or (A[2]>655360) or (A[3]<A[2]) or (A[3]>655360) then
    Fail(17,'Limites $M incorrectes');
  if A[2]<>0 then Unsupported('$M minheap non nul');
  StackSize:=(A[1]+1) and $FFFE;
  MinHeap:=0; MaxHeap:=(A[3]+15) div 16;
end;

procedure Directive(S: TShortString);
var P: Integer; Cmd, Arg: TShortString; Test: Boolean;
begin
  S:=Trim(S);
  P:=1;
  while (P<=Length(S)) and (S[P]>' ') do Inc(P);
  Cmd:=Upper(Copy(S,1,P-1)); Arg:=Trim(Copy(S,P+1,255));
  if (Cmd='IFDEF') or (Cmd='IFNDEF') then begin
    if CondDepth=32 then Unsupported('imbrication conditionnelle > 32');
    Test:=IsDefined(Arg); if Cmd='IFNDEF' then Test:=not Test;
    Inc(CondDepth);
    Conditions[CondDepth].ParentActive:=Active;
    Conditions[CondDepth].Test:=Test;
    Conditions[CondDepth].SeenElse:=False;
    Active:=Active and Test;
  end else if Cmd='ELSE' then begin
    if CondDepth=0 then Fail(127,'$ELSE sans $IFDEF');
    if Conditions[CondDepth].SeenElse then Fail(127,'$ELSE duplique');
    Conditions[CondDepth].SeenElse:=True;
    Active:=Conditions[CondDepth].ParentActive and not Conditions[CondDepth].Test;
  end else if Cmd='ENDIF' then begin
    if CondDepth=0 then Fail(127,'$ENDIF sans $IFDEF');
    Active:=Conditions[CondDepth].ParentActive; Dec(CondDepth);
  end else if Active then begin
    if Cmd='DEFINE' then Define(Arg)
    else if Cmd='UNDEF' then Undefine(Arg)
    else if (Length(Cmd)=2) and (Cmd[2] in ['+','-']) then SetSwitch(Cmd)
    else if (Length(Cmd)>0) and (Cmd[1]='M') then
      MemoryDirective(Trim(Copy(S,2,255)))
    else Unsupported('directive $'+S);
  end;
end;

procedure SkipComment(Paren: Boolean);
var S: TShortString; IsDirective, Closed: Boolean;
begin
  Advance; if Paren then Advance;
  IsDirective:=Peek='$'; if IsDirective then Advance;
  S:=''; Closed:=False;
  while (Peek<>#0) and not Closed do begin
    if (not Paren and (Peek='}')) or
      (Paren and (Peek='*') and (PeekNext=')')) then begin
      Advance; if Paren then Advance; Closed:=True;
    end else begin
      if IsDirective then AppendChar(S,Peek);
      Advance;
    end;
  end;
  if not Closed then Fail(10,'Fin de fichier dans un commentaire');
  if IsDirective then Directive(S);
end;

function Keyword(S: TShortString): Byte;
const
  Names: array[1..49] of string[14] = (
    'AND','ARRAY','BEGIN','CASE','CONST','CONSTRUCTOR','DESTRUCTOR','DIV',
    'DO','DOWNTO','ELSE','END','ASM','FILE','FOR','FUNCTION','GOTO','IF',
    'IMPLEMENTATION','IN','INLINE','INTERFACE','LABEL','MOD','NIL','NOT',
    'OBJECT','OF','OR','PACKED','PROCEDURE','PROGRAM','RECORD','REPEAT',
    'SET','SHL','SHR','STRING','THEN','TYPE','TO','UNIT','UNTIL','USES',
    'VAR','WHILE','WITH','XOR','');
  Values: array[1..49] of Byte = (
    28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,44,45,46,47,48,49,
    50,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,
    72,73,74,76,77,78,1);
var I: Integer;
begin
  Keyword:=tkIdent;
  for I:=1 to 48 do if S=Names[I] then Keyword:=Values[I];
end;

function ReadNumber: Longint;
var Base, Digit: Integer; N: Longint; C: Char;
begin
  Base:=10; N:=0;
  if Peek='$' then begin Base:=16; Advance end;
  if ((Base=10) and not (Peek in ['0'..'9'])) or
    ((Base=16) and not (UpCase(Peek) in ['0'..'9','A'..'F'])) then
    Fail(7,'Nombre attendu');
  while True do begin
    C:=UpCase(Peek);
    if C in ['0'..'9'] then Digit:=Ord(C)-Ord('0')
    else if (Base=16) and (C in ['A'..'F']) then Digit:=Ord(C)-Ord('A')+10
    else Break;
    if Digit>=Base then Break;
    if N>(2147483647-Digit) div Base then Fail(7,'Constante hors limites');
    N:=N*Base+Digit; Advance;
  end;
  ReadNumber:=N;
end;

procedure NextToken;
var C: Char; N: Longint; Closed: Boolean;
begin
  repeat
    while (Peek<>#0) and (Peek<=' ') do Advance;
    TokenLine:=Line; TokenColumn:=Column;
    if Peek='{' then SkipComment(False)
    else if (Peek='(') and (PeekNext='*') then SkipComment(True)
    else if not Active and (Peek<>#0) then Advance
    else Break;
  until False;
  TokenText:=''; TokenValue:=0; TokenIsString:=False;
  TokenLine:=Line; TokenColumn:=Column; C:=Peek;
  if C=#0 then begin
    if CondDepth<>0 then Fail(128,'$ENDIF manquant');
    Token:=tkEOF; Exit;
  end;
  if UpCase(C) in ['A'..'Z','_'] then begin
    while UpCase(Peek) in ['A'..'Z','0'..'9','_'] do begin
      AppendChar(TokenText,UpCase(Peek)); Advance;
    end;
    if Length(TokenText)>63 then Unsupported('identificateur > 63 caracteres');
    Token:=Keyword(TokenText); Exit;
  end;
  if C in ['0'..'9','$'] then begin
    Token:=tkConstant; TokenValue:=ReadNumber;
    if (Peek='.') and (PeekNext<>'.') then Unsupported('constantes reelles');
    if UpCase(Peek)='E' then Unsupported('constantes reelles');
    Exit;
  end;
  if C in ['''','#'] then begin
    Token:=tkConstant; TokenIsString:=True;
    repeat
      if Peek='#' then begin
        Advance; N:=ReadNumber;
        if N>255 then Fail(76,'Code caractere hors limites');
        AppendChar(TokenText,Chr(N));
      end else begin
        Advance; Closed:=False;
        while not Closed do begin
          if Peek in [#0,#10,#13] then Fail(8,'Chaine non terminee');
          if Peek='''' then begin
            Advance;
            if Peek='''' then begin AppendChar(TokenText,''''); Advance end
            else Closed:=True;
          end else begin AppendChar(TokenText,Peek); Advance end;
        end;
      end;
    until not (Peek in ['''','#']);
    Exit;
  end;
  Advance;
  case C of
    '+':Token:=tkPlus; '-':Token:=tkMinus; '*':Token:=tkTimes;
    '/':Token:=tkSlash; '=':Token:=tkEqual; '(':Token:=tkLP;
    ')':Token:=tkRP; '[':Token:=tkLB; ']':Token:=tkRB;
    ',':Token:=tkComma; ';':Token:=tkSemi; '^':Token:=tkCaret; '@':Token:=tkAt;
    ':':begin Token:=tkColon; if Peek='=' then begin Advance; Token:=tkAssign end end;
    '.':begin Token:=tkDot; if Peek='.' then begin Advance; Token:=tkRange end end;
    '<':begin Token:=tkLess;
      if Peek='=' then begin Advance; Token:=tkLE end
      else if Peek='>' then begin Advance; Token:=tkNE end;
    end;
    '>':begin Token:=tkGreater; if Peek='=' then begin Advance; Token:=tkGE end end;
  else Fail(5,'Caractere inattendu');
  end;
end;

procedure Need(T: Byte);
var E: Word;
begin
  if Token<>T then begin
    case T of
      tkIdent:E:=2; tkBegin:E:=36; tkEnd:E:=37; tkDo:E:=50;
      tkOf:E:=54; tkInterface:E:=55; tkThen:E:=57;
      tkImplementation:E:=73; tkUnit:E:=84;
      tkSemi:E:=85; tkColon:E:=86; tkComma:E:=87; tkLP:E:=88;
      tkRP:E:=89; tkEqual:E:=90; tkAssign:E:=91; tkLB:E:=92;
      tkRB:E:=93; tkDot:E:=94; tkRange:E:=95; tkNil:E:=120;
    else E:=5;
    end;
    Fail(E,'Symbole attendu');
  end;
  NextToken;
end;

procedure Emit(B: Byte);
begin
  if CodeSize=MaxImage then Fail(48,'Segment de code trop grand');
  CodeOwners[CodeSize]:=CurrentUnit;
  Image[CodeSize]:=B; Inc(CodeSize);
end;

procedure EmitWord(W: Word);
begin Emit(W and 255); Emit(W shr 8) end;

procedure PatchWord(P, W: Word);
begin Image[P]:=W and 255; Image[P+1]:=W shr 8 end;

procedure Emit2(A,B: Byte);
begin Emit(A); Emit(B) end;

function Jump: Word;
begin Emit($E9); Jump:=CodeSize; EmitWord(0) end;

procedure PatchJump(P, Target: Word);
var I: Word;
begin
  PatchWord(P,Word(Longint(Target)-P-2));
  if CodeOwners[P]=0 then Exit;
  for I:=1 to RelativeCount do if RelativeFixups[I].Position=P then begin
    RelativeFixups[I].Target:=Target; Exit;
  end;
  if RelativeCount=MaxFixups then Unsupported('trop de references de code');
  Inc(RelativeCount); RelativeFixups[RelativeCount].Position:=P;
  RelativeFixups[RelativeCount].Target:=Target;
end;

procedure JumpTo(Target: Word);
var P: Word;
begin P:=Jump; PatchJump(P,Target) end;

function JumpZero: Word;
begin
  Emit2($09,$C0);             { or ax,ax }
  Emit2($75,$03);             { jnz +3: 8086 n'a pas Jcc near }
  JumpZero:=Jump;
end;

procedure CallTo(Target: Word);
var P: Word;
begin Emit($E8); P:=CodeSize; EmitWord(0); PatchJump(P,Target) end;

procedure LoadImmediate(W: Word);
begin Emit($B8); EmitWord(W) end;

procedure DataAddress(Offs: Word);
begin
  if FixupCount=MaxFixups then Unsupported('trop de references de donnees');
  Inc(FixupCount); Fixups[FixupCount].Position:=CodeSize;
  Fixups[FixupCount].DataOffset:=Offs; EmitWord(0);
end;

function AllocData(N: Word): Word;
var I: Word;
begin
  if Longint(DataSize)+N>MaxImage then Fail(49,'Segment de donnees trop grand');
  if N<>0 then for I:=DataSize to DataSize+N-1 do DataOwners[I]:=CurrentUnit;
  AllocData:=DataSize; Inc(DataSize,N);
end;

function StoreString(S: TShortString): Word;
var A: Word; I: Integer;
begin
  A:=AllocData(Length(S)+1); Data[A]:=Ord(S[0]);
  for I:=1 to Length(S) do Data[A+I]:=Ord(S[I]);
  StoreString:=A;
end;

function FindOwnSymbol(S: TShortString): Word;
var I: Word;
begin
  FindOwnSymbol:=0;
  for I:=1 to SymbolCount do
    if (Symbols[I].Name=S) and (Symbols[I].Owner=CurrentUnit) then
      FindOwnSymbol:=I;
end;

function FindSymbol(S: TShortString): Word;
var I: Word; J: Integer;
begin
  I:=FindOwnSymbol(S);
  if I<>0 then begin FindSymbol:=I; Exit end;
  FindSymbol:=0;
  for J:=ImportCount downto 1 do
    for I:=1 to SymbolCount do
      if (Symbols[I].Name=S) and Symbols[I].Exported and
        (Symbols[I].Owner=ImportOrder[J]) then begin FindSymbol:=I; Exit end;
end;

procedure AddImport(U: Byte);
var I, J: Byte;
begin
  { Ne pas reconstruire une unite deja compilee; sa priorite de recherche
    depend de la clause uses courante et non de l'ordre de compilation. }
  for I:=1 to ImportCount do if ImportOrder[I]=U then begin
    for J:=I to ImportCount-1 do ImportOrder[J]:=ImportOrder[J+1];
    Dec(ImportCount); Break;
  end;
  Inc(ImportCount); ImportOrder[ImportCount]:=U;
  Imports:=Imports+[U];
  if (CurrentUnit<>0) and (Units[U].Name<>'SYSTEM') then
    Units[CurrentUnit].Dependencies:=Units[CurrentUnit].Dependencies+[U];
end;

function FindBuildUnit(S: TShortString): Byte;
var I: Byte;
begin
  FindBuildUnit:=0;
  for I:=1 to UnitCount do if Units[I].Name=S then FindBuildUnit:=I;
end;

{ Le premier identificateur est deja consomme. Gere Unite.Symbole sans
  rendre accessibles les symboles prives ou les dependances transitives. }
function ResolveSymbol(Name: TShortString): Word;
var U: Byte; I: Word;
begin
  if Token<>tkDot then begin
    I:=FindSymbol(Name);
    if I=0 then Fail(3,'Identificateur inconnu: '+Name);
    if Symbols[I].Kind=skForeign then
      Unsupported('symbole Borland '+Units[Symbols[I].Owner].Name+'.'+Name+
        ': signature hors du sous-ensemble ABI');
    ResolveSymbol:=I; Exit;
  end;
  U:=FindBuildUnit(Name);
  if (U=0) or not ((U in Imports) or (U=CurrentUnit)) then
    Fail(3,'Unite inconnue: '+Name);
  NextToken;
  if Token<>tkIdent then Fail(2,'Identificateur qualifie attendu');
  I:=0;
  for I:=1 to SymbolCount do
    if (Symbols[I].Owner=U) and (Symbols[I].Name=TokenText) and
      (Symbols[I].Exported or (U=CurrentUnit)) then begin
      if Symbols[I].Kind=skForeign then
        Unsupported('symbole Borland '+Name+'.'+TokenText+
          ': signature hors du sous-ensemble ABI');
      ResolveSymbol:=I; NextToken; Exit;
    end;
  Fail(3,'Identificateur inconnu: '+Name+'.'+TokenText);
end;

function NewSymbol(S: TShortString): Word;
begin
  if FindOwnSymbol(S)<>0 then Fail(4,'Identificateur duplique: '+S);
  if SymbolCount=MaxSymbols then Fail(123,'Table des symboles pleine');
  Inc(SymbolCount); FillChar(Symbols[SymbolCount],SizeOf(TSymbol),0);
  Symbols[SymbolCount].Owner:=CurrentUnit;
  Symbols[SymbolCount].Exported:=InInterface;
  Symbols[SymbolCount].Name:=S; NewSymbol:=SymbolCount;
end;

procedure AddSegmentRelocation(P: Word; Kind: Byte);
begin
  if RelocationCount=MaxNativeRefs then Unsupported('trop de relocalisations MZ');
  Inc(RelocationCount); Relocations[RelocationCount].Offs:=P;
  Relocations[RelocationCount].Segm:=0; RelocationKinds[RelocationCount]:=Kind;
end;

procedure NativeReference(U, Kind: Byte; Map, Target: Word);
begin
  if NativeRefCount=MaxNativeRefs then Unsupported('trop de references Borland');
  Inc(NativeRefCount); NativeRefs[NativeRefCount].Position:=CodeSize;
  NativeRefs[NativeRefCount].U:=U; NativeRefs[NativeRefCount].Kind:=Kind;
  NativeRefs[NativeRefCount].Map:=Map; NativeRefs[NativeRefCount].Target:=Target;
  EmitWord(0);
end;

procedure NeedNative(U: Byte);
begin
  if CurrentUnit<>0 then Unsupported('pont ABI Borland dans une TPU de code locale');
  NativeNeeded:=True; ActivateNative(U);
end;

procedure SetNativeDS;
begin
  Emit($BA); AddSegmentRelocation(CodeSize,1); EmitWord(0);
  Emit2($8E,$DA); { mov ds,dx; preserve AX }
end;

procedure NativeVarAddress(I: Word);
var K: Byte;
begin
  K:=1; if Symbols[I].NativeConst then K:=2;
  NativeReference(Symbols[I].Owner,K,Symbols[I].NativeMap,Symbols[I].Addr);
end;

procedure LoadSymbol(I: Word);
begin
  if Symbols[I].Native and (Symbols[I].Kind=skVar) then begin
    NeedNative(Symbols[I].Owner); Emit($1E); SetNativeDS;
    if Symbols[I].Width=1 then Emit($A0) else Emit($A1);
    NativeVarAddress(I); Emit($1F);
    if Symbols[I].Width=1 then begin
      if Symbols[I].SignedByte then Emit($98) else Emit2($30,$E4);
    end;
  end else if Symbols[I].Kind=skConst then begin
    if Symbols[I].Typ=ttString then begin Emit($B8); DataAddress(Symbols[I].Addr) end
    else LoadImmediate(Word(Symbols[I].Value));
  end else if Symbols[I].Typ=ttString then begin
    Emit($B8); DataAddress(Symbols[I].Addr);
  end else if Symbols[I].Width=1 then begin
    Emit($A0); DataAddress(Symbols[I].Addr); Emit2($30,$E4);
  end else begin Emit($A1); DataAddress(Symbols[I].Addr) end;
end;

procedure SaveSymbol(I: Word);
begin
  if Symbols[I].Native then begin
    NeedNative(Symbols[I].Owner); Emit($1E); SetNativeDS;
    if Symbols[I].Width=1 then Emit($A2) else Emit($A3);
    NativeVarAddress(I); Emit($1F); Exit;
  end;
  if Symbols[I].Width=1 then Emit($A2) else Emit($A3);
  DataAddress(Symbols[I].Addr);
end;

function Expression: Byte; forward;
procedure Statement; forward;
function NativeCall(I: Word): Byte; forward;

procedure RequireInteger(T: Byte);
begin
  if T<>ttInteger then Fail(38,'Expression entiere attendue');
end;

procedure RequireBoolean(T: Byte);
begin
  if T<>ttBoolean then Fail(40,'Expression booleenne attendue');
end;

function Factor: Byte;
var T: Byte; I: Word; Name: TShortString;
begin
  T:=ttInteger;
  if Token=tkConstant then begin
    if TokenIsString then begin
      if Length(TokenText)=1 then begin T:=ttChar; LoadImmediate(Ord(TokenText[1])) end
      else begin T:=ttString; Emit($B8); DataAddress(StoreString(TokenText)) end;
    end else begin
      if TokenValue>65535 then Unsupported('constante Longint');
      LoadImmediate(Word(TokenValue));
    end;
    NextToken;
  end else if Token=tkLP then begin NextToken; T:=Expression; Need(tkRP) end
  else if Token=tkNot then begin
    NextToken; T:=Factor;
    if T=ttBoolean then begin Emit2($35,$01); Emit(0) end
    else begin RequireInteger(T); Emit2($F7,$D0) end;
  end else if Token=tkIdent then begin
    Name:=TokenText; NextToken;
    if (Token<>tkDot) and ((Name='TRUE') or (Name='FALSE')) then begin
      T:=ttBoolean; if Name='TRUE' then LoadImmediate(1) else LoadImmediate(0);
    end else if (Token<>tkDot) and ((Name='LENGTH') or (Name='ORD') or (Name='CHR') or
      (Name='ABS') or (Name='SQR') or (Name='SUCC') or (Name='PRED')) then begin
      Need(tkLP); T:=Expression; Need(tkRP);
      if Name='LENGTH' then begin
        if T=ttString then begin Emit2($89,$C3); Emit2($8A,$07); Emit2($30,$E4) end
        else if T=ttChar then LoadImmediate(1) else Fail(66,'Chaine attendue');
        T:=ttInteger;
      end else if Name='ORD' then begin
        if not (T in [ttInteger,ttBoolean,ttChar]) then Fail(26,'Type ordinal attendu');
        T:=ttInteger;
      end else if Name='CHR' then begin RequireInteger(T); Emit2($30,$E4); T:=ttChar end
      else begin
        RequireInteger(T);
        if Name='ABS' then begin Emit2($09,$C0); Emit2($79,$02); Emit2($F7,$D8) end;
        if Name='SQR' then Emit2($F7,$E8);
        if Name='SUCC' then Emit($40);
        if Name='PRED' then Emit($48);
      end;
    end else begin
      I:=ResolveSymbol(Name);
      if Symbols[I].Kind=skProc then begin
        if not Symbols[I].Native then Unsupported('fonction: '+Name);
        T:=NativeCall(I);
        if T=ttVoid then Fail(42,'Fonction attendue');
      end else begin T:=Symbols[I].Typ; LoadSymbol(I) end;
      if Token=tkLB then begin
        if T<>ttString then Unsupported('indexation non string');
        Emit($50); NextToken; RequireInteger(Expression); Need(tkRB);
        Emit($5B); Emit2($01,$C3); Emit2($8A,$07); Emit2($30,$E4); T:=ttChar;
      end;
    end;
  end else if Token=tkEOF then Fail(10,'Fin de fichier inattendue')
  else Unsupported('expression: '+TokenText);
  Factor:=T;
end;

function Term: Byte;
var T, R, Op: Byte; Skip: Word; ShortCircuit: Boolean;
begin
  T:=Factor;
  while Token in [tkTimes,tkSlash,tkDiv,tkMod,tkAnd,tkShl,tkShr] do begin
    Op:=Token;
    if Op=tkSlash then Unsupported('division reelle');
    ShortCircuit:=(Op=tkAnd) and (T=ttBoolean);
    if ShortCircuit then Skip:=JumpZero;
    Emit($50); NextToken; R:=Factor; Emit2($89,$C3); Emit($58);
    if Op=tkAnd then begin
      if (T<>R) or not (T in [ttInteger,ttBoolean]) then Fail(26,'Types incompatibles');
      Emit2($21,$D8);
    end else begin
      RequireInteger(T); RequireInteger(R);
      case Op of
        tkTimes:Emit2($F7,$EB);
        tkDiv,tkMod:begin
          Emit($99); Emit2($F7,$FB);
          if Op=tkMod then Emit2($89,$D0);
        end;
        tkShl,tkShr:begin
          Emit2($89,$D9);
          if Op=tkShl then Emit2($D3,$E0) else Emit2($D3,$E8);
        end;
      end;
    end;
    if ShortCircuit then PatchJump(Skip,CodeSize);
  end;
  Term:=T;
end;

function SimpleExpression: Byte;
var T,R,Op,Sign: Byte; Skip: Word; ShortCircuit: Boolean;
begin
  Sign:=0;
  if Token in [tkPlus,tkMinus] then begin Sign:=Token; NextToken end;
  T:=Term;
  if Sign<>0 then RequireInteger(T);
  if Sign=tkMinus then Emit2($F7,$D8);
  while Token in [tkPlus,tkMinus,tkOr,tkXor] do begin
    Op:=Token;
    ShortCircuit:=(Op=tkOr) and (T=ttBoolean);
    if ShortCircuit then begin
      Emit2($09,$C0); Emit2($74,$03); Skip:=Jump;
    end;
    Emit($50); NextToken; R:=Term;
    Emit2($89,$C3); Emit($58);
    if Op in [tkOr,tkXor] then begin
      if (T<>R) or not (T in [ttInteger,ttBoolean]) then Fail(26,'Types incompatibles');
      if Op=tkOr then Emit2($09,$D8) else Emit2($31,$D8);
    end else begin
      RequireInteger(T); RequireInteger(R);
      if Op=tkPlus then Emit2($01,$D8) else Emit2($29,$D8);
    end;
    if ShortCircuit then PatchJump(Skip,CodeSize);
  end;
  SimpleExpression:=T;
end;

function Expression: Byte;
var T,R,Op,Jcc: Byte;
begin
  T:=SimpleExpression;
  if Token in [tkEqual,tkNE,tkGreater,tkLess,tkGE,tkLE] then begin
    Op:=Token; Emit($50); NextToken; R:=SimpleExpression;
    if T<>R then Fail(26,'Comparaison de types incompatibles');
    if T=ttString then Unsupported('comparaison de chaines');
    Emit2($89,$C3); Emit($58); Emit2($39,$D8);
    Jcc:=$74;
    case Op of
      tkEqual:Jcc:=$74; tkNE:Jcc:=$75; tkGreater:Jcc:=$7F;
      tkLess:Jcc:=$7C; tkGE:Jcc:=$7D; tkLE:Jcc:=$7E;
    end;
    if T in [ttChar,ttBoolean] then case Op of
      tkGreater:Jcc:=$77; tkLess:Jcc:=$72; tkGE:Jcc:=$73; tkLE:Jcc:=$76;
    end;
    LoadImmediate(1); Emit2(Jcc,$02); Emit2($31,$C0); T:=ttBoolean;
  end;
  Expression:=T;
end;

function NativeCall(I: Word): Byte;
var J, V: Word; T: Byte; Name: TShortString;
begin
  NeedNative(Symbols[I].Owner);
  Emit($1E); Emit($06); Emit($55); { saves BELOW arguments, not between args and return }
  if Symbols[I].ParamCount<>0 then begin
    Need(tkLP);
    for J:=1 to Symbols[I].ParamCount do begin
      if J<>1 then Need(tkComma);
      if Symbols[I].ParamFlags[J]=6 then begin
        if Token<>tkIdent then Fail(20,'Parametre var attendu');
        Name:=TokenText; NextToken; V:=ResolveSymbol(Name);
        if (Symbols[V].Kind<>skVar) or (Symbols[V].Typ<>Symbols[I].ParamTypes[J]) or
          (Symbols[V].Width<>Symbols[I].ParamWidths[J]) or
          (Symbols[V].SignedByte<>Symbols[I].ParamSigned[J]) then Fail(26,'Type du parametre var');
        if Symbols[V].Native then begin
          NeedNative(Symbols[V].Owner);
          Emit($B8); AddSegmentRelocation(CodeSize,1); EmitWord(0); Emit($50);
          Emit($B8); NativeVarAddress(V); Emit($50);
        end else begin
          Emit($1E); Emit($B8); DataAddress(Symbols[V].Addr); Emit($50);
        end;
      end else begin
        T:=Expression;
        if T<>Symbols[I].ParamTypes[J] then Fail(26,'Type du parametre valeur');
        if Symbols[I].ParamWidths[J]=1 then begin
          if Symbols[I].ParamSigned[J] then Emit($98) else Emit2($30,$E4);
        end;
        Emit($50); { TP6 empile les scalaires courts dans un mot }
      end;
    end;
    Need(tkRP);
  end else if Token=tkLP then begin NextToken; Need(tkRP) end;
  SetNativeDS; Emit2($8E,$C2); { es=ds }
  Emit($9A); NativeReference(Symbols[I].Owner,3,Symbols[I].NativeMap,0);
  AddSegmentRelocation(CodeSize,0); EmitWord(0);
  Emit($5D); Emit($07); Emit($1F); { callee a retire les parametres avec retf N }
  if Symbols[I].Width=1 then begin
    if Symbols[I].SignedByte then Emit($98) else Emit2($30,$E4);
  end;
  NativeCall:=Symbols[I].Typ;
end;

procedure Assignment(I: Word);
var T: Byte; Indexed: Boolean;
begin
  if Symbols[I].Kind<>skVar then Fail(43,'Variable attendue');
  Indexed:=Token=tkLB;
  if Indexed then begin
    if Symbols[I].Typ<>ttString then Unsupported('affectation indexee non string');
    NextToken; RequireInteger(Expression); Need(tkRB); Emit($50);
  end;
  Need(tkAssign); T:=Expression;
  if Indexed then begin
    if T<>ttChar then Fail(106,'Caractere attendu');
    Emit($5B); Emit2($88,$87); DataAddress(Symbols[I].Addr);
  end else if Symbols[I].Typ=ttString then begin
    if T=ttChar then begin
      Emit($A2); DataAddress(Symbols[I].Addr+1);
      Emit2($C6,$06); DataAddress(Symbols[I].Addr); Emit(1);
    end else if T=ttString then begin
      Emit2($89,$C6); Emit($BF); DataAddress(Symbols[I].Addr);
      Emit($B9); EmitWord(Symbols[I].Capacity); CallTo(RuntimeCopy);
    end else Fail(26,'Chaine attendue');
  end else begin
    if T<>Symbols[I].Typ then Fail(26,'Types incompatibles');
    SaveSymbol(I);
  end;
end;

procedure WriteStatement(NewLine: Boolean);
var T: Byte;
begin
  if Token=tkLP then begin
    NextToken;
    repeat
      T:=Expression;
      if Token=tkColon then Unsupported('largeur de champ Write');
      case T of
        ttString:CallTo(RuntimeString);
        ttChar:CallTo(RuntimeChar);
        ttInteger:CallTo(RuntimeInteger);
        ttBoolean:CallTo(RuntimeBoolean);
      else Unsupported('type non imprimable');
      end;
      if Token<>tkComma then Break;
      NextToken;
    until False;
    Need(tkRP);
  end;
  if NewLine then begin
    LoadImmediate(13); CallTo(RuntimeChar); LoadImmediate(10); CallTo(RuntimeChar);
  end;
end;

procedure StatementList(Stop: Byte);
begin
  while Token<>Stop do begin
    if Token=tkEOF then Fail(10,'Fin de fichier inattendue');
    Statement;
    if Token=Stop then Break;
    Need(tkSemi);
  end;
end;

procedure Statement;
var I, Start, P, Q, Limit: Word; Direction, Ignored: Byte; Name, VarName: TShortString;
begin
  case Token of
    tkBegin:begin NextToken; StatementList(tkEnd); Need(tkEnd) end;
    tkIf:begin
      NextToken; RequireBoolean(Expression); Need(tkThen); P:=JumpZero;
      Statement;
      if Token=tkElse then begin
        Q:=Jump; PatchJump(P,CodeSize); NextToken; Statement; PatchJump(Q,CodeSize);
      end else PatchJump(P,CodeSize);
    end;
    tkWhile:begin
      NextToken; Start:=CodeSize; RequireBoolean(Expression); Need(tkDo);
      P:=JumpZero; Statement; JumpTo(Start); PatchJump(P,CodeSize);
    end;
    tkRepeat:begin
      NextToken; Start:=CodeSize; StatementList(tkUntil); Need(tkUntil);
      RequireBoolean(Expression); P:=JumpZero; PatchJump(P,Start);
    end;
    tkFor:begin
      NextToken;
      if Token<>tkIdent then Fail(2,'Variable de boucle attendue');
      Name:=TokenText; NextToken; I:=ResolveSymbol(Name);
      if (Symbols[I].Kind<>skVar) or (Symbols[I].Typ<>ttInteger) or
        (Symbols[I].Width<>2) then Unsupported('FOR non Integer');
      Need(tkAssign); RequireInteger(Expression); SaveSymbol(I);
      Direction:=Token;
      if not (Direction in [tkTo,tkDownto]) then Fail(58,'TO ou DOWNTO attendu');
      NextToken; RequireInteger(Expression);
      Limit:=AllocData(2); Emit($A3); DataAddress(Limit); Need(tkDo);
      Start:=CodeSize; LoadSymbol(I); Emit2($3B,$06); DataAddress(Limit);
      if Direction=tkTo then Emit2($7E,$03) else Emit2($7D,$03);
      P:=Jump; Statement;
      { Tester l'egalite AVANT inc/dec evite le debordement a +/-32768. }
      LoadSymbol(I); Emit2($3B,$06); DataAddress(Limit); Emit2($75,$03); Q:=Jump;
      if Direction=tkTo then Emit($40) else Emit($48);
      SaveSymbol(I); JumpTo(Start); PatchJump(P,CodeSize); PatchJump(Q,CodeSize);
    end;
    tkIdent:begin
      Name:=TokenText; NextToken;
      if (Token<>tkDot) and ((Name='WRITE') or (Name='WRITELN')) then WriteStatement(Name='WRITELN')
      else if (Token<>tkDot) and (Name='HALT') then begin
        if Token=tkLP then begin NextToken; RequireInteger(Expression); Need(tkRP) end
        else LoadImmediate(0);
        CallTo(RuntimeHalt);
      end else if (Token<>tkDot) and (Name='EXIT') then begin
        if not InProcedure then Unsupported('EXIT du programme principal');
        Emit($C3);
      end else if (Token<>tkDot) and ((Name='INC') or (Name='DEC')) then begin
        Need(tkLP);
        if Token<>tkIdent then Fail(2,'Variable attendue');
        VarName:=TokenText; NextToken; I:=ResolveSymbol(VarName);
        if (Symbols[I].Kind<>skVar) or (Symbols[I].Typ<>ttInteger) then
          Fail(38,'Variable entiere attendue');
        LoadSymbol(I);
        if Token=tkComma then begin
          Emit($50); NextToken; RequireInteger(Expression);
          Emit2($89,$C3); Emit($58);
          if Name='INC' then Emit2($01,$D8) else Emit2($29,$D8);
        end else if Name='INC' then Emit($40) else Emit($48);
        Need(tkRP); SaveSymbol(I);
      end else begin
        I:=ResolveSymbol(Name);
        if Symbols[I].Kind=skProc then begin
          if Symbols[I].Native then begin
            Ignored:=NativeCall(I);
            if Ignored<>ttVoid then Unsupported('resultat de fonction ignore sans $X+');
          end else begin
            if Token=tkLP then Unsupported('parametres de procedure');
            CallTo(Symbols[I].Addr);
          end;
        end else Assignment(I);
      end;
    end;
    tkSemi,tkEnd,tkElse,tkUntil:; { instruction vide }
    tkEOF:Fail(10,'Fin de fichier inattendue');
  else Unsupported('instruction: '+TokenText);
  end;
end;

procedure ConstDeclarations;
var I: Word; Sign: Integer;
begin
  NextToken;
  while Token=tkIdent do begin
    I:=NewSymbol(TokenText); Symbols[I].Kind:=skConst; NextToken; Need(tkEqual);
    Sign:=1;
    if Token in [tkPlus,tkMinus] then begin
      if Token=tkMinus then Sign:=-1; NextToken;
    end;
    if Token<>tkConstant then Unsupported('expression constante non litterale');
    if TokenIsString then begin
      if Sign<>1 then Fail(26,'Signe sur une chaine');
      if Length(TokenText)=1 then begin
        Symbols[I].Typ:=ttChar; Symbols[I].Value:=Ord(TokenText[1]);
      end else begin
        Symbols[I].Typ:=ttString; Symbols[I].StrValue:=TokenText;
        Symbols[I].Addr:=StoreString(TokenText);
      end;
    end else begin
      if ((Sign=1) and (TokenValue>32767)) or
        ((Sign=-1) and (TokenValue>32768)) then Unsupported('constante non Integer');
      Symbols[I].Typ:=ttInteger; Symbols[I].Value:=TokenValue*Sign;
    end;
    NextToken; Need(tkSemi);
  end;
end;

procedure VarDeclarations;
var First, Last, I: Word; T, Width, Capacity: Byte; S: TShortString;
begin
  NextToken;
  while Token=tkIdent do begin
    First:=SymbolCount+1;
    repeat
      if Token<>tkIdent then Fail(2,'Identificateur attendu');
      I:=NewSymbol(TokenText); Symbols[I].Kind:=skVar; NextToken;
      if Token<>tkComma then Break;
      NextToken;
    until False;
    Last:=SymbolCount; Need(tkColon); Capacity:=0;
    if Token=tkString then begin
      T:=ttString; Width:=0; Capacity:=255; NextToken;
      if Token=tkLB then begin
        NextToken;
        if (Token<>tkConstant) or TokenIsString then Fail(5,'Taille string attendue');
        if (TokenValue<1) or (TokenValue>255) then Fail(25,'Taille string hors limites');
        Capacity:=TokenValue; NextToken; Need(tkRB);
      end;
    end else begin
      S:=TokenText; Need(tkIdent); T:=ttInteger; Width:=2;
      if S='BYTE' then Width:=1
      else if S='BOOLEAN' then begin T:=ttBoolean; Width:=1 end
      else if S='CHAR' then begin T:=ttChar; Width:=1 end
      else if S<>'INTEGER' then Unsupported('type: '+S);
    end;
    for I:=First to Last do begin
      Symbols[I].Typ:=T; Symbols[I].Width:=Width; Symbols[I].Capacity:=Capacity;
      if T=ttString then Symbols[I].Addr:=AllocData(Word(Capacity)+1)
      else Symbols[I].Addr:=AllocData(Width);
    end;
    Need(tkSemi);
  end;
end;

procedure ProcedureDeclaration;
var I: Word;
begin
  if InProcedure then Unsupported('procedure imbriquee');
  NextToken;
  if Token<>tkIdent then Fail(2,'Nom de procedure attendu');
  I:=FindOwnSymbol(TokenText);
  if (I<>0) and not InInterface then begin
    if (Symbols[I].Kind<>skProc) or Symbols[I].HasBody then
      Fail(4,'Identificateur duplique: '+TokenText);
  end else begin
    I:=NewSymbol(TokenText); Symbols[I].Kind:=skProc; Symbols[I].Addr:=CodeSize;
  end;
  NextToken;
  if Token=tkLP then Unsupported('procedure a parametres');
  Need(tkSemi);
  if InInterface then begin
    { Point d'entree stable pour les appels avant la definition du corps. }
    Symbols[I].ForwardJump:=Jump; Exit;
  end;
  if Token<>tkBegin then Unsupported('declarations locales ou directives de procedure');
  if Symbols[I].Exported then PatchJump(Symbols[I].ForwardJump,CodeSize);
  Symbols[I].HasBody:=True;
  InProcedure:=True; Statement; Emit($C3); InProcedure:=False; Need(tkSemi);
end;

procedure DeclarationPart;
begin
  while Token in [tkConst,tkVar,tkProcedure] do case Token of
    tkConst:ConstDeclarations; tkVar:VarDeclarations;
    tkProcedure:ProcedureDeclaration;
  end;
  if Token in [tkType,tkFunction,tkLabel,tkConstructor,tkDestructor] then
    Unsupported('declaration: '+TokenText);
end;

procedure LoadSource; forward;
procedure UsesClause; forward;
procedure ImportLibrarySystem; forward;

procedure SaveParser(var P: PParserState);
begin
  New(P); New(P^.Buffer);
  Move(Source,P^.Buffer^,SourceSize);
  P^.SourceName:=SourceName; P^.SourceSize:=SourceSize; P^.SourcePos:=SourcePos;
  P^.Line:=Line; P^.Column:=Column;
  P^.TokenLine:=TokenLine; P^.TokenColumn:=TokenColumn;
  P^.Token:=Token; P^.TokenText:=TokenText; P^.TokenValue:=TokenValue;
  P^.TokenIsString:=TokenIsString; P^.Active:=Active;
  P^.InProcedure:=InProcedure; P^.InInterface:=InInterface;
  P^.CondDepth:=CondDepth; P^.CurrentUnit:=CurrentUnit; P^.Imports:=Imports;
  Move(ImportOrder,P^.ImportOrder,SizeOf(ImportOrder)); P^.ImportCount:=ImportCount;
  Move(Conditions,P^.Conditions,SizeOf(Conditions));
  Move(Defines,P^.Defines,SizeOf(Defines)); P^.DefineCount:=DefineCount;
  P^.OptionBits:=OptionBits; P^.StackSize:=StackSize;
  P^.MinHeap:=MinHeap; P^.MaxHeap:=MaxHeap;
end;

procedure RestoreParser(P: PParserState);
begin
  Move(P^.Buffer^,Source,P^.SourceSize);
  SourceName:=P^.SourceName; SourceSize:=P^.SourceSize; SourcePos:=P^.SourcePos;
  Line:=P^.Line; Column:=P^.Column;
  TokenLine:=P^.TokenLine; TokenColumn:=P^.TokenColumn;
  Token:=P^.Token; TokenText:=P^.TokenText; TokenValue:=P^.TokenValue;
  TokenIsString:=P^.TokenIsString; Active:=P^.Active;
  InProcedure:=P^.InProcedure; InInterface:=P^.InInterface;
  CondDepth:=P^.CondDepth; CurrentUnit:=P^.CurrentUnit; Imports:=P^.Imports;
  Move(P^.ImportOrder,ImportOrder,SizeOf(ImportOrder)); ImportCount:=P^.ImportCount;
  Move(P^.Conditions,Conditions,SizeOf(Conditions));
  Move(P^.Defines,Defines,SizeOf(Defines)); DefineCount:=P^.DefineCount;
  OptionBits:=P^.OptionBits; StackSize:=P^.StackSize;
  MinHeap:=P^.MinHeap; MaxHeap:=P^.MaxHeap;
  Dispose(P^.Buffer); Dispose(P);
end;

procedure CompileSourceUnit(U: Byte; Path: TShortString);
var P: PParserState; I: Word;
begin
  SaveParser(P);
  SourceName:=Path; CurrentUnit:=U; Imports:=[]; ImportCount:=0;
  Units[U].FromSource:=True; Units[U].Path:=Path;
  InInterface:=True; InProcedure:=False;
  { Les directives locales d'une unite ne fuient ni dans ses dependances
    ni dans le programme appelant. Les /D de la CLI restent disponibles. }
  Move(InitialDefines,Defines,SizeOf(Defines)); DefineCount:=InitialDefineCount;
  OptionBits:=InitialOptions;
  LoadSource;
  if not Quiet then WriteLn('Building unit ',Units[U].Name,': ',Path);
  ImportLibrarySystem;
  NextToken; Need(tkUnit);
  if Token<>tkIdent then Fail(2,'Nom d''unite attendu');
  if TokenText<>Units[U].Name then Fail(69,Units[U].Name+' <> '+TokenText);
  NextToken; Need(tkSemi); Need(tkInterface);
  UsesClause; DeclarationPart;
  Units[U].InterfaceReady:=True;
  Units[U].Checksum:=0; { calcule apres compilation; sources /B prioritaires }
  Need(tkImplementation); InInterface:=False;
  UsesClause; DeclarationPart;
  for I:=1 to SymbolCount do
    if (Symbols[I].Owner=U) and (Symbols[I].Kind=skProc) and
      not Symbols[I].HasBody then Fail(59,Symbols[I].Name);
  if Token=tkBegin then begin
    Units[U].HasInit:=True; Units[U].InitAddress:=CodeSize;
    { EXIT dans le bloc d'initialisation revient a l'appelant. }
    InProcedure:=True; Statement; InProcedure:=False; Emit($C3);
  end else Need(tkEnd);
  Need(tkDot);
  if Token<>tkEOF then Fail(10,'Texte apres END.');
  Units[U].State:=2;
  if Units[U].HasInit then begin Inc(InitCount); InitOrder[InitCount]:=U end;
  RestoreParser(P);
end;

procedure OpenBinaryRead(var F: file; var E: Integer);
var SavedMode: Byte;
begin
  SavedMode:=FileMode; FileMode:=0;
  {$I-} Reset(F,1); E:=IOResult; {$I+}
  FileMode:=SavedMode;
end;

function FileExists(S: TShortString): Boolean;
var F: file; E: Integer;
begin
  Assign(F,S); OpenBinaryRead(F,E);
  FileExists:=E=0;
  if E=0 then begin {$I-} Close(F); E:=IOResult; {$I+} end;
end;

function JoinPath(Dir, Name: TShortString): TShortString;
begin
  if (Dir<>'') and not (Dir[Length(Dir)] in ['\','/']) then Dir:=Dir+'\';
  if Length(Dir)+Length(Name)>255 then CLIError('Chemin trop long');
  JoinPath:=Dir+Name;
end;

function FindUnitPath(Name, Extension: TShortString): TShortString;
var D, MainDir: DirStr; N: NameStr; E: ExtStr;
    S, Part, Candidate: TShortString; P: Integer;
begin
  FindUnitPath:='';
  { TP6 consulte le repertoire de sortie avant les repertoires d'unites
    pour les TPU, mais PAS pour choisir le source a reconstruire. }
  if (Extension='.TPU') and (OutputDir<>'') then begin
    Candidate:=JoinPath(OutputDir,Name+Extension);
    if FileExists(Candidate) then begin FindUnitPath:=Candidate; Exit end;
  end;
  FSplit(SourceName,D,N,E); FSplit(MainSourceName,MainDir,N,E);
  if Length(D)+Length(MainDir)+Length(UnitDirs)+Length(TurboDirs)+5>255 then
    CLIError('Liste de recherche des unites trop longue');
  S:=D+';'+MainDir+';.;'+UnitDirs+';'+TurboDirs;
  repeat
    P:=Pos(';',S);
    if P=0 then begin Part:=S; S:='' end
    else begin Part:=Copy(S,1,P-1); Delete(S,1,P) end;
    Candidate:=JoinPath(Part,Name+Extension);
    if FileExists(Candidate) then begin FindUnitPath:=Candidate; Exit end;
  until S='';
end;

function Align16(N: Longint): Longint;
begin Align16:=(N+15) and not Longint(15) end;

function UnitFileSize(var H: TUnitHeader): Longint;
begin
  UnitFileSize:=Align16(H.EndTrace)+Align16(H.CodeSize)+Align16(H.ConstSize)+
    Align16(H.CodeFixupSize)+Align16(H.DataFixupSize);
end;

procedure ValidateUnitHeader(Name: TShortString; Limit: Longint; var H: TUnitHeader);
begin
  if (H.Signature[0]<>'T') or (H.Signature[1]<>'P') or
    (H.Signature[2]<>'U') or (H.Signature[3]<>'9') then
    Fail(72,'Signature TPU9 attendue: '+Name);
  if (H.EndTrace<SizeOf(H)) or (UnitFileSize(H)>Limit) or
    (H.Name<SizeOf(H)) or (H.Name>=H.EndTrace) or
    (H.Interf<SizeOf(H)) or (H.Interf>=H.EndTrace) then
    Fail(72,'En-tete TPU incoherent: '+Name);
end;

procedure ReadUnitHeaderAt(Name: TShortString; Base, Limit: Longint; var H: TUnitHeader);
var F: file; Count: Word; E: Integer; Size: Longint;
begin
  Assign(F,Name); OpenBinaryRead(F,E);
  if E<>0 then Fail(15,'Fichier introuvable: '+Name);
  {$I-} Size:=FileSize(F); E:=IOResult; {$I+}
  if (E<>0) or (Base<0) or (Base>Size-SizeOf(H)) then begin
    Close(F); Fail(72,'En-tete TPU/TPL hors fichier: '+Name);
  end;
  if Limit=0 then Limit:=Size-Base;
  if (Limit<SizeOf(H)) or (Limit>Size-Base) then begin
    Close(F); Fail(72,'Taille TPU/TPL incoherente: '+Name);
  end;
  {$I-} Seek(F,Base); BlockRead(F,H,SizeOf(H),Count); E:=IOResult;
  Close(F); if IOResult<>0 then E:=1; {$I+}
  if (E<>0) or (Count<>SizeOf(H)) then Fail(72,'Unite tronquee: '+Name);
  ValidateUnitHeader(Name,Limit,H);
end;

procedure ReadTPUHeader(Name: TShortString; var H: TUnitHeader);
begin ReadUnitHeaderAt(Name,0,0,H) end;

function FindLibraryUnit(Name: TShortString): Word;
var I: Word;
begin
  FindLibraryUnit:=0;
  for I:=1 to LibraryCount do if LibraryUnits[I].Name=Name then begin
    FindLibraryUnit:=I; Exit;
  end;
end;

procedure ReadLibrary(Name: TShortString);
var F: file; H: TUnitHeader; Base, Size, Span: Longint;
    Prefix: TSymbolPrefix; S: TShortString; Count: Word; E, I: Integer;
begin
  LibraryCount:=0; LibraryName:=Name;
  Assign(F,Name); OpenBinaryRead(F,E);
  if E<>0 then Fail(15,'Bibliotheque introuvable: '+Name);
  Size:=FileSize(F);
  if Size=0 then begin Close(F); Fail(72,'Bibliotheque TPL vide: '+Name) end;
  Base:=0;
  while Base<Size do begin
    if Size-Base<SizeOf(H) then Fail(72,'En-tete TPL tronque: '+Name);
    {$I-} Seek(F,Base); BlockRead(F,H,SizeOf(H),Count); E:=IOResult; {$I+}
    if (E<>0) or (Count<>SizeOf(H)) then Fail(72,'En-tete TPL illisible: '+Name);
    ValidateUnitHeader(Name,Size-Base,H); Span:=UnitFileSize(H);
    if (H.Interf>=H.ProcMap) or (H.ProcMap>H.CodeMap) or
      (H.CodeMap>H.ConstMap) or (H.ConstMap>H.DataMap) or
      (H.DataMap>H.EndMaps) or (H.EndMaps>H.Units) or
      (H.Units>H.Sources) or (H.Sources>H.Trace) or
      (H.Trace>H.EndTrace) or (H.Name+Longint(SizeOf(Prefix))>H.ProcMap) then
      Fail(72,'Sections TPL incoherentes: '+Name);
    {$I-} Seek(F,Base+H.Name); BlockRead(F,Prefix,SizeOf(Prefix),Count); E:=IOResult; {$I+}
    if (E<>0) or (Count<>SizeOf(Prefix)) or (Prefix.Typ<>89) or
      (Prefix.NameLength=0) or (Prefix.NameLength>63) or
      (H.Name+Longint(SizeOf(Prefix))+Prefix.NameLength+8>H.ProcMap) then
      Fail(72,'Nom d''unite TPL invalide: '+Name);
    S:=''; S[0]:=Chr(Prefix.NameLength);
    {$I-} BlockRead(F,S[1],Prefix.NameLength,Count); E:=IOResult; {$I+}
    if (E<>0) or (Count<>Prefix.NameLength) then Fail(72,'Nom TPL tronque');
    S:=Upper(S);
    for I:=1 to Length(S) do
      if not (S[I] in ['A'..'Z','_','0'..'9']) then Fail(72,'Identificateur TPL invalide');
    if S[1] in ['0'..'9'] then Fail(72,'Identificateur TPL invalide');
    if FindLibraryUnit(S)<>0 then Fail(72,'Unite TPL dupliquee: '+S);
    if LibraryCount=MaxLibraryUnits then Unsupported('plus de 256 unites TPL');
    Inc(LibraryCount); LibraryUnits[LibraryCount].Name:=S;
    LibraryUnits[LibraryCount].Offset:=Base; LibraryUnits[LibraryCount].Size:=Span;
    LibraryUnits[LibraryCount].Header:=H;
    Inc(Base,Span);
  end;
  {$I-} Close(F); E:=IOResult; {$I+}
  if E<>0 then Fail(72,'Erreur de lecture TPL');
end;

procedure FindAndReadLibrary;
var D: DirStr; N: NameStr; E: ExtStr; S, Part, Candidate: TShortString; P: Integer;
begin
  LibraryCount:=0; LibraryName:='';
  FSplit(FExpand(ParamStr(0)),D,N,E);
  if Length(TurboDirs)+Length(D)+4>255 then CLIError('Liste de recherche TPL trop longue');
  S:='.;'+TurboDirs+';'+D;
  repeat
    P:=Pos(';',S);
    if P=0 then begin Part:=S; S:='' end
    else begin Part:=Copy(S,1,P-1); Delete(S,1,P) end;
    if Part<>'' then begin
      Candidate:=JoinPath(Part,'TURBO.TPL');
      if FileExists(Candidate) then begin ReadLibrary(Candidate); Exit end;
    end;
  until S='';
end;

{ Profil TPU9/TPC1: conteneur TPU9 et structures historiques, mais ABI locale
  near/CS=DS. Reserved[0..2] = 'TP','C1',1 et Flags=$8000 l'identifient.
  Ces fichiers ne sont PAS annonces compatibles avec le linker Borland.
  Les fixups code $4000 sont relatifs IP, $8000 absolus DS; Map=$FFFF
  designe une routine du runtime local. Aucun pointeur hote sur disque. }
function LocalOffset(Target: Word; U: Byte; IsCode: Boolean): Word;
var I, N: Word;
begin
  N:=0;
  if Target<>0 then for I:=0 to Target-1 do begin
    if IsCode then begin if CodeOwners[I]=U then Inc(N) end
    else if DataOwners[I]=U then Inc(N);
  end;
  LocalOffset:=N;
end;

function GlobalOffset(Offset: Word; U: Byte; IsCode: Boolean): Word;
var I, N, Limit, Last: Word;
begin
  if IsCode then Limit:=CodeSize else Limit:=DataSize;
  N:=0; Last:=0;
  if Limit<>0 then for I:=0 to Limit-1 do begin
    if (IsCode and (CodeOwners[I]=U)) or (not IsCode and (DataOwners[I]=U)) then begin
      if N=Offset then begin GlobalOffset:=I; Exit end;
      Inc(N); Last:=I+1;
    end;
  end;
  if IsCode and (N<>0) and (N=Offset) then begin GlobalOffset:=Last; Exit end;
  Fail(72,'Offset hors section d''unite'); GlobalOffset:=0;
end;

function InterfaceChecksum(U: Byte): Word;
var I, K, N, Temp: Word; J: Integer; H: Word;
  Order: array[1..MaxSymbols] of Word;
  procedure Mix(W: Word);
  begin H:=((H shl 1) or (H shr 15))+W end;
begin
  H:=0; N:=0;
  for I:=1 to SymbolCount do if (Symbols[I].Owner=U) and Symbols[I].Exported then begin
    Inc(N); Order[N]:=I;
  end;
  for I:=2 to N do begin
    K:=I;
    while K>1 do begin
      if Symbols[Order[K-1]].Name<Symbols[Order[K]].Name then Break;
      Temp:=Order[K-1]; Order[K-1]:=Order[K]; Order[K]:=Temp; Dec(K);
    end;
  end;
  for K:=1 to N do begin
    I:=Order[K];
    for J:=1 to Length(Symbols[I].Name) do Mix(Ord(Symbols[I].Name[J]));
    Mix(Symbols[I].Kind); Mix(Symbols[I].Typ);
    if Symbols[I].Kind=skConst then begin Mix(0); Mix(0) end
    else begin Mix(Symbols[I].Width); Mix(Symbols[I].Capacity) end;
    if Symbols[I].Kind=skConst then begin
      Mix(Word(Symbols[I].Value));
      for J:=0 to Length(Symbols[I].StrValue) do Mix(Ord(Symbols[I].StrValue[J]));
    end;
  end;
  if H=0 then H:=$FFFF;
  InterfaceChecksum:=H;
end;

function RuntimeNumber(Target: Word): Word;
begin
  if Target=RuntimeString then RuntimeNumber:=216
  else if Target=RuntimeInteger then RuntimeNumber:=220
  else if Target=RuntimeBoolean then RuntimeNumber:=224
  else if Target=RuntimeChar then RuntimeNumber:=228
  else if Target=RuntimeCopy then RuntimeNumber:=48
  else if Target=RuntimeHalt then RuntimeNumber:=12
  else begin Unsupported('reference de code hors unite'); RuntimeNumber:=0 end;
end;

function RuntimeAddress(N: Word): Word;
begin
  case N of
    216:RuntimeAddress:=RuntimeString; 220:RuntimeAddress:=RuntimeInteger;
    224:RuntimeAddress:=RuntimeBoolean; 228:RuntimeAddress:=RuntimeChar;
    48:RuntimeAddress:=RuntimeCopy;
    12:RuntimeAddress:=RuntimeHalt;
  else begin Unsupported('routine du runtime TPU'); RuntimeAddress:=0 end;
  end;
end;

procedure WriteCompiledUnit(U: Byte);
var B: PBinaryBuffer; H: TUnitHeader; F: file;
    Posn, I, A, TypAddr, Bucket, CheckPos, CodeLen, DataLen: Word;
    FixLen, InitEntry, PayloadCheck: Word; V, TargetOwner: Byte;
    Refs: array[0..MaxUnits] of Word;
    Stubs: array[0..MaxUnits] of Word;
    MapStubs: array[1..MaxSymbols] of Word;
    FilePos, CodeStart, DataStart, RelStart: Longint;
    Count: Longint; E: Integer; Path: TShortString;
    D: DirStr; N: NameStr; Ext: ExtStr;
    NativeConstants: Boolean;
  procedure PutByte(X: Byte);
  begin
    if Posn>=MaxImage then Fail(123,'Dictionnaire TPU trop grand');
    B^[Posn]:=X; Inc(Posn);
  end;
  procedure PutWord(X: Word);
  begin PutByte(X and 255); PutByte(X shr 8) end;
  procedure SetWord(P, X: Word);
  begin B^[P]:=X and 255; B^[P+1]:=X shr 8 end;
  function GetWord(P: Word): Word;
  begin GetWord:=B^[P]+Word(B^[P+1])*256 end;
  procedure PutString(S: TShortString);
  var K: Integer;
  begin PutByte(Length(S)); for K:=1 to Length(S) do PutByte(Ord(S[K])) end;
  function SymbolEntry(S: TShortString; Kind: Byte): Word;
  var P: Word;
  begin
    P:=Posn; Bucket:=H.Interf+2+(HashIdent(S) and 126);
    PutWord(GetWord(Bucket)); SetWord(Bucket,P);
    PutByte(Kind); PutString(S); SymbolEntry:=P;
  end;
  procedure UnitEntry(V: Byte; S: TShortString; Check: Word);
  var Prev, P: Word;
  begin
    Prev:=Stubs[U];
    if V<>U then begin
      Prev:=H.Name;
      while GetWord(Prev+4+B^[Prev+3]+4)<>0 do
        Prev:=GetWord(Prev+4+B^[Prev+3]+4);
    end;
    A:=SymbolEntry(S,89); Stubs[V]:=A;
    PutWord(0); PutWord(Check); PutWord(0); PutWord(0);
    if V<>U then begin P:=Prev+4+B^[Prev+3]; SetWord(P+4,A) end;
  end;
  procedure Reloc(Position, Target: Word; IsData: Boolean);
  var Flags, Number: Word;
  begin
    if IsData then begin
      TargetOwner:=DataOwners[Target]; Flags:=$8000;
      Number:=LocalOffset(Target,TargetOwner,False);
    end else begin
      { Un saut vers la fin du corps peut viser le premier octet suivant. }
      if Target<CodeSize then TargetOwner:=CodeOwners[Target] else TargetOwner:=U;
      Flags:=$4000;
      Number:=LocalOffset(Target,TargetOwner,True);
      if Image[Position-1]=$E9 then begin
        TargetOwner:=U; Number:=LocalOffset(Target,U,True);
      end;
    end;
    if (TargetOwner<>U) and (TargetOwner<>0) and
      not (TargetOwner in Units[U].Dependencies) then
      Unsupported('reference TPU vers une unite non declaree');
    SetWord(Posn,Flags or Refs[TargetOwner]); Inc(Posn,2);
    if not IsData and (TargetOwner=0) then begin
      SetWord(Posn,$FFFF); Inc(Posn,2);
      SetWord(Posn,RuntimeNumber(Target)); Inc(Posn,2);
    end else begin
      SetWord(Posn,0); Inc(Posn,2); SetWord(Posn,Number); Inc(Posn,2);
    end;
    SetWord(Posn,LocalOffset(Position,U,True)); Inc(Posn,2);
  end;
begin
  { Cas natif sans code ni dependance utilisateur: les constantes utilisent
    directement les types SYSTEM historiques. La compatibilite du layout
    est testee; une validation avec le linker Borland reste necessaire. }
  NativeConstants:=UnitOutput and (U=1) and
    not Units[U].HasInit and (Units[U].Dependencies=[]);
  for I:=1 to SymbolCount do if (Symbols[I].Owner=U) and
    (Symbols[I].Kind<>skConst) then NativeConstants:=False;
  New(B); FillChar(B^,SizeOf(TBinaryBuffer),0); FillChar(H,SizeOf(H),0);
  FillChar(MapStubs,SizeOf(MapStubs),0); FillChar(Refs,SizeOf(Refs),0);
  FillChar(Stubs,SizeOf(Stubs),0);
  H.Signature[0]:='T'; H.Signature[1]:='P'; H.Signature[2]:='U'; H.Signature[3]:='9';
  H.Flags:=$8000; H.Reserved[0]:=$5054; H.Reserved[1]:=$3143; H.Reserved[2]:=1;
  Units[U].Checksum:=InterfaceChecksum(U);
  Posn:=80; H.Interf:=Posn; PutWord(126);
  for I:=1 to 64 do PutWord(0);
  H.Name:=Posn;
  if NativeConstants then UnitEntry(U,Units[U].Name,0)
  else UnitEntry(U,Units[U].Name,Units[U].Checksum);
  CheckPos:=H.Name+4+Length(Units[U].Name)+2;
  UnitEntry(0,'SYSTEM',0);
  for V:=1 to UnitCount do if V in Units[U].Dependencies then
    UnitEntry(V,Units[V].Name,Units[V].Checksum);
  { Types locaux: la partie segment reference le symbole d'unite. }
  for I:=1 to SymbolCount do if (Symbols[I].Owner=U) and Symbols[I].Exported then begin
    TypAddr:=Posn; PutByte(Symbols[I].Typ);
    if Symbols[I].Typ=ttInteger then begin
      if Symbols[I].Width=1 then PutByte(2) else PutByte(5);
    end else PutByte(0);
    if (Symbols[I].Typ=ttString) and (Symbols[I].Kind=skConst) then PutWord(256)
    else if Symbols[I].Typ=ttString then PutWord(Word(Symbols[I].Capacity)+1)
    else if Symbols[I].Kind=skConst then begin
      if Symbols[I].Typ=ttInteger then PutWord(2) else PutWord(1);
    end else PutWord(Symbols[I].Width);
    PutWord(0);
    if Symbols[I].Typ=ttInteger then begin
      if Symbols[I].Width=1 then begin PutWord(0); PutWord(0); PutWord(255); PutWord(0) end
      else begin PutWord($8000); PutWord($FFFF); PutWord($7FFF); PutWord(0) end;
      PutWord(TypAddr); PutWord(H.Name+4+Length(Units[U].Name));
    end;
    case Symbols[I].Kind of
      skConst:begin
        A:=SymbolEntry(Symbols[I].Name,80);
        if NativeConstants then begin
          case Symbols[I].Typ of
            ttInteger:PutWord($114); ttChar:PutWord($14C);
            ttBoolean:PutWord($130); ttString:PutWord($A0);
          end;
          PutWord(Stubs[0]+4+6);
        end else begin
          PutWord(TypAddr); PutWord(H.Name+4+Length(Units[U].Name));
        end;
        if Symbols[I].Typ=ttString then PutString(Symbols[I].StrValue)
        else begin
          PutWord(Word(Symbols[I].Value));
          if Symbols[I].Value<0 then PutWord($FFFF) else PutWord(0);
        end;
      end;
      skVar:begin
        A:=SymbolEntry(Symbols[I].Name,82); PutByte(0);
        PutWord(LocalOffset(Symbols[I].Addr,U,False)); PutWord(0);
        PutWord(TypAddr); PutWord(H.Name+4+Length(Units[U].Name));
      end;
      skProc:begin
        A:=SymbolEntry(Symbols[I].Name,83); MapStubs[I]:=A+4+Length(Symbols[I].Name);
        PutByte(0); PutByte(0); PutWord(0); PutWord(0); PutWord(0); PutWord(0);
        PutByte(ttProc); PutByte(0); PutWord(0); PutWord(0);
        PutWord(0); PutWord(0); PutWord(0);
      end;
    end;
  end;
  if Odd(Posn) then PutByte(0);
  if NativeConstants then begin
    PayloadCheck:=0; I:=H.Interf;
    while I+1<Posn do begin
      PayloadCheck:=((PayloadCheck shl 1) or (PayloadCheck shr 15))+GetWord(I);
      Inc(I,2);
    end;
    if PayloadCheck=0 then PayloadCheck:=$FFFF;
    SetWord(CheckPos,PayloadCheck); Units[U].Checksum:=PayloadCheck;
  end;
  H.ProcMap:=Posn;
  InitEntry:=$FFFF;
  if Units[U].HasInit then InitEntry:=LocalOffset(Units[U].InitAddress,U,True);
  PutWord(0); PutWord(0);
  if NativeConstants then begin PutWord($FFFF); PutWord(0) end
  else begin PutWord(0); PutWord(InitEntry) end;
  for I:=1 to SymbolCount do if MapStubs[I]<>0 then begin
    SetWord(MapStubs[I]+2,Posn-H.ProcMap);
    PutWord(MapStubs[I]); PutWord(0); PutWord(0);
    PutWord(LocalOffset(Symbols[I].Addr,U,True));
  end;
  CodeLen:=LocalOffset(CodeSize,U,True); DataLen:=LocalOffset(DataSize,U,False);
  if NativeConstants then begin CodeLen:=0; DataLen:=0 end;
  FixLen:=0;
  for I:=1 to FixupCount do if CodeOwners[Fixups[I].Position]=U then begin
    if FixLen>MaxImage-8 then Unsupported('trop de fixups dans une unite');
    Inc(FixLen,8);
  end;
  for I:=1 to RelativeCount do if CodeOwners[RelativeFixups[I].Position]=U then begin
    if FixLen>MaxImage-8 then Unsupported('trop de fixups dans une unite');
    Inc(FixLen,8);
  end;
  if Longint(Posn)+FixLen+1024>MaxImage then Unsupported('dictionnaire et fixups TPU trop grands');
  H.CodeMap:=Posn;
  if not NativeConstants then begin PutWord(0); PutWord(CodeLen); PutWord(FixLen); PutWord(0) end;
  H.ConstMap:=Posn;
  if not NativeConstants then begin PutWord(0); PutWord(DataLen); PutWord(0); PutWord(0) end;
  H.DataMap:=Posn; H.EndMaps:=Posn; H.Units:=Posn;
  Refs[U]:=0; PutWord(0); PutString(Units[U].Name);
  Refs[0]:=Posn-H.Units; PutWord(0); PutString('SYSTEM');
  for V:=1 to UnitCount do if V in Units[U].Dependencies then begin
    Refs[V]:=Posn-H.Units; PutWord(0); PutString(Units[V].Name);
  end;
  H.Sources:=Posn; H.Trace:=Posn; H.EndTrace:=Posn; H.DebugHash:=H.Interf;
  H.CodeSize:=CodeLen; H.ConstSize:=DataLen; H.CodeFixupSize:=FixLen;
  H.Reserved[3]:=CheckPos; { profil: emplacement du checksum d'interface }
  if NativeConstants then begin
    H.Flags:=0; FillChar(H.Reserved,SizeOf(H.Reserved),0);
  end;
  CodeStart:=Align16(Posn); FilePos:=CodeStart;
  for I:=0 to CodeSize-1 do if CodeOwners[I]=U then begin B^[FilePos]:=Image[I]; Inc(FilePos) end;
  DataStart:=CodeStart+Align16(CodeLen); FilePos:=DataStart;
  if not NativeConstants then
    for I:=0 to DataSize-1 do if DataOwners[I]=U then begin B^[FilePos]:=Data[I]; Inc(FilePos) end;
  RelStart:=DataStart+Align16(DataLen);
  { Les fixups sont apres les deux sections; reutiliser un curseur Word
    uniquement dans une zone temporaire puis copier vers le fichier. }
  Posn:=H.EndTrace;
  for I:=1 to FixupCount do if CodeOwners[Fixups[I].Position]=U then
    Reloc(Fixups[I].Position,Fixups[I].DataOffset,True);
  for I:=1 to RelativeCount do if CodeOwners[RelativeFixups[I].Position]=U then
    Reloc(RelativeFixups[I].Position,RelativeFixups[I].Target,False);
  Move(B^[H.EndTrace],B^[RelStart],FixLen);
  { Effacer seulement la zone entre dictionnaire et code: elle avait servi
    de temporaire et peut recouvrir le code. Celui-ci est reconstitue. }
  FilePos:=CodeStart;
  for I:=0 to CodeSize-1 do if CodeOwners[I]=U then begin B^[FilePos]:=Image[I]; Inc(FilePos) end;
  FilePos:=DataStart;
  if not NativeConstants then
    for I:=0 to DataSize-1 do if DataOwners[I]=U then begin B^[FilePos]:=Data[I]; Inc(FilePos) end;
  FilePos:=RelStart+Align16(FixLen); PayloadCheck:=0;
  for CodeStart:=80 to FilePos-1 do
    PayloadCheck:=((PayloadCheck shl 1) or (PayloadCheck shr 15))+B^[CodeStart];
  if not NativeConstants then H.Reserved[4]:=PayloadCheck;
  Move(H,B^,SizeOf(H));
  FSplit(Units[U].Path,D,N,Ext);
  if OutputDir='' then Path:=D+Units[U].Name+'.TPU'
  else Path:=JoinPath(OutputDir,Units[U].Name+'.TPU');
  Assign(F,Path); {$I-} Rewrite(F,1); E:=IOResult; {$I+}
  if E<>0 then begin Dispose(B); Fail(16,'Creation TPU impossible: '+Path) end;
  FilePos:=RelStart+Align16(FixLen);
  {$I-} BlockWrite(F,B^,FilePos,Count); E:=IOResult; Close(F);
  if IOResult<>0 then E:=1;
  if (E<>0) or (Count<>FilePos) then begin Erase(F); E:=IOResult; E:=1 end;
  {$I+}
  Dispose(B);
  if E<>0 then Fail(16,'Ecriture TPU impossible: '+Path);
  if not Quiet then begin
    if NativeConstants then WriteLn('TPU9 constantes (sans code): ',Path)
    else WriteLn('TPU9/TPC1: ',Path);
  end;
end;

procedure WriteUnits;
var U, V: Byte;
begin
  { Checksums connus avant l'ecriture pour les cycles d'implementation. }
  for U:=1 to UnitCount do if Units[U].FromSource then
    Units[U].Checksum:=InterfaceChecksum(U);
  for U:=1 to UnitCount do for V:=1 to UnitCount do
    if (Units[U].DependencyChecks[V]<>0) and
      (Units[U].DependencyChecks[V]<>Units[V].Checksum) then
      Fail(70,Units[U].Name+' / '+Units[V].Name);
  for U:=1 to UnitCount do if Units[U].FromSource then WriteCompiledUnit(U);
end;

procedure LoadCompiledUnit(U: Byte; Path: TShortString); forward;
procedure RequireUnit(Name: TShortString; var U: Byte);
var Path: TShortString; Entry: Word;
begin
  U:=FindBuildUnit(Name);
  if U<>0 then begin
    if (U=CurrentUnit) or ((Units[U].State=1) and not Units[U].InterfaceReady) then
      Fail(68,Name);
    Exit;
  end;
  if UnitCount=MaxUnits then Unsupported('plus de 64 unites');
  Entry:=FindLibraryUnit(Name);
  Path:=''; if (Entry=0) and BuildMode then Path:=FindUnitPath(Name,'.PAS');
  Inc(UnitCount); U:=UnitCount; FillChar(Units[U],SizeOf(TBuildUnit),0);
  Units[U].Name:=Name; Units[U].State:=1;
  Units[U].LibraryEntry:=Entry;
  if Entry<>0 then LoadCompiledUnit(U,LibraryName)
  else if Path<>'' then CompileSourceUnit(U,Path)
  else begin
    Path:=FindUnitPath(Name,'.TPU');
    if Path='' then Fail(15,'Fichier introuvable: '+Name+'.TPU');
    LoadCompiledUnit(U,Path);
  end;
end;

procedure LoadCompiledUnit(U: Byte; Path: TShortString);
var B: PBinaryBuffer; H: TUnitHeader; F: file; P: PParserState;
  Size, Base, Count, CodeStart, DataStart, RelStart, X: Longint;
    A, Stub, I, J, Bucket, Next, Steps, W, R, Map, Target: Word;
    ParamN, K: Word;
    MapSum, FixSum: Longint;
    V, Typ, Width, Capacity, Kind: Byte;
    IsLocal, ProjectForeign, TypeSupported, TypeSigned: Boolean; Name: TShortString;
    RefOffsets, RefChecks: array[0..MaxUnits+1] of Word;
    RefUnits: array[0..MaxUnits+1] of Byte;
    RefCount: Integer; E: Integer; Value: Longint;
  procedure Bounds(P, N: Longint);
  begin
    if (P<0) or (N<0) or (P>Size-N) then Fail(72,'Reference TPU hors fichier');
  end;
  procedure DictBounds(P, N: Longint);
  begin
    Bounds(P,N);
    if (P<80) or (P+N>H.ProcMap) then Fail(72,'Reference hors dictionnaire TPU');
  end;
  function ReadWord(P: Longint): Word;
  begin Bounds(P,2); ReadWord:=B^[P]+Word(B^[P+1])*256 end;
  function ReadString(P: Longint): TShortString;
  var K: Integer; S: TShortString;
  begin
    Bounds(P,1); Bounds(P+1,B^[P]); S:='';
    for K:=1 to B^[P] do S:=S+Chr(B^[P+K]);
    ReadString:=S;
  end;
  function SymbolStub(P: Word): Word;
  begin
    DictBounds(P,4); DictBounds(P,4+B^[P+3]);
    if (B^[P+3]=0) or (B^[P+3]>63) then Fail(72,'Nom de symbole TPU invalide');
    SymbolStub:=P+4+B^[P+3];
  end;
  function CheckForUnit(S: TShortString): Word;
  var K, Addr, Limit: Word;
  begin
    CheckForUnit:=0;
    for K:=0 to ReadWord(H.Interf) div 2 do begin
      Addr:=ReadWord(H.Interf+2+K*2); Limit:=0;
      while Addr<>0 do begin
        Inc(Limit); if Limit>MaxSymbols then Fail(72,'Cycle dans le hash TPU');
        W:=SymbolStub(Addr);
        if (Upper(ReadString(Addr+3))=S) and (B^[Addr+2]=89) then begin
          DictBounds(W,8);
          CheckForUnit:=ReadWord(W+2); Exit;
        end;
        DictBounds(Addr,4); Addr:=ReadWord(Addr);
      end;
    end;
  end;
  procedure DecodeType(P: Word);
  var T, S, Addr, StubAddr, Limit: Word; UnitName: TShortString;
    procedure Reject(S: TShortString);
    begin
      if ProjectForeign then TypeSupported:=False else Unsupported(S);
    end;
  begin
    TypeSupported:=True; TypeSigned:=False;
    DictBounds(P,4); T:=ReadWord(P); S:=ReadWord(P+2);
    Width:=0; Capacity:=0;
    if S=SymbolStub(H.Name) then begin
      DictBounds(T,6); Typ:=B^[T]; W:=ReadWord(T+2);
      TypeSigned:=(Typ=ttInteger) and (B^[T+1] and 1<>0);
      if (Typ<>ttString) and (W>4) then begin Reject('taille de type TPU'); Exit end;
      Width:=W;
      if Typ=ttString then begin
        W:=ReadWord(T+2);
        if (W<2) or (W>256) then Fail(72,'Type string TPU invalide');
        Capacity:=W-1; Width:=0;
      end;
      if (Typ=ttInteger) and not (Width in [1,2]) and
        not ((Kind=80) and (Width=4) and not IsLocal) then
        begin Reject('type entier TPU > 16 bits'); Exit end;
    end else begin
      { Les pointeurs disque originaux referencent un symbole d'unite,
        pas un segment hote. Types SYSTEM standards dans COMPILER.INC. }
      Addr:=H.Name; Limit:=0; UnitName:='';
      while Addr<>0 do begin
        Inc(Limit); if Limit>MaxUnits+2 then Fail(72,'Cycle des stubs d''unites TPU');
        StubAddr:=SymbolStub(Addr); DictBounds(StubAddr,8);
        if S=StubAddr then begin UnitName:=Upper(ReadString(Addr+3)); Break end;
        Addr:=ReadWord(StubAddr+4);
      end;
      if UnitName='' then Fail(72,'Segment du type TPU invalide');
      if UnitName<>'SYSTEM' then begin Reject('type d''une autre unite TPU'); Exit end;
      case T of
        $A0:begin Typ:=ttString; Capacity:=255 end;
        $DE:begin Typ:=ttInteger; Width:=1 end;
        $F0:begin Typ:=ttInteger; Width:=2 end;
        $102:begin Typ:=ttInteger; Width:=2 end;
        $114:begin Typ:=ttInteger; Width:=4 end;
        $130:begin Typ:=ttBoolean; Width:=1 end;
        $14C:begin Typ:=ttChar; Width:=1 end;
      else begin Reject('type SYSTEM non pris en charge dans la TPU'); Exit end;
      end;
    end;
    if not (Typ in [ttString,ttInteger,ttBoolean,ttChar]) then begin
      Reject('type TPU non pris en charge'); Exit;
    end;
    if (Typ in [ttChar,ttBoolean]) and (Width<>1) then Fail(72,'Taille ordinale TPU invalide');
  end;
begin
  Base:=0; Size:=0;
  if Units[U].LibraryEntry<>0 then begin
    Base:=LibraryUnits[Units[U].LibraryEntry].Offset;
    Size:=LibraryUnits[Units[U].LibraryEntry].Size;
  end;
  ReadUnitHeaderAt(Path,Base,Size,H);
  SaveParser(P); CurrentUnit:=U; SourceName:=Path;
  TokenLine:=1; TokenColumn:=1; InInterface:=True; Imports:=[]; ImportCount:=0;
  Units[U].Path:=Path;
  Assign(F,Path); OpenBinaryRead(F,E);
  if E<>0 then Fail(15,Path);
  if Units[U].LibraryEntry=0 then Size:=FileSize(F);
  if (Size<80) or (Size>SizeOf(TBinaryBuffer)) then begin Close(F); Fail(72,'Taille TPU invalide') end;
  New(B);
  {$I-} Seek(F,Base); BlockRead(F,B^,Size,Count); E:=IOResult; Close(F);
  if IOResult<>0 then E:=1; {$I+}
  if (E<>0) or (Count<>Size) then Fail(72,'Lecture TPU incomplete');
  if (H.Interf>=H.ProcMap) or (H.ProcMap>H.CodeMap) or
    (H.CodeMap>H.ConstMap) or (H.ConstMap>H.DataMap) or
    (H.DataMap>H.EndMaps) or (H.EndMaps>H.Units) or
    (H.Units>H.Sources) or (H.Sources>H.EndTrace) then
    Fail(72,'Ordre des sections TPU invalide');
  A:=SymbolStub(H.Name); DictBounds(A,8);
  if B^[H.Name+2]<>89 then Fail(72,'Symbole de nom TPU invalide');
  Name:=Upper(ReadString(H.Name+3));
  if Name<>Units[U].Name then Fail(69,Name+' <> '+Units[U].Name);
  Units[U].Checksum:=ReadWord(A+2);
  IsLocal:=(H.Flags=$8000) and (H.Reserved[0]=$5054) and (H.Reserved[1]=$3143);
  ProjectForeign:=not IsLocal;
  if IsLocal and (H.Reserved[2]<>1) then Fail(72,'Version du profil TPC1 inconnue');
  if IsLocal then begin
    W:=0;
    for X:=80 to Size-1 do W:=((W shl 1) or (W shr 15))+B^[X];
    if W<>H.Reserved[4] then Fail(72,'Integrite de la TPU TPC1 invalide');
  end;
  if not IsLocal then begin
    if ((H.CodeMap-H.ProcMap) mod 8<>0) or
      ((H.ConstMap-H.CodeMap) mod 8<>0) or ((H.DataMap-H.ConstMap) mod 8<>0) or
      ((H.EndMaps-H.DataMap) mod 8<>0) then Fail(72,'Cartes natives TPU invalides');
    MapSum:=0; FixSum:=0; X:=H.CodeMap;
    while X<H.ConstMap do begin
      if Longint(MapSum)+ReadWord(X+2)>65535 then Fail(72,'Code natif trop grand');
      Inc(MapSum,ReadWord(X+2)); Inc(FixSum,ReadWord(X+4)); Inc(X,8);
    end;
    if (MapSum<>H.CodeSize) or (FixSum<>H.CodeFixupSize) then Fail(72,'Tailles code natif incoherentes');
    MapSum:=0; FixSum:=0; X:=H.ConstMap;
    while X<H.DataMap do begin
      Inc(MapSum,ReadWord(X+2)); Inc(FixSum,ReadWord(X+4)); Inc(X,8);
    end;
    if (MapSum<>H.ConstSize) or (FixSum<>H.DataFixupSize) then Fail(72,'Tailles constantes natives incoherentes');
    MapSum:=0; X:=H.DataMap;
    while X<H.EndMaps do begin Inc(MapSum,ReadWord(X+2)); Inc(X,8) end;
    if MapSum<>H.DataSize then Fail(72,'Taille donnees natives incoherente');
    NativeBuffers[U]:=B; NativeHeaders[U]:=H;
  end;
  CodeStart:=Align16(H.EndTrace); DataStart:=CodeStart+Align16(H.CodeSize);
  RelStart:=DataStart+Align16(H.ConstSize);
  Units[U].CodeBase:=CodeSize; Units[U].DataBase:=DataSize;
  if IsLocal then begin
    if (H.ConstMap-H.CodeMap<>8) or (H.DataMap-H.ConstMap<>8) or
      (H.EndMaps<>H.DataMap) or (H.DataSize<>0) or (H.DataFixupSize<>0) or
      ((H.CodeMap-H.ProcMap) mod 8<>0) or (H.CodeMap-H.ProcMap<8) or
      (H.CodeFixupSize mod 8<>0) then Fail(72,'Cartes du profil TPC1 invalides');
    if (ReadWord(H.CodeMap+2)<>H.CodeSize) or
      (ReadWord(H.CodeMap+4)<>H.CodeFixupSize) or
      (ReadWord(H.ConstMap+2)<>H.ConstSize) then Fail(72,'Tailles cartes incoherentes');
    if H.CodeSize<>0 then for I:=0 to H.CodeSize-1 do Emit(B^[CodeStart+I]);
    A:=AllocData(H.ConstSize);
    if H.ConstSize<>0 then Move(B^[DataStart],Data[A],H.ConstSize);
    W:=ReadWord(H.ProcMap+6);
    if W<>$FFFF then begin
      if W>=H.CodeSize then Fail(72,'Initialisation TPU hors code');
      Units[U].HasInit:=True; Units[U].InitAddress:=Units[U].CodeBase+W;
    end;
  end;
  DictBounds(H.Interf,2); W:=ReadWord(H.Interf);
  if (W>510) or Odd(W) then Fail(72,'Hash TPU invalide');
  DictBounds(H.Interf,Word(W)+4);
  for Bucket:=0 to W div 2 do begin
    A:=ReadWord(H.Interf+2+Bucket*2); Steps:=0;
    while A<>0 do begin
      Inc(Steps); if Steps>MaxSymbols then Fail(72,'Cycle de symboles TPU');
      Stub:=SymbolStub(A); Next:=ReadWord(A); Kind:=B^[A+2];
      Name:=Upper(ReadString(A+3));
      if Kind in [80,82,83] then begin
        I:=NewSymbol(Name);
        if ProjectForeign and (Kind=83) then begin
          Symbols[I].Kind:=skForeign;
          DictBounds(Stub,22); ParamN:=ReadWord(Stub+20);
          Map:=ReadWord(Stub+2);
          if (Map mod 8<>0) or (Map+Longint(8)>H.CodeMap-H.ProcMap) then
            Fail(72,'Carte procedure native invalide');
          if (ParamN<=MaxNativeParams) and (B^[Stub] and $F6=0) and
            (B^[Stub] and 1<>0) and (ReadWord(H.ProcMap+Map+4)<>$FFFF) then begin
            DictBounds(Stub,22+5*ParamN);
            if (ReadWord(Stub+16)=0) and (ReadWord(Stub+18)=0) then begin
              TypeSupported:=True; TypeSigned:=False; Typ:=ttVoid; Width:=0;
            end else DecodeType(Stub+16);
            if TypeSupported and (Typ<>ttString) and (Width<=2) then begin
              Symbols[I].Typ:=Typ; Symbols[I].Width:=Width;
              Symbols[I].SignedByte:=TypeSigned and (Width=1);
              Symbols[I].Kind:=skProc; Symbols[I].Native:=True;
              Symbols[I].NativeMap:=Map; Symbols[I].ParamCount:=ParamN;
              for K:=1 to ParamN do begin
                DecodeType(Stub+22+(K-1)*5);
                if not TypeSupported or (Typ=ttString) or (Width>2) or
                  not (B^[Stub+26+(K-1)*5] in [2,6]) then Symbols[I].Kind:=skForeign;
                Symbols[I].ParamTypes[K]:=Typ; Symbols[I].ParamWidths[K]:=Width;
                Symbols[I].ParamFlags[K]:=B^[Stub+26+(K-1)*5];
                Symbols[I].ParamSigned[K]:=TypeSigned and (Width=1);
              end;
            end;
          end;
        end else if ProjectForeign and (Kind=82) then begin
          Symbols[I].Kind:=skForeign; DictBounds(Stub,9); DecodeType(Stub+5);
          if TypeSupported and (Typ<>ttString) and (Width<=2) and (B^[Stub] in [0,1]) then begin
            Map:=ReadWord(Stub+3); Target:=ReadWord(Stub+1);
            if B^[Stub]=1 then J:=H.ConstMap else J:=H.DataMap;
            if (Map mod 8<>0) or ((B^[Stub]=1) and (Longint(J)+Map+8>H.DataMap)) or
              ((B^[Stub]=0) and (Longint(J)+Map+8>H.EndMaps)) then Fail(72,'Carte variable native invalide');
            if Longint(Target)+Width>ReadWord(J+Map+2) then Fail(72,'Variable native hors carte');
            Symbols[I].Kind:=skVar; Symbols[I].Native:=True;
            Symbols[I].Typ:=Typ; Symbols[I].Width:=Width;
            Symbols[I].SignedByte:=TypeSigned and (Width=1);
            Symbols[I].NativeMap:=Map; Symbols[I].NativeConst:=B^[Stub]=1;
            Symbols[I].Addr:=Target;
          end;
        end else if Kind=83 then begin
          if not IsLocal then Unsupported('procedure TPU Borland');
          DictBounds(Stub,22);
          Map:=ReadWord(Stub+2);
          if (Map mod 8<>0) or (Map>=H.CodeMap-H.ProcMap) then Fail(72,'ProcMap TPU invalide');
          Target:=ReadWord(H.ProcMap+Map+6);
          if Target>=H.CodeSize then Fail(72,'Procedure TPU hors code');
          Symbols[I].Kind:=skProc; Symbols[I].HasBody:=True;
          Symbols[I].Addr:=Units[U].CodeBase+Target;
        end else begin
          if Kind=80 then begin
            Symbols[I].Kind:=skConst; DecodeType(Stub);
            if not TypeSupported then Symbols[I].Kind:=skForeign
            else if Typ=ttString then begin
              DictBounds(Stub+4,1); DictBounds(Stub+4,1+B^[Stub+4]);
              Symbols[I].StrValue:=ReadString(Stub+4);
              Symbols[I].Addr:=StoreString(Symbols[I].StrValue);
            end else begin
              DictBounds(Stub+4,4); Value:=ReadWord(Stub+4);
              if Width=4 then begin
                Move(B^[Stub+4],Value,4);
                if (Value<-32768) or (Value>32767) then begin
                  if ProjectForeign then Symbols[I].Kind:=skForeign
                  else Unsupported('constante TPU Longint hors Integer');
                end;
                Width:=2;
              end else if (Typ=ttInteger) and (Width=2) and (Value>32767) then Dec(Value,65536);
              if (Typ=ttBoolean) and (Value>1) then Fail(72,'Constante Boolean TPU invalide');
              if (Typ=ttChar) and (Value>255) then Fail(72,'Constante Char TPU invalide');
              Symbols[I].Value:=Value;
            end;
          end else begin
            if not IsLocal then Unsupported('variable TPU Borland');
            DictBounds(Stub,9); Symbols[I].Kind:=skVar;
            DecodeType(Stub+5); Target:=ReadWord(Stub+1);
            if Typ=ttString then J:=Word(Capacity)+1 else J:=Width;
            if Longint(Target)+J>H.ConstSize then Fail(72,'Variable TPU hors donnees');
            Symbols[I].Addr:=Units[U].DataBase+Target;
          end;
          Symbols[I].Typ:=Typ; Symbols[I].Width:=Width; Symbols[I].Capacity:=Capacity;
        end;
      end else if not (Kind in [89]) then begin
        if ProjectForeign then begin I:=NewSymbol(Name); Symbols[I].Kind:=skForeign end
        else Unsupported('categorie de symbole TPU');
      end;
      A:=Next;
    end;
  end;
  Units[U].InterfaceReady:=True;
  if IsLocal and (InterfaceChecksum(U)<>Units[U].Checksum) then begin
    { L'ordre des buckets differe de l'ordre des declarations: le checksum
      est verifie par la representation canonique triee ci-dessous. }
    Fail(72,'Checksum d''interface TPU invalide');
  end;
  RefCount:=0; X:=H.Units;
  while X<H.Sources do begin
    if RefCount>MaxUnits+1 then Fail(72,'Trop de references TPU');
    Bounds(X,3); Name:=Upper(ReadString(X+2));
    if (Length(Name)=0) or (Length(Name)>63) or (X+3+Length(Name)>H.Sources) then
      Fail(72,'Liste de dependances TPU invalide');
    RefOffsets[RefCount]:=X-H.Units;
    RefChecks[RefCount]:=CheckForUnit(Name);
    if Name=Units[U].Name then RefUnits[RefCount]:=U
    else if Name='SYSTEM' then RefUnits[RefCount]:=0
    else begin
      RequireUnit(Name,V); RefUnits[RefCount]:=V;
      Units[U].Dependencies:=Units[U].Dependencies+[V];
      Units[U].DependencyChecks[V]:=RefChecks[RefCount];
      if not Units[V].FromSource and (RefChecks[RefCount]<>0) and
        (RefChecks[RefCount]<>Units[V].Checksum) then Fail(70,Name);
    end;
    Inc(RefCount); Inc(X,3+Length(Name));
  end;
  if IsLocal then begin
    for I:=1 to H.CodeFixupSize div 8 do begin
      X:=RelStart+(Longint(I)-1)*8; Bounds(X,8);
      R:=ReadWord(X); Map:=ReadWord(X+2); Target:=ReadWord(X+4); A:=ReadWord(X+6);
      if Longint(A)+2>H.CodeSize then Fail(72,'Fixup TPU hors code');
      J:=0;
      while (J<RefCount) and (RefOffsets[J]<>(R and $0FFF)) do Inc(J);
      if J=RefCount then Fail(72,'Reference d''unite TPU invalide');
      V:=RefUnits[J]; A:=A+Units[U].CodeBase;
      if R and $F000=$8000 then begin
        if (V=0) or (Map<>0) then Fail(72,'Fixup de donnees TPU invalide');
        Target:=GlobalOffset(Target,V,False);
        if (Target>=DataSize) or (DataOwners[Target]<>V) then Fail(72,'Cible de donnees TPU invalide');
        if FixupCount=MaxFixups then Unsupported('trop de fixups TPU');
        Inc(FixupCount); Fixups[FixupCount].Position:=A;
        Fixups[FixupCount].DataOffset:=Target; PatchWord(A,0);
      end else if R and $F000=$4000 then begin
        if (V=0) and (Map=$FFFF) then Target:=RuntimeAddress(Target)
        else begin
          if (V=0) or (Map<>0) then Fail(72,'Fixup de code TPU invalide');
          Target:=GlobalOffset(Target,V,True);
          if Target>CodeSize then Fail(72,'Cible de code TPU invalide');
        end;
        PatchJump(A,Target);
      end else Fail(72,'Nature de fixup TPU inconnue');
    end;
  end;
  Units[U].State:=2;
  if Units[U].HasInit then begin Inc(InitCount); InitOrder[InitCount]:=U end;
  if not Quiet then begin
    Write('Loaded unit ',Units[U].Name,': ',Path);
    if ProjectForeign then Write(' (ABI Borland: scalaires et appels far)');
    WriteLn;
  end;
  if IsLocal then Dispose(B);
  RestoreParser(P);
end;

procedure ImportLibrarySystem;
var U: Byte;
begin
  if FindLibraryUnit('SYSTEM')=0 then Exit;
  if (CurrentUnit<>0) and (Units[CurrentUnit].Name='SYSTEM') then Exit;
  RequireUnit('SYSTEM',U); AddImport(U);
end;

function NativeWord(U: Byte; P: Longint): Word;
begin
  if (NativeBuffers[U]=nil) or (P<0) or (P+2>UnitFileSize(NativeHeaders[U])) then
    Fail(72,'Reference native hors unite');
  NativeWord:=NativeBuffers[U]^[P]+Word(NativeBuffers[U]^[P+1])*256;
end;

procedure ActivateNative(U: Byte);
var H: TUnitHeader; P: Word; S: TShortString; I: Integer; V: Byte;
begin
  if NativeActive[U] then Exit;
  if NativeBuffers[U]=nil then Unsupported('dependance native non Borland: '+Units[U].Name);
  H:=NativeHeaders[U];
  if Units[U].Name='OVERLAY' then Unsupported('gestion des overlays Borland');
  if H.Flags and 1<>0 then Unsupported('ABI native 8087');
  NativeActive[U]:=True; P:=H.Units;
  while P<H.Sources do begin
    S:='';
    for I:=1 to NativeBuffers[U]^[P+2] do S:=S+Chr(NativeBuffers[U]^[P+2+I]);
    S:=Upper(S);
    if S<>Units[U].Name then begin
      V:=FindBuildUnit(S);
      if V=0 then RequireUnit(S,V);
      ActivateNative(V);
    end;
    Inc(P,3+Length(S));
  end;
  Inc(NativeInitCount); NativeInitOrder[NativeInitCount]:=U;
end;

function NativeMapAddress(U, Category: Byte; Map: Word): Word;
var H: TUnitHeader; First, Last, P: Word; A: Longint;
begin
  H:=NativeHeaders[U];
  case Category of
    0:begin First:=H.CodeMap; Last:=H.ConstMap; A:=NativeCodeBases[U] end;
    1:begin First:=H.DataMap; Last:=H.EndMaps; A:=NativeVarBases[U] end;
    2:begin First:=H.ConstMap; Last:=H.DataMap; A:=NativeConstBases[U] end;
  else begin Fail(72,'Categorie de carte native'); First:=0; Last:=0; A:=0 end;
  end;
  if (Map mod 8<>0) or (Longint(First)+Map+8>Last) then Fail(72,'Index carte native hors unite');
  P:=First;
  while P<First+Map do begin Inc(A,NativeWord(U,P+2)); Inc(P,8) end;
  if A>65535 then Fail(49,'Adresse native trop grande');
  NativeMapAddress:=A;
end;

function NativeProcAddress(U: Byte; Map: Word): Word;
var H: TUnitHeader; P, CodeMap, Entry: Word;
begin
  H:=NativeHeaders[U];
  if (Map mod 8<>0) or (Longint(H.ProcMap)+Map+8>H.CodeMap) then Fail(72,'Index procedure native');
  P:=H.ProcMap+Map; CodeMap:=NativeWord(U,P+4); Entry:=NativeWord(U,P+6);
  if CodeMap=$FFFF then Fail(59,'Procedure native non resolue');
  if Entry>=NativeWord(U,H.CodeMap+CodeMap+2) then Fail(72,'Entree procedure native hors segment');
  NativeProcAddress:=NativeMapAddress(U,0,CodeMap)+Entry;
end;

procedure NativeDataRelocation(P: Word; Kind: Byte);
begin
  if RelocationCount=MaxNativeRefs then Unsupported('trop de relocalisations MZ');
  Inc(RelocationCount); Relocations[RelocationCount].Offs:=P;
  Relocations[RelocationCount].Segm:=$FFFF; RelocationKinds[RelocationCount]:=Kind;
end;

procedure LinkNative;
var U, Sys: Byte; I, P, Offset, Value: Word;
  H: TUnitHeader; X, CodeStart, ConstStart: Longint;
  function RefUnit(U: Byte; Ref: Word): Byte;
  var P: Longint; S: TShortString; K: Integer; V: Byte;
  begin
    P:=NativeHeaders[U].Units; S:='';
    { Ref est un offset dans la liste, pas un numero ordinal. }
    while P<NativeHeaders[U].Sources do begin
      if P=NativeHeaders[U].Units+Ref then begin
        for K:=1 to NativeBuffers[U]^[P+2] do S:=S+Chr(NativeBuffers[U]^[P+2+K]);
        V:=FindBuildUnit(Upper(S));
        if V=0 then Fail(72,'Dependance native non resolue');
        RefUnit:=V;
        Exit;
      end;
      Inc(P,3+NativeBuffers[U]^[P+2]);
    end;
    Fail(72,'Offset reference d''unite native invalide'); RefUnit:=0;
  end;
  procedure WriteAt(P: Word; W: Word; InConst: Boolean);
  begin
    if InConst then begin
      if Longint(P)+2>NativeDataSize then Fail(72,'Fixup natif hors donnees');
      NativeData[P]:=W and 255; NativeData[P+1]:=W shr 8;
    end else begin
      if Longint(P)+2>CodeSize then Fail(72,'Fixup natif hors code');
      PatchWord(P,W);
    end;
  end;
  procedure ResolveMaps(U: Byte; InConst: Boolean);
  var H: TUnitHeader; M, EndMap, Raw, FixRaw, Posn, Source, L, FS, N: Word;
      R, TM, T, At, W, SG: Word; Q: Longint; V: Byte;
  begin
    H:=NativeHeaders[U]; Raw:=0; FixRaw:=0;
    if InConst then begin
      M:=H.ConstMap; EndMap:=H.DataMap;
      Q:=Align16(H.EndTrace)+Align16(H.CodeSize)+Align16(H.ConstSize)+Align16(H.CodeFixupSize);
    end else begin
      M:=H.CodeMap; EndMap:=H.ConstMap;
      Q:=Align16(H.EndTrace)+Align16(H.CodeSize)+Align16(H.ConstSize);
    end;
    while M<EndMap do begin
      L:=NativeWord(U,M+2); FS:=NativeWord(U,M+4);
      if FS mod 8<>0 then Fail(72,'Taille fixups natifs invalide');
      if InConst then Source:=NativeConstBases[U]+Raw else Source:=NativeCodeBases[U]+Raw;
      for N:=1 to FS div 8 do begin
        Posn:=FixRaw+(N-1)*8;
        R:=NativeWord(U,Q+Posn); TM:=NativeWord(U,Q+Posn+2);
        T:=NativeWord(U,Q+Posn+4); At:=NativeWord(U,Q+Posn+6);
        W:=2; if R and $3000=$3000 then W:=4;
        if Longint(At)+W>L then Fail(72,'Position de fixup hors carte native');
        V:=RefUnit(U,R and $FFF); SG:=0;
        if R and $8000<>0 then begin
          SG:=1;
          if R and $4000<>0 then W:=NativeMapAddress(V,2,TM)+T
          else W:=NativeMapAddress(V,1,TM)+T;
        end else if R and $4000<>0 then W:=NativeMapAddress(V,0,TM)+T
        else W:=NativeProcAddress(V,TM)+T;
        At:=At+Source;
        if R and $1000<>0 then begin WriteAt(At,W,InConst); Inc(At,2) end
        else if R and $2000=0 then begin WriteAt(At,Word(Longint(W)-At-2),InConst) end;
        if R and $2000<>0 then begin
          WriteAt(At,0,InConst);
          if InConst then NativeDataRelocation(At,SG) else AddSegmentRelocation(At,SG);
        end;
      end;
      Inc(Raw,L); Inc(FixRaw,FS); Inc(M,8);
    end;
  end;
  procedure FarCallTo(Address: Word);
  begin Emit($9A); EmitWord(Address); AddSegmentRelocation(CodeSize,0); EmitWord(0) end;
begin
  if not NativeNeeded then Exit;
  NativeDataSize:=2; FillChar(NativeData,SizeOf(NativeData),0);
  for U:=1 to UnitCount do if NativeActive[U] then begin
    H:=NativeHeaders[U]; NativeCodeBases[U]:=CodeSize;
    CodeStart:=Align16(H.EndTrace);
    if H.CodeSize<>0 then for X:=0 to H.CodeSize-1 do Emit(NativeBuffers[U]^[CodeStart+X]);
    NativeConstBases[U]:=NativeDataSize;
    if Longint(NativeDataSize)+H.ConstSize>MaxImage then Fail(49,'Constantes natives trop grandes');
    ConstStart:=CodeStart+Align16(H.CodeSize);
    if H.ConstSize<>0 then Move(NativeBuffers[U]^[ConstStart],NativeData[NativeDataSize],H.ConstSize);
    Inc(NativeDataSize,H.ConstSize);
  end;
  for U:=1 to UnitCount do if NativeActive[U] then begin
    NativeVarBases[U]:=NativeDataSize;
    if Longint(NativeDataSize)+NativeHeaders[U].DataSize>MaxImage then Fail(49,'Donnees natives trop grandes');
    Inc(NativeDataSize,NativeHeaders[U].DataSize);
  end;
  for U:=1 to UnitCount do if NativeActive[U] then begin ResolveMaps(U,False); ResolveMaps(U,True) end;
  for I:=1 to NativeRefCount do begin
    U:=NativeRefs[I].U;
    if NativeRefs[I].Kind=3 then Value:=NativeProcAddress(U,NativeRefs[I].Map)+NativeRefs[I].Target
    else Value:=NativeMapAddress(U,NativeRefs[I].Kind,NativeRefs[I].Map)+NativeRefs[I].Target;
    PatchWord(NativeRefs[I].Position,Value);
  end;
  Sys:=FindBuildUnit('SYSTEM');
  P:=CodeSize; PatchJump(EntryFixup,P);
  Emit($1E); Emit($06); Emit($55);
  SetNativeDS; Emit2($8E,$C2);
  if (Sys<>0) and NativeActive[Sys] then begin
    { ES=PSP a l'entree de _InitTurbo; CS principal est le segment de charge. }
    Emit2($8C,$C8); Emit($2D); EmitWord($10); Emit2($8E,$C0);
    FarCallTo(NativeProcAddress(Sys,8));
  end;
  for I:=1 to NativeInitCount do begin
    U:=NativeInitOrder[I];
    if U<>Sys then
      if NativeWord(U,NativeHeaders[U].ProcMap+4)<>$FFFF then FarCallTo(NativeProcAddress(U,0));
  end;
  Emit($5D); Emit($07); Emit($1F); JumpTo(MainEntry);
  if (Sys<>0) and NativeActive[Sys] then begin
    { _HaltTurbo restitue les vecteurs installees par _InitTurbo. }
    Offset:=RuntimeHalt;
    Image[Offset]:=$BA; PatchWord(Offset+1,0); AddSegmentRelocation(Offset+1,1);
    Image[Offset+3]:=$8E; Image[Offset+4]:=$DA; Image[Offset+5]:=$9A;
    PatchWord(Offset+6,NativeProcAddress(Sys,24)); PatchWord(Offset+8,0);
    AddSegmentRelocation(Offset+8,0);
  end;
end;

procedure UsesClause;
var Name: TShortString; U: Byte;
begin
  if Token<>tkUses then Exit;
  NextToken;
  repeat
    if Token<>tkIdent then Fail(2,'Nom d''unite attendu');
    Name:=TokenText; NextToken;
    if (Name<>'SYSTEM') or (FindLibraryUnit('SYSTEM')<>0) then begin
      RequireUnit(Name,U);
      AddImport(U);
      if (NativeBuffers[U]<>nil) and (Name<>'SYSTEM') then
        if (NativeHeaders[U].CodeMap-NativeHeaders[U].ProcMap>=8) and
          (NativeWord(U,NativeHeaders[U].ProcMap+4)<>$FFFF) then begin
          NativeNeeded:=True; ActivateNative(U);
        end;
    end;
    if Token<>tkComma then Break;
    NextToken;
  until False;
  Need(tkSemi);
end;

procedure EmitRuntime;
var P, Q, LoopStart: Word;
begin
  NumberBuffer:=AllocData(6);
  TrueText:=StoreString('TRUE'); FalseText:=StoreString('FALSE');
  RuntimeChar:=CodeSize;
  Emit2($89,$C2); Emit2($B4,$02); Emit2($CD,$21); Emit($C3);

  RuntimeString:=CodeSize;
  Emit2($89,$C6); Emit2($31,$C9); Emit2($8A,$0C); Emit($46);
  Emit2($09,$C9); Emit2($75,$03); P:=Jump;
  LoopStart:=CodeSize;
  Emit($AC); CallTo(RuntimeChar); Emit($E2);
  Emit(Byte(Longint(LoopStart)-CodeSize-1));
  PatchJump(P,CodeSize); Emit($C3);

  RuntimeInteger:=CodeSize;
  Emit2($09,$C0); Emit2($79,$0A); Emit($50);
  LoadImmediate(Ord('-')); CallTo(RuntimeChar); Emit($58); Emit2($F7,$D8);
  Emit($BF); DataAddress(NumberBuffer+6); Emit($BB); EmitWord(10);
  Emit2($31,$C9); LoopStart:=CodeSize;
  Emit2($31,$D2); Emit2($F7,$F3); Emit2($80,$C2); Emit(Ord('0'));
  Emit($4F); Emit2($88,$15); Emit($41); Emit2($09,$C0); Emit2($75,0);
  Image[CodeSize-1]:=Byte(Longint(LoopStart)-CodeSize);
  Emit2($89,$FE); LoopStart:=CodeSize; Emit($AC); CallTo(RuntimeChar);
  Emit($E2); Emit(Byte(Longint(LoopStart)-CodeSize-1)); Emit($C3);

  RuntimeBoolean:=CodeSize;
  Emit2($09,$C0); Emit2($74,$06);
  Emit($B8); DataAddress(TrueText); Q:=Jump;
  Emit($B8); DataAddress(FalseText); PatchJump(Q,CodeSize);
  JumpTo(RuntimeString);

  RuntimeCopy:=CodeSize;      { DS:SI source, ES:DI dest, CX capacite }
  Emit2($31,$C0); Emit($AC); Emit2($39,$C8); Emit2($76,$02);
  Emit2($89,$C8); Emit($AA); Emit2($89,$C1); Emit2($F3,$A4); Emit($C3);
  RuntimeHalt:=CodeSize; Emit2($B4,$4C); Emit2($CD,$21);
  for P:=1 to 16 do Emit($90);
end;

procedure CompileProgram;
var I: Byte;
begin
  CodeSize:=0; DataSize:=0; SymbolCount:=0; FixupCount:=0;
  RelativeCount:=0; UnitOutput:=False;
  NativeNeeded:=False; NativeRefCount:=0; RelocationCount:=0; NativeInitCount:=0;
  UnitCount:=0; InitCount:=0; CurrentUnit:=0; Imports:=[]; ImportCount:=0;
  InInterface:=False;
  Emit($0E); Emit($1F); Emit($0E); Emit($07); Emit($FC); { DS=ES=CS; cld }
  EntryFixup:=Jump;
  EmitRuntime;
  NextToken;
  if Token=tkUnit then begin
    NextToken;
    if Token<>tkIdent then Fail(2,'Nom d''unite attendu');
    UnitCount:=1; FillChar(Units[1],SizeOf(TBuildUnit),0);
    Units[1].Name:=TokenText; Units[1].State:=1;
    CompileSourceUnit(1,MainSourceName); UnitOutput:=True; Exit;
  end;
  if Token=tkProgram then begin
    NextToken; Need(tkIdent);
    if Token=tkLP then begin
      NextToken; Need(tkIdent);
      while Token=tkComma do begin NextToken; Need(tkIdent) end;
      Need(tkRP);
    end;
    Need(tkSemi);
  end;
  ImportLibrarySystem;
  UsesClause;
  DeclarationPart;
  MainEntry:=CodeSize;
  PatchJump(EntryFixup,CodeSize);
  for I:=1 to InitCount do CallTo(Units[InitOrder[I]].InitAddress);
  Need(tkBegin); StatementList(tkEnd); Need(tkEnd); Need(tkDot);
  if Token<>tkEOF then Fail(10,'Texte apres END.');
  LoadImmediate(0); CallTo(RuntimeHalt);
end;

procedure LoadSource;
var F: file; N: Word; E: Integer;
begin
  Assign(F,SourceName); OpenBinaryRead(F,E);
  if E<>0 then Fail(15,'Fichier introuvable: '+SourceName);
  SourceSize:=FileSize(F);
  if SourceSize>MaxSource then begin Close(F); Unsupported('source > 60000 octets') end;
  {$I-} BlockRead(F,Source,SourceSize,N); E:=IOResult; Close(F);
  if IOResult<>0 then E:=1; {$I+}
  if (E<>0) or (N<>SourceSize) then Fail(15,'Lecture du source impossible');
  SourcePos:=1; Line:=1; Column:=1; CondDepth:=0; Active:=True;
end;

procedure WriteExecutable;
var H: array[0..15] of Word; F: file; Size, AllocParas, HeaderBytes, Location: Longint;
    I, Base, StackSeg, Pad, N: Word; E: Integer; Path: TShortString;
  NativeSegment: Word; Padding: array[0..15] of Byte;
    D: DirStr; Name: NameStr; Ext: ExtStr;
begin
  Base:=CodeSize;
  if Longint(Base)+DataSize>65520 then Fail(49,'CS/DS depasse 65520 octets');
  Size:=Longint(CodeSize)+DataSize;
  if Size>MaxImage then Fail(49,'Image trop grande');
  for I:=1 to FixupCount do
    PatchWord(Fixups[I].Position,Base+Fixups[I].DataOffset);
  for I:=0 to DataSize-1 do Image[Base+I]:=Data[I];
  NativeSegment:=0;
  if NativeNeeded then begin
    NativeSegment:=Align16(Size) div 16;
    Size:=Longint(NativeSegment)*16+NativeDataSize;
    if Size>MaxImage then Fail(49,'Image Borland trop grande');
    Move(NativeData,Image[Longint(NativeSegment)*16],NativeDataSize);
    for I:=1 to RelocationCount do begin
      if Relocations[I].Segm=$FFFF then Relocations[I].Segm:=NativeSegment;
      Location:=Longint(Relocations[I].Segm)*16+Relocations[I].Offs;
      if Location+2>Size then Fail(72,'Relocalisation MZ hors image');
      if RelocationKinds[I]=1 then PatchWord(Location,NativeSegment)
      else PatchWord(Location,0);
    end;
  end;
  StackSeg:=(Size+15) div 16;
  Pad:=StackSeg*16-Size;
  { Pile non stockee dans le fichier: e_minalloc la reserve a la charge. }
  AllocParas:=(Longint(StackSize)+Pad+15) div 16;
  FillChar(H,SizeOf(H),0);
  HeaderBytes:=Align16(32+Longint(RelocationCount)*4);
  H[0]:=$5A4D; H[1]:=(Size+HeaderBytes) mod 512; H[2]:=(Size+HeaderBytes+511) div 512;
  H[3]:=RelocationCount; H[4]:=HeaderBytes div 16; H[5]:=AllocParas+MinHeap;
  if AllocParas+MaxHeap>65535 then H[6]:=$FFFF
  else H[6]:=AllocParas+MaxHeap;
  H[7]:=StackSeg;
  H[8]:=StackSize; H[12]:=32;
  FSplit(SourceName,D,Name,Ext);
  if OutputDir='' then Path:=D+Name+'.EXE' else Path:=JoinPath(OutputDir,Name+'.EXE');
  if Upper(Path)=Upper(SourceName) then CLIError('Sortie identique au source');
  Assign(F,Path); {$I-} Rewrite(F,1); E:=IOResult; {$I+}
  if E<>0 then Fail(16,'Creation impossible: '+Path);
  {$I-}
  BlockWrite(F,H,32,N); E:=IOResult; if N<>32 then E:=1;
  if (E=0) and (RelocationCount<>0) then begin
    BlockWrite(F,Relocations,RelocationCount*4,N); E:=IOResult;
    if N<>RelocationCount*4 then E:=1;
  end;
  Pad:=HeaderBytes-32-RelocationCount*4; FillChar(Padding,SizeOf(Padding),0);
  if (E=0) and (Pad<>0) then begin BlockWrite(F,Padding,Pad,N); E:=IOResult; if N<>Pad then E:=1 end;
  if E=0 then begin
    BlockWrite(F,Image,Size,N); E:=IOResult; if N<>Size then E:=1;
  end;
  Close(F); if IOResult<>0 then E:=1;
  if E<>0 then begin Erase(F); if IOResult<>0 then E:=1 end;
  {$I+}
  if E<>0 then Fail(16,'Ecriture impossible: '+Path);
  if not Quiet then WriteLn('8086 DOS MZ: ',Path,'; code=',CodeSize,
    ', donnees=',DataSize,', pile=',StackSize);
end;

procedure InspectTPU;
var H: TUnitHeader;
begin
  ReadTPUHeader(InspectName,H);
  WriteLn('TPU9: en-tete=',SizeOf(H),' octets; fin dictionnaire=',H.EndTrace);
  WriteLn('Code=',H.CodeSize,' constantes=',H.ConstSize,' donnees=',H.DataSize);
  WriteLn('Fixups code=',H.CodeFixupSize,' constantes=',H.DataFixupSize);
  if (H.Flags=$8000) and (H.Reserved[0]=$5054) and (H.Reserved[1]=$3143) then
    WriteLn('Profil TPC1: ABI locale near/CS=DS, non compatible Borland.')
  else WriteLn('TPU9 Borland: appels far et donnees ordinales; ABI partielle.');
end;

procedure InspectLibrary;
var I: Word; H: TUnitHeader;
begin
  ReadLibrary(InspectLibraryName);
  WriteLn('TPL: ',LibraryName,'; unites=',LibraryCount);
  for I:=1 to LibraryCount do begin
    H:=LibraryUnits[I].Header;
    Write(LibraryUnits[I].Name,' offset=',LibraryUnits[I].Offset,
      ' taille=',LibraryUnits[I].Size,' code=',H.CodeSize,' constantes=',H.ConstSize);
    if (H.Flags=$8000) and (H.Reserved[0]=$5054) and (H.Reserved[1]=$3143) then
      Write(' profil=TPC1')
    else if (H.CodeSize<>0) or (H.ConstSize<>0) or (H.DataSize<>0) then
      Write(' Borland: ABI ordinale/far')
    else Write(' TPU9 sans code');
    WriteLn;
  end;
end;

procedure Help;
begin
  WriteLn('TPC - portage PARTIEL de Turbo Pascal 6, cible DOS 8086');
  WriteLn('TPC fichier.pas [/Erepertoire] [/Urepertoires] [/Dsymboles] [/$X-]');
  WriteLn('/B reconstruit les unites depuis leurs sources (sous-ensemble Pascal).');
  WriteLn('Production/liaison TPU9 profil TPC1; ABI locale, pas ABI Borland.');
  WriteLn('TPU9/TPL Borland: appels far, parametres et globals ordinaux 8/16 bits.');
  WriteLn('Signatures avancees, 8087 et overlays restent non implementes.');
  WriteLn('/M reconnu, refuse: reconstruction incrementale non implementee.');
  WriteLn('/Q silencieux; /T repertoires Turbo (TURBO.TPL et TPU).');
  WriteLn('TPL charge automatiquement: repertoire courant, /T, repertoire de TPC.');
  WriteLn('/I, /O, /L, /V, /F, /G reconnus mais refuses: fonctions manquantes.');
  WriteLn('Extension locale: --inspect-tpu=fichier.tpu; --quiet; --help.');
  WriteLn('Extension locale: --inspect-tpl=fichier.tpl.');
  WriteLn('Toutes les chaines internes sont string[255] (longueur en [0]).');
  WriteLn('Pas de compatibilite binaire promise avec le code Borland.');
end;

procedure ParseArguments;
var I, P: Integer; S, Arg, Part: TShortString; C: Char;
begin
  if ParamCount=0 then begin Help; Halt(0) end;
  for I:=1 to ParamCount do begin
    S:=ParamStr(I);
    if (S='--help') or (S='/?') or (S='-?') then begin Help; Halt(0) end
    else if S='--quiet' then Quiet:=True
    else if Copy(S,1,14)='--inspect-tpu=' then InspectName:=Copy(S,15,255)
    else if Copy(S,1,14)='--inspect-tpl=' then InspectLibraryName:=Copy(S,15,255)
    else if (Length(S)>0) and (S[1] in ['/','-']) then begin
      if Length(S)<2 then CLIError('Option vide');
      C:=UpCase(S[2]); Arg:=Copy(S,3,255);
      case C of
        '$':begin
          if (Length(Arg)>0) and (UpCase(Arg[1])='M') then
            MemoryDirective(Copy(Arg,2,255))
          else SetSwitch(Upper(Arg));
        end;
        'E':begin if Arg='' then CLIError('Repertoire /E manquant'); OutputDir:=Arg end;
        'U':begin if Arg='' then CLIError('Repertoire /U manquant'); UnitDirs:=Arg end;
        'T':begin if Arg='' then CLIError('Repertoire /T manquant'); TurboDirs:=Arg end;
        'Q':begin if Arg<>'' then CLIError('Option /Q incorrecte'); Quiet:=True end;
        'D':begin
          repeat
            P:=Pos(';',Arg);
            if P=0 then begin Part:=Arg; Arg:='' end
            else begin Part:=Copy(Arg,1,P-1); Delete(Arg,1,P) end;
            Define(Part);
          until Arg='';
        end;
        'B':begin if Arg<>'' then CLIError('Option /B incorrecte'); BuildMode:=True end;
        'M':begin if Arg<>'' then CLIError('Option /M incorrecte'); MakeMode:=True end;
        'I','O','L','V','F','G':Unsupported('parametre '+S);
      else CLIError('Option inconnue: '+S);
      end;
    end else begin
      if InputName<>'' then CLIError('Un seul fichier source attendu'); InputName:=S;
    end;
  end;
end;

procedure CheckLayout;
var Actual: Word;
begin
  Actual:=SizeOf(TUnitHeader);
  if Actual<>80 then CLIError('Disposition en-tete TPU incompatible');
  Actual:=SizeOf(TTypeDescriptor);
  if Actual<>6 then CLIError('Disposition descripteur incompatible');
  Actual:=SizeOf(TSymbolPrefix);
  if Actual<>4 then CLIError('Disposition symbole incompatible');
  Actual:=SizeOf(TTPUFixup);
  if Actual<>8 then CLIError('Disposition fixup incompatible');
  Actual:=SizeOf(TShortString);
  if Actual<>256 then CLIError('Disposition shortstring incompatible');
end;

var D: DirStr; N: NameStr; E: ExtStr;
begin
  { TP6 structures fixes, verifier avant toute lecture binaire. }
  CheckLayout;
  StackSize:=16384; MinHeap:=0; MaxHeap:=$FFFF;
  OptionBits:=$1411; { sous-ensemble: A+, E+, I+, V+; autres desactives }
  TokenLine:=1; TokenColumn:=1;
  Define('VER60'); Define('MSDOS'); Define('CPU86');
  ParseArguments;
  if InspectName<>'' then begin SourceName:=InspectName; InspectTPU; Halt(0) end;
  if InspectLibraryName<>'' then begin SourceName:=InspectLibraryName; InspectLibrary; Halt(0) end;
  if InputName='' then CLIError('Fichier source manquant');
  if MakeMode and not BuildMode then Unsupported('/M: construction incrementale des unites');
  SourceName:=InputName; FSplit(SourceName,D,N,E);
  if E='' then SourceName:=SourceName+'.PAS';
  MainSourceName:=SourceName;
  FindAndReadLibrary;
  Move(Defines,InitialDefines,SizeOf(Defines)); InitialDefineCount:=DefineCount;
  InitialOptions:=OptionBits;
  if not Quiet then WriteLn('TPC: portage partiel TP6; hote Pascal, cible DOS 8086');
  LoadSource; CompileProgram; WriteUnits;
  if not UnitOutput then begin LinkNative; WriteExecutable end;
end.