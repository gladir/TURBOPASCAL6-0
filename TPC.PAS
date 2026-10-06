program TPC;
{ Portage partiel, et NON un remplacement integral de Turbo Pascal 6.
  Reference: N:\IBMPC\CODER\TurboPascalSource\COMPILER (VER60 / TPU9).
  Les tokens, NeedToken, CalcHash et les structures TPU ci-dessous suivent
  COMPILER.INC et LEX.ASM. Le parseur et le runtime sont nouveaux: le code
  produit n'est pas identique a celui de Borland. Aucun backend FPC externe.
  Hote valide: Free Pascal 3.2, mode TP, strings courts uniquement.
  Cible: DOS MZ, instructions 8086, un segment CS/DS et pile separee.
  Restrictions explicites: pas de linker TPU/OBJ, real, tableaux, objets,
  types utilisateurs, procedures a parametres, routines imbriquees, ASM.
  /B recompile recursivement les sources d'unites dans l'image EXE, sans
  produire de TPU9. Les TPU sans source restent non liables.
  Les fonctionnalites manquantes ont un diagnostic propre sans faux numero TP.
  Numeros verifies dans le source et dans la table du TPC.EXE original DISK1.
  Les messages anglais ci-dessous couvrent les erreurs utilisees ici; les
  details supplementaires sont locaux, les positions ne sont pas garanties
  identiques a Borland. }
{$IFDEF FPC}
{$MODE TP}
{$H-}
{$ENDIF}
{$R-}{$Q-}

uses Dos;

const
  MaxSource = 60000;
  MaxImage = 60000;
  MaxSymbols = 512;
  MaxFixups = 4096;
  MaxDefines = 128;
  MaxUnits = 64;
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
  skVar=1; skConst=2; skProc=3;

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
  end;
  TAddressFixup = record Position, DataOffset: Word end;
  TCondition = record ParentActive, Test, SeenElse: Boolean end;
  TUnitSet = set of 0..MaxUnits;
  TBuildUnit = record
    Name: string[63];
    State: Byte; { 1 = compilation en cours; 2 = compilee }
    InterfaceReady, HasInit: Boolean;
    InitAddress: Word;
  end;
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
begin PatchWord(P,Word(Longint(Target)-P-2)) end;

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
begin Emit($E8); EmitWord(Word(Longint(Target)-CodeSize-2)) end;

procedure LoadImmediate(W: Word);
begin Emit($B8); EmitWord(W) end;

procedure DataAddress(Offs: Word);
begin
  if FixupCount=MaxFixups then Unsupported('trop de references de donnees');
  Inc(FixupCount); Fixups[FixupCount].Position:=CodeSize;
  Fixups[FixupCount].DataOffset:=Offs; EmitWord(0);
end;

function AllocData(N: Word): Word;
begin
  if Longint(DataSize)+N>MaxImage then Fail(49,'Segment de donnees trop grand');
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

procedure LoadSymbol(I: Word);
begin
  if Symbols[I].Kind=skConst then begin
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
  if Symbols[I].Width=1 then Emit($A2) else Emit($A3);
  DataAddress(Symbols[I].Addr);
end;

function Expression: Byte; forward;
procedure Statement; forward;

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
      if Symbols[I].Kind=skProc then Unsupported('fonction: '+Name);
      T:=Symbols[I].Typ; LoadSymbol(I);
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
var I, Start, P, Q, Limit: Word; Direction: Byte; Name, VarName: TShortString;
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
        Emit2($B4,$4C); Emit2($CD,$21);
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
          if Token=tkLP then Unsupported('parametres de procedure');
          CallTo(Symbols[I].Addr);
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
  InInterface:=True; InProcedure:=False;
  { Les directives locales d'une unite ne fuient ni dans ses dependances
    ni dans le programme appelant. Les /D de la CLI restent disponibles. }
  Move(InitialDefines,Defines,SizeOf(Defines)); DefineCount:=InitialDefineCount;
  OptionBits:=InitialOptions;
  LoadSource;
  if not Quiet then WriteLn('Building unit ',Units[U].Name,': ',Path);
  NextToken; Need(tkUnit);
  if Token<>tkIdent then Fail(2,'Nom d''unite attendu');
  if TokenText<>Units[U].Name then Fail(69,Units[U].Name+' <> '+TokenText);
  NextToken; Need(tkSemi); Need(tkInterface);
  UsesClause; DeclarationPart;
  Units[U].InterfaceReady:=True;
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

function FileExists(S: TShortString): Boolean;
var F: file; E: Integer;
begin
  Assign(F,S); {$I-} Reset(F,1); E:=IOResult; {$I+}
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
  if Length(D)+Length(MainDir)+Length(UnitDirs)+4>255 then
    CLIError('Liste de recherche des unites trop longue');
  S:=D+';'+MainDir+';.;'+UnitDirs;
  repeat
    P:=Pos(';',S);
    if P=0 then begin Part:=S; S:='' end
    else begin Part:=Copy(S,1,P-1); Delete(S,1,P) end;
    Candidate:=JoinPath(Part,Name+Extension);
    if FileExists(Candidate) then begin FindUnitPath:=Candidate; Exit end;
  until S='';
end;

procedure ReadTPUHeader(Name: TShortString; var H: TUnitHeader);
var F: file; Count: Word; E: Integer; Size, Needed: Longint;
begin
  Assign(F,Name); {$I-} Reset(F,1); E:=IOResult; {$I+}
  if E<>0 then Fail(15,'Fichier introuvable: '+Name);
  {$I-} Size:=FileSize(F); BlockRead(F,H,SizeOf(H),Count); E:=IOResult;
  Close(F); if IOResult<>0 then E:=1; {$I+}
  if (E<>0) or (Count<>SizeOf(H)) then Fail(72,'Unite tronquee: '+Name);
  if (H.Signature[0]<>'T') or (H.Signature[1]<>'P') or
    (H.Signature[2]<>'U') or (H.Signature[3]<>'9') then
    Fail(72,'Signature TPU9 attendue: '+Name);
  Needed:=((Longint(H.EndTrace)+15) div 16)*16;
  Needed:=Needed+((Longint(H.CodeSize)+15) div 16)*16;
  Needed:=Needed+((Longint(H.ConstSize)+15) div 16)*16;
  Needed:=Needed+((Longint(H.CodeFixupSize)+15) div 16)*16;
  Needed:=Needed+((Longint(H.DataFixupSize)+15) div 16)*16;
  if (H.EndTrace<SizeOf(H)) or (Needed>Size) or
    (H.Name<SizeOf(H)) or (H.Name>=H.EndTrace) or
    (H.Interf<SizeOf(H)) or (H.Interf>=H.EndTrace) then
    Fail(72,'En-tete TPU incoherent: '+Name);
end;

procedure UsesClause;
var Name, Path: TShortString; H: TUnitHeader; U: Byte;
begin
  if Token<>tkUses then Exit;
  NextToken;
  repeat
    if Token<>tkIdent then Fail(2,'Nom d''unite attendu');
    Name:=TokenText; NextToken;
    if Name<>'SYSTEM' then begin
      U:=FindBuildUnit(Name);
      if U<>0 then begin
        if (U=CurrentUnit) or ((Units[U].State=1) and not Units[U].InterfaceReady) then
          Fail(68,Name);
      end else begin
        Path:='';
        if BuildMode then Path:=FindUnitPath(Name,'.PAS');
        if Path<>'' then begin
          if UnitCount=MaxUnits then Unsupported('plus de 64 unites');
          Inc(UnitCount); U:=UnitCount;
          FillChar(Units[U],SizeOf(TBuildUnit),0);
          Units[U].Name:=Name; Units[U].State:=1;
          CompileSourceUnit(U,Path);
        end else begin
          Path:=FindUnitPath(Name,'.TPU');
          if Path='' then Fail(15,'Fichier introuvable: '+Name+'.TPU');
          ReadTPUHeader(Path,H);
          Unsupported('liaison TPU9 de '+Name+' (source absent, en-tete valide)');
        end;
      end;
      AddImport(U);
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
end;

procedure CompileProgram;
var I: Byte;
begin
  CodeSize:=0; DataSize:=0; SymbolCount:=0; FixupCount:=0;
  UnitCount:=0; InitCount:=0; CurrentUnit:=0; Imports:=[]; ImportCount:=0;
  InInterface:=False;
  Emit($0E); Emit($1F); Emit($0E); Emit($07); Emit($FC); { DS=ES=CS; cld }
  EntryFixup:=Jump;
  EmitRuntime;
  NextToken;
  if Token=tkUnit then Unsupported('production d''une TPU9');
  if Token=tkProgram then begin
    NextToken; Need(tkIdent);
    if Token=tkLP then begin
      NextToken; Need(tkIdent);
      while Token=tkComma do begin NextToken; Need(tkIdent) end;
      Need(tkRP);
    end;
    Need(tkSemi);
  end;
  UsesClause;
  DeclarationPart;
  PatchJump(EntryFixup,CodeSize);
  for I:=1 to InitCount do CallTo(Units[InitOrder[I]].InitAddress);
  Need(tkBegin); StatementList(tkEnd); Need(tkEnd); Need(tkDot);
  if Token<>tkEOF then Fail(10,'Texte apres END.');
  LoadImmediate($4C00); Emit2($CD,$21);
end;

procedure LoadSource;
var F: file; N: Word; E: Integer;
begin
  Assign(F,SourceName); {$I-} Reset(F,1); E:=IOResult; {$I+}
  if E<>0 then Fail(15,'Fichier introuvable: '+SourceName);
  SourceSize:=FileSize(F);
  if SourceSize>MaxSource then begin Close(F); Unsupported('source > 60000 octets') end;
  {$I-} BlockRead(F,Source,SourceSize,N); E:=IOResult; Close(F);
  if IOResult<>0 then E:=1; {$I+}
  if (E<>0) or (N<>SourceSize) then Fail(15,'Lecture du source impossible');
  SourcePos:=1; Line:=1; Column:=1; CondDepth:=0; Active:=True;
end;

procedure WriteExecutable;
var H: array[0..15] of Word; F: file; Size, AllocParas: Longint;
    I, Base, StackSeg, Pad, N: Word; E: Integer; Path: TShortString;
    D: DirStr; Name: NameStr; Ext: ExtStr;
begin
  Base:=CodeSize;
  if Longint(Base)+DataSize>65520 then Fail(49,'CS/DS depasse 65520 octets');
  Size:=Longint(CodeSize)+DataSize;
  if Size>MaxImage then Fail(49,'Image trop grande');
  for I:=1 to FixupCount do
    PatchWord(Fixups[I].Position,Base+Fixups[I].DataOffset);
  for I:=0 to DataSize-1 do Image[Base+I]:=Data[I];
  StackSeg:=(Size+15) div 16;
  Pad:=StackSeg*16-Size;
  { Pile non stockee dans le fichier: e_minalloc la reserve a la charge. }
  AllocParas:=(Longint(StackSize)+Pad+15) div 16;
  FillChar(H,SizeOf(H),0);
  H[0]:=$5A4D; H[1]:=(Size+32) mod 512; H[2]:=(Size+32+511) div 512;
  H[4]:=2; H[5]:=AllocParas+MinHeap;
  if AllocParas+MaxHeap>65535 then H[6]:=$FFFF
  else H[6]:=AllocParas+MaxHeap;
  H[7]:=StackSeg;
  H[8]:=StackSize; H[12]:=$1C;
  FSplit(SourceName,D,Name,Ext);
  if OutputDir='' then Path:=D+Name+'.EXE' else Path:=JoinPath(OutputDir,Name+'.EXE');
  if Upper(Path)=Upper(SourceName) then CLIError('Sortie identique au source');
  Assign(F,Path); {$I-} Rewrite(F,1); E:=IOResult; {$I+}
  if E<>0 then Fail(16,'Creation impossible: '+Path);
  {$I-}
  BlockWrite(F,H,32,N); E:=IOResult; if N<>32 then E:=1;
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
  WriteLn('Inspection seulement: symboles et liaison non implementes.');
end;

procedure Help;
begin
  WriteLn('TPC - portage PARTIEL de Turbo Pascal 6, cible DOS 8086');
  WriteLn('TPC fichier.pas [/Erepertoire] [/Urepertoires] [/Dsymboles] [/$X-]');
  WriteLn('/B reconstruit les unites depuis leurs sources (sous-ensemble Pascal).');
  WriteLn('Pas de production TPU; liaison des TPU existantes non implementee.');
  WriteLn('/M reconnu, refuse: reconstruction incrementale non implementee.');
  WriteLn('/Q silencieux; /T repertoire Turbo (cherche les TPU).');
  WriteLn('/I, /O, /L, /V, /F, /G reconnus mais refuses: fonctions manquantes.');
  WriteLn('Extension locale: --inspect-tpu=fichier.tpu; --quiet; --help.');
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
        'T':begin if Arg='' then CLIError('Repertoire /T manquant'); UnitDirs:=Arg end;
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
  if InputName='' then CLIError('Fichier source manquant');
  if MakeMode and not BuildMode then Unsupported('/M: construction incrementale des unites');
  SourceName:=InputName; FSplit(SourceName,D,N,E);
  if E='' then SourceName:=SourceName+'.PAS';
  MainSourceName:=SourceName;
  Move(Defines,InitialDefines,SizeOf(Defines)); InitialDefineCount:=DefineCount;
  InitialOptions:=OptionBits;
  if not Quiet then WriteLn('TPC: portage partiel TP6; hote Pascal, cible DOS 8086');
  LoadSource; CompileProgram; WriteExecutable;
end.