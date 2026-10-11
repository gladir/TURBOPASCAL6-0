{ @author: Sylvain Maltais (support@gladir.com)
 @created: 2026
 @website(https://www.gladir.com/turbopascal6-0)
 @abstract(Target: Free Pascal)
 @description: Clone du compilateur Turbo Pascal 6.0 }

Program TPC;

{ Portage partiel, et NON un remplacement integral de Turbo Pascal 6.
  Reference: N:\IBMPC\CODER\TurboPascalSource\COMPILER (VER60 / TPU9).
  Les tokens, NeedToken, CalcHash et les structures TPU ci-dessous suivent
  COMPILER.INC et LEX.ASM. Le parseur et le runtime sont nouveaux: le code
  produit n'est pas identique a celui de Borland. Aucun backend FPC externe.
  Hote valide: Free Pascal 3.2, mode TP, strings courts uniquement.
  Cible: DOS MZ multi-segments, instructions 8086, CS/DS local et pile separee.
  Imports OMF86 Use16 via $L/$LINK; routines EXTERNAL Pascal far.
  Restrictions explicites: ABI Borland partielle (ordinaux 8/16 bits), real, tableaux, objets,
  types structures, signatures structurees, ASM.
  Dictionnaire par unite/portee; types nommes ordinaux/chaine, constantes
  calculees et typees, frames locales et liens statiques pour procedures.
  /B recompile les sources et produit des fichiers TPU. Unites de code:
  profil TPU9/TPC1 marque, ABI locale near, incompatible ABI Borland.
  Unites autonomes de constantes seules: layout TPU9 sans extension.
  TURBO.TPL: index TPU9 concatene, lecture directe par tranche, import des
  constantes et routines Borland. Ponts far, donnees DS separees, fixups MZ;
  initialisation/finalisation SYSTEM et initialisations des unites liees.
  Profil local v4: persistance des ponts/references natifs; types ordinaux et
  parametres shortstring natifs. ABI structuree/8087/overlays non complete.
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
 tkEOF=0;
 tkIdent=1;
 tkConstant=2;
 tkPlus=3;
 tkMinus=4;
 tkTimes=5;
 tkSlash=6;
 tkEqual=7;
 tkNE=8;
 tkGreater=9;
 tkLess=10;
 tkGE=11;
 tkLE=12;
 tkLP=13;
 tkRP=14;
 tkLB=15;
 tkRB=16;
 tkDot=17;
 tkComma=18;
 tkColon=19;
 tkSemi=20;
 tkCaret=21;
 tkAssign=22;
 tkRange=23;
 tkAt=24;
 tkAnd=28;
 tkArray=29;
 tkBegin=30;
 tkCase=31;
 tkConst=32;
 tkConstructor=33;
 tkDestructor=34;
 tkDiv=35;
 tkDo=36;
 tkDownto=37;
 tkElse=38;
 tkEnd=39;
 tkAsm=40;
 tkFile=41;
 tkFor=42;
 tkFunction=44;
 tkGoto=45;
 tkIf=46;
 tkImplementation=47;
 tkIn=48;
 tkInline=49;
 tkInterface=50;
 tkLabel=52;
 tkMod=53;
 tkNil=54;
 tkNot=55;
 tkObject=56;
 tkOf=57;
 tkOr=58;
 tkPacked=59;
 tkProcedure=60;
 tkProgram=61;
 tkRecord=62;
 tkRepeat=63;
 tkSet=64;
 tkShl=65;
 tkShr=66;
 tkString=67;
 tkThen=68;
 tkType=69;
 tkTo=70;
 tkUnit=71;
 tkUntil=72;
 tkUses=73;
 tkVar=74;
 tkWhile=76;
 tkWith=77;
 tkXor=78;
 ttVoid=0;
 ttArray=1;
 ttRecord=2;
 ttObject=3;
 ttFile=4;
 ttText=5;
 ttProc=6;
 ttSet=7;
 ttPointer=8;
 ttString=9;
 tt8087=10;
 ttReal=11;
 ttInteger=12;
 ttBoolean=13;
 ttChar=14;
 ttEnum=15;
 skVar=1;
 skConst=2;
 skProc=3;
 skForeign=4;
 skType=5;
 MaxTypes=256;
 MaxScopes=128;
 MaxNativeParams = 8;
 MaxNativeRefs = 4096;
 MaxObjects = 64;
 MaxObjSegments = 256;
 MaxObjNames = 512;
 MaxObjGroups = 128;
 MaxLinkedImage = 524288;

Type
 TShortString = String[255];
  { Packed + Word: jamais de pointeurs natifs 32/64 bits dans une TPU. }
 TUnitHeader = Packed Record
  Signature: Array[0..3] Of Char;
  Next, Link, Name, Interf, ProcMap, CodeMap, ConstMap, DataMap: Word;
  EndMaps, Units, Sources, Trace, EndTrace: Word;
  CodeSize, ConstSize, CodeFixupSize, DataFixupSize, DataSize: Word;
  DebugHash, Flags, CodeStart, CodeLength, OverlayLength: Word;
  TpuName, CodeSeg, ConstSeg, CodeFixupSeg, ConstFixupSeg: Word;
  Reserved: Array[0..9] Of Word;
 End;
 TTypeDescriptor = Packed Record
  Typ, Modifier: Byte;
  SizeOfType, Next: Word;
 End;
 TSymbolPrefix = Packed Record
  Prev: Word;
  Typ, NameLength: Byte;
 End;
 TFarAddress = Packed Record
  Offs, Segm: Word
 End;
 TTPUFixup = Packed Record
  UnitRef, Map, Target, Offs: Word
 End;
 TSegMap = Packed Record
  Addr, Len, FixupLength, Owner: Word
 End;
 TProcMap = Packed Record
  Stub, Flags, CodeMap, EntryPoint: Word
 End;
 TSymbol = Record
  Name: String[63];
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
  ParamTypes, ParamWidths, ParamFlags: Array[1..MaxNativeParams] Of Byte;
  SignedByte: Boolean;
  ParamSigned: Array[1..MaxNativeParams] Of Boolean;
  Scope, HashNext, TypeId: Word;
  Local: Boolean;
  ByReference, ResultVariable, FarRoutine, ForwardDeclared: Boolean;
  LegacyCall: Boolean;
  RoutineSymbol, ResultSymbol, ParamBytes: Word;
  ParamTypeIds: Array[1..MaxNativeParams] Of Word;
  ParamNames: Array[1..MaxNativeParams] Of String[63];
 End;
 TTypeInfo = Packed Record
  Typ, Width, Capacity: Byte;
  Signed: Boolean;
  Base: Word;
  LowBound, HighBound: Longint;
  IdentityUnit, IdentityName: String[63];
 End;
 TScopeInfo = Record
  Parent, ProcSymbol, LocalSize: Word;
  LinkOffset: Word;
  Owner: Byte;
 End;
 TConstValue = Record
  TypeId: Word;
  Value: Longint;
  Text: TShortString;
 End;
 TAddressFixup = Record
  Position, DataOffset: Word
 End;
 TRelativeFixup = Record
  Position, Target: Word
 End;
 TCondition = Record
  ParentActive, Test, SeenElse: Boolean
 End;
 TUnitSet = Set Of 0..MaxUnits;
 TBuildUnit = Record
  Name: String[63];
  State: Byte;
 { 1 = compilation en cours; 2 = compilee }
  InterfaceReady, HasInit: Boolean;
  InitAddress: Word;
  FromSource: Boolean;
  Path: TShortString;
  Dependencies: TUnitSet;
  NativeDependencies: TUnitSet;
  DependencyChecks: Array[1..MaxUnits] Of Word;
  Checksum: Word;
  CodeBase, DataBase: Word;
  LibraryEntry: Word;
 End;
 TLibraryEntry = Record
  Name: String[63];
  Offset, Size: Longint;
  Header: TUnitHeader;
 End;
 TBinaryBuffer = Array[0..262143] Of Byte;
 PBinaryBuffer = ^TBinaryBuffer;
 TNativeRef = Record
  Position, Map, Target: Word;
  U, Kind: Byte
 End;
 TMZRelocation = Packed Record
  Offs, Segm: Word
 End;
 TLinkedImage = Array[0..MaxLinkedImage-1] Of Byte;
 PLinkedImage = ^TLinkedImage;
 TObjectFile = Record
  Path: TShortString;
  Owner: Byte;
  Bytes: PBinaryBuffer;
  Length: Longint;
 End;
 TObjectSegment = Record
  Name, ClassName: String[63];
  Combine, Alignment: Byte;
  Root: Word;
  Length, Contribution, Base: Longint;
  Bytes: PBinaryBuffer;
 End;
 TObjectGroup = Record
  Name: String[63];
  Members: Array[1..MaxObjSegments] Of Word;
  Count: Word;
  Base: Longint;
 End;
 TObjectPublic = Record
  Name: String[63];
  Segment, GroupIndex, Offset: Word;
 End;
 TObjectFixup = Record
  Segment, Offset, FrameIndex, TargetIndex, Displacement: Word;
  Location, FrameMethod, TargetMethod: Byte;
  Relative: Boolean;
 End;
 TObjectCall = Record
  Name: String[63];
  Position: Word;
 End;
 TSourceBuffer = Array[1..MaxSource] Of Char;
 PSourceBuffer = ^TSourceBuffer;
 PParserState = ^TParserState;
 TParserState = Record
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
  ImportOrder: Array[1..MaxUnits] Of Byte;
  ImportCount: Byte;
  Conditions: Array[1..32] Of TCondition;
  Defines: Array[1..MaxDefines] Of String[63];
  DefineCount, OptionBits, StackSize, MinHeap, MaxHeap: Word;
  CurrentScope: Word;
 End;

Var
 Source: Array[1..MaxSource] Of Char;
 Image, Data: Array[0..MaxImage-1] Of Byte;
 Symbols: Array[1..MaxSymbols] Of TSymbol;
 Types: Array[1..MaxTypes] Of TTypeInfo;
 Scopes: Array[0..MaxScopes] Of TScopeInfo;
 Dictionary: Array[0..63] Of Word;
 TypeCount, ScopeCount, CurrentScope, ExprType: Word;
 NativeTypeOwners: Array[1..MaxTypes] Of Byte;
 NativeTypeOffsets: Array[1..MaxTypes] Of Word;
 ExprUnsigned: Boolean;
 ExprKnown: Boolean;
 ExprValue: Longint;
 Fixups: Array[1..MaxFixups] Of TAddressFixup;
 RelativeFixups: Array[1..MaxFixups] Of TRelativeFixup;
 RelativeCount: Word;
 CodeOwners, DataOwners: Array[0..MaxImage-1] Of Byte;
 Defines: Array[1..MaxDefines] Of String[63];
 Conditions: Array[1..32] Of TCondition;
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
 LibraryUnits: Array[1..MaxLibraryUnits] Of TLibraryEntry;
 LibraryCount: Word;
 OptionBits, StackSize, MinHeap, MaxHeap: Word;
 BuildMode, MakeMode, Quiet, InProcedure: Boolean;
 EntryFixup, RuntimeString, RuntimeInteger, RuntimeChar: Word;
 RuntimeBoolean, RuntimeCopy: Word;
 NumberBuffer, TrueText, FalseText: Word;
 Units: Array[1..MaxUnits] Of TBuildUnit;
 InitOrder: Array[1..MaxUnits] Of Byte;
 UnitCount, InitCount, CurrentUnit: Byte;
 Imports: TUnitSet;
 ImportOrder: Array[1..MaxUnits] Of Byte;
 ImportCount: Byte;
 InInterface: Boolean;
 MainSourceName: TShortString;
 InitialDefines: Array[1..MaxDefines] Of String[63];
 InitialDefineCount, InitialOptions: Word;
 UnitOutput: Boolean;
 NativeBuffers: Array[1..MaxUnits] Of PBinaryBuffer;
 NativeHeaders: Array[1..MaxUnits] Of TUnitHeader;
 NativeCodeBases, NativeConstBases, NativeVarBases: Array[1..MaxUnits] Of Word;
 NativeActive: Array[1..MaxUnits] Of Boolean;
 NativeData: Array[0..MaxImage-1] Of Byte;
 NativeDataSize: Word;
 NativeRefs: Array[1..MaxNativeRefs] Of TNativeRef;
 NativeRefCount: Word;
 Relocations: Array[1..MaxNativeRefs] Of TMZRelocation;
 RelocationKinds: Array[1..MaxNativeRefs] Of Byte;
 RelocationCount: Word;
 NativeNeeded: Boolean;
 RuntimeHalt, MainEntry: Word;
 RuntimeUnsigned: Word;
 NativeInitOrder: Array[1..MaxUnits] Of Byte;
 NativeInitCount: Byte;
 ObjectFiles: Array[1..MaxObjects] Of TObjectFile;
 ObjectCount: Word;
 ObjectSegments: Array[1..MaxObjSegments] Of TObjectSegment;
 ObjectSegmentCount: Word;
 ObjectGroups: Array[1..MaxObjGroups] Of TObjectGroup;
 ObjectGroupCount: Word;
 ObjectPublics: Array[1..MaxObjNames] Of TObjectPublic;
 ObjectPublicCount: Word;
 ObjectExternals: Array[1..MaxObjNames] Of String[63];
 ObjectExternalCount: Word;
 ObjectFixups: Array[1..MaxFixups] Of TObjectFixup;
 ObjectFixupCount: Word;
 ObjectCalls: Array[1..MaxSymbols] Of TObjectCall;
 ObjectCallCount: Word;
 LinkedImage: PLinkedImage;
 LinkedSize: Longint;
Procedure ActivateNative(U: Byte);Forward;
 Procedure QueueObject(Name: TShortString);Forward;

Function Upper(S: TShortString): TShortString;
Var
 I: Integer;
Begin
 For I:=1 To Length(S) Do S[I]:=UpCase(S[I]);
 Upper:=S;
End;

Function HashIdent(S: TShortString): Byte;
Var
 I: Integer;
 H: Word;
Begin
 H:=0;
 For I:=1 To Length(S) Do H:=(H+Ord(UpCase(S[I]))-1) And 255;
 HashIdent:=(H*2) And 255;
End;

Function ErrorMessage(N: Word): TShortString;Begin
 Case N Of
  2:ErrorMessage:='Identifier expected';
  3:ErrorMessage:='Unknown identifier';
  4:ErrorMessage:='Duplicate identifier';
  5:ErrorMessage:='Syntax error';
  7:ErrorMessage:='Error in integer constant';
  8:ErrorMessage:='String constant exceeds line';
  10:ErrorMessage:='Unexpected end of file';
  12:ErrorMessage:='Type identifier expected';
  15:ErrorMessage:='File not found';
  16:ErrorMessage:='Disk full';
  17:ErrorMessage:='Invalid compiler directive';
  20:ErrorMessage:='Variable identifier expected';
  25:ErrorMessage:='Invalid string length';
  26:ErrorMessage:='Type mismatch';
  27:ErrorMessage:='Invalid subrange base type';
  28:ErrorMessage:='Lower bound greater than upper bound';
  31:ErrorMessage:='Constant expected';
  34:ErrorMessage:='Invalid function result type';
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
  61:ErrorMessage:='Division by zero';
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
  97:ErrorMessage:='Invalid FOR control variable';
  101:ErrorMessage:='String length mismatch';
 106:ErrorMessage:='Character expression expected';
 120:ErrorMessage:='NIL expected';
 123:ErrorMessage:='Too many symbols';
 127:ErrorMessage:='Misplaced conditional directive';
 128:ErrorMessage:='ENDIF directive missing';
  130:ErrorMessage:='Header does not match previous definition';
 Else ErrorMessage:='Compiler error';
End;
End;

Procedure Fail(N: Word; S: TShortString);Begin
 WriteLn(SourceName,'(',TokenLine,',',TokenColumn,'): Error ',N,': ',ErrorMessage(N),
 ' (',S,')');
 Halt(1);
End;

Procedure Unsupported(S: TShortString);Begin
 WriteLn(SourceName,'(',TokenLine,',',TokenColumn,
 '): TPC: fonctionnalite non implementee: ',S);
 Halt(2);
End;

Procedure CLIError(S: TShortString);Begin
 WriteLn('TPC: ',S);
 Halt(2);
End;

Function Peek: Char;Begin
 If SourcePos>SourceSize Then Peek:=#0 Else Peek:=Source[SourcePos];
End;

Function PeekNext: Char;Begin
 If SourcePos>=SourceSize Then PeekNext:=#0 Else PeekNext:=Source[SourcePos+1];
End;

Procedure Advance;Begin
 If Peek=#10 Then Begin
  Inc(Line); Column:=1
 End
 Else Inc(Column);
 Inc(SourcePos);
End;

Procedure AppendChar(Var S: TShortString; C: Char);Begin
 If Length(S)=255 Then Unsupported('chaine ou lexeme > 255 octets');
 S:=S+C;
End;

Function IsDefined(S: TShortString): Boolean;
Var
 I: Word;
Begin
 S:=Upper(S);
 IsDefined:=False;
 For I:=1 To DefineCount Do If Defines[I]=S Then IsDefined:=True;
End;

Procedure Define(S: TShortString);Begin
 S:=Upper(S);
 If (S='') Or (Length(S)>63) Then Fail(2,'Identificateur de define attendu');
 If Not IsDefined(S) Then Begin
  If DefineCount=MaxDefines Then Unsupported('trop de defines');
  Inc(DefineCount); Defines[DefineCount]:=S;
 End;
End;

Procedure Undefine(S: TShortString);
Var
 I: Word;
Begin
 S:=Upper(S);
 For I:=1 To DefineCount Do If Defines[I]=S Then Defines[I]:='';
End;

Function Trim(S: TShortString): TShortString;Begin
 While (Length(S)>0) And (S[1]<=' ') Do Delete(S,1,1);
 While (Length(S)>0) And (S[Length(S)]<=' ') Do Delete(S,Length(S),1);
 Trim:=S;
End;

Function SwitchBit(C: Char): Word;Begin
 Case UpCase(C) Of
 'I':SwitchBit:=$0001; 'R':SwitchBit:=$0002; 'S':SwitchBit:=$0004;
 'X':SwitchBit:=$0008; 'V':SwitchBit:=$0010; 'F':SwitchBit:=$0020;
 'B':SwitchBit:=$0040; 'N':SwitchBit:=$0080; 'D':SwitchBit:=$0100;
 'L':SwitchBit:=$0200; 'E':SwitchBit:=$0400; 'O':SwitchBit:=$0800;
 'A':SwitchBit:=$1000; 'G':SwitchBit:=$2000;
 Else SwitchBit:=0;
End;
End;

Procedure SetSwitch(S: TShortString);
Var
 B: Word;
Begin
 If (Length(S)<>2) Or Not (S[2] In ['+','-']) Then    CLIError(
 'Option attendue sous la forme $X+ ou $X-');
 B:=SwitchBit(S[1]);
 If B=0 Then CLIError('Option inconnue: $'+S);
  { Accepter une option sans en respecter l'effet serait trompeur. }
 If S[2]='+' Then Begin
  If UpCase(S[1]) In ['R','S','B','N','G','D','L','O','X'] Then      Unsupported(
  'option $'+Upper(S));
  OptionBits:=OptionBits Or B;
 End Else OptionBits:=OptionBits And Not B;
End;

Procedure MemoryDirective(S: TShortString);
Var
 A: Array[1..3] Of Longint;
 I, P, E: Integer;
 Part: TShortString;
Begin
 For I:=1 To 3 Do Begin
  P:=Pos(',',S);
  If P=0 Then Begin
   Part:=Trim(S); S:=''
  End
   Else
  Begin
   Part:=Trim(Copy(S,1,P-1)); Delete(S,1,P)
  End;
  Val(Part,A[I],E);
  If E<>0 Then Fail(17,'Directive $M incorrecte');
 End;
 If (S<>'') Or (A[1]<1024) Or (A[1]>65520) Or
 (A[2]<0) Or (A[2]>655360) Or (A[3]<A[2]) Or (A[3]>655360) Then    Fail(17,
 'Limites $M incorrectes');
 If A[2]<>0 Then Unsupported('$M minheap non nul');
 StackSize:=(A[1]+1) And $FFFE;
 MinHeap:=0; MaxHeap:=(A[3]+15) Div 16;
End;

Procedure Directive(S: TShortString);
Var
 P: Integer;
 Cmd, Arg: TShortString;
 Test: Boolean;
Begin
 S:=Trim(S);
 P:=1;
 While (P<=Length(S)) And (S[P]>' ') Do Inc(P);
 Cmd:=Upper(Copy(S,1,P-1)); Arg:=Trim(Copy(S,P+1,255));
 If (Cmd='IFDEF') Or (Cmd='IFNDEF') Then Begin
  If CondDepth=32 Then Unsupported('imbrication conditionnelle > 32');
  Test:=IsDefined(Arg); If Cmd='IFNDEF' Then Test:=Not Test;
  Inc(CondDepth);
  Conditions[CondDepth].ParentActive:=Active;
  Conditions[CondDepth].Test:=Test;
  Conditions[CondDepth].SeenElse:=False;
  Active:=Active And Test;
 End Else If Cmd='ELSE' Then Begin
  If CondDepth=0 Then Fail(127,'$ELSE sans $IFDEF');
  If Conditions[CondDepth].SeenElse Then Fail(127,'$ELSE duplique');
  Conditions[CondDepth].SeenElse:=True;
  Active:=Conditions[CondDepth].ParentActive And Not Conditions[CondDepth].Test;
 End Else If Cmd='ENDIF' Then Begin
  If CondDepth=0 Then Fail(127,'$ENDIF sans $IFDEF');
  Active:=Conditions[CondDepth].ParentActive; Dec(CondDepth);
 End Else If Active Then Begin
  If Cmd='DEFINE' Then Define(Arg) Else
  If Cmd='UNDEF' Then Undefine(Arg) Else
  If (Cmd='L') Or (Cmd='LINK') Then QueueObject(Arg) Else
  If (Length(Cmd)=2) And (Cmd[2] In ['+','-']) Then SetSwitch(Cmd) Else
  If (Length(Cmd)>0) And (Cmd[1]='M') Then      MemoryDirective(Trim(Copy(S,2,255)))
                                      Else Unsupported('directive $'+S);
 End;
End;

Procedure SkipComment(Paren: Boolean);
Var
 S: TShortString;
 IsDirective, Closed: Boolean;
Begin
 Advance; If Paren Then Advance;
 IsDirective:=Peek='$'; If IsDirective Then Advance;
 S:=''; Closed:=False;
 While (Peek<>#0) And Not Closed Do Begin
  If (Not Paren And (Peek='}')) Or
  (Paren And (Peek='*') And (PeekNext=')')) Then Begin
   Advance; If Paren Then Advance; Closed:=True;
  End Else
  Begin
   If IsDirective Then AppendChar(S,Peek);
   Advance;
  End;
 End;
 If Not Closed Then Fail(10,'Fin de fichier dans un commentaire');
 If IsDirective Then Directive(S);
End;

Function Keyword(S: TShortString): Byte;
Const
 Names: Array[1..49] Of String[14] = (
 'AND','ARRAY','BEGIN','CASE','CONST','CONSTRUCTOR','DESTRUCTOR','DIV',
 'DO','DOWNTO','ELSE','END','ASM','FILE','FOR','FUNCTION','GOTO','IF',
 'IMPLEMENTATION','IN','INLINE','INTERFACE','LABEL','MOD','NIL','NOT',
 'OBJECT','OF','OR','PACKED','PROCEDURE','PROGRAM','RECORD','REPEAT',
 'SET','SHL','SHR','STRING','THEN','TYPE','TO','UNIT','UNTIL','USES',
 'VAR','WHILE','WITH','XOR','');
 Values: Array[1..49] Of Byte = (
 28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,44,45,46,47,48,49,
 50,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,
 72,73,74,76,77,78,1);
Var
 I: Integer;
Begin
 Keyword:=tkIdent;
 For I:=1 To 48 Do If S=Names[I] Then Keyword:=Values[I];
End;

Function ReadNumber: Longint;
Var
 Base, Digit: Integer;
 N: Longint;
 C: Char;
Begin
 Base:=10; N:=0;
 If Peek='$' Then Begin
  Base:=16; Advance
 End;
 If ((Base=10) And Not (Peek In ['0'..'9'])) Or
 ((Base=16) And Not (UpCase(Peek) In ['0'..'9','A'..'F'])) Then    Fail(7,
 'Nombre attendu');
 While True Do Begin
  C:=UpCase(Peek);
  If C In ['0'..'9'] Then Digit:=Ord(C)-Ord('0') Else
  If (Base=16) And (C In ['A'..'F']) Then Digit:=Ord(C)-Ord('A')+10
                                     Else Break;
  If Digit>=Base Then Break;
  If N>(2147483647-Digit) Div Base Then Fail(7,'Constante hors limites');
  N:=N*Base+Digit; Advance;
 End;
 ReadNumber:=N;
End;

Procedure NextToken;
Var
 C: Char;
 N: Longint;
 Closed: Boolean;
Begin
 Repeat
 While (Peek<>#0) And (Peek<=' ') Do Advance;
 TokenLine:=Line; TokenColumn:=Column;
 If Peek='{' Then SkipComment(False) Else
 If (Peek='(') And (PeekNext='*') Then SkipComment(True) Else
 If Not Active And (Peek<>#0) Then Advance
                              Else Break;
 Until False;
 TokenText:=''; TokenValue:=0; TokenIsString:=False;
 TokenLine:=Line; TokenColumn:=Column; C:=Peek;
 If C=#0 Then Begin
  If CondDepth<>0 Then Fail(128,'$ENDIF manquant');
  Token:=tkEOF; Exit;
 End;
 If UpCase(C) In ['A'..'Z','_'] Then Begin
  While UpCase(Peek) In ['A'..'Z','0'..'9','_'] Do Begin
   AppendChar(TokenText,UpCase(Peek)); Advance;
  End;
  If Length(TokenText)>63 Then Unsupported('identificateur > 63 caracteres');
  Token:=Keyword(TokenText); Exit;
 End;
 If C In ['0'..'9','$'] Then Begin
  Token:=tkConstant; TokenValue:=ReadNumber;
  If (Peek='.') And (PeekNext<>'.') Then Unsupported('constantes reelles');
  If UpCase(Peek)='E' Then Unsupported('constantes reelles');
  Exit;
 End;
 If C In ['''','#'] Then Begin
  Token:=tkConstant; TokenIsString:=True;
  Repeat
  If Peek='#' Then Begin
   Advance; N:=ReadNumber;
   If N>255 Then Fail(76,'Code caractere hors limites');
   AppendChar(TokenText,Chr(N));
  End Else
  Begin
   Advance; Closed:=False;
   While Not Closed Do Begin
    If Peek In [#0,#10,#13] Then Fail(8,'Chaine non terminee');
    If Peek='''' Then Begin
     Advance;
     If Peek='''' Then Begin
      AppendChar(TokenText,''''); Advance
     End
     Else Closed:=True;
    End Else
    Begin
     AppendChar(TokenText,Peek); Advance
    End;
   End;
  End;
  Until Not (Peek In ['''','#']);
  Exit;
 End;
 Advance;
 Case C Of
 '+':Token:=tkPlus; '-':Token:=tkMinus; '*':Token:=tkTimes;
 '/':Token:=tkSlash; '=':Token:=tkEqual; '(':Token:=tkLP;
 ')':Token:=tkRP; '[':Token:=tkLB; ']':Token:=tkRB;
 ',':Token:=tkComma; ';':Token:=tkSemi; '^':Token:=tkCaret; '@':Token:=tkAt;
 ':':
 Begin
  Token:=tkColon; If Peek='=' Then Begin
   Advance; Token:=tkAssign
  End
 End;
 '.':
 Begin
  Token:=tkDot; If Peek='.' Then Begin
   Advance; Token:=tkRange
  End
 End;
 '<':
 Begin
  Token:=tkLess;
  If Peek='=' Then Begin
   Advance; Token:=tkLE
  End
  Else If Peek='>' Then Begin
   Advance; Token:=tkNE
  End;
 End;
 '>':
 Begin
  Token:=tkGreater; If Peek='=' Then Begin
   Advance; Token:=tkGE
  End
 End;
 Else Fail(5,'Caractere inattendu');
End;
End;

Procedure Need(T: Byte);
Var
 E: Word;
Begin
 If Token<>T Then Begin
  Case T Of
  tkIdent:E:=2; tkBegin:E:=36; tkEnd:E:=37; tkDo:E:=50;
  tkOf:E:=54; tkInterface:E:=55; tkThen:E:=57;
  tkImplementation:E:=73; tkUnit:E:=84;
  tkSemi:E:=85; tkColon:E:=86; tkComma:E:=87; tkLP:E:=88;
  tkRP:E:=89; tkEqual:E:=90; tkAssign:E:=91; tkLB:E:=92;
  tkRB:E:=93; tkDot:E:=94; tkRange:E:=95; tkNil:E:=120;
  Else E:=5;
 End;
 Fail(E,'Symbole attendu');
End;
NextToken;
End;

Procedure Emit(B: Byte);Begin
 If CodeSize=MaxImage Then Fail(48,'Segment de code trop grand');
 CodeOwners[CodeSize]:=CurrentUnit;
 Image[CodeSize]:=B; Inc(CodeSize);
End;

Procedure EmitWord(W: Word);Begin
 Emit(W And 255); Emit(W Shr 8)
End;

Procedure PatchWord(P, W: Word);Begin
 Image[P]:=W And 255; Image[P+1]:=W Shr 8
End;

Procedure Emit2(A,B: Byte);Begin
 Emit(A); Emit(B)
End;

Function Jump: Word;Begin
 Emit($E9); Jump:=CodeSize; EmitWord(0)
End;

Procedure PatchJump(P, Target: Word);
Var
 I: Word;
Begin
 PatchWord(P,Word(Longint(Target)-P-2));
 If CodeOwners[P]=0 Then Exit;
 For I:=1 To RelativeCount Do If RelativeFixups[I].Position=P Then Begin
  RelativeFixups[I].Target:=Target; Exit;
 End;
 If RelativeCount=MaxFixups Then Unsupported('trop de references de code');
 Inc(RelativeCount); RelativeFixups[RelativeCount].Position:=P;
 RelativeFixups[RelativeCount].Target:=Target;
End;

Procedure JumpTo(Target: Word);
Var
 P: Word;
Begin
 P:=Jump; PatchJump(P,Target)
End;

Function JumpZero: Word;Begin
 Emit2($09,$C0);             { or ax,ax }
 Emit2($75,$03);             { jnz +3: 8086 n'a pas Jcc near }
 JumpZero:=Jump;
End;

Procedure CallTo(Target: Word);
Var
 P: Word;
Begin
 Emit($E8); P:=CodeSize; EmitWord(0); PatchJump(P,Target)
End;

Procedure LoadImmediate(W: Word);Begin
 Emit($B8); EmitWord(W)
End;

Procedure DataAddress(Offs: Word);Begin
 If FixupCount=MaxFixups Then Unsupported('trop de references de donnees');
 Inc(FixupCount); Fixups[FixupCount].Position:=CodeSize;
 Fixups[FixupCount].DataOffset:=Offs; EmitWord(0);
End;

Function AllocData(N: Word): Word;
Var
 I: Word;
Begin
 If Longint(DataSize)+N>MaxImage Then Fail(49,'Segment de donnees trop grand');
 If N<>0 Then
 For I:=DataSize To DataSize+N-1 Do DataOwners[I]:=CurrentUnit;
 AllocData:=DataSize; Inc(DataSize,N);
End;

Function StoreString(S: TShortString): Word;
Var
 A: Word;
 I: Integer;
Begin
 A:=AllocData(Length(S)+1); Data[A]:=Ord(S[0]);
 For I:=1 To Length(S) Do Data[A+I]:=Ord(S[I]);
 StoreString:=A;
End;

Function FindAtScope(S: TShortString; Owner: Byte; Scope: Word): Word;
Var I: Word;
Begin
 I:=Dictionary[(HashIdent(S) And 126) Div 2];
 While I<>0 Do Begin
  If (Symbols[I].Name=S) And (Symbols[I].Owner=Owner) And
    (Symbols[I].Scope=Scope) Then Begin FindAtScope:=I; Exit End;
  I:=Symbols[I].HashNext;
 End;
 FindAtScope:=0;
End;

Function FindOwnSymbol(S: TShortString): Word;
Begin FindOwnSymbol:=FindAtScope(S,CurrentUnit,CurrentScope) End;

Function FindLexicalSymbol(S: TShortString): Word;
Var Scope,I: Word;
Begin
 Scope:=CurrentScope;
 Repeat
  I:=FindAtScope(S,CurrentUnit,Scope);
  If I<>0 Then Begin FindLexicalSymbol:=I; Exit End;
  If Scope=0 Then Break;
  Scope:=Scopes[Scope].Parent;
 Until False;
 FindLexicalSymbol:=0;
End;

Function FindSymbol(S: TShortString): Word;
Var
 I: Word;
 J: Integer; Scope: Word;
Begin
 Scope:=CurrentScope;
 Repeat
  I:=FindAtScope(S,CurrentUnit,Scope);
  If I<>0 Then Begin FindSymbol:=I; Exit End;
  If Scope=0 Then Break;
  Scope:=Scopes[Scope].Parent;
 Until False;
 FindSymbol:=0;
 For J:=ImportCount Downto 1 Do
 Begin
 I:=FindAtScope(S,ImportOrder[J],0);
 If (I<>0) And Symbols[I].Exported Then Begin
  FindSymbol:=I; Exit
 End;
 End;
 FindSymbol:=FindAtScope(S,255,0);
End;

Procedure AddImport(U: Byte);
Var
 I, J: Byte;
Begin
  { Ne pas reconstruire une unite deja compilee; sa priorite de recherche
    depend de la clause uses courante et non de l'ordre de compilation. }
 For I:=1 To ImportCount Do If ImportOrder[I]=U Then Begin
  For J:=I To ImportCount-1 Do ImportOrder[J]:=ImportOrder[J+1];
  Dec(ImportCount); Break;
 End;
 Inc(ImportCount); ImportOrder[ImportCount]:=U;
 Imports:=Imports+[U];
 If (CurrentUnit<>0) And (Units[U].Name<>'SYSTEM')
 Then    Units[CurrentUnit].Dependencies:=Units[CurrentUnit].Dependencies+[U];
End;

Function FindBuildUnit(S: TShortString): Byte;
Var
 I: Byte;
Begin
 FindBuildUnit:=0;
 For I:=1 To UnitCount Do If Units[I].Name=S Then FindBuildUnit:=I;
End;
{ Le premier identificateur est deja consomme. Gere Unite.Symbole sans
  rendre accessibles les symboles prives ou les dependances transitives. }

Function ResolveSymbol(Name: TShortString): Word;
Var
 U: Byte;
 I: Word;
Begin
 If Token<>tkDot Then Begin
  I:=FindSymbol(Name);
  If I=0 Then Fail(3,'Identificateur inconnu: '+Name);
  If Symbols[I].Kind=skForeign Then      Unsupported('symbole Borland '+
  Units[Symbols[I].Owner].Name+'.'+Name+
  ': signature hors du sous-ensemble ABI');
  ResolveSymbol:=I; Exit;
 End;
 U:=FindBuildUnit(Name);
 If (U=0) Or Not ((U In Imports) Or (U=CurrentUnit)) Then    Fail(3,'Unite inconnue: '+
 Name);
 NextToken;
 If Token<>tkIdent Then Fail(2,'Identificateur qualifie attendu');
 I:=0;
 For I:=1 To SymbolCount Do    If (Symbols[I].Owner=U) And (Symbols[I].Name=TokenText) And
 (Symbols[I].Scope=0) And (Symbols[I].Exported Or (U=CurrentUnit)) Then Begin
  If Symbols[I].Kind=skForeign Then        Unsupported('symbole Borland '+Name+'.'+
  TokenText+
  ': signature hors du sous-ensemble ABI');
  ResolveSymbol:=I; NextToken; Exit;
 End;
 Fail(3,'Identificateur inconnu: '+Name+'.'+TokenText);
End;

Function NewSymbol(S: TShortString): Word;
Var Bucket: Word;
Begin
 If FindOwnSymbol(S)<>0 Then Fail(4,'Identificateur duplique: '+S);
 If SymbolCount=MaxSymbols Then Fail(123,'Table des symboles pleine');
 Inc(SymbolCount); FillChar(Symbols[SymbolCount],SizeOf(TSymbol),0);
 Symbols[SymbolCount].Owner:=CurrentUnit;
 Symbols[SymbolCount].Scope:=CurrentScope;
 Symbols[SymbolCount].Exported:=InInterface And (CurrentScope=0);
 Bucket:=(HashIdent(S) And 126) Div 2;
 Symbols[SymbolCount].HashNext:=Dictionary[Bucket]; Dictionary[Bucket]:=SymbolCount;
 Symbols[SymbolCount].Name:=S; NewSymbol:=SymbolCount;
End;

Function NewType(Typ, Width, Capacity: Byte; Signed: Boolean;
                 LowBound, HighBound: Longint; Base: Word): Word;
Begin
 If TypeCount=MaxTypes Then Fail(123,'Table des types pleine');
 Inc(TypeCount); FillChar(Types[TypeCount],SizeOf(TTypeInfo),0);
 Types[TypeCount].Typ:=Typ; Types[TypeCount].Width:=Width;
 Types[TypeCount].Capacity:=Capacity; Types[TypeCount].Signed:=Signed;
 Types[TypeCount].LowBound:=LowBound; Types[TypeCount].HighBound:=HighBound;
 If Base=0 Then Base:=TypeCount;
 Types[TypeCount].Base:=Base; NewType:=TypeCount;
End;

Procedure InitTypes;
Begin
 TypeCount:=0;
 FillChar(NativeTypeOwners,SizeOf(NativeTypeOwners),0);
 FillChar(NativeTypeOffsets,SizeOf(NativeTypeOffsets),0);
 TypeCount:=NewType(ttInteger,2,0,True,-32768,32767,0);
 TypeCount:=NewType(ttInteger,1,0,False,0,255,1);
 TypeCount:=NewType(ttInteger,2,0,False,0,65535,1);
 TypeCount:=NewType(ttInteger,1,0,True,-128,127,1);
 TypeCount:=NewType(ttBoolean,1,0,False,0,1,0);
 TypeCount:=NewType(ttChar,1,0,False,0,255,0);
 TypeCount:=NewType(ttString,0,255,False,0,255,0);
End;

Function BuiltinType(S: TShortString): Word;
Begin
 BuiltinType:=0;
 If S='INTEGER' Then BuiltinType:=1 Else If S='BYTE' Then BuiltinType:=2
 Else If S='WORD' Then BuiltinType:=3 Else If S='SHORTINT' Then BuiltinType:=4
 Else If S='BOOLEAN' Then BuiltinType:=5 Else If S='CHAR' Then BuiltinType:=6
 Else If S='STRING' Then BuiltinType:=7;
End;

Procedure ApplyType(I, T: Word);
Begin
 Symbols[I].TypeId:=T; Symbols[I].Typ:=Types[T].Typ;
 Symbols[I].Width:=Types[T].Width; Symbols[I].Capacity:=Types[T].Capacity;
 Symbols[I].SignedByte:=Types[T].Signed And (Types[T].Width=1);
End;

Procedure InstallStandardTypes;
Const Names: Array[1..7] Of String[8]=('INTEGER','BYTE','WORD','SHORTINT','BOOLEAN','CHAR','STRING');
Var T,I: Word;
Begin
 CurrentUnit:=255;
 For T:=1 To 7 Do Begin I:=NewSymbol(Names[T]); Symbols[I].Kind:=skType; ApplyType(I,T) End;
 CurrentUnit:=0;
End;

Function SymbolType(I: Word): Word;
Begin
 If Symbols[I].TypeId<>0 Then Begin SymbolType:=Symbols[I].TypeId; Exit End;
 Case Symbols[I].Typ Of
  ttBoolean:SymbolType:=5; ttChar:SymbolType:=6; ttString:SymbolType:=7;
  ttInteger:Begin
   If Symbols[I].Width=1 Then Begin
    If Symbols[I].SignedByte Then SymbolType:=4 Else SymbolType:=2;
   End Else SymbolType:=1;
  End;
 Else SymbolType:=0;
 End;
End;

Function CompatibleTypes(A, B: Word): Boolean;
Begin
 CompatibleTypes:=(A=0) Or (B=0);
 If (A<>0) And (B<>0) Then
  CompatibleTypes:=(Types[A].Typ=Types[B].Typ) And (Types[A].Base=Types[B].Base);
End;

Procedure ScopeAddress(Scope: Word);
Var S: Word;
Begin
 Emit2($89,$EB); { bx=bp }
 S:=CurrentScope;
 While S<>Scope Do Begin
  If S=0 Then Unsupported('lien statique vers une portee non accessible');
  Emit($36); Emit2($8B,$9F); EmitWord(Scopes[S].LinkOffset);
  S:=Scopes[S].Parent;
 End;
End;

Procedure AddSegmentRelocation(P: Word; Kind: Byte);Begin
 If RelocationCount=MaxNativeRefs Then Unsupported('trop de relocalisations MZ');
 Inc(RelocationCount); Relocations[RelocationCount].Offs:=P;
 Relocations[RelocationCount].Segm:=0; RelocationKinds[RelocationCount]:=Kind;
End;

Procedure EmitLocalCall(I: Word);
Begin
 ScopeAddress(Symbols[I].Scope); Emit($53);
 If Symbols[I].FarRoutine Then Emit($0E);
 CallTo(Symbols[I].Addr);
 If Symbols[I].LegacyCall Then Begin Emit2($83,$C4); Emit(2) End;
End;

Procedure ProcedureExit;
Var I: Word;
Begin
 I:=Scopes[CurrentScope].ProcSymbol;
 If Symbols[I].ResultSymbol<>0 Then Begin
  { AX/AL contient le resultat ordinal apres restauration de la frame. }
  Emit2($8B,$86); EmitWord(Symbols[Symbols[I].ResultSymbol].Addr);
  If Symbols[I].Width=1 Then Begin
   If Symbols[I].SignedByte Then Emit($98) Else Emit2($30,$E4);
  End;
 End;
 Emit2($89,$EC); Emit($5D);
 If Symbols[I].FarRoutine Then Emit($CA) Else Emit($C2);
 EmitWord(Symbols[I].ParamBytes+2); { parametres + lien statique local }
End;

Procedure NativeReference(U, Kind: Byte; Map, Target: Word);Begin
 If NativeRefCount=MaxNativeRefs Then Unsupported('trop de references Borland');
 Inc(NativeRefCount); NativeRefs[NativeRefCount].Position:=CodeSize;
 NativeRefs[NativeRefCount].U:=U; NativeRefs[NativeRefCount].Kind:=Kind;
 NativeRefs[NativeRefCount].Map:=Map; NativeRefs[NativeRefCount].Target:=Target;
 EmitWord(0);
End;

Procedure NeedNative(U: Byte);Begin
 If CurrentUnit<>0 Then
  Units[CurrentUnit].NativeDependencies:=Units[CurrentUnit].NativeDependencies+[U];
 NativeNeeded:=True; ActivateNative(U);
End;

Procedure SetNativeDS;Begin
 Emit($BA); AddSegmentRelocation(CodeSize,1); EmitWord(0);
 Emit2($8E,$DA); { mov ds,dx; preserve AX }
End;

Procedure NativeVarAddress(I: Word);
Var
 K: Byte;
Begin
 K:=1; If Symbols[I].NativeConst Then K:=2;
 NativeReference(Symbols[I].Owner,K,Symbols[I].NativeMap,Symbols[I].Addr);
End;

Procedure ReferencePointer(I: Word);
Begin
 ScopeAddress(Symbols[I].Scope);
 Emit($36); Emit2($C4,$BF); EmitWord(Symbols[I].Addr); { les di,ss:[bx+offset] }
End;

Procedure PushVariableAddress(I: Word);
Begin
 If Symbols[I].ByReference Then Begin
  ReferencePointer(I); Emit($06); Emit($57);
 End Else If Symbols[I].Native Then Begin
  NeedNative(Symbols[I].Owner);
  Emit($B8); AddSegmentRelocation(CodeSize,1); EmitWord(0); Emit($50);
  Emit($B8); NativeVarAddress(I); Emit($50);
 End Else If Symbols[I].Local Then Begin
  ScopeAddress(Symbols[I].Scope); Emit2($81,$C3); EmitWord(Symbols[I].Addr);
  Emit($16); Emit($53);
 End Else Begin
  Emit($1E); Emit($B8); DataAddress(Symbols[I].Addr); Emit($50);
 End;
End;

Procedure LoadSymbol(I: Word);Begin
 If Symbols[I].Kind=skType Then Fail(42,'Type utilise comme valeur');
 If (Symbols[I].Kind=skConst) And (Symbols[I].Typ<>ttString) And
    ((Symbols[I].Value<-32768) Or (Symbols[I].Value>65535)) Then
  Unsupported('valeur constante hors code ordinal 16 bits');
 If Symbols[I].ByReference Then Begin
  ReferencePointer(I); Emit($26);
  If Symbols[I].Width=1 Then Emit2($8A,$05) Else Emit2($8B,$05);
  If Symbols[I].Width=1 Then Begin
   If Symbols[I].SignedByte Then Emit($98) Else Emit2($30,$E4);
  End;
 End Else If Symbols[I].Local Then Begin
  ScopeAddress(Symbols[I].Scope); Emit($36);
  If Symbols[I].Width=1 Then Emit2($8A,$87) Else Emit2($8B,$87);
  EmitWord(Symbols[I].Addr);
  If Symbols[I].Width=1 Then Begin
   If Symbols[I].SignedByte Then Emit($98) Else Emit2($30,$E4);
  End;
 End Else If Symbols[I].Native And (Symbols[I].Kind=skVar) Then Begin
  NeedNative(Symbols[I].Owner); Emit($1E); SetNativeDS;
  If Symbols[I].Width=1 Then Emit($A0) Else Emit($A1);
  NativeVarAddress(I); Emit($1F);
  If Symbols[I].Width=1 Then Begin
   If Symbols[I].SignedByte Then Emit($98) Else Emit2($30,$E4);
  End;
 End Else If Symbols[I].Kind=skConst Then Begin
  If Symbols[I].Typ=ttString Then Begin
   Emit($B8); DataAddress(Symbols[I].Addr)
  End
  Else LoadImmediate(Word(Symbols[I].Value));
 End Else If Symbols[I].Typ=ttString Then Begin
  Emit($B8); DataAddress(Symbols[I].Addr);
 End Else If Symbols[I].Width=1 Then Begin
  Emit($A0); DataAddress(Symbols[I].Addr);
  If Symbols[I].SignedByte Then Emit($98) Else Emit2($30,$E4);
 End Else
 Begin
  Emit($A1); DataAddress(Symbols[I].Addr)
 End;
End;

Procedure SaveSymbol(I: Word);Begin
 If Symbols[I].ByReference Then Begin
  ReferencePointer(I); Emit($26);
  If Symbols[I].Width=1 Then Emit2($88,$05) Else Emit2($89,$05);
  Exit;
 End;
 If Symbols[I].Local Then Begin
  ScopeAddress(Symbols[I].Scope); Emit($36);
  If Symbols[I].Width=1 Then Emit2($88,$87) Else Emit2($89,$87);
  EmitWord(Symbols[I].Addr); Exit;
 End;
 If Symbols[I].Native Then Begin
  NeedNative(Symbols[I].Owner); Emit($1E); SetNativeDS;
  If Symbols[I].Width=1 Then Emit($A2) Else Emit($A3);
  NativeVarAddress(I); Emit($1F); Exit;
 End;
 If Symbols[I].Width=1 Then Emit($A2) Else Emit($A3);
 DataAddress(Symbols[I].Addr);
End;
Function Expression: Byte;Forward;
Procedure Statement;Forward;
Function NativeCall(I: Word): Byte;Forward;
Function UserCall(I: Word): Byte;Forward;
Function ReadType: Word; Forward;

Procedure RequireInteger(T: Byte);Begin
 If T<>ttInteger Then Fail(38,'Expression entiere attendue');
End;

Procedure RequireBoolean(T: Byte);Begin
 If T<>ttBoolean Then Fail(40,'Expression booleenne attendue');
End;

Function Factor: Byte;
Var
 T: Byte;
 I,CastType: Word;
 Name: TShortString;
Begin
 T:=ttInteger; ExprType:=1; ExprKnown:=False;
 If Token=tkConstant Then Begin
  ExprKnown:=True; ExprValue:=TokenValue;
  If TokenIsString Then Begin
   If Length(TokenText)=1 Then Begin
    T:=ttChar; ExprType:=6; ExprValue:=Ord(TokenText[1]); LoadImmediate(Ord(TokenText[1]))
   End
    Else
   Begin
    T:=ttString; ExprType:=7; Emit($B8); DataAddress(StoreString(TokenText))
   End;
  End Else
  Begin
   If TokenValue>65535 Then Unsupported('constante Longint');
  If TokenValue>32767 Then ExprType:=3;
   LoadImmediate(Word(TokenValue));
  End;
  NextToken;
 End Else If Token=tkLP Then Begin
  NextToken; T:=Expression; Need(tkRP)
 End
 Else If Token=tkNot Then Begin
  NextToken; T:=Factor;
  ExprKnown:=False;
  If T=ttBoolean Then Begin
   Emit2($35,$01); Emit(0)
  End
   Else
  Begin
   RequireInteger(T); Emit2($F7,$D0)
  End;
 End Else If Token=tkIdent Then Begin
  Name:=TokenText; NextToken;
  I:=FindLexicalSymbol(Name);
  CastType:=0;
  If (I=0) And (Token<>tkDot) Then CastType:=BuiltinType(Name);
  If (I<>0) And (Symbols[I].Kind=skType) Then CastType:=Symbols[I].TypeId;
  If (Token=tkLP) And (CastType<>0) Then Begin
   NextToken; T:=Expression; Need(tkRP);
   If Not (T In [ttInteger,ttBoolean,ttChar,ttEnum]) Or
      Not (Types[CastType].Typ In [ttInteger,ttBoolean,ttChar,ttEnum]) Then
    Fail(60,'Conversion ordinale invalide');
   T:=Types[CastType].Typ; ExprType:=CastType;
  ExprKnown:=False;
   If Types[CastType].Width=1 Then Begin
    If Types[CastType].Signed Then Emit($98) Else Emit2($30,$E4);
   End;
  End Else If (I=0) And (Token<>tkDot) And (Name='SIZEOF') Then Begin
   Need(tkLP); CastType:=ReadType; Need(tkRP);
   If Types[CastType].Typ=ttString Then LoadImmediate(Word(Types[CastType].Capacity)+1)
   Else LoadImmediate(Types[CastType].Width);
   T:=ttInteger; ExprType:=1;
  End Else If (I=0) And (Token<>tkDot) And ((Name='TRUE') Or (Name='FALSE')) Then Begin
  T:=ttBoolean; ExprType:=5; ExprKnown:=True;
  If Name='TRUE' Then Begin ExprValue:=1; LoadImmediate(1) End
  Else Begin ExprValue:=0; LoadImmediate(0) End;
  End Else If (I=0) And (Token<>tkDot) And ((Name='LENGTH') Or (Name='ORD') Or (Name='CHR') Or
  (Name='ABS') Or (Name='SQR') Or (Name='SUCC') Or (Name='PRED')) Then Begin
   Need(tkLP); T:=Expression; Need(tkRP);
   If Name='LENGTH' Then Begin
    If T=ttString Then Begin
     Emit2($89,$C3); Emit2($8A,$07); Emit2($30,$E4)
    End
    Else If T=ttChar Then LoadImmediate(1) Else Fail(66,'Chaine attendue');
    T:=ttInteger; ExprType:=1;
   End Else If Name='ORD' Then Begin
    If Not (T In [ttInteger,ttBoolean,ttChar,ttEnum]) Then Fail(26,'Type ordinal attendu');
    T:=ttInteger; ExprType:=1;
   End Else If Name='CHR' Then Begin
    RequireInteger(T); Emit2($30,$E4); T:=ttChar; ExprType:=6
   End
    Else
   Begin
    If Not ((Name='SUCC') Or (Name='PRED')) Then RequireInteger(T)
    Else If Not (T In [ttInteger,ttBoolean,ttChar,ttEnum]) Then Fail(26,'Type ordinal attendu');
    If Name='ABS' Then Begin
     Emit2($09,$C0); Emit2($79,$02); Emit2($F7,$D8)
    End;
    If Name='SQR' Then Emit2($F7,$E8);
    If Name='SUCC' Then Emit($40);
    If Name='PRED' Then Emit($48);
   End;
    ExprKnown:=False;
  End Else
  Begin
   I:=ResolveSymbol(Name);
  If Symbols[I].ResultVariable And (Token=tkLP) Then I:=Symbols[I].RoutineSymbol;
   If Symbols[I].Kind=skProc Then Begin
   If Symbols[I].Typ=ttVoid Then Fail(42,'Procedure utilisee comme fonction');
   If Symbols[I].Native Then T:=NativeCall(I) Else T:=UserCall(I);
    ExprKnown:=False;
    ExprType:=SymbolType(I);
    If T=ttVoid Then Fail(42,'Fonction attendue');
   End Else
   Begin
    T:=Symbols[I].Typ; ExprType:=SymbolType(I); LoadSymbol(I);
    ExprKnown:=Symbols[I].Kind=skConst; ExprValue:=Symbols[I].Value;
   End;
   If Token=tkLB Then Begin
    If T<>ttString Then Unsupported('indexation non string');
    Emit($50); NextToken; RequireInteger(Expression); Need(tkRB);
    Emit($5B); Emit2($01,$C3); Emit2($8A,$07); Emit2($30,$E4); T:=ttChar; ExprType:=6; ExprKnown:=False;
   End;
  End;
 End Else If Token=tkEOF Then Fail(10,'Fin de fichier inattendue')
                         Else Unsupported('expression: '+TokenText);
 ExprUnsigned:=(ExprType<>0) And Not Types[ExprType].Signed And (T=ttInteger);
 Factor:=T;
End;

Function Term: Byte;
Var
 T, R, Op: Byte;
 Skip: Word;
 ShortCircuit: Boolean;
 LeftType: Word; LeftUnsigned: Boolean;
 LeftKnown: Boolean; LeftValue: Longint; Check: Real;
Begin
 T:=Factor;
 While Token In [tkTimes,tkSlash,tkDiv,tkMod,tkAnd,tkShl,tkShr] Do Begin
  Op:=Token;
  If Op=tkSlash Then Unsupported('division reelle');
  ShortCircuit:=(Op=tkAnd) And (T=ttBoolean);
  LeftType:=ExprType; LeftUnsigned:=ExprUnsigned;
  LeftKnown:=ExprKnown; LeftValue:=ExprValue;
  If ShortCircuit Then Skip:=JumpZero;
  Emit($50); NextToken; R:=Factor; Emit2($89,$C3); Emit($58);
  If Op=tkAnd Then Begin
   If (T<>R) Or Not (T In [ttInteger,ttBoolean]) Then Fail(26,'Types incompatibles');
   Emit2($21,$D8);
  End Else
  Begin
   RequireInteger(T); RequireInteger(R);
   Case Op Of
   tkTimes:Emit2($F7,$EB);
   tkDiv,tkMod:
   Begin
    If LeftUnsigned And ExprUnsigned Then Begin Emit2($31,$D2); Emit2($F7,$F3) End
    Else Begin Emit($99); Emit2($F7,$FB) End;
    If Op=tkMod Then Emit2($89,$D0);
   End;
   tkShl,tkShr:
   Begin
    Emit2($89,$D9);
    If Op=tkShl Then Emit2($D3,$E0) Else Emit2($D3,$E8);
   End;
  End;
 End;
 If ShortCircuit Then PatchJump(Skip,CodeSize);
 ExprKnown:=LeftKnown And ExprKnown;
 If ExprKnown Then Begin
  Case Op Of
   tkTimes:Begin
    Check:=LeftValue; Check:=Check*ExprValue;
    If (Check<-2147483647.0-1) Or (Check>2147483647.0) Then Fail(76,'Debordement expression constante');
    ExprValue:=LeftValue*ExprValue;
   End;
   tkDiv,tkMod:Begin
    If (ExprValue=0) Or ((LeftValue=-2147483647-1) And (ExprValue=-1)) Then ExprKnown:=False
    Else If Op=tkDiv Then ExprValue:=LeftValue Div ExprValue Else ExprValue:=LeftValue Mod ExprValue;
   End;
   tkAnd:ExprValue:=LeftValue And ExprValue;
   tkShl,tkShr:Begin
    If (ExprValue<0) Or (ExprValue>31) Then ExprKnown:=False
    Else If Op=tkShl Then ExprValue:=LeftValue Shl ExprValue Else ExprValue:=LeftValue Shr ExprValue;
   End;
  End;
 End;
 If T=ttInteger Then Begin
  If LeftUnsigned And ExprUnsigned Then ExprType:=3 Else ExprType:=1;
  ExprUnsigned:=ExprType=3;
 End Else ExprType:=LeftType;
End;
Term:=T;
End;

Function SimpleExpression: Byte;
Var
 T,R,Op,Sign: Byte;
 Skip: Word;
 ShortCircuit: Boolean;
 LeftType: Word; LeftUnsigned: Boolean;
 LeftKnown: Boolean; LeftValue: Longint; Check: Real;
Begin
 Sign:=0;
 If Token In [tkPlus,tkMinus] Then Begin
  Sign:=Token; NextToken
 End;
 T:=Term;
 If Sign<>0 Then RequireInteger(T);
 If Sign=tkMinus Then Begin
  Emit2($F7,$D8); ExprType:=1; ExprUnsigned:=False; ExprValue:=-ExprValue;
 End;
 While Token In [tkPlus,tkMinus,tkOr,tkXor] Do Begin
  Op:=Token;
  ShortCircuit:=(Op=tkOr) And (T=ttBoolean);
  LeftType:=ExprType; LeftUnsigned:=ExprUnsigned;
  LeftKnown:=ExprKnown; LeftValue:=ExprValue;
  If ShortCircuit Then Begin
   Emit2($09,$C0); Emit2($74,$03); Skip:=Jump;
  End;
  Emit($50); NextToken; R:=Term;
  Emit2($89,$C3); Emit($58);
  If Op In [tkOr,tkXor] Then Begin
   If (T<>R) Or Not (T In [ttInteger,ttBoolean]) Then Fail(26,'Types incompatibles');
   If Op=tkOr Then Emit2($09,$D8) Else Emit2($31,$D8);
  End Else
  Begin
   RequireInteger(T); RequireInteger(R);
   If Op=tkPlus Then Emit2($01,$D8) Else Emit2($29,$D8);
  End;
  If ShortCircuit Then PatchJump(Skip,CodeSize);
  ExprKnown:=LeftKnown And ExprKnown;
  If ExprKnown Then Begin
   Check:=LeftValue;
   If Op=tkPlus Then Check:=Check+ExprValue Else If Op=tkMinus Then Check:=Check-ExprValue;
   If (Check<-2147483647.0-1) Or (Check>2147483647.0) Then Fail(76,'Debordement expression constante');
   Case Op Of
    tkPlus:ExprValue:=LeftValue+ExprValue; tkMinus:ExprValue:=LeftValue-ExprValue;
    tkOr:ExprValue:=LeftValue Or ExprValue; tkXor:ExprValue:=LeftValue Xor ExprValue;
   End;
  End;
  If T=ttInteger Then Begin
   If LeftUnsigned And ExprUnsigned Then ExprType:=3 Else ExprType:=1;
   ExprUnsigned:=ExprType=3;
  End Else ExprType:=LeftType;
 End;
 SimpleExpression:=T;
End;

Function Expression: Byte;
Var
 T,R,Op,Jcc: Byte;
 LeftType: Word; LeftUnsigned: Boolean;
Begin
 T:=SimpleExpression;
 If Token In [tkEqual,tkNE,tkGreater,tkLess,tkGE,tkLE] Then Begin
  LeftType:=ExprType; LeftUnsigned:=ExprUnsigned;
  Op:=Token; Emit($50); NextToken; R:=SimpleExpression;
  If T<>R Then Fail(26,'Comparaison de types incompatibles');
  If Not CompatibleTypes(LeftType,ExprType) Then Fail(26,'Identites ordinales incompatibles');
  If T=ttString Then Unsupported('comparaison de chaines');
  Emit2($89,$C3); Emit($58); Emit2($39,$D8);
  Jcc:=$74;
  Case Op Of
  tkEqual:Jcc:=$74; tkNE:Jcc:=$75; tkGreater:Jcc:=$7F;
  tkLess:Jcc:=$7C; tkGE:Jcc:=$7D; tkLE:Jcc:=$7E;
 End;
 If (T In [ttChar,ttBoolean,ttEnum]) Or (LeftUnsigned And ExprUnsigned) Then Case Op Of
 tkGreater:Jcc:=$77; tkLess:Jcc:=$72; tkGE:Jcc:=$73; tkLE:Jcc:=$76;
End;
LoadImmediate(1); Emit2(Jcc,$02); Emit2($31,$C0); T:=ttBoolean; ExprType:=5; ExprUnsigned:=False; ExprKnown:=False;
End;
Expression:=T;
End;

Function NativeCall(I: Word): Byte;
Var
 J, V, A, ParamType: Word;
 T: Byte;
 Name: TShortString;
Begin
 NeedNative(Symbols[I].Owner);
 Emit($1E); Emit($06); Emit($55); { saves BELOW arguments, not between args and return }
 If Symbols[I].ParamCount<>0 Then Begin
  Need(tkLP);
  For J:=1 To Symbols[I].ParamCount Do Begin
   If J<>1 Then Need(tkComma);
  ParamType:=Symbols[I].ParamTypeIds[J];
   If Symbols[I].ParamFlags[J]=6 Then Begin
    If Token<>tkIdent Then Fail(20,'Parametre var attendu');
    Name:=TokenText; NextToken; V:=ResolveSymbol(Name);
    If (Symbols[V].Kind<>skVar) Or (Symbols[V].Typ<>Symbols[I].ParamTypes[J]) Or
    (Symbols[V].Width<>Symbols[I].ParamWidths[J]) Or
    (Symbols[V].SignedByte<>Symbols[I].ParamSigned[J]) Then Fail(26,
    'Type du parametre var');
    If (Symbols[I].ParamTypes[J]=ttString) And
       ((Symbols[V].Capacity<>Types[ParamType].Capacity) And (OptionBits And $10<>0)) Then
      Fail(101,'Longueur de chaine du parametre var');
    PushVariableAddress(V);
   End Else
   Begin
    T:=Expression;
    If Symbols[I].ParamTypes[J]=ttString Then Begin
     If Not (T In [ttString,ttChar]) Then Fail(26,'Chaine pour parametre natif attendue');
     If T=ttChar Then Begin
      A:=AllocData(2); Emit($A2); DataAddress(A+1);
      Emit2($C6,$06); DataAddress(A); Emit(1); Emit($B8); DataAddress(A);
     End;
     Emit($1E); Emit($50); { segment et adresse du shortstring source }
    End Else Begin
    If T<>Symbols[I].ParamTypes[J] Then Fail(26,'Type du parametre valeur');
    If Symbols[I].ParamWidths[J]=1 Then Begin
     If Symbols[I].ParamSigned[J] Then Emit($98) Else Emit2($30,$E4);
    End;
    Emit($50); { TP6 empile les scalaires courts dans un mot }
    End;
   End;
  End;
  Need(tkRP);
 End Else If Token=tkLP Then Begin
  NextToken; Need(tkRP)
 End;
 SetNativeDS; Emit2($8E,$C2); { es=ds }
 Emit($9A); NativeReference(Symbols[I].Owner,3,Symbols[I].NativeMap,0);
 AddSegmentRelocation(CodeSize,0); EmitWord(0);
 Emit($5D); Emit($07); Emit($1F); { callee a retire les parametres avec retf N }
 If Symbols[I].Width=1 Then Begin
  If Symbols[I].SignedByte Then Emit($98) Else Emit2($30,$E4);
 End;
 NativeCall:=Symbols[I].Typ;
End;

Function UserCall(I: Word): Byte;
Var J,V,T: Word; Kind: Byte; Name: TShortString;
Begin
 Emit($06); { preserve ES: indirect var accesses use LES }
 If Symbols[I].ParamCount<>0 Then Begin
  Need(tkLP);
  For J:=1 To Symbols[I].ParamCount Do Begin
   If J<>1 Then Need(tkComma);
   T:=Symbols[I].ParamTypeIds[J];
   If Symbols[I].ParamFlags[J]=6 Then Begin
    If Token<>tkIdent Then Fail(20,'Variable pour parametre var attendue');
    Name:=TokenText; NextToken; V:=ResolveSymbol(Name);
    If (Symbols[V].Kind<>skVar) Or (SymbolType(V)<>T) Then Fail(26,'Identite du parametre var');
    PushVariableAddress(V);
   End Else Begin
    Kind:=Expression;
    If (Kind<>Types[T].Typ) Or Not CompatibleTypes(T,ExprType) Then Fail(26,'Type du parametre valeur');
    If ExprKnown And ((ExprValue<Types[T].LowBound) Or (ExprValue>Types[T].HighBound)) Then
      Fail(76,'Parametre constant hors limites');
    If Types[T].Width=1 Then Begin
     If Types[T].Signed Then Emit($98) Else Emit2($30,$E4);
    End;
    Emit($50);
   End;
  End;
  Need(tkRP);
 End Else If Token=tkLP Then Begin NextToken; Need(tkRP) End;
 EmitLocalCall(I); Emit($07);
 UserCall:=Symbols[I].Typ;
 ExprType:=SymbolType(I); ExprKnown:=False;
 ExprUnsigned:=(Symbols[I].Typ=ttInteger) And (ExprType<>0) And Not Types[ExprType].Signed;
End;

Procedure Assignment(I: Word);
Var
 T: Byte;
 Indexed: Boolean;
Begin
 If Symbols[I].Kind<>skVar Then Fail(43,'Variable attendue');
 Indexed:=Token=tkLB;
 If Indexed Then Begin
  If Symbols[I].Typ<>ttString Then Unsupported('affectation indexee non string');
  NextToken; RequireInteger(Expression); Need(tkRB); Emit($50);
 End;
 Need(tkAssign); T:=Expression;
 If Indexed Then Begin
  If T<>ttChar Then Fail(106,'Caractere attendu');
  Emit($5B); Emit2($88,$87); DataAddress(Symbols[I].Addr);
 End Else If Symbols[I].Typ=ttString Then Begin
  If T=ttChar Then Begin
   Emit($A2); DataAddress(Symbols[I].Addr+1);
   Emit2($C6,$06); DataAddress(Symbols[I].Addr); Emit(1);
  End Else If T=ttString Then Begin
   Emit2($89,$C6); Emit($BF); DataAddress(Symbols[I].Addr);
   Emit($B9); EmitWord(Symbols[I].Capacity); CallTo(RuntimeCopy);
  End Else Fail(26,'Chaine attendue');
 End Else
 Begin
  If T<>Symbols[I].Typ Then Fail(26,'Types incompatibles');
  If Not CompatibleTypes(SymbolType(I),ExprType) Then Fail(26,'Identite du type ordinal');
  If ExprKnown And (Symbols[I].TypeId<>0) Then
   If (ExprValue<Types[Symbols[I].TypeId].LowBound) Or
       (ExprValue>Types[Symbols[I].TypeId].HighBound) Then Fail(76,'Affectation constante hors limites');
  SaveSymbol(I);
 End;
End;

Procedure WriteStatement(NewLine: Boolean);
Var
 T: Byte;
Begin
 If Token=tkLP Then Begin
  NextToken;
  Repeat
  T:=Expression;
  If Token=tkColon Then Unsupported('largeur de champ Write');
  Case T Of
  ttString:CallTo(RuntimeString);
  ttChar:CallTo(RuntimeChar);
  ttInteger:Begin
   If ExprUnsigned Then CallTo(RuntimeUnsigned) Else CallTo(RuntimeInteger);
  End;
  ttBoolean:CallTo(RuntimeBoolean);
  Else Unsupported('type non imprimable');
 End;
 If Token<>tkComma Then Break;
 NextToken;
 Until False;
 Need(tkRP);
End;
If NewLine Then Begin
 LoadImmediate(13); CallTo(RuntimeChar); LoadImmediate(10); CallTo(RuntimeChar);
End;
End;

Procedure StatementList(Stop: Byte);Begin
 While Token<>Stop Do Begin
  If Token=tkEOF Then Fail(10,'Fin de fichier inattendue');
  Statement;
  If Token=Stop Then Break;
  Need(tkSemi);
 End;
End;

Procedure Statement;
Var
 I, Start, P, Q: Word;
 Direction, Ignored: Byte;
 Name, VarName: TShortString;
Begin
 Case Token Of
 tkBegin:
 Begin
  NextToken; StatementList(tkEnd); Need(tkEnd)
 End;
 tkIf:
 Begin
  NextToken; RequireBoolean(Expression); Need(tkThen); P:=JumpZero;
  Statement;
  If Token=tkElse Then Begin
   Q:=Jump; PatchJump(P,CodeSize); NextToken; Statement; PatchJump(Q,CodeSize);
  End Else PatchJump(P,CodeSize);
 End;
 tkWhile:
 Begin
  NextToken; Start:=CodeSize; RequireBoolean(Expression); Need(tkDo);
  P:=JumpZero; Statement; JumpTo(Start); PatchJump(P,CodeSize);
 End;
 tkRepeat:
 Begin
  NextToken; Start:=CodeSize; StatementList(tkUntil); Need(tkUntil);
  RequireBoolean(Expression); P:=JumpZero; PatchJump(P,Start);
 End;
 tkFor:
 Begin
  NextToken;
  If Token<>tkIdent Then Fail(2,'Variable de boucle attendue');
  Name:=TokenText; NextToken; I:=ResolveSymbol(Name);
  If (Symbols[I].Kind<>skVar) Or Not (Symbols[I].Typ In [ttInteger,ttChar,ttBoolean,ttEnum]) Then
   Fail(97,'Variable de controle FOR non ordinale');
  Need(tkAssign); Ignored:=Expression;
  If Not CompatibleTypes(SymbolType(I),ExprType) Then Fail(26,'Valeur initiale FOR');
  SaveSymbol(I);
  Direction:=Token;
  If Not (Direction In [tkTo,tkDownto]) Then Fail(58,'TO ou DOWNTO attendu');
  NextToken; Ignored:=Expression;
  If Not CompatibleTypes(SymbolType(I),ExprType) Then Fail(26,'Borne FOR');
  Emit($50); Need(tkDo);
  Start:=CodeSize; LoadSymbol(I); Emit2($89,$E3); Emit($36); Emit2($3B,$07);
  If Types[SymbolType(I)].Signed Then Begin
   If Direction=tkTo Then Emit2($7E,$03) Else Emit2($7D,$03);
  End Else Begin
   If Direction=tkTo Then Emit2($76,$03) Else Emit2($73,$03);
  End;
  P:=Jump; Statement;
      { Tester l'egalite AVANT inc/dec evite le debordement a +/-32768. }
  LoadSymbol(I); Emit2($89,$E3); Emit($36); Emit2($3B,$07); Emit2($75,$03); Q:=Jump;
  If Direction=tkTo Then Emit($40) Else Emit($48);
  SaveSymbol(I); JumpTo(Start); PatchJump(P,CodeSize); PatchJump(Q,CodeSize);
  Emit2($83,$C4); Emit(2);
 End;
 tkIdent:
 Begin
  Name:=TokenText; NextToken;
  I:=FindLexicalSymbol(Name);
  If (I=0) And (Token<>tkDot) And ((Name='WRITE') Or (Name='WRITELN')) Then WriteStatement(Name=
  'WRITELN')
  Else If (I=0) And (Token<>tkDot) And (Name='HALT') Then Begin
   If Token=tkLP Then Begin
    NextToken; RequireInteger(Expression); Need(tkRP)
   End
   Else LoadImmediate(0);
   CallTo(RuntimeHalt);
  End Else If (I=0) And (Token<>tkDot) And (Name='EXIT') Then Begin
   If Not InProcedure Then Unsupported('EXIT du programme principal');
  If CurrentScope<>0 Then ProcedureExit Else Emit($C3);
  End Else If (I=0) And (Token<>tkDot) And ((Name='INC') Or (Name='DEC')) Then Begin
   Need(tkLP);
   If Token<>tkIdent Then Fail(2,'Variable attendue');
   VarName:=TokenText; NextToken; I:=ResolveSymbol(VarName);
   If (Symbols[I].Kind<>skVar) Or (Symbols[I].Typ<>ttInteger) Then          Fail(38,
   'Variable entiere attendue');
   LoadSymbol(I);
   If Token=tkComma Then Begin
    Emit($50); NextToken; RequireInteger(Expression);
    Emit2($89,$C3); Emit($58);
    If Name='INC' Then Emit2($01,$D8) Else Emit2($29,$D8);
   End Else If Name='INC' Then Emit($40) Else Emit($48);
   Need(tkRP); SaveSymbol(I);
  End Else
  Begin
   I:=ResolveSymbol(Name);
   If Symbols[I].Kind=skProc Then Begin
    If Symbols[I].Native Then Begin
     Ignored:=NativeCall(I);
     If Ignored<>ttVoid Then Unsupported('resultat de fonction ignore sans $X+');
    End Else
    Begin
      Ignored:=UserCall(I);
      If Ignored<>ttVoid Then Unsupported('resultat de fonction ignore sans $X+');
    End;
   End Else Assignment(I);
  End;
 End;
 tkSemi,tkEnd,tkElse,tkUntil:; { instruction vide }
 tkEOF:Fail(10,'Fin de fichier inattendue');
 Else Unsupported('instruction: '+TokenText);
End;
End;

Function ConstExpression: TConstValue; Forward;

Function ConstText(V: TConstValue): TShortString;
Begin
 If Types[V.TypeId].Typ=ttChar Then ConstText:=Chr(V.Value)
 Else If Types[V.TypeId].Typ=ttString Then ConstText:=V.Text
 Else Begin Fail(26,'Constante chaine attendue'); ConstText:='' End;
End;

Procedure ConstInteger(V: TConstValue);
Begin If Types[V.TypeId].Typ<>ttInteger Then Fail(26,'Constante entiere attendue') End;

Function ConstFactor: TConstValue;
Var V: TConstValue; Name: TShortString; I, T: Word;
Begin
 FillChar(V,SizeOf(V),0); V.TypeId:=1;
 If Token=tkConstant Then Begin
  If TokenIsString Then Begin
   If Length(TokenText)=1 Then Begin V.TypeId:=6; V.Value:=Ord(TokenText[1]) End
   Else Begin V.TypeId:=7; V.Text:=TokenText End;
  End Else Begin
   V.Value:=TokenValue;
   If (V.Value>32767) And (V.Value<=65535) Then V.TypeId:=3;
  End;
  NextToken;
 End Else If Token=tkLP Then Begin NextToken; V:=ConstExpression; Need(tkRP) End
 Else If Token=tkNot Then Begin
  NextToken; V:=ConstFactor;
  If Types[V.TypeId].Typ=ttBoolean Then V.Value:=1-V.Value
  Else Begin ConstInteger(V); V.Value:=Not V.Value; V.TypeId:=1 End;
 End Else If Token=tkIdent Then Begin
  Name:=TokenText; NextToken;
  If (FindLexicalSymbol(Name)=0) And (Token<>tkDot) And ((Name='TRUE') Or (Name='FALSE')) Then Begin
   V.TypeId:=5; If Name='TRUE' Then V.Value:=1;
  End Else If (FindLexicalSymbol(Name)=0) And (Token<>tkDot) And (Token=tkLP) And
   ((Name='ORD') Or (Name='CHR') Or (Name='LENGTH') Or (Name='ABS') Or
    (Name='SQR') Or (Name='SUCC') Or (Name='PRED') Or (Name='SIZEOF')) Then Begin
   NextToken;
   If Name='SIZEOF' Then Begin
    T:=ReadType;
    If Types[T].Typ=ttString Then V.Value:=Word(Types[T].Capacity)+1
    Else V.Value:=Types[T].Width;
   End Else Begin
    V:=ConstExpression;
    If Name='ORD' Then Begin
     If Types[V.TypeId].Typ=ttString Then Fail(26,'Constante ordinale attendue');
     V.TypeId:=1;
    End Else If Name='CHR' Then Begin
     ConstInteger(V); If (V.Value<0) Or (V.Value>255) Then Fail(76,'CHR hors limites'); V.TypeId:=6;
    End Else If Name='LENGTH' Then Begin V.Value:=Length(ConstText(V)); V.TypeId:=1 End
    Else If (Name='SUCC') Or (Name='PRED') Then Begin
     If Types[V.TypeId].Typ=ttString Then Fail(26,'Constante ordinale attendue');
     If Name='SUCC' Then Inc(V.Value) Else Dec(V.Value);
     If (V.Value<Types[V.TypeId].LowBound) Or (V.Value>Types[V.TypeId].HighBound) Then
      Fail(76,'SUCC/PRED hors limites');
    End Else Begin
     ConstInteger(V);
     If (V.Value=-2147483647-1) Or ((Name='SQR') And (Abs(V.Value)>46340)) Then
      Fail(76,'Debordement constant');
     If Name='ABS' Then V.Value:=Abs(V.Value) Else V.Value:=V.Value*V.Value;
     V.TypeId:=1;
    End;
   End;
   Need(tkRP);
  End Else Begin
   I:=ResolveSymbol(Name);
   If Symbols[I].Kind<>skConst Then Fail(31,'Constante attendue: '+Name);
   V.TypeId:=SymbolType(I); V.Value:=Symbols[I].Value; V.Text:=Symbols[I].StrValue;
  End;
 End Else Begin Fail(31,'Expression constante attendue') End;
 ConstFactor:=V;
End;

Function ConstTerm: TConstValue;
Var V,R: TConstValue; Op: Byte; Check: Real;
Begin
 V:=ConstFactor;
 While Token In [tkTimes,tkDiv,tkMod,tkAnd,tkShl,tkShr,tkSlash] Do Begin
  Op:=Token; NextToken; R:=ConstFactor;
  If Op=tkSlash Then Unsupported('constante reelle');
  If (Op=tkAnd) And (Types[V.TypeId].Typ=ttBoolean) Then Begin
   If Types[R.TypeId].Typ<>ttBoolean Then Fail(26,'AND constant');
   V.Value:=V.Value And R.Value;
  End Else Begin
   ConstInteger(V); ConstInteger(R);
   Case Op Of
    tkTimes:Begin
     Check:=V.Value; Check:=Check*R.Value;
     If (Check<-2147483647.0-1) Or (Check>2147483647.0) Then Fail(76,'Debordement constant');
     V.Value:=V.Value*R.Value;
    End;
    tkDiv,tkMod:Begin
     If R.Value=0 Then Fail(61,'Division constante par zero');
     If (V.Value=-2147483647-1) And (R.Value=-1) Then Fail(76,'Debordement constant');
     If Op=tkDiv Then V.Value:=V.Value Div R.Value Else V.Value:=V.Value Mod R.Value;
    End;
    tkAnd:V.Value:=V.Value And R.Value;
    tkShl,tkShr:Begin
     If (R.Value<0) Or (R.Value>31) Then Fail(76,'Decalage constant hors limites');
     If Op=tkShl Then V.Value:=V.Value Shl R.Value Else V.Value:=V.Value Shr R.Value;
    End;
   End;
   V.TypeId:=1;
  End;
 End;
 ConstTerm:=V;
End;

Function ConstSimple: TConstValue;
Var V,R: TConstValue; Op, Sign: Byte; Check: Real; S: TShortString;
Begin
 Sign:=0;
 If Token In [tkPlus,tkMinus] Then Begin Sign:=Token; NextToken End;
 V:=ConstTerm;
 If Sign<>0 Then ConstInteger(V);
 If Sign=tkMinus Then Begin
  If V.Value=-2147483647-1 Then Fail(76,'Debordement constant');
  V.Value:=-V.Value; V.TypeId:=1;
 End;
 While Token In [tkPlus,tkMinus,tkOr,tkXor] Do Begin
  Op:=Token; NextToken; R:=ConstTerm;
  If (Op=tkPlus) And (Types[V.TypeId].Typ In [ttString,ttChar]) Then Begin
   S:=ConstText(V);
   If Length(S)+Length(ConstText(R))>255 Then Fail(76,'Chaine constante >255');
   V.Text:=S+ConstText(R); V.TypeId:=7;
  End Else If (Op In [tkOr,tkXor]) And (Types[V.TypeId].Typ=ttBoolean) Then Begin
   If Types[R.TypeId].Typ<>ttBoolean Then Fail(26,'Operation booleenne constante');
   If Op=tkOr Then V.Value:=V.Value Or R.Value Else V.Value:=V.Value Xor R.Value;
  End Else Begin
   ConstInteger(V); ConstInteger(R); Check:=V.Value;
   Case Op Of
    tkPlus:Begin Check:=Check+R.Value End;
    tkMinus:Begin Check:=Check-R.Value End;
   End;
   If (Check<-2147483647.0-1) Or (Check>2147483647.0) Then Fail(76,'Debordement constant');
   Case Op Of
    tkPlus:V.Value:=V.Value+R.Value; tkMinus:V.Value:=V.Value-R.Value;
    tkOr:V.Value:=V.Value Or R.Value; tkXor:V.Value:=V.Value Xor R.Value;
   End;
   V.TypeId:=1;
  End;
 End;
 ConstSimple:=V;
End;

Function ConstExpression: TConstValue;
Var V,R: TConstValue; Op: Byte; C: Integer; S,T: TShortString; B: Boolean;
Begin
 V:=ConstSimple;
 If Token In [tkEqual,tkNE,tkLess,tkGreater,tkLE,tkGE] Then Begin
  Op:=Token; NextToken; R:=ConstSimple;
  If Types[V.TypeId].Typ In [ttString,ttChar] Then Begin
   S:=ConstText(V); T:=ConstText(R); C:=0; If S<T Then C:=-1 Else If S>T Then C:=1;
  End Else Begin
   If Not CompatibleTypes(V.TypeId,R.TypeId) Then Fail(26,'Comparaison constante incompatible');
   C:=0; If V.Value<R.Value Then C:=-1 Else If V.Value>R.Value Then C:=1;
  End;
  B:=False;
  Case Op Of
   tkEqual:B:=C=0; tkNE:B:=C<>0; tkLess:B:=C<0;
   tkGreater:B:=C>0; tkLE:B:=C<=0; tkGE:B:=C>=0;
  End;
  V.TypeId:=5; V.Value:=Ord(B); V.Text:='';
 End;
 ConstExpression:=V;
End;

Function ReadType: Word;
Var T,I,E: Word; First,Last: TConstValue; Name: TShortString; W: Byte;
  SavedPos: Longint; SavedLine, SavedColumn, SavedTokenLine, SavedTokenColumn: Word;
Begin
 If Token In [tkArray,tkRecord,tkSet,tkFile,tkObject,tkCaret,tkProcedure,tkFunction] Then
  Unsupported('type structure/pointeur/procedural');
 If (Token=tkIdent) And ((TokenText='REAL') Or (TokenText='LONGINT') Or
   (TokenText='SINGLE') Or (TokenText='DOUBLE') Or (TokenText='EXTENDED') Or (TokenText='COMP')) Then
  Unsupported('type: '+TokenText);
 If Token=tkString Then Begin
  NextToken; T:=7;
  If Token=tkLB Then Begin
   NextToken; First:=ConstExpression; ConstInteger(First);
   If (First.Value<1) Or (First.Value>255) Then Fail(25,'Longueur string');
   Need(tkRB); T:=NewType(ttString,0,First.Value,False,0,First.Value,7);
  End;
 End Else If Token=tkLP Then Begin
  NextToken; T:=NewType(ttEnum,1,0,False,0,0,0); E:=0;
  Repeat
   If Token<>tkIdent Then Fail(2,'Identificateur enumere attendu');
   I:=NewSymbol(TokenText); Symbols[I].Kind:=skConst; ApplyType(I,T); Symbols[I].Value:=E;
   Inc(E); NextToken;
   If Token<>tkComma Then Break;
   NextToken;
  Until False;
  Need(tkRP);
  If E>256 Then Unsupported('enumeration >256 valeurs');
  Types[T].HighBound:=E-1;
 End Else Begin
  T:=0;
  If Token=tkIdent Then Begin
   SavedPos:=SourcePos; SavedLine:=Line; SavedColumn:=Column;
   SavedTokenLine:=TokenLine; SavedTokenColumn:=TokenColumn;
   I:=FindSymbol(TokenText);
   If (I<>0) And (Symbols[I].Kind=skType) Then Begin
    Name:=TokenText; NextToken; I:=ResolveSymbol(Name); T:=Symbols[I].TypeId;
    If T=0 Then Fail(12,'Type en cours de definition');
   End Else If I=0 Then Begin
    T:=BuiltinType(TokenText); If T<>0 Then NextToken;
    If (T=0) And (FindBuildUnit(TokenText)=0) And
      (TokenText<>'TRUE') And (TokenText<>'FALSE') Then Fail(12,'Type inconnu: '+TokenText);
   End;
   If (T=0) And (Token=tkIdent) And (Peek<>#0) Then Begin
    { Une reference qualifiee peut designer un type ou une constante borne. }
    Name:=TokenText;
    If FindBuildUnit(Name)<>0 Then Begin
     NextToken; I:=ResolveSymbol(Name);
     If Symbols[I].Kind=skType Then T:=Symbols[I].TypeId
     Else If Symbols[I].Kind=skConst Then Begin
      SourcePos:=SavedPos; Line:=SavedLine; Column:=SavedColumn;
      TokenLine:=SavedTokenLine; TokenColumn:=SavedTokenColumn;
      Token:=tkIdent; TokenText:=Name; TokenIsString:=False; TokenValue:=0;
      T:=0;
     End Else Fail(12,'Type attendu');
    End;
   End;
  End;
  If T=0 Then First:=ConstExpression;
  If (T=0) Or (T=$FFFF) Then Begin
   If Types[First.TypeId].Typ=ttString Then Fail(27,'Borne non ordinale');
   Need(tkRange); Last:=ConstExpression;
   If Not CompatibleTypes(First.TypeId,Last.TypeId) Then Fail(26,'Types des bornes');
   If First.Value>Last.Value Then Fail(28,'Bornes inversees');
   If (First.Value<-32768) Or (Last.Value>65535) Then Unsupported('sous-intervalle >16 bits');
   W:=2;
   If (First.Value>=0) And (Last.Value<=255) Then W:=1;
   If (First.Value>=-128) And (Last.Value<=127) Then W:=1;
   T:=NewType(Types[First.TypeId].Typ,W,0,First.Value<0,First.Value,Last.Value,Types[First.TypeId].Base);
  End;
 End;
 ReadType:=T;
End;

Procedure TypeDeclarations;
Var I,T: Word;
Begin
 NextToken;
 While Token=tkIdent Do Begin
  I:=NewSymbol(TokenText); Symbols[I].Kind:=skType; NextToken; Need(tkEqual);
  T:=ReadType;
  If (Types[T].Typ=ttEnum) And (Types[T].IdentityName='') Then Begin
   If CurrentUnit=0 Then Types[T].IdentityUnit:='$PROGRAM'
   Else Types[T].IdentityUnit:=Units[CurrentUnit].Name;
   Types[T].IdentityName:=Symbols[I].Name;
   If CurrentScope<>0 Then Types[T].IdentityName:=Symbols[I].Name+'$LOCAL';
  End;
  ApplyType(I,T); Need(tkSemi);
 End;
End;

Procedure CheckConstType(T: Word; V: TConstValue);
Begin
 If Types[T].Typ=ttString Then Begin
  If Not (Types[V.TypeId].Typ In [ttChar,ttString]) Then Fail(26,'Chaine constante attendue');
  If Length(ConstText(V))>Types[T].Capacity Then Fail(76,'Chaine initiale trop longue');
 End Else Begin
  If Not CompatibleTypes(T,V.TypeId) Then Fail(26,'Type constant incompatible');
  If (V.Value<Types[T].LowBound) Or (V.Value>Types[T].HighBound) Then Fail(76,'Constante hors limites du type');
 End;
End;

Procedure AllocateVariable(I: Word);
Var N: Word;
Begin
 If Symbols[I].Typ=ttString Then N:=Word(Symbols[I].Capacity)+1 Else N:=Symbols[I].Width;
 If CurrentScope<>0 Then Begin
  If Symbols[I].Typ=ttString Then Unsupported('chaine locale sur pile');
  N:=(N+1) And $FFFE;
  If Longint(Scopes[CurrentScope].LocalSize)+N>32766 Then Fail(49,'Variables locales trop grandes');
  Inc(Scopes[CurrentScope].LocalSize,N); Symbols[I].Local:=True;
  Symbols[I].Addr:=Word(-Longint(Scopes[CurrentScope].LocalSize));
 End Else Symbols[I].Addr:=AllocData(N);
End;

Procedure ConstDeclarations;
Var
 I,T,A: Word; V: TConstValue; S: TShortString; K: Integer; Typed: Boolean;
Begin
 NextToken;
 While Token=tkIdent Do Begin
  I:=NewSymbol(TokenText); NextToken;
  Typed:=Token=tkColon; T:=0;
  If Typed Then Begin NextToken; T:=ReadType End;
  Need(tkEqual); V:=ConstExpression;
  If Typed Then Begin
   CheckConstType(T,V); ApplyType(I,T); Symbols[I].Kind:=skVar;
   { TP6: constantes typees modifiables, stockage statique meme en procedure. }
   If Symbols[I].Typ=ttString Then A:=AllocData(Word(Symbols[I].Capacity)+1)
   Else A:=AllocData(Symbols[I].Width);
   Symbols[I].Addr:=A;
   If Symbols[I].Typ=ttString Then Begin
    S:=ConstText(V); Data[A]:=Length(S);
    For K:=1 To Length(S) Do Data[A+K]:=Ord(S[K]);
   End Else Begin
    Data[A]:=Word(V.Value) And 255;
    If Symbols[I].Width=2 Then Data[A+1]:=Word(V.Value) Shr 8;
   End;
  End Else Begin
   Symbols[I].Kind:=skConst;
   T:=V.TypeId;
   If Types[T].Typ=ttInteger Then Begin
    If (V.Value>=0) And (V.Value>32767) And (V.Value<=65535) Then T:=3 Else T:=1;
   End;
   ApplyType(I,T); Symbols[I].Value:=V.Value; Symbols[I].StrValue:=V.Text;
   If Symbols[I].Typ=ttString Then Symbols[I].Addr:=StoreString(V.Text);
  End;
  Need(tkSemi);
 End;
End;

Procedure VarDeclarations;
Var
 First, Last, I,T: Word;
Begin
 NextToken;
 While Token=tkIdent Do Begin
  First:=SymbolCount+1;
  Repeat
  If Token<>tkIdent Then Fail(2,'Identificateur attendu');
  I:=NewSymbol(TokenText); Symbols[I].Kind:=skVar; NextToken;
  If Token<>tkComma Then Break;
  NextToken;
  Until False;
  Last:=SymbolCount; Need(tkColon); T:=ReadType;
  For I:=First To Last Do Begin
   ApplyType(I,T); AllocateVariable(I);
  End;
  Need(tkSemi);
 End;
End;

Procedure DeclarationPart; Forward;

Procedure ProcedureDeclaration;
Var
 I,Parent,FramePatch,Skip,J,K,T,V,ParamOffset,Size,Link: Word;
 SavedProcedure,IsFunction,Existing,FullHeading,ByVar,IsForward,HasDistance,IsExternal: Boolean;
 Sig: TSymbol; Name: TShortString;
 Names: Array[1..MaxNativeParams] Of String[63]; N: Byte;
Begin
 IsFunction:=Token=tkFunction; FillChar(Sig,SizeOf(Sig),0);
 Sig.Kind:=skProc; Sig.Typ:=ttVoid;
 NextToken;
 If Token<>tkIdent Then Fail(2,'Nom de procedure attendu');
 Name:=TokenText;
 I:=FindOwnSymbol(TokenText);
 Existing:=I<>0;
 If Existing Then Begin
  If (Symbols[I].Kind<>skProc) Or Symbols[I].HasBody Then      Fail(4,
  'Identificateur duplique: '+TokenText);
 End;
 NextToken;
 FullHeading:=Token=tkLP;
 If Token=tkLP Then Begin
  NextToken;
  While Token<>tkRP Do Begin
   ByVar:=Token=tkVar; If ByVar Then NextToken;
   N:=0;
   Repeat
    If Token<>tkIdent Then Fail(2,'Nom de parametre attendu');
    If N=MaxNativeParams Then Unsupported('plus de 8 parametres');
    Inc(N); Names[N]:=TokenText; NextToken;
    If Token<>tkComma Then Break;
    NextToken;
   Until False;
   Need(tkColon); T:=ReadType;
   If Not (Types[T].Typ In [ttInteger,ttBoolean,ttChar,ttEnum]) Then
    Unsupported('parametre utilisateur non ordinal');
   For J:=1 To N Do Begin
    If Sig.ParamCount=MaxNativeParams Then Unsupported('plus de 8 parametres');
    Inc(Sig.ParamCount); K:=Sig.ParamCount;
    For V:=1 To K-1 Do If Sig.ParamNames[V]=Names[J] Then Fail(4,'Parametre duplique');
    Sig.ParamNames[K]:=Names[J]; Sig.ParamTypeIds[K]:=T;
    Sig.ParamTypes[K]:=Types[T].Typ; Sig.ParamWidths[K]:=Types[T].Width;
    Sig.ParamSigned[K]:=Types[T].Signed And (Types[T].Width=1);
    If ByVar Then Begin Sig.ParamFlags[K]:=6; Inc(Sig.ParamBytes,4) End
    Else Begin Sig.ParamFlags[K]:=2; Inc(Sig.ParamBytes,2) End;
   End;
   If Token<>tkSemi Then Break;
   NextToken;
  End;
  Need(tkRP);
 End;
 If IsFunction Then Begin
  If Token=tkColon Then Begin
   FullHeading:=True; NextToken; T:=ReadType;
   If Not (Types[T].Typ In [ttInteger,ttBoolean,ttChar,ttEnum]) Then
    Fail(34,'Resultat de fonction non ordinal');
   Sig.TypeId:=T; Sig.Typ:=Types[T].Typ; Sig.Width:=Types[T].Width;
   Sig.SignedByte:=Types[T].Signed And (Types[T].Width=1);
  End Else If Not Existing Then Need(tkColon);
 End;
 Need(tkSemi);
 IsForward:=False; HasDistance:=False; IsExternal:=False;
 Sig.FarRoutine:=InInterface Or (OptionBits And $20<>0);
 While (Token=tkIdent) And ((TokenText='FORWARD') Or (TokenText='NEAR') Or (TokenText='FAR') Or (TokenText='EXTERNAL')) Do Begin
  If TokenText='FORWARD' Then IsForward:=True
  Else If TokenText='EXTERNAL' Then IsExternal:=True
  Else Begin
   If HasDistance Then Fail(5,'Directive de distance dupliquee');
   HasDistance:=True; Sig.FarRoutine:=TokenText='FAR';
  End;
  NextToken; Need(tkSemi);
 End;
 If IsExternal And IsForward Then Fail(5,'EXTERNAL et FORWARD incompatibles');
 If Existing Then Begin
  If IsFunction<>(Symbols[I].Typ<>ttVoid) Then Fail(130,'Procedure/fonction differente');
  If FullHeading Then Begin
   If (Sig.ParamCount<>Symbols[I].ParamCount) Or (Sig.TypeId<>Symbols[I].TypeId) Then
    Fail(130,'Signature de routine differente');
   For J:=1 To Sig.ParamCount Do
    If (Sig.ParamNames[J]<>Symbols[I].ParamNames[J]) Or
      (Sig.ParamTypeIds[J]<>Symbols[I].ParamTypeIds[J]) Or
      (Sig.ParamFlags[J]<>Symbols[I].ParamFlags[J]) Then Fail(130,'Signature de parametre differente');
  End;
  If HasDistance And (Sig.FarRoutine<>Symbols[I].FarRoutine) Then Fail(130,'Distance near/far differente');
  If InInterface Or IsForward Then Fail(4,'Declaration de routine dupliquee');
 End Else Begin
  I:=NewSymbol(Name);
  { Conserver l'entree du dictionnaire, remplir uniquement la signature. }
  Symbols[I].Kind:=skProc; Symbols[I].Typ:=Sig.Typ; Symbols[I].Width:=Sig.Width;
  Symbols[I].TypeId:=Sig.TypeId; Symbols[I].SignedByte:=Sig.SignedByte;
  Symbols[I].ParamCount:=Sig.ParamCount; Symbols[I].ParamBytes:=Sig.ParamBytes;
  Symbols[I].FarRoutine:=Sig.FarRoutine;
  For J:=1 To Sig.ParamCount Do Begin
   Symbols[I].ParamTypeIds[J]:=Sig.ParamTypeIds[J]; Symbols[I].ParamNames[J]:=Sig.ParamNames[J];
   Symbols[I].ParamTypes[J]:=Sig.ParamTypes[J]; Symbols[I].ParamWidths[J]:=Sig.ParamWidths[J];
   Symbols[I].ParamSigned[J]:=Sig.ParamSigned[J]; Symbols[I].ParamFlags[J]:=Sig.ParamFlags[J];
  End;
  Symbols[I].Addr:=CodeSize; Symbols[I].ForwardJump:=Jump;
 End;
 If InInterface Or IsForward Then Begin Symbols[I].ForwardDeclared:=True; Exit End;
 PatchJump(Symbols[I].ForwardJump,CodeSize);
 Symbols[I].HasBody:=True;
 If IsExternal Then Begin
  If CurrentScope<>0 Then Unsupported('EXTERNAL imbrique');
  If ObjectCallCount=MaxSymbols Then Unsupported('trop de routines EXTERNAL');
  { Pont ABI locale (lien statique) vers ABI Pascal OBJ far sans lien.
    Copier les arguments afin que RETF n'enleve pas la frame du pont. }
  Emit($55); Emit2($89,$E5); Emit($1E); Emit($06);
  Emit($53); Emit($56); Emit($57);
  Link:=4; If Symbols[I].FarRoutine Then Link:=6;
  J:=Symbols[I].ParamBytes;
  While J<>0 Do Begin
   Emit2($FF,$B6); EmitWord(Link+J); Dec(J,2);
  End;
  Emit($9A); Inc(ObjectCallCount);
  ObjectCalls[ObjectCallCount].Name:=Name;
  ObjectCalls[ObjectCallCount].Position:=CodeSize;
  EmitWord(0); EmitWord(0);
  Emit($5F); Emit($5E); Emit($5B); Emit($07); Emit($1F); Emit($5D);
  If Symbols[I].FarRoutine Then Emit($CA) Else Emit($C2);
  EmitWord(Symbols[I].ParamBytes+2);
  Exit;
 End;
 Parent:=CurrentScope; SavedProcedure:=InProcedure;
 If ScopeCount=MaxScopes Then Unsupported('plus de 128 portees');
 Inc(ScopeCount); CurrentScope:=ScopeCount;
 Scopes[CurrentScope].Parent:=Parent; Scopes[CurrentScope].Owner:=CurrentUnit;
 Scopes[CurrentScope].ProcSymbol:=I; Scopes[CurrentScope].LocalSize:=0;
 If Symbols[I].FarRoutine Then Link:=6 Else Link:=4;
 Scopes[CurrentScope].LinkOffset:=Link;
 ParamOffset:=Link+2+Symbols[I].ParamBytes;
 For J:=1 To Symbols[I].ParamCount Do Begin
  Size:=2; If Symbols[I].ParamFlags[J]=6 Then Size:=4;
  Dec(ParamOffset,Size); V:=NewSymbol(Symbols[I].ParamNames[J]);
  Symbols[V].Kind:=skVar; ApplyType(V,Symbols[I].ParamTypeIds[J]);
  Symbols[V].Local:=True; Symbols[V].Addr:=ParamOffset;
  Symbols[V].ByReference:=Symbols[I].ParamFlags[J]=6;
 End;
 If IsFunction Then Begin
  V:=NewSymbol(Name); Symbols[V].Kind:=skVar; ApplyType(V,Symbols[I].TypeId);
  AllocateVariable(V); Symbols[V].ResultVariable:=True; Symbols[V].RoutineSymbol:=I;
  Symbols[I].ResultSymbol:=V;
 End;
 InProcedure:=True;
 Emit($55); Emit2($89,$E5); Emit2($81,$EC); FramePatch:=CodeSize; EmitWord(0);
 Skip:=Jump; DeclarationPart; PatchJump(Skip,CodeSize);
 For J:=1 To SymbolCount Do If (Symbols[J].Owner=CurrentUnit) And
   (Symbols[J].Scope=CurrentScope) And (Symbols[J].Kind=skProc) And
   Not Symbols[J].HasBody Then Fail(59,Symbols[J].Name);
 PatchWord(FramePatch,Scopes[CurrentScope].LocalSize);
 Statement; ProcedureExit;
 CurrentScope:=Parent; InProcedure:=SavedProcedure; Need(tkSemi);
End;

Procedure DeclarationPart;Begin
 While Token In [tkConst,tkType,tkVar,tkProcedure,tkFunction] Do Case Token Of
 tkConst:ConstDeclarations; tkVar:VarDeclarations;
 tkType:TypeDeclarations;
 tkProcedure,tkFunction:ProcedureDeclaration;
End;
If Token In [tkLabel,tkConstructor,tkDestructor] Then    Unsupported(
'declaration: '+TokenText);
End;
Procedure LoadSource;Forward;
Procedure UsesClause;Forward;
Procedure ImportLibrarySystem;Forward;

Procedure SaveParser(Var P: PParserState);Begin
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
 P^.CurrentScope:=CurrentScope;
 P^.MinHeap:=MinHeap; P^.MaxHeap:=MaxHeap;
End;

Procedure RestoreParser(P: PParserState);Begin
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
 CurrentScope:=P^.CurrentScope;
 MinHeap:=P^.MinHeap; MaxHeap:=P^.MaxHeap;
 Dispose(P^.Buffer); Dispose(P);
End;

Procedure CompileSourceUnit(U: Byte; Path: TShortString);
Var
 P: PParserState;
 I: Word;
Begin
 SaveParser(P);
 SourceName:=Path; CurrentUnit:=U; Imports:=[]; ImportCount:=0;
 CurrentScope:=0;
 Units[U].FromSource:=True; Units[U].Path:=Path;
 InInterface:=True; InProcedure:=False;
  { Les directives locales d'une unite ne fuient ni dans ses dependances
    ni dans le programme appelant. Les /D de la CLI restent disponibles. }
 Move(InitialDefines,Defines,SizeOf(Defines)); DefineCount:=InitialDefineCount;
 OptionBits:=InitialOptions;
 LoadSource;
 If Not Quiet Then WriteLn('Building unit ',Units[U].Name,': ',Path);
 ImportLibrarySystem;
 NextToken; Need(tkUnit);
 If Token<>tkIdent Then Fail(2,'Nom d''unite attendu');
 If TokenText<>Units[U].Name Then Fail(69,Units[U].Name+' <> '+TokenText);
 NextToken; Need(tkSemi); Need(tkInterface);
 UsesClause; DeclarationPart;
 Units[U].InterfaceReady:=True;
 Units[U].Checksum:=0; { calcule apres compilation; sources /B prioritaires }
 Need(tkImplementation); InInterface:=False;
 UsesClause; DeclarationPart;
 For I:=1 To SymbolCount Do    If (Symbols[I].Owner=U) And (Symbols[I].Kind=skProc) And
 Not Symbols[I].HasBody Then Fail(59,Symbols[I].Name);
 If Token=tkBegin Then Begin
  Units[U].HasInit:=True; Units[U].InitAddress:=CodeSize;
    { EXIT dans le bloc d'initialisation revient a l'appelant. }
  InProcedure:=True; Statement; InProcedure:=False; Emit($C3);
 End Else Need(tkEnd);
 Need(tkDot);
 If Token<>tkEOF Then Fail(10,'Texte apres END.');
 Units[U].State:=2;
 If Units[U].HasInit Then Begin
  Inc(InitCount); InitOrder[InitCount]:=U
 End;
 RestoreParser(P);
End;

Procedure OpenBinaryRead(Var F: File; Var E: Integer);
Var
 SavedMode: Byte;
Begin
 SavedMode:=FileMode; FileMode:=0;
  {$I-} Reset(F,1); E:=IOResult; {$I+}
 FileMode:=SavedMode;
End;

Function FileExists(S: TShortString): Boolean;
Var
 F: File;
 E: Integer;
Begin
 Assign(F,S); OpenBinaryRead(F,E);
 FileExists:=E=0;
 If E=0 Then Begin
 {$I-} Close(F); E:=IOResult; {$I+} 
 End;
End;

Function JoinPath(Dir, Name: TShortString): TShortString;Begin
 If (Dir<>'') And Not (Dir[Length(Dir)] In ['\','/']) Then Dir:=Dir+'\';
 If Length(Dir)+Length(Name)>255 Then CLIError('Chemin trop long');
 JoinPath:=Dir+Name;
End;

Function FindUnitPath(Name, Extension: TShortString): TShortString;
Var
 D, MainDir: DirStr;
 N: NameStr;
 E: ExtStr;
 S, Part, Candidate: TShortString;
 P: Integer;
Begin
 FindUnitPath:='';
  { TP6 consulte le repertoire de sortie avant les repertoires d'unites
    pour les TPU, mais PAS pour choisir le source a reconstruire. }
 If (Extension='.TPU') And (OutputDir<>'') Then Begin
  Candidate:=JoinPath(OutputDir,Name+Extension);
  If FileExists(Candidate) Then Begin
   FindUnitPath:=Candidate; Exit
  End;
 End;
 FSplit(SourceName,D,N,E); FSplit(MainSourceName,MainDir,N,E);
 If Length(D)+Length(MainDir)+Length(UnitDirs)+Length(TurboDirs)+5>255 Then    CLIError(
 'Liste de recherche des unites trop longue');
 S:=D+';'+MainDir+';.;'+UnitDirs+';'+TurboDirs;
 Repeat
 P:=Pos(';',S);
 If P=0 Then Begin
  Part:=S; S:=''
 End
  Else
 Begin
  Part:=Copy(S,1,P-1); Delete(S,1,P)
 End;
 Candidate:=JoinPath(Part,Name+Extension);
 If FileExists(Candidate) Then Begin
  FindUnitPath:=Candidate; Exit
 End;
 Until S='';
End;

Function Align16(N: Longint): Longint;Begin
 Align16:=(N+15) And Not Longint(15)
End;

Procedure QueueObject(Name: TShortString);
Var D: DirStr; N: NameStr; E: ExtStr; Path: TShortString; I: Word;
 F: File; Error: Integer; Count: Longint;
Begin
 Name:=Trim(Name);
 If (Length(Name)>1) And (Name[1]='''') And (Name[Length(Name)]='''') Then
  Name:=Copy(Name,2,Length(Name)-2);
 If Name='' Then Fail(17,'Nom OBJ manquant');
 FSplit(Name,D,N,E); If E='' Then Name:=Name+'.OBJ';
 If D='' Then Path:=FindUnitPath(N,Copy(Name,Length(N)+1,255))
 Else Begin
  FSplit(SourceName,D,N,E); Path:=JoinPath(D,Name);
  If Not FileExists(Path) Then Path:=Name;
 End;
 If Path='' Then Fail(15,'OBJ introuvable: '+Name);
 Path:=FExpand(Path);
 For I:=1 To ObjectCount Do
  If (Upper(ObjectFiles[I].Path)=Upper(Path)) And
     (ObjectFiles[I].Owner=CurrentUnit) Then Exit;
 If ObjectCount=MaxObjects Then Unsupported('trop de fichiers OBJ');
 Inc(ObjectCount); ObjectFiles[ObjectCount].Path:=Path;
 ObjectFiles[ObjectCount].Owner:=CurrentUnit;
 Assign(F,Path); OpenBinaryRead(F,Error);
 If Error<>0 Then Fail(15,'OBJ introuvable: '+Path);
 ObjectFiles[ObjectCount].Length:=FileSize(F);
 If (ObjectFiles[ObjectCount].Length<4) Or
    (ObjectFiles[ObjectCount].Length>SizeOf(TBinaryBuffer)) Then Fail(72,'Taille OBJ invalide');
 New(ObjectFiles[ObjectCount].Bytes);
 {$I-} BlockRead(F,ObjectFiles[ObjectCount].Bytes^,ObjectFiles[ObjectCount].Length,Count);
 Error:=IOResult; Close(F); If IOResult<>0 Then Error:=1; {$I+}
 If (Error<>0) Or (Count<>ObjectFiles[ObjectCount].Length) Then Fail(72,'Lecture OBJ impossible');
End;

{ OMF86 Use16. Les index du fichier sont traduits en index globaux lors
  de la lecture; aucun pointeur hote ne figure dans les records disque. }
Procedure ReadObject(Path: TShortString; B: PBinaryBuffer; FileLength: Longint);
Var
 P, Last, RecordEnd, Q: Longint;
 RecType, Check, A, C, D, Loc, FD, FM, TM: Byte;
 SegMap: Array[1..MaxObjSegments] Of Word;
 GroupMap: Array[1..MaxObjGroups] Of Word;
 ExtMap: Array[1..MaxObjNames] Of Word;
 Names: Array[1..MaxObjNames] Of String[63];
 SegCount, GroupCount, ExtCount, NameCount: Word;
 S, G, X, Offs, L, I, TI, FI, Disp: Word;
 LastSegment, LastOffset: Word; LastLength: Longint;
 FrameMethods, TargetMethods: Array[0..3] Of Byte;
 FrameIndices, TargetIndices: Array[0..3] Of Word;
 FrameDefined, TargetDefined: Array[0..3] Of Boolean;
 Name: TShortString; Started, Ended, Relative: Boolean;

Function GetByte: Byte;
Begin
 If P>=Last Then Fail(72,'Record OBJ tronque: '+Path);
 GetByte:=B^[P]; Inc(P);
End;
Function GetWord: Word;
Var V: Word;
Begin V:=GetByte; GetWord:=V+Word(GetByte)*256 End;
Function GetIndex: Word;
Var V: Word;
Begin
 V:=GetByte;
 If V And $80<>0 Then V:=(V And $7F)*256+GetByte;
 GetIndex:=V;
End;
Function GetName: TShortString;
Var V,K: Word; T: TShortString;
Begin
 V:=GetByte; If V>63 Then Unsupported('nom OMF de plus de 63 caracteres');
 T:=''; For K:=1 To V Do T:=T+Chr(GetByte);
 If T='' Then Fail(72,'Nom OMF vide'); GetName:=Upper(T);
End;
Function SegmentIndex(V: Word): Word;
Begin
 If (V=0) Or (V>SegCount) Then Fail(72,'Index SEGDEF OBJ invalide');
 SegmentIndex:=SegMap[V];
End;
Function GroupIndex(V: Word): Word;
Begin
 If (V=0) Or (V>GroupCount) Then Fail(72,'Index GRPDEF OBJ invalide');
 GroupIndex:=GroupMap[V];
End;
Function NameIndex(V: Word): TShortString;
Begin
 If (V=0) Or (V>NameCount) Then Fail(72,'Index LNAMES OBJ invalide');
 NameIndex:=Names[V];
End;
Function MethodIndex(Method: Byte; V: Word): Word;
Begin
 Case Method Of
  0:MethodIndex:=SegmentIndex(V);
  1:MethodIndex:=GroupIndex(V);
  2:Begin
   If (V=0) Or (V>ExtCount) Then Fail(72,'Index EXTDEF OBJ invalide');
   MethodIndex:=ExtMap[V];
  End;
 Else Fail(72,'Methode de fixup OMF invalide'); MethodIndex:=0;
 End;
End;
Procedure IteratedBlock(Depth: Word);
Var RepeatCount, Blocks, K: Word; Start, Finish, Length: Longint;
Begin
 If Depth>16 Then Fail(72,'LIDATA trop imbrique');
 RepeatCount:=GetWord; Blocks:=GetWord; Start:=LastLength;
 If Blocks=0 Then Begin
  K:=GetByte;
  If Longint(LastOffset)+LastLength+K>ObjectSegments[LastSegment].Length Then
   Fail(72,'LIDATA hors segment');
  While K<>0 Do Begin
   ObjectSegments[LastSegment].Bytes^[LastOffset+LastLength]:=GetByte;
   Inc(LastLength); Dec(K);
  End;
 End Else For K:=1 To Blocks Do IteratedBlock(Depth+1);
 Finish:=LastLength; Length:=Finish-Start;
 If RepeatCount=0 Then LastLength:=Start
 Else Begin
  If Longint(LastOffset)+Start+Length*RepeatCount>ObjectSegments[LastSegment].Length Then
   Fail(72,'Expansion LIDATA hors segment');
  For K:=2 To RepeatCount Do Begin
   Move(ObjectSegments[LastSegment].Bytes^[LastOffset+Start],
        ObjectSegments[LastSegment].Bytes^[LastOffset+LastLength],Length);
   Inc(LastLength,Length);
  End;
 End;
End;
Begin
 SegCount:=0; GroupCount:=0; ExtCount:=0; NameCount:=0;
 LastSegment:=0; LastOffset:=0; LastLength:=0; P:=0; Started:=False; Ended:=False;
 FillChar(FrameDefined,SizeOf(FrameDefined),0);
 FillChar(TargetDefined,SizeOf(TargetDefined),0);
 While P<FileLength Do Begin
  If Ended Then Fail(72,'Texte apres MODEND OBJ');
  If P+3>FileLength Then Fail(72,'En-tete record OBJ tronque');
  RecType:=B^[P]; L:=B^[P+1]+Word(B^[P+2])*256;
  If (L=0) Or (P+3+L>FileLength) Then Fail(72,'Longueur record OBJ invalide');
  RecordEnd:=P+3+L; Last:=RecordEnd-1;
  Check:=0; For Q:=P To RecordEnd-1 Do Check:=Check+B^[Q];
  If (B^[Last]<>0) And (Check<>0) Then Fail(72,'Checksum OBJ invalide');
  Inc(P,3);
  If Not Started And (RecType<>$80) Then Fail(72,'THEADR OBJ attendu');
  If (RecType<>$9C) And (RecType<>$A0) And (RecType<>$A2) Then LastSegment:=0;
  Case RecType Of
   $80:Begin
    If Started Then Fail(72,'THEADR OBJ duplique');
    Name:=GetName; Started:=True;
   End;
   $88,$94: P:=Last; { commentaires et numeros de lignes }
   $96:While P<Last Do Begin
    If NameCount=MaxObjNames Then Unsupported('trop de LNAMES OBJ');
    Inc(NameCount);
    { Le nom overlay vide est autorise dans LNAMES. }
    If B^[P]=0 Then Begin Names[NameCount]:=''; Inc(P) End
    Else Names[NameCount]:=GetName;
   End;
   $98:Begin
    If (SegCount=MaxObjSegments) Or (ObjectSegmentCount=MaxObjSegments) Then
     Unsupported('trop de segments OBJ');
    A:=GetByte; C:=(A Shr 2) And 7; D:=A Shr 5;
    If (A And 1<>0) Or (D=0) Or (D>4) Or Not (C In [0,2,4,5,6,7]) Then
     Unsupported('SEGDEF absolu/Use32/alignement/combinaison');
    If C In [4,7] Then C:=2; { synonymes PUBLIC OMF86 }
    L:=GetWord;
    If (A And 2<>0) And (L<>0) Then Fail(72,'SEGDEF Big avec longueur non nulle');
    Inc(ObjectSegmentCount); S:=ObjectSegmentCount;
    FillChar(ObjectSegments[S],SizeOf(TObjectSegment),0);
    ObjectSegments[S].Length:=L;
    If A And 2<>0 Then ObjectSegments[S].Length:=65536;
    X:=GetIndex; ObjectSegments[S].Name:=NameIndex(X);
    X:=GetIndex; ObjectSegments[S].ClassName:=NameIndex(X);
    X:=GetIndex; Name:=NameIndex(X);
    If Name<>'' Then Unsupported('overlay OBJ');
    ObjectSegments[S].Combine:=C; ObjectSegments[S].Alignment:=D;
    ObjectSegments[S].Root:=S;
    New(ObjectSegments[S].Bytes); FillChar(ObjectSegments[S].Bytes^,SizeOf(TBinaryBuffer),0);
    Inc(SegCount); SegMap[SegCount]:=S;
   End;
   $9A:Begin
    X:=GetIndex; Name:=NameIndex(X); G:=0;
    For I:=1 To ObjectGroupCount Do If ObjectGroups[I].Name=Name Then G:=I;
    If G=0 Then Begin
     If ObjectGroupCount=MaxObjGroups Then Unsupported('trop de groupes OBJ');
     Inc(ObjectGroupCount); G:=ObjectGroupCount;
     FillChar(ObjectGroups[G],SizeOf(TObjectGroup),0); ObjectGroups[G].Name:=Name;
    End;
    If GroupCount=MaxObjGroups Then Unsupported('trop de GRPDEF OBJ');
    Inc(GroupCount); GroupMap[GroupCount]:=G;
    While P<Last Do Begin
     If GetByte<>$FF Then Unsupported('composant GRPDEF non segment');
     X:=GetIndex; S:=SegmentIndex(X);
     If ObjectGroups[G].Count=MaxObjSegments Then Unsupported('groupe OBJ trop grand');
     Inc(ObjectGroups[G].Count); ObjectGroups[G].Members[ObjectGroups[G].Count]:=S;
    End;
   End;
   $8C:While P<Last Do Begin
    Name:=GetName; X:=GetIndex;
    If (ExtCount=MaxObjNames) Or (ObjectExternalCount=MaxObjNames) Then
     Unsupported('trop de EXTDEF OBJ');
    Inc(ObjectExternalCount); ObjectExternals[ObjectExternalCount]:=Name;
    Inc(ExtCount); ExtMap[ExtCount]:=ObjectExternalCount;
   End;
   $90:Begin
    X:=GetIndex; G:=0; If X<>0 Then G:=GroupIndex(X);
    X:=GetIndex; S:=0; If X<>0 Then S:=SegmentIndex(X);
    If S=0 Then Unsupported('PUBDEF absolu');
    While P<Last Do Begin
     Name:=GetName; Offs:=GetWord; X:=GetIndex;
     If Offs>ObjectSegments[S].Length Then Fail(72,'PUBDEF hors segment');
     For I:=1 To ObjectPublicCount Do If ObjectPublics[I].Name=Name Then
      Fail(4,'PUBDEF OBJ duplique: '+Name);
     If ObjectPublicCount=MaxObjNames Then Unsupported('trop de PUBDEF OBJ');
     Inc(ObjectPublicCount);
     ObjectPublics[ObjectPublicCount].Name:=Name;
     ObjectPublics[ObjectPublicCount].Segment:=S;
     ObjectPublics[ObjectPublicCount].GroupIndex:=G;
     ObjectPublics[ObjectPublicCount].Offset:=Offs;
    End;
   End;
   $A0,$A2:Begin
    X:=GetIndex; LastSegment:=SegmentIndex(X); LastOffset:=GetWord;
    LastLength:=0;
    If LastOffset>ObjectSegments[LastSegment].Length Then Fail(72,'Donnees OBJ hors segment');
    If RecType=$A0 Then Begin
     If Longint(LastOffset)+Last-P>ObjectSegments[LastSegment].Length Then
      Fail(72,'LEDATA hors segment');
     LastLength:=Last-P;
     Move(B^[P],ObjectSegments[LastSegment].Bytes^[LastOffset],LastLength); P:=Last;
    End Else Begin
     While P<Last Do IteratedBlock(0);
     { FIXUPP sur LIDATA exige les offsets du flux encode; refuse clairement. }
     LastSegment:=0;
    End;
   End;
   $9C:While P<Last Do Begin
    A:=GetByte;
    If A And $80=0 Then Begin
     I:=A And 3; FM:=(A Shr 2) And 7;
     If A And $20<>0 Then Fail(72,'Bit reserve THREAD OBJ');
     FI:=0;
     If FM<3 Then Begin X:=GetIndex; FI:=MethodIndex(FM,X) End;
     If A And $40<>0 Then Begin
      If Not (FM In [0,1,2,4,5]) Then Unsupported('methode frame THREAD OBJ');
      FrameMethods[I]:=FM; FrameIndices[I]:=FI; FrameDefined[I]:=True;
     End Else Begin
      If FM>2 Then Unsupported('methode target THREAD OBJ');
      TargetMethods[I]:=FM; TargetIndices[I]:=FI; TargetDefined[I]:=True;
     End;
    End Else Begin
     If LastSegment=0 Then Fail(72,'FIXUPP sans LEDATA');
     Loc:=(A Shr 2) And 15; Relative:=A And $40=0;
     Offs:=Word(A And 3)*256+GetByte;
     If Not (Loc In [0,1,2,3,5]) Then Unsupported('location FIXUPP non 16 bits');
     L:=2; If Loc=0 Then L:=1 Else If Loc=3 Then L:=4;
     If Longint(Offs)+L>LastLength Then Fail(72,'FIXUPP hors LEDATA');
     If Relative And Not (Loc In [0,1,5]) Then Fail(72,'FIXUPP relatif de segment');
     FD:=GetByte; FM:=(FD Shr 4) And 7; FI:=0;
     If FD And $80<>0 Then Begin
      I:=FM And 3; If Not FrameDefined[I] Then Fail(72,'Thread frame OBJ indefini');
      FM:=FrameMethods[I]; FI:=FrameIndices[I];
     End Else If FM<3 Then Begin X:=GetIndex; FI:=MethodIndex(FM,X) End;
     If Not (FM In [0,1,2,4,5]) Then Unsupported('methode frame FIXUPP');
     TM:=FD And 3;
     If FD And 8<>0 Then Begin
      If Not TargetDefined[TM] Then Fail(72,'Thread target OBJ indefini');
      TI:=TargetIndices[TM]; TM:=TargetMethods[TM];
     End Else Begin
      If TM=3 Then Unsupported('target absolu FIXUPP');
      X:=GetIndex; TI:=MethodIndex(TM,X);
     End;
     Disp:=0; If FD And 4=0 Then Disp:=GetWord;
     If ObjectFixupCount=MaxFixups Then Unsupported('trop de FIXUPP OBJ');
     Inc(ObjectFixupCount);
     With ObjectFixups[ObjectFixupCount] Do Begin
      Segment:=LastSegment; Offset:=LastOffset+Offs; FrameIndex:=FI;
      TargetIndex:=TI; Displacement:=Disp; Location:=Loc;
      FrameMethod:=FM; TargetMethod:=TM;
     End;
     ObjectFixups[ObjectFixupCount].Relative:=Relative;
    End;
   End;
   $8A:Begin
    A:=GetByte; If A<>0 Then Unsupported('MODEND OBJ avec point d''entree');
    Ended:=True;
   End;
  Else Begin Str(RecType,Name); Unsupported('record OMF '+Name) End;
  End;
  If P<>Last Then Fail(72,'Taille record OBJ incoherente');
  P:=RecordEnd;
 End;
 If Not Ended Then Fail(72,'MODEND OBJ manquant');
End;

Function UnitFileSize(Var H: TUnitHeader): Longint;
Var Size: Longint;
Begin
 Size:=Align16(H.EndTrace)+Align16(H.CodeSize)+Align16(H.ConstSize)+
 Align16(H.CodeFixupSize)+Align16(H.DataFixupSize);
 If (H.Flags=$8000) And (H.Reserved[0]=$5054) And (H.Reserved[1]=$3143) And
    (H.Reserved[2]>=5) Then Begin
  If H.Reserved[9]>3 Then Fail(72,'Payload OBJ TPU trop grand');
  Size:=Size+H.Reserved[8]+Longint(H.Reserved[9])*65536;
  If Size>SizeOf(TBinaryBuffer) Then Fail(72,'TPU avec OBJ trop grande');
 End;
 UnitFileSize:=Size;
End;

Procedure ValidateUnitHeader(Name: TShortString; Limit: Longint; Var H: TUnitHeader);Begin
 If (H.Signature[0]<>'T') Or (H.Signature[1]<>'P') Or
 (H.Signature[2]<>'U') Or (H.Signature[3]<>'9') Then    Fail(72,
 'Signature TPU9 attendue: '+Name);
 If (H.EndTrace<SizeOf(H)) Or (UnitFileSize(H)>Limit) Or
 (H.Name<SizeOf(H)) Or (H.Name>=H.EndTrace) Or
 (H.Interf<SizeOf(H)) Or (H.Interf>=H.EndTrace) Then    Fail(72,
 'En-tete TPU incoherent: '+Name);
End;

Procedure ReadUnitHeaderAt(Name: TShortString; Base, Limit: Longint; Var H: TUnitHeader);
Var
 F: File;
 Count: Word;
 E: Integer;
 Size: Longint;
Begin
 Assign(F,Name); OpenBinaryRead(F,E);
 If E<>0 Then Fail(15,'Fichier introuvable: '+Name);
  {$I-} Size:=FileSize(F); E:=IOResult; {$I+}
 If (E<>0) Or (Base<0) Or (Base>Size-SizeOf(H)) Then Begin
  Close(F); Fail(72,'En-tete TPU/TPL hors fichier: '+Name);
 End;
 If Limit=0 Then Limit:=Size-Base;
 If (Limit<SizeOf(H)) Or (Limit>Size-Base) Then Begin
  Close(F); Fail(72,'Taille TPU/TPL incoherente: '+Name);
 End;
  {$I-} Seek(F,Base); BlockRead(F,H,SizeOf(H),Count); E:=IOResult;
 Close(F); If IOResult<>0 Then E:=1; {$I+}
 If (E<>0) Or (Count<>SizeOf(H)) Then Fail(72,'Unite tronquee: '+Name);
 ValidateUnitHeader(Name,Limit,H);
End;

Procedure ReadTPUHeader(Name: TShortString; Var H: TUnitHeader);Begin
 ReadUnitHeaderAt(Name,0,0,H)
End;

Function FindLibraryUnit(Name: TShortString): Word;
Var
 I: Word;
Begin
 FindLibraryUnit:=0;
 For I:=1 To LibraryCount Do If LibraryUnits[I].Name=Name Then Begin
  FindLibraryUnit:=I; Exit;
 End;
End;

Procedure ReadLibrary(Name: TShortString);
Var
 F: File;
 H: TUnitHeader;
 Base, Size, Span: Longint;
 Prefix: TSymbolPrefix;
 S: TShortString;
 Count: Word;
 E, I: Integer;
Begin
 LibraryCount:=0; LibraryName:=Name;
 Assign(F,Name); OpenBinaryRead(F,E);
 If E<>0 Then Fail(15,'Bibliotheque introuvable: '+Name);
 Size:=FileSize(F);
 If Size=0 Then Begin
  Close(F); Fail(72,'Bibliotheque TPL vide: '+Name)
 End;
 Base:=0;
 While Base<Size Do Begin
  If Size-Base<SizeOf(H) Then Fail(72,'En-tete TPL tronque: '+Name);
    {$I-} Seek(F,Base); BlockRead(F,H,SizeOf(H),Count); E:=IOResult; {$I+}
  If (E<>0) Or (Count<>SizeOf(H)) Then Fail(72,'En-tete TPL illisible: '+Name);
  ValidateUnitHeader(Name,Size-Base,H); Span:=UnitFileSize(H);
  If (H.Interf>=H.ProcMap) Or (H.ProcMap>H.CodeMap) Or
  (H.CodeMap>H.ConstMap) Or (H.ConstMap>H.DataMap) Or
  (H.DataMap>H.EndMaps) Or (H.EndMaps>H.Units) Or
  (H.Units>H.Sources) Or (H.Sources>H.Trace) Or
  (H.Trace>H.EndTrace) Or (H.Name+Longint(SizeOf(Prefix))>H.ProcMap) Then      Fail(72,
  'Sections TPL incoherentes: '+Name);
    {$I-} Seek(F,Base+H.Name); BlockRead(F,Prefix,SizeOf(Prefix),Count); E:=IOResult; {$I+}
  If (E<>0) Or (Count<>SizeOf(Prefix)) Or (Prefix.Typ<>89) Or
  (Prefix.NameLength=0) Or (Prefix.NameLength>63) Or
  (H.Name+Longint(SizeOf(Prefix))+Prefix.NameLength+8>H.ProcMap) Then      Fail(72,
  'Nom d''unite TPL invalide: '+Name);
  S:=''; S[0]:=Chr(Prefix.NameLength);
    {$I-} BlockRead(F,S[1],Prefix.NameLength,Count); E:=IOResult; {$I+}
  If (E<>0) Or (Count<>Prefix.NameLength) Then Fail(72,'Nom TPL tronque');
  S:=Upper(S);
  For I:=1 To Length(S) Do      If Not (S[I] In ['A'..'Z','_','0'..'9']) Then Fail(72,
  'Identificateur TPL invalide');
  If S[1] In ['0'..'9'] Then Fail(72,'Identificateur TPL invalide');
  If FindLibraryUnit(S)<>0 Then Fail(72,'Unite TPL dupliquee: '+S);
  If LibraryCount=MaxLibraryUnits Then Unsupported('plus de 256 unites TPL');
  Inc(LibraryCount); LibraryUnits[LibraryCount].Name:=S;
  LibraryUnits[LibraryCount].Offset:=Base; LibraryUnits[LibraryCount].Size:=Span;
  LibraryUnits[LibraryCount].Header:=H;
  Inc(Base,Span);
 End;
  {$I-} Close(F); E:=IOResult; {$I+}
 If E<>0 Then Fail(72,'Erreur de lecture TPL');
End;

Procedure FindAndReadLibrary;
Var
 D: DirStr;
 N: NameStr;
 E: ExtStr;
 S, Part, Candidate: TShortString;
 P: Integer;
Begin
 LibraryCount:=0; LibraryName:='';
 FSplit(FExpand(ParamStr(0)),D,N,E);
 If Length(TurboDirs)+Length(D)+4>255 Then CLIError('Liste de recherche TPL trop longue');
 S:='.;'+TurboDirs+';'+D;
 Repeat
 P:=Pos(';',S);
 If P=0 Then Begin
  Part:=S; S:=''
 End
  Else
 Begin
  Part:=Copy(S,1,P-1); Delete(S,1,P)
 End;
 If Part<>'' Then Begin
  Candidate:=JoinPath(Part,'TURBO.TPL');
  If FileExists(Candidate) Then Begin
   ReadLibrary(Candidate); Exit
  End;
 End;
 Until S='';
End;
{ Profil TPU9/TPC1: conteneur TPU9 et structures historiques, mais ABI locale
  near/CS=DS. Reserved[0..2] = 'TP','C1',1 et Flags=$8000 l'identifient.
  Ces fichiers ne sont PAS annonces compatibles avec le linker Borland.
  Les fixups code $4000 sont relatifs IP, $8000 absolus DS; Map=$FFFF
  designe une routine du runtime local. Aucun pointeur hote sur disque. }

Function LocalOffset(Target: Word; U: Byte; IsCode: Boolean): Word;
Var
 I, N: Word;
Begin
 N:=0;
 If Target<>0 Then
 For I:=0 To Target-1 Do Begin
  If IsCode Then Begin
   If CodeOwners[I]=U Then Inc(N)
  End
  Else If DataOwners[I]=U Then Inc(N);
 End;
 LocalOffset:=N;
End;

Function GlobalOffset(Offset: Word; U: Byte; IsCode: Boolean): Word;
Var
 I, N, Limit, Last: Word;
Begin
 If IsCode Then Limit:=CodeSize Else Limit:=DataSize;
 N:=0; Last:=0;
 If Limit<>0 Then
 For I:=0 To Limit-1 Do Begin
  If (IsCode And (CodeOwners[I]=U)) Or (Not IsCode And (DataOwners[I]=U)) Then Begin
   If N=Offset Then Begin
    GlobalOffset:=I; Exit
   End;
   Inc(N); Last:=I+1;
  End;
 End;
 If IsCode And (N<>0) And (N=Offset) Then Begin
  GlobalOffset:=Last; Exit
 End;
 Fail(72,'Offset hors section d''unite'); GlobalOffset:=0;
End;

Function InterfaceChecksumMode(U: Byte; WithTypes, WithCalls: Boolean): Word;
Var
 I, K, N, Temp, T, Root: Word;
 J: Integer;
 H: Word;
 Order: Array[1..MaxSymbols] Of Word;

Procedure Mix(W: Word);Begin
 H:=((H Shl 1) Or (H Shr 15))+W
End;
Begin
 H:=0; N:=0;
 For I:=1 To SymbolCount Do If (Symbols[I].Owner=U) And Symbols[I].Exported Then Begin
  Inc(N); Order[N]:=I;
 End;
 For I:=2 To N Do Begin
  K:=I;
  While K>1 Do Begin
   If Symbols[Order[K-1]].Name<Symbols[Order[K]].Name Then Break;
   Temp:=Order[K-1]; Order[K-1]:=Order[K]; Order[K]:=Temp; Dec(K);
  End;
 End;
 For K:=1 To N Do Begin
  I:=Order[K];
  For J:=1 To Length(Symbols[I].Name) Do Mix(Ord(Symbols[I].Name[J]));
  Mix(Symbols[I].Kind); Mix(Symbols[I].Typ);
  If WithCalls And (Symbols[I].Kind=skProc) Then Begin
   Mix(Ord(Symbols[I].FarRoutine)); Mix(Symbols[I].ParamCount); Mix(Symbols[I].ParamBytes);
   For J:=1 To Symbols[I].ParamCount Do Begin
    Mix(Symbols[I].ParamFlags[J]); T:=Symbols[I].ParamTypeIds[J];
    Mix(Types[T].Typ); Mix(Types[T].Width); Mix(Types[T].Capacity); Mix(Ord(Types[T].Signed));
    Mix(Word(Types[T].LowBound)); Mix(Word(Types[T].LowBound Shr 16));
    Mix(Word(Types[T].HighBound)); Mix(Word(Types[T].HighBound Shr 16));
    Root:=Types[T].Base;
    For Temp:=1 To Length(Types[Root].IdentityUnit) Do Mix(Ord(Types[Root].IdentityUnit[Temp]));
    For Temp:=1 To Length(Types[Root].IdentityName) Do Mix(Ord(Types[Root].IdentityName[Temp]));
   End;
  End;
  T:=SymbolType(I);
  If WithTypes And (T<>0) Then Begin
   Mix(Types[T].Width); Mix(Types[T].Capacity); Mix(Ord(Types[T].Signed));
   Mix(Word(Types[T].LowBound)); Mix(Word(Types[T].LowBound Shr 16));
   Mix(Word(Types[T].HighBound)); Mix(Word(Types[T].HighBound Shr 16));
   Root:=Types[T].Base;
   For J:=1 To Length(Types[Root].IdentityUnit) Do Mix(Ord(Types[Root].IdentityUnit[J]));
   For J:=1 To Length(Types[Root].IdentityName) Do Mix(Ord(Types[Root].IdentityName[J]));
  End;
  If Symbols[I].Kind=skConst Then Begin
   Mix(0); Mix(0)
  End
   Else
  Begin
   Mix(Symbols[I].Width); Mix(Symbols[I].Capacity)
  End;
  If Symbols[I].Kind=skConst Then Begin
   Mix(Word(Symbols[I].Value));
    If WithTypes Then Mix(Word(Symbols[I].Value Shr 16));
   For J:=0 To Length(Symbols[I].StrValue) Do Mix(Ord(Symbols[I].StrValue[J]));
  End;
 End;
 If H=0 Then H:=$FFFF;
 InterfaceChecksumMode:=H;
End;

Function InterfaceChecksum(U: Byte): Word;
Begin InterfaceChecksum:=InterfaceChecksumMode(U,True,True) End;

Function RuntimeNumber(Target: Word): Word;Begin
 If Target=RuntimeUnsigned Then RuntimeNumber:=221 Else
 If Target=RuntimeString Then RuntimeNumber:=216 Else
 If Target=RuntimeInteger Then RuntimeNumber:=220 Else
 If Target=RuntimeBoolean Then RuntimeNumber:=224 Else
 If Target=RuntimeChar Then RuntimeNumber:=228 Else
 If Target=RuntimeCopy Then RuntimeNumber:=48 Else
 If Target=RuntimeHalt Then RuntimeNumber:=12
  Else
 Begin
  Unsupported('reference de code hors unite'); RuntimeNumber:=0
 End;
End;

Function RuntimeAddress(N: Word): Word;Begin
 Case N Of
 216:RuntimeAddress:=RuntimeString; 220:RuntimeAddress:=RuntimeInteger;
 224:RuntimeAddress:=RuntimeBoolean; 228:RuntimeAddress:=RuntimeChar;
 48:RuntimeAddress:=RuntimeCopy;
 12:RuntimeAddress:=RuntimeHalt;
    221:RuntimeAddress:=RuntimeUnsigned;
  Else
 Begin
  Unsupported('routine du runtime TPU'); RuntimeAddress:=0
 End;
End;
End;

Procedure WriteCompiledUnit(U: Byte);
Var
 B: PBinaryBuffer;
 H: TUnitHeader;
 F: File;
 Posn, I, A, TypAddr, Bucket, CheckPos, CodeLen, DataLen: Word;
 FixLen, InitEntry, PayloadCheck: Word;
 V, TargetOwner: Byte;
 Refs: Array[0..MaxUnits] Of Word;
 Stubs: Array[0..MaxUnits] Of Word;
 MapStubs: Array[1..MaxSymbols] Of Word;
 SymbolEntries: Array[1..MaxSymbols] Of Word;
 FilePos, CodeStart, DataStart, RelStart: Longint;
 Count: Longint;
 E: Integer;
 Path: TShortString;
 D: DirStr;
 N: NameStr;
 Ext: ExtStr;
 NativeConstants: Boolean;
 MetadataCount,J: Word;

Procedure PutByte(X: Byte);Begin
 If Posn>=MaxImage Then Fail(123,'Dictionnaire TPU trop grand');
 B^[Posn]:=X; Inc(Posn);
End;

Procedure PutWord(X: Word);Begin
 PutByte(X And 255); PutByte(X Shr 8)
End;

Procedure SetWord(P, X: Word);Begin
 B^[P]:=X And 255; B^[P+1]:=X Shr 8
End;

Function GetWord(P: Word): Word;Begin
 GetWord:=B^[P]+Word(B^[P+1])*256
End;

Procedure PutString(S: TShortString);
Var
 K: Integer;
Begin
 PutByte(Length(S));
 For K:=1 To Length(S) Do PutByte(Ord(S[K]))
End;

Function SymbolEntry(S: TShortString; Kind: Byte): Word;
Var
 P: Word;
Begin
 P:=Posn; Bucket:=H.Interf+2+(HashIdent(S) And 126);
 PutWord(GetWord(Bucket)); SetWord(Bucket,P);
 PutByte(Kind); PutString(S); SymbolEntry:=P;
End;

Procedure UnitEntry(V: Byte; S: TShortString; Check: Word);
Var
 Prev, P: Word;
Begin
 Prev:=Stubs[U];
 If V<>U Then Begin
  Prev:=H.Name;
  While GetWord(Prev+4+B^[Prev+3]+4)<>0 Do        Prev:=GetWord(Prev+4+B^[Prev+3]+4);
 End;
 A:=SymbolEntry(S,89); Stubs[V]:=A;
 PutWord(0); PutWord(Check); PutWord(0); PutWord(0);
 If V<>U Then Begin
  P:=Prev+4+B^[Prev+3]; SetWord(P+4,A)
 End;
End;

Procedure Reloc(Position, Target: Word; IsData: Boolean);
Var
 Flags, Number: Word;
Begin
 If IsData Then Begin
  TargetOwner:=DataOwners[Target]; Flags:=$8000;
  Number:=LocalOffset(Target,TargetOwner,False);
 End Else
 Begin
      { Un saut vers la fin du corps peut viser le premier octet suivant. }
  If Target<CodeSize Then TargetOwner:=CodeOwners[Target] Else TargetOwner:=U;
  Flags:=$4000;
  Number:=LocalOffset(Target,TargetOwner,True);
  If Image[Position-1]=$E9 Then Begin
   TargetOwner:=U; Number:=LocalOffset(Target,U,True);
  End;
 End;
 If (TargetOwner<>U) And (TargetOwner<>0) And
 Not (TargetOwner In Units[U].Dependencies) Then      Unsupported(
 'reference TPU vers une unite non declaree');
 SetWord(Posn,Flags Or Refs[TargetOwner]); Inc(Posn,2);
 If Not IsData And (TargetOwner=0) Then Begin
  SetWord(Posn,$FFFF); Inc(Posn,2);
  SetWord(Posn,RuntimeNumber(Target)); Inc(Posn,2);
 End Else
 Begin
  SetWord(Posn,0); Inc(Posn,2); SetWord(Posn,Number); Inc(Posn,2);
 End;
 SetWord(Posn,LocalOffset(Position,U,True)); Inc(Posn,2);
End;
Begin
  { Cas natif sans code ni dependance utilisateur: les constantes utilisent
    directement les types SYSTEM historiques. La compatibilite du layout
    est testee; une validation avec le linker Borland reste necessaire. }
 NativeConstants:=UnitOutput And (U=1) And
 Not Units[U].HasInit And (Units[U].Dependencies=[]);
 For I:=1 To ObjectCount Do If ObjectFiles[I].Owner=U Then NativeConstants:=False;
 For I:=1 To SymbolCount Do If (Symbols[I].Owner=U) And
 (Symbols[I].Kind<>skConst) Then NativeConstants:=False;
 If Not NativeConstants Then
  For I:=1 To SymbolCount Do If (Symbols[I].Owner=U) And Symbols[I].Exported And
    (Symbols[I].Kind=skConst) And (Symbols[I].Typ<>ttString) And
    ((Symbols[I].Value<-32768) Or (Symbols[I].Value>65535)) Then
      Unsupported('export constante Longint dans le profil local');
 New(B); FillChar(B^,SizeOf(TBinaryBuffer),0); FillChar(H,SizeOf(H),0);
 FillChar(MapStubs,SizeOf(MapStubs),0); FillChar(Refs,SizeOf(Refs),0);
 FillChar(SymbolEntries,SizeOf(SymbolEntries),0);
 FillChar(Stubs,SizeOf(Stubs),0);
 H.Signature[0]:='T'; H.Signature[1]:='P'; H.Signature[2]:='U'; H.Signature[3]:='9';
 H.Flags:=$8000; H.Reserved[0]:=$5054; H.Reserved[1]:=$3143; H.Reserved[2]:=4;
 Units[U].Checksum:=InterfaceChecksum(U);
 Posn:=80; H.Interf:=Posn; PutWord(126);
 For I:=1 To 64 Do PutWord(0);
 H.Name:=Posn;
 If NativeConstants Then UnitEntry(U,Units[U].Name,0)
                    Else UnitEntry(U,Units[U].Name,Units[U].Checksum);
 CheckPos:=H.Name+4+Length(Units[U].Name)+2;
 UnitEntry(0,'SYSTEM',0);
 For V:=1 To UnitCount Do If V In Units[U].Dependencies Then    UnitEntry(V,Units[V].Name,
 Units[V].Checksum);
  { Types locaux: la partie segment reference le symbole d'unite. }
 For I:=1 To SymbolCount Do If (Symbols[I].Owner=U) And Symbols[I].Exported Then Begin
  TypAddr:=Posn; PutByte(Symbols[I].Typ);
  If Symbols[I].Typ=ttInteger Then Begin
   If Symbols[I].Width=1 Then PutByte(2) Else PutByte(5);
  End Else PutByte(0);
  If (Symbols[I].Typ=ttString) And (Symbols[I].Kind=skConst) Then PutWord(256) Else
  If Symbols[I].Typ=ttString Then PutWord(Word(Symbols[I].Capacity)+1) Else
  If Symbols[I].Kind=skConst Then Begin
   If Symbols[I].Typ=ttInteger Then PutWord(2) Else PutWord(1);
  End Else PutWord(Symbols[I].Width);
  PutWord(0);
  If Symbols[I].Typ=ttInteger Then Begin
   If Symbols[I].Width=1 Then Begin
    PutWord(0); PutWord(0); PutWord(255); PutWord(0)
   End
    Else
   Begin
    PutWord($8000); PutWord($FFFF); PutWord($7FFF); PutWord(0)
   End;
   PutWord(TypAddr); PutWord(H.Name+4+Length(Units[U].Name));
  End;
  Case Symbols[I].Kind Of
  skType:Begin
   A:=SymbolEntry(Symbols[I].Name,81); PutWord(TypAddr);
   PutWord(H.Name+4+Length(Units[U].Name));
  End;
  skConst:
  Begin
   A:=SymbolEntry(Symbols[I].Name,80);
   If NativeConstants Then Begin
    Case Symbols[I].Typ Of
    ttInteger:PutWord($114); ttChar:PutWord($14C);
    ttBoolean:PutWord($130); ttString:PutWord($A0);
   End;
   PutWord(Stubs[0]+4+6);
  End Else
  Begin
   PutWord(TypAddr); PutWord(H.Name+4+Length(Units[U].Name));
  End;
  If Symbols[I].Typ=ttString Then PutString(Symbols[I].StrValue)
   Else
  Begin
   PutWord(Word(Symbols[I].Value));
  PutWord(Word(Symbols[I].Value Shr 16));
  End;
 End;
 skVar:
 Begin
  A:=SymbolEntry(Symbols[I].Name,82); PutByte(0);
  PutWord(LocalOffset(Symbols[I].Addr,U,False)); PutWord(0);
  PutWord(TypAddr); PutWord(H.Name+4+Length(Units[U].Name));
 End;
 skProc:
 Begin
  A:=SymbolEntry(Symbols[I].Name,83); MapStubs[I]:=A+4+Length(Symbols[I].Name);
  PutByte(Ord(Symbols[I].FarRoutine)); PutByte(0); PutWord(0); PutWord(0); PutWord(0); PutWord(0);
  PutByte(ttProc); PutByte(0); PutWord(0); PutWord(0);
  PutWord(0); PutWord(0); PutWord(0);
 End;
End;
 SymbolEntries[I]:=A;
End;
If Not NativeConstants Then Begin
 H.Reserved[5]:=Posn; PutWord(TypeCount);
 For I:=1 To TypeCount Do Begin
  If Longint(Posn)+SizeOf(TTypeInfo)>MaxImage Then Fail(123,'Types TPU trop grands');
  Move(Types[I],B^[Posn],SizeOf(TTypeInfo)); Inc(Posn,SizeOf(TTypeInfo));
 End;
 MetadataCount:=0;
 For I:=1 To SymbolCount Do If (SymbolEntries[I]<>0) And (SymbolType(I)<>0) Then Inc(MetadataCount);
 PutWord(MetadataCount);
 For I:=1 To SymbolCount Do If (SymbolEntries[I]<>0) And (SymbolType(I)<>0) Then Begin
  PutWord(SymbolEntries[I]); PutWord(SymbolType(I));
 End;
 MetadataCount:=0;
 For I:=1 To SymbolCount Do If (SymbolEntries[I]<>0) And (Symbols[I].Kind=skProc) Then Inc(MetadataCount);
 PutWord(MetadataCount);
 For I:=1 To SymbolCount Do If (SymbolEntries[I]<>0) And (Symbols[I].Kind=skProc) Then Begin
  PutWord(SymbolEntries[I]); PutWord(Symbols[I].ParamCount); PutWord(Symbols[I].ParamBytes);
  PutWord(Ord(Symbols[I].FarRoutine));
  For J:=1 To Symbols[I].ParamCount Do Begin
   PutWord(Symbols[I].ParamTypeIds[J]); PutWord(Symbols[I].ParamFlags[J]);
  End;
 End;
 H.Reserved[6]:=Posn;
 MetadataCount:=0;
 For V:=1 To UnitCount Do If V In Units[U].NativeDependencies Then Inc(MetadataCount);
 PutWord(MetadataCount);
 For V:=1 To UnitCount Do If V In Units[U].NativeDependencies Then Begin
  PutString(Units[V].Name); PutWord(Units[V].Checksum);
 End;
 MetadataCount:=0;
 For I:=1 To NativeRefCount Do If CodeOwners[NativeRefs[I].Position]=U Then Inc(MetadataCount);
 PutWord(MetadataCount);
 For I:=1 To NativeRefCount Do If CodeOwners[NativeRefs[I].Position]=U Then Begin
  PutWord(LocalOffset(NativeRefs[I].Position,U,True));
  PutString(Units[NativeRefs[I].U].Name); PutWord(Units[NativeRefs[I].U].Checksum);
  PutWord(NativeRefs[I].Kind); PutWord(NativeRefs[I].Map); PutWord(NativeRefs[I].Target);
 End;
 MetadataCount:=0;
 For I:=1 To RelocationCount Do If (Relocations[I].Segm=0) And
   (CodeOwners[Relocations[I].Offs]=U) Then Inc(MetadataCount);
 PutWord(MetadataCount);
 For I:=1 To RelocationCount Do If (Relocations[I].Segm=0) And
   (CodeOwners[Relocations[I].Offs]=U) Then Begin
  PutWord(LocalOffset(Relocations[I].Offs,U,True)); PutWord(RelocationKinds[I]);
 End;
 MetadataCount:=0;
 For I:=1 To ObjectCount Do If ObjectFiles[I].Owner=U Then Inc(MetadataCount);
 For I:=1 To ObjectCallCount Do If CodeOwners[ObjectCalls[I].Position]=U Then Inc(MetadataCount);
 If MetadataCount<>0 Then Begin
  H.Reserved[2]:=5; H.Reserved[7]:=Posn;
  MetadataCount:=0;
  For I:=1 To ObjectCallCount Do If CodeOwners[ObjectCalls[I].Position]=U Then Inc(MetadataCount);
  PutWord(MetadataCount);
  For I:=1 To ObjectCallCount Do If CodeOwners[ObjectCalls[I].Position]=U Then Begin
   PutWord(LocalOffset(ObjectCalls[I].Position,U,True)); PutString(ObjectCalls[I].Name);
  End;
 End;
End;
If Odd(Posn) Then PutByte(0);
If NativeConstants Then Begin
 PayloadCheck:=0; I:=H.Interf;
 While I+1<Posn Do Begin
  PayloadCheck:=((PayloadCheck Shl 1) Or (PayloadCheck Shr 15))+GetWord(I);
  Inc(I,2);
 End;
 If PayloadCheck=0 Then PayloadCheck:=$FFFF;
 SetWord(CheckPos,PayloadCheck); Units[U].Checksum:=PayloadCheck;
End;
H.ProcMap:=Posn;
InitEntry:=$FFFF;
If Units[U].HasInit Then InitEntry:=LocalOffset(Units[U].InitAddress,U,True);
PutWord(0); PutWord(0);
If NativeConstants Then Begin
 PutWord($FFFF); PutWord(0)
End
 Else
Begin
 PutWord(0); PutWord(InitEntry)
End;
For I:=1 To SymbolCount Do If MapStubs[I]<>0 Then Begin
 SetWord(MapStubs[I]+2,Posn-H.ProcMap);
 PutWord(MapStubs[I]); PutWord(0); PutWord(0);
 PutWord(LocalOffset(Symbols[I].Addr,U,True));
End;
CodeLen:=LocalOffset(CodeSize,U,True); DataLen:=LocalOffset(DataSize,U,False);
If NativeConstants Then Begin
 CodeLen:=0; DataLen:=0
End;
FixLen:=0;
For I:=1 To FixupCount Do If CodeOwners[Fixups[I].Position]=U Then Begin
 If FixLen>MaxImage-8 Then Unsupported('trop de fixups dans une unite');
 Inc(FixLen,8);
End;
For I:=1 To RelativeCount Do If CodeOwners[RelativeFixups[I].Position]=U Then Begin
 If FixLen>MaxImage-8 Then Unsupported('trop de fixups dans une unite');
 Inc(FixLen,8);
End;
If Longint(Posn)+FixLen+1024>MaxImage Then Unsupported(
'dictionnaire et fixups TPU trop grands');
H.CodeMap:=Posn;
If Not NativeConstants Then Begin
 PutWord(0); PutWord(CodeLen); PutWord(FixLen); PutWord(0)
End;
H.ConstMap:=Posn;
If Not NativeConstants Then Begin
 PutWord(0); PutWord(DataLen); PutWord(0); PutWord(0)
End;
H.DataMap:=Posn; H.EndMaps:=Posn; H.Units:=Posn;
Refs[U]:=0; PutWord(0); PutString(Units[U].Name);
Refs[0]:=Posn-H.Units; PutWord(0); PutString('SYSTEM');
For V:=1 To UnitCount Do If V In Units[U].Dependencies Then Begin
 Refs[V]:=Posn-H.Units; PutWord(0); PutString(Units[V].Name);
End;
H.Sources:=Posn; H.Trace:=Posn; H.EndTrace:=Posn; H.DebugHash:=H.Interf;
H.CodeSize:=CodeLen; H.ConstSize:=DataLen; H.CodeFixupSize:=FixLen;
H.Reserved[3]:=CheckPos; { profil: emplacement du checksum d'interface }
If NativeConstants Then Begin
 H.Flags:=0; FillChar(H.Reserved,SizeOf(H.Reserved),0);
End;
CodeStart:=Align16(Posn); FilePos:=CodeStart;
For I:=0 To CodeSize-1 Do If CodeOwners[I]=U Then Begin
 B^[FilePos]:=Image[I]; Inc(FilePos)
End;
DataStart:=CodeStart+Align16(CodeLen); FilePos:=DataStart;
If Not NativeConstants Then
For I:=0 To DataSize-1 Do If DataOwners[I]=U Then Begin
 B^[FilePos]:=Data[I]; Inc(FilePos)
End;
RelStart:=DataStart+Align16(DataLen);
  { Les fixups sont apres les deux sections; reutiliser un curseur Word
    uniquement dans une zone temporaire puis copier vers le fichier. }
Posn:=H.EndTrace;
For I:=1 To FixupCount Do If CodeOwners[Fixups[I].Position]=U Then    Reloc(
Fixups[I].Position,Fixups[I].DataOffset,True);
For I:=1 To RelativeCount Do If CodeOwners[RelativeFixups[I].Position]=U Then    Reloc(
RelativeFixups[I].Position,RelativeFixups[I].Target,False);
Move(B^[H.EndTrace],B^[RelStart],FixLen);
  { Effacer seulement la zone entre dictionnaire et code: elle avait servi
    de temporaire et peut recouvrir le code. Celui-ci est reconstitue. }
FilePos:=CodeStart;
For I:=0 To CodeSize-1 Do If CodeOwners[I]=U Then Begin
 B^[FilePos]:=Image[I]; Inc(FilePos)
End;
FilePos:=DataStart;
If Not NativeConstants Then
For I:=0 To DataSize-1 Do If DataOwners[I]=U Then Begin
 B^[FilePos]:=Data[I]; Inc(FilePos)
End;
FilePos:=RelStart+Align16(FixLen);
If H.Reserved[2]=5 Then Begin
 MetadataCount:=0;
 For I:=1 To ObjectCount Do If ObjectFiles[I].Owner=U Then Inc(MetadataCount);
 If FilePos+2>SizeOf(TBinaryBuffer) Then Unsupported('TPU avec OBJ trop grande');
 B^[FilePos]:=MetadataCount And 255; B^[FilePos+1]:=MetadataCount Shr 8; Inc(FilePos,2);
 For I:=1 To ObjectCount Do If ObjectFiles[I].Owner=U Then Begin
  If FilePos+5+Length(ObjectFiles[I].Path)+ObjectFiles[I].Length>SizeOf(TBinaryBuffer) Then
   Unsupported('TPU avec OBJ trop grande');
  For J:=0 To 3 Do B^[FilePos+J]:=(ObjectFiles[I].Length Shr (J*8)) And 255;
  Inc(FilePos,4); B^[FilePos]:=Length(ObjectFiles[I].Path); Inc(FilePos);
  Move(ObjectFiles[I].Path[1],B^[FilePos],Length(ObjectFiles[I].Path));
  Inc(FilePos,Length(ObjectFiles[I].Path));
  Move(ObjectFiles[I].Bytes^,B^[FilePos],ObjectFiles[I].Length);
  Inc(FilePos,ObjectFiles[I].Length);
 End;
 If Align16(FilePos)>SizeOf(TBinaryBuffer) Then Unsupported('TPU avec OBJ trop grande');
 FilePos:=Align16(FilePos);
 H.Reserved[8]:=Word(FilePos-RelStart-Align16(FixLen));
 H.Reserved[9]:=(FilePos-RelStart-Align16(FixLen)) Shr 16;
End;
PayloadCheck:=0;
For CodeStart:=80 To FilePos-1 Do    PayloadCheck:=((PayloadCheck Shl 1) Or (
PayloadCheck Shr 15))+B^[CodeStart];
If Not NativeConstants Then H.Reserved[4]:=PayloadCheck;
Move(H,B^,SizeOf(H));
FSplit(Units[U].Path,D,N,Ext);
If OutputDir='' Then Path:=D+Units[U].Name+'.TPU'
                Else Path:=JoinPath(OutputDir,Units[U].Name+'.TPU');
Assign(F,Path); {$I-} Rewrite(F,1); E:=IOResult; {$I+}
If E<>0 Then Begin
 Dispose(B); Fail(16,'Creation TPU impossible: '+Path)
End;
FilePos:=UnitFileSize(H);
  {$I-} BlockWrite(F,B^,FilePos,Count); E:=IOResult; Close(F);
If IOResult<>0 Then E:=1;
If (E<>0) Or (Count<>FilePos) Then Begin
 Erase(F); E:=IOResult; E:=1
End;
  {$I+}
Dispose(B);
If E<>0 Then Fail(16,'Ecriture TPU impossible: '+Path);
If Not Quiet Then Begin
 If NativeConstants Then WriteLn('TPU9 constantes (sans code): ',Path)
                    Else WriteLn('TPU9/TPC1: ',Path);
End;
End;

Procedure WriteUnits;
Var
 U, V: Byte;
Begin
  { Checksums connus avant l'ecriture pour les cycles d'implementation. }
 For U:=1 To UnitCount Do If Units[U].FromSource Then    Units[U].Checksum:=
 InterfaceChecksum(U);
 For U:=1 To UnitCount Do
 For V:=1 To UnitCount Do    If (Units[U].DependencyChecks[V]<>0) And
 (Units[U].DependencyChecks[V]<>Units[V].Checksum) Then      Fail(70,Units[U].Name+' / '+
 Units[V].Name);
 For U:=1 To UnitCount Do If Units[U].FromSource Then WriteCompiledUnit(U);
End;
Procedure LoadCompiledUnit(U: Byte; Path: TShortString);Forward;
Function DecodeNativeType(U: Byte; Offset: Word): Word; Forward;

Procedure RequireUnit(Name: TShortString; Var U: Byte);
Var
 Path: TShortString;
 Entry: Word;
Begin
 U:=FindBuildUnit(Name);
 If U<>0 Then Begin
  If (U=CurrentUnit) Or ((Units[U].State=1) And Not Units[U].InterfaceReady)
  Then      Fail(68,Name);
  Exit;
 End;
 If UnitCount=MaxUnits Then Unsupported('plus de 64 unites');
 Entry:=FindLibraryUnit(Name);
 Path:=''; If (Entry=0) And BuildMode Then Path:=FindUnitPath(Name,'.PAS');
 Inc(UnitCount); U:=UnitCount; FillChar(Units[U],SizeOf(TBuildUnit),0);
 Units[U].Name:=Name; Units[U].State:=1;
 Units[U].LibraryEntry:=Entry;
 If Entry<>0 Then LoadCompiledUnit(U,LibraryName) Else
 If Path<>'' Then CompileSourceUnit(U,Path)
  Else
 Begin
  Path:=FindUnitPath(Name,'.TPU');
  If Path='' Then Fail(15,'Fichier introuvable: '+Name+'.TPU');
  LoadCompiledUnit(U,Path);
 End;
End;

Procedure LoadCompiledUnit(U: Byte; Path: TShortString);
Var
 B: PBinaryBuffer;
 H: TUnitHeader;
 F: File;
 P: PParserState;
 Size, Base, Count, CodeStart, DataStart, RelStart, X: Longint;
 A, Stub, I, J, Bucket, Next, Steps, W, R, Map, Target: Word;
 ParamN, K: Word;
  MetaPos, MetaCount, DiskCount, TIndex, NewIndex: Word;
  DiskTypes: Array[1..MaxTypes] Of TTypeInfo;
  TypeMap: Array[1..MaxTypes] Of Word;
 MapSum, FixSum: Longint;
 V, Typ, Width, Capacity, Kind: Byte;
 IsLocal, ProjectForeign, TypeSupported, TypeSigned: Boolean;
 Name: TShortString;
 RefOffsets, RefChecks: Array[0..MaxUnits+1] Of Word;
 RefUnits: Array[0..MaxUnits+1] Of Byte;
 RefCount: Integer;
 E: Integer;
 Value: Longint;
 DecodedTypeId: Word;

Procedure Bounds(P, N: Longint);Begin
 If (P<0) Or (N<0) Or (P>Size-N) Then Fail(72,'Reference TPU hors fichier');
End;

Procedure DictBounds(P, N: Longint);Begin
 Bounds(P,N);
 If (P<80) Or (P+N>H.ProcMap) Then Fail(72,'Reference hors dictionnaire TPU');
End;

Function ReadWord(P: Longint): Word;Begin
 Bounds(P,2); ReadWord:=B^[P]+Word(B^[P+1])*256
End;

Function ReadString(P: Longint): TShortString;
Var
 K: Integer;
 S: TShortString;
Begin
 Bounds(P,1); Bounds(P+1,B^[P]); S:='';
 For K:=1 To B^[P] Do S:=S+Chr(B^[P+K]);
 ReadString:=S;
End;

Function SymbolStub(P: Word): Word;Begin
 DictBounds(P,4); DictBounds(P,4+B^[P+3]);
 If (B^[P+3]=0) Or (B^[P+3]>63) Then Fail(72,'Nom de symbole TPU invalide');
 SymbolStub:=P+4+B^[P+3];
End;

Function CheckForUnit(S: TShortString): Word;
Var
 K, Addr, Limit: Word;
Begin
 CheckForUnit:=0;
 For K:=0 To ReadWord(H.Interf) Div 2 Do Begin
  Addr:=ReadWord(H.Interf+2+K*2); Limit:=0;
  While Addr<>0 Do Begin
   Inc(Limit); If Limit>MaxSymbols Then Fail(72,'Cycle dans le hash TPU');
   W:=SymbolStub(Addr);
   If (Upper(ReadString(Addr+3))=S) And (B^[Addr+2]=89) Then Begin
    DictBounds(W,8);
    CheckForUnit:=ReadWord(W+2); Exit;
   End;
   DictBounds(Addr,4); Addr:=ReadWord(Addr);
  End;
 End;
End;

Procedure DecodeType(P: Word);
Var
 T, S, Addr, StubAddr, Limit: Word;
 UnitName: TShortString;

Procedure Reject(S: TShortString);Begin
 If ProjectForeign Then TypeSupported:=False Else Unsupported(S);
End;
Begin
 TypeSupported:=True; TypeSigned:=False;
 DecodedTypeId:=0;
 DictBounds(P,4); T:=ReadWord(P); S:=ReadWord(P+2);
 Width:=0; Capacity:=0;
 If ProjectForeign Then Begin
  Addr:=H.Name; Limit:=0; UnitName:='';
  While Addr<>0 Do Begin
   Inc(Limit); If Limit>MaxUnits+2 Then Fail(72,'Cycle des stubs de types Borland');
   StubAddr:=SymbolStub(Addr); DictBounds(StubAddr,8);
   If S=StubAddr Then Begin UnitName:=Upper(ReadString(Addr+3)); Break End;
   Addr:=ReadWord(StubAddr+4);
  End;
  If UnitName='' Then Fail(72,'Proprietaire de type Borland invalide');
  If (UnitName='SYSTEM') And (FindBuildUnit('SYSTEM')=0) And
     (FindLibraryUnit('SYSTEM')=0) And (FindUnitPath('SYSTEM','.TPU')='') Then Begin
   { Import de constantes sans runtime: offsets standard verifies dans
     COMPILER.INC. Aucun code n'est lie par ce chemin de secours. }
   Case T Of
    $A0:DecodedTypeId:=7; $DE:DecodedTypeId:=2; $F0:DecodedTypeId:=1;
    $102:DecodedTypeId:=3; $130:DecodedTypeId:=5; $14C:DecodedTypeId:=6;
    $114:DecodedTypeId:=NewType(ttInteger,4,0,True,-2147483647-1,2147483647,1);
   Else Begin Reject('type SYSTEM sans descripteur disponible'); Exit End;
   End;
   Typ:=Types[DecodedTypeId].Typ; Width:=Types[DecodedTypeId].Width;
   Capacity:=Types[DecodedTypeId].Capacity; TypeSigned:=Types[DecodedTypeId].Signed;
   Exit;
  End;
  If UnitName=Units[U].Name Then V:=U Else RequireUnit(UnitName,V);
  DecodedTypeId:=DecodeNativeType(V,T);
  If DecodedTypeId=0 Then Begin Reject('descripteur de type Borland non pris en charge'); Exit End;
  Typ:=Types[DecodedTypeId].Typ; Width:=Types[DecodedTypeId].Width;
  Capacity:=Types[DecodedTypeId].Capacity; TypeSigned:=Types[DecodedTypeId].Signed;
  Exit;
 End;
 If S=SymbolStub(H.Name) Then Begin
  DictBounds(T,6); Typ:=B^[T]; W:=ReadWord(T+2);
  TypeSigned:=(Typ=ttInteger) And (B^[T+1] And 1<>0);
  If (Typ<>ttString) And (W>4) Then Begin
   Reject('taille de type TPU'); Exit
  End;
  Width:=W;
  If Typ=ttString Then Begin
   W:=ReadWord(T+2);
   If (W<2) Or (W>256) Then Fail(72,'Type string TPU invalide');
   Capacity:=W-1; Width:=0;
  End;
  If (Typ=ttInteger) And Not (Width In [1,2]) And
  Not ((Kind=80) And (Width=4) And Not IsLocal) Then Begin
   Reject('type entier TPU > 16 bits'); Exit
  End;
 End Else
 Begin
      { Les pointeurs disque originaux referencent un symbole d'unite,
        pas un segment hote. Types SYSTEM standards dans COMPILER.INC. }
  Addr:=H.Name; Limit:=0; UnitName:='';
  While Addr<>0 Do Begin
   Inc(Limit); If Limit>MaxUnits+2 Then Fail(72,'Cycle des stubs d''unites TPU');
   StubAddr:=SymbolStub(Addr); DictBounds(StubAddr,8);
   If S=StubAddr Then Begin
    UnitName:=Upper(ReadString(Addr+3)); Break
   End;
   Addr:=ReadWord(StubAddr+4);
  End;
  If UnitName='' Then Fail(72,'Segment du type TPU invalide');
  If UnitName<>'SYSTEM' Then Begin
   Reject('type d''une autre unite TPU'); Exit
  End;
  Case T Of
  $A0:
  Begin
   Typ:=ttString; Capacity:=255
  End;
  $DE:
  Begin
   Typ:=ttInteger; Width:=1
  End;
  $F0:
  Begin
   Typ:=ttInteger; Width:=2
  End;
  $102:
  Begin
   Typ:=ttInteger; Width:=2
  End;
  $114:
  Begin
   Typ:=ttInteger; Width:=4
  End;
  $130:
  Begin
   Typ:=ttBoolean; Width:=1
  End;
  $14C:
  Begin
   Typ:=ttChar; Width:=1
  End;
   Else
  Begin
   Reject('type SYSTEM non pris en charge dans la TPU'); Exit
  End;
 End;
End;
  If Not (Typ In [ttString,ttInteger,ttBoolean,ttChar,ttEnum]) Then Begin
 Reject('type TPU non pris en charge'); Exit;
End;
If (Typ In [ttChar,ttBoolean]) And (Width<>1) Then Fail(72,'Taille ordinale TPU invalide')
;
End;
Begin
 Base:=0; Size:=0;
 If Units[U].LibraryEntry<>0 Then Begin
  Base:=LibraryUnits[Units[U].LibraryEntry].Offset;
  Size:=LibraryUnits[Units[U].LibraryEntry].Size;
 End;
 ReadUnitHeaderAt(Path,Base,Size,H);
 SaveParser(P); CurrentUnit:=U; SourceName:=Path;
  CurrentScope:=0;
 TokenLine:=1; TokenColumn:=1; InInterface:=True; Imports:=[]; ImportCount:=0;
 Units[U].Path:=Path;
 Assign(F,Path); OpenBinaryRead(F,E);
 If E<>0 Then Fail(15,Path);
 If Units[U].LibraryEntry=0 Then Size:=FileSize(F);
 If (Size<80) Or (Size>SizeOf(TBinaryBuffer)) Then Begin
  Close(F); Fail(72,'Taille TPU invalide')
 End;
 New(B);
  {$I-} Seek(F,Base); BlockRead(F,B^,Size,Count); E:=IOResult; Close(F);
 If IOResult<>0 Then E:=1; {$I+}
 If (E<>0) Or (Count<>Size) Then Fail(72,'Lecture TPU incomplete');
 If (H.Interf>=H.ProcMap) Or (H.ProcMap>H.CodeMap) Or
 (H.CodeMap>H.ConstMap) Or (H.ConstMap>H.DataMap) Or
 (H.DataMap>H.EndMaps) Or (H.EndMaps>H.Units) Or
 (H.Units>H.Sources) Or (H.Sources>H.EndTrace) Then    Fail(72,
 'Ordre des sections TPU invalide');
 A:=SymbolStub(H.Name); DictBounds(A,8);
 If B^[H.Name+2]<>89 Then Fail(72,'Symbole de nom TPU invalide');
 Name:=Upper(ReadString(H.Name+3));
 If Name<>Units[U].Name Then Fail(69,Name+' <> '+Units[U].Name);
 Units[U].Checksum:=ReadWord(A+2);
 IsLocal:=(H.Flags=$8000) And (H.Reserved[0]=$5054) And (H.Reserved[1]=$3143);
 ProjectForeign:=Not IsLocal;
  If IsLocal And Not (H.Reserved[2] In [1,2,3,4,5]) Then Fail(72,'Version du profil TPC1 inconnue');
 If IsLocal Then Begin
  W:=0;
  For X:=80 To Size-1 Do W:=((W Shl 1) Or (W Shr 15))+B^[X];
  If W<>H.Reserved[4] Then Fail(72,'Integrite de la TPU TPC1 invalide');
 End;
 If Not IsLocal Then Begin
  If ((H.CodeMap-H.ProcMap) Mod 8<>0) Or
  ((H.ConstMap-H.CodeMap) Mod 8<>0) Or ((H.DataMap-H.ConstMap) Mod 8<>0) Or
  ((H.EndMaps-H.DataMap) Mod 8<>0) Then Fail(72,'Cartes natives TPU invalides');
  MapSum:=0; FixSum:=0; X:=H.CodeMap;
  While X<H.ConstMap Do Begin
    If ReadWord(X+4) Mod 8<>0 Then Fail(72,'Fixups code Borland non alignes');
   If Longint(MapSum)+ReadWord(X+2)>65535 Then Fail(72,'Code natif trop grand');
   Inc(MapSum,ReadWord(X+2)); Inc(FixSum,ReadWord(X+4)); Inc(X,8);
  End;
  If (MapSum<>H.CodeSize) Or (FixSum<>H.CodeFixupSize) Then Fail(72,
  'Tailles code natif incoherentes');
  MapSum:=0; FixSum:=0; X:=H.ConstMap;
  While X<H.DataMap Do Begin
    If ReadWord(X+4) Mod 8<>0 Then Fail(72,'Fixups constantes Borland non alignes');
   Inc(MapSum,ReadWord(X+2)); Inc(FixSum,ReadWord(X+4)); Inc(X,8);
  End;
  If (MapSum<>H.ConstSize) Or (FixSum<>H.DataFixupSize) Then Fail(72,
  'Tailles constantes natives incoherentes');
  MapSum:=0; X:=H.DataMap;
  While X<H.EndMaps Do Begin
   Inc(MapSum,ReadWord(X+2)); Inc(X,8)
  End;
  If MapSum<>H.DataSize Then Fail(72,'Taille donnees natives incoherente');
  NativeBuffers[U]:=B; NativeHeaders[U]:=H;
 End;
 CodeStart:=Align16(H.EndTrace); DataStart:=CodeStart+Align16(H.CodeSize);
 RelStart:=DataStart+Align16(H.ConstSize);
 Units[U].CodeBase:=CodeSize; Units[U].DataBase:=DataSize;
 If IsLocal Then Begin
  If (H.ConstMap-H.CodeMap<>8) Or (H.DataMap-H.ConstMap<>8) Or
  (H.EndMaps<>H.DataMap) Or (H.DataSize<>0) Or (H.DataFixupSize<>0) Or
  ((H.CodeMap-H.ProcMap) Mod 8<>0) Or (H.CodeMap-H.ProcMap<8) Or
  (H.CodeFixupSize Mod 8<>0) Then Fail(72,'Cartes du profil TPC1 invalides');
  If (ReadWord(H.CodeMap+2)<>H.CodeSize) Or
  (ReadWord(H.CodeMap+4)<>H.CodeFixupSize) Or
  (ReadWord(H.ConstMap+2)<>H.ConstSize) Then Fail(72,'Tailles cartes incoherentes');
  If H.CodeSize<>0 Then
  For I:=0 To H.CodeSize-1 Do Emit(B^[CodeStart+I]);
  A:=AllocData(H.ConstSize);
  If H.ConstSize<>0 Then Move(B^[DataStart],Data[A],H.ConstSize);
  W:=ReadWord(H.ProcMap+6);
  If W<>$FFFF Then Begin
   If W>=H.CodeSize Then Fail(72,'Initialisation TPU hors code');
   Units[U].HasInit:=True; Units[U].InitAddress:=Units[U].CodeBase+W;
  End;
 End;
 DictBounds(H.Interf,2); W:=ReadWord(H.Interf);
 If (W>510) Or Odd(W) Then Fail(72,'Hash TPU invalide');
 DictBounds(H.Interf,Word(W)+4);
 For Bucket:=0 To W Div 2 Do Begin
  A:=ReadWord(H.Interf+2+Bucket*2); Steps:=0;
  While A<>0 Do Begin
   Inc(Steps); If Steps>MaxSymbols Then Fail(72,'Cycle de symboles TPU');
   Stub:=SymbolStub(A); Next:=ReadWord(A); Kind:=B^[A+2];
   Name:=Upper(ReadString(A+3));
      If Kind In [80,81,82,83] Then Begin
    I:=NewSymbol(Name);
        If Kind=81 Then Begin
          Symbols[I].Kind:=skType; DecodeType(Stub);
          If Not TypeSupported Or (Width>2) Then Symbols[I].Kind:=skForeign
          Else Begin
            Symbols[I].Typ:=Typ; Symbols[I].Width:=Width; Symbols[I].Capacity:=Capacity;
            If ProjectForeign Then Begin
              ApplyType(I,DecodedTypeId);
            End;
          End;
        End Else If ProjectForeign And (Kind=83) Then Begin
     Symbols[I].Kind:=skForeign;
     DictBounds(Stub,22); ParamN:=ReadWord(Stub+20);
     Map:=ReadWord(Stub+2);
     If (Map Mod 8<>0) Or (Map+Longint(8)>H.CodeMap-H.ProcMap) Then            Fail(72,
     'Carte procedure native invalide');
     If (ParamN<=MaxNativeParams) And (B^[Stub] And $F6=0) And
     (B^[Stub] And 1<>0) And (ReadWord(H.ProcMap+Map+4)<>$FFFF) Then Begin
      DictBounds(Stub,22+5*ParamN);
      If (ReadWord(Stub+16)=0) And (ReadWord(Stub+18)=0) Then Begin
       TypeSupported:=True; TypeSigned:=False; Typ:=ttVoid; Width:=0;
      DecodedTypeId:=0;
      End Else DecodeType(Stub+16);
      If TypeSupported And (Typ<>ttString) And (Width<=2) Then Begin
       Symbols[I].Typ:=Typ; Symbols[I].Width:=Width;
       Symbols[I].SignedByte:=TypeSigned And (Width=1);
      Symbols[I].TypeId:=DecodedTypeId;
       Symbols[I].Kind:=skProc; Symbols[I].Native:=True;
       Symbols[I].NativeMap:=Map; Symbols[I].ParamCount:=ParamN;
       For K:=1 To ParamN Do Begin
        DecodeType(Stub+22+(K-1)*5);
        If Not TypeSupported Or (Width>2) Or
        Not (B^[Stub+26+(K-1)*5] In [2,6]) Then Symbols[I].Kind:=skForeign;
        Symbols[I].ParamTypes[K]:=Typ; Symbols[I].ParamWidths[K]:=Width;
        Symbols[I].ParamFlags[K]:=B^[Stub+26+(K-1)*5];
        Symbols[I].ParamSigned[K]:=TypeSigned And (Width=1);
        Symbols[I].ParamTypeIds[K]:=DecodedTypeId;
       End;
      End;
     End;
    End Else If ProjectForeign And (Kind=82) Then Begin
     Symbols[I].Kind:=skForeign; DictBounds(Stub,9); DecodeType(Stub+5);
     If TypeSupported And (Typ<>ttString) And (Width<=2) And (B^[Stub] In [0,1])
     Then Begin
      Map:=ReadWord(Stub+3); Target:=ReadWord(Stub+1);
      If B^[Stub]=1 Then J:=H.ConstMap Else J:=H.DataMap;
      If (Map Mod 8<>0) Or ((B^[Stub]=1) And (Longint(J)+Map+8>H.DataMap)) Or
      ((B^[Stub]=0) And (Longint(J)+Map+8>H.EndMaps)) Then Fail(72,
      'Carte variable native invalide');
      If Longint(Target)+Width>ReadWord(J+Map+2) Then Fail(72,
      'Variable native hors carte');
      Symbols[I].Kind:=skVar; Symbols[I].Native:=True;
      Symbols[I].Typ:=Typ; Symbols[I].Width:=Width;
      Symbols[I].SignedByte:=TypeSigned And (Width=1);
      Symbols[I].TypeId:=DecodedTypeId;
      Symbols[I].NativeMap:=Map; Symbols[I].NativeConst:=B^[Stub]=1;
      Symbols[I].Addr:=Target;
     End;
    End Else If Kind=83 Then Begin
     If Not IsLocal Then Unsupported('procedure TPU Borland');
     DictBounds(Stub,22);
     Map:=ReadWord(Stub+2);
     If (Map Mod 8<>0) Or (Map>=H.CodeMap-H.ProcMap) Then Fail(72,'ProcMap TPU invalide');
     Target:=ReadWord(H.ProcMap+Map+6);
     If Target>=H.CodeSize Then Fail(72,'Procedure TPU hors code');
     Symbols[I].Kind:=skProc; Symbols[I].HasBody:=True;
    Symbols[I].LegacyCall:=H.Reserved[2]<3;
     Symbols[I].Addr:=Units[U].CodeBase+Target;
    End Else
    Begin
     If Kind=80 Then Begin
      Symbols[I].Kind:=skConst; DecodeType(Stub);
      Symbols[I].TypeId:=DecodedTypeId;
      If Not TypeSupported Then Symbols[I].Kind:=skForeign Else
      If Typ=ttString Then Begin
       DictBounds(Stub+4,1); DictBounds(Stub+4,1+B^[Stub+4]);
       Symbols[I].StrValue:=ReadString(Stub+4);
       Symbols[I].Addr:=StoreString(Symbols[I].StrValue);
      End Else
      Begin
       DictBounds(Stub+4,4); Value:=ReadWord(Stub+4);
              If IsLocal And (H.Reserved[2]>=2) Then Begin
                Move(B^[Stub+4],Value,4);
                If (Value<-32768) Or (Value>65535) Then Fail(72,'Constante locale hors 16 bits');
              End Else If Width=4 Then Begin
        Move(B^[Stub+4],Value,4);
                If (Value<-32768) Or (Value>65535) Then Begin
         If ProjectForeign Then Symbols[I].Kind:=skForeign
                           Else Unsupported('constante TPU Longint hors Integer');
        End;
        Width:=2;
        If Symbols[I].Kind<>skForeign Then Symbols[I].TypeId:=1;
       End Else If (Typ=ttInteger) And (Width=2) And (Value>32767) Then Dec(Value,65536);
       If (Typ=ttBoolean) And (Value>1) Then Fail(72,'Constante Boolean TPU invalide');
       If (Typ=ttChar) And (Value>255) Then Fail(72,'Constante Char TPU invalide');
              Symbols[I].Value:=Value;
              If (Typ=ttInteger) And (Value>32767) And (Value<=65535) Then Symbols[I].TypeId:=3;
      End;
     End Else
     Begin
      If Not IsLocal Then Unsupported('variable TPU Borland');
      DictBounds(Stub,9); Symbols[I].Kind:=skVar;
      DecodeType(Stub+5); Target:=ReadWord(Stub+1);
      If Typ=ttString Then J:=Word(Capacity)+1 Else J:=Width;
      If Longint(Target)+J>H.ConstSize Then Fail(72,'Variable TPU hors donnees');
      Symbols[I].Addr:=Units[U].DataBase+Target;
     End;
     Symbols[I].Typ:=Typ; Symbols[I].Width:=Width; Symbols[I].Capacity:=Capacity;
    End;
   End Else If Not (Kind In [89]) Then Begin
    If ProjectForeign Then Begin
     I:=NewSymbol(Name); Symbols[I].Kind:=skForeign
    End
    Else Unsupported('categorie de symbole TPU');
   End;
   A:=Next;
  End;
 End;
  If IsLocal And (H.Reserved[2]>=2) Then Begin
    MetaPos:=H.Reserved[5]; DictBounds(MetaPos,2); DiskCount:=ReadWord(MetaPos); Inc(MetaPos,2);
    If (DiskCount<7) Or (DiskCount>MaxTypes) Then Fail(72,'Table des types TPU invalide');
    DictBounds(MetaPos,Longint(DiskCount)*SizeOf(TTypeInfo));
    For K:=1 To DiskCount Do Begin
      Move(B^[MetaPos],DiskTypes[K],SizeOf(TTypeInfo)); Inc(MetaPos,SizeOf(TTypeInfo));
      If (DiskTypes[K].Base=0) Or (DiskTypes[K].Base>DiskCount) Or
        (DiskTypes[K].IdentityUnit[0]>Chr(63)) Or (DiskTypes[K].IdentityName[0]>Chr(63)) Or
        Not (DiskTypes[K].Typ In [ttInteger,ttBoolean,ttChar,ttString,ttEnum]) Or
        (DiskTypes[K].LowBound>DiskTypes[K].HighBound) Then Fail(72,'Descripteur de type TPU invalide');
      If DiskTypes[K].Typ=ttString Then Begin
        If (DiskTypes[K].Width<>0) Or (DiskTypes[K].Capacity=0) Then Fail(72,'Taille string de metadonnees TPU');
      End Else If Not (DiskTypes[K].Width In [1,2,4]) Or
        ((DiskTypes[K].Width=4) And (DiskTypes[K].Typ<>ttInteger)) Or
        ((DiskTypes[K].Width<>4) And ((DiskTypes[K].LowBound<-32768) Or (DiskTypes[K].HighBound>65535))) Then
          Fail(72,'Taille ou bornes ordinales de metadonnees TPU');
      If K<=7 Then
        If (DiskTypes[K].Typ<>Types[K].Typ) Or (DiskTypes[K].Width<>Types[K].Width) Or
          (DiskTypes[K].Capacity<>Types[K].Capacity) Or (DiskTypes[K].Base<>Types[K].Base) Or
          (DiskTypes[K].LowBound<>Types[K].LowBound) Or (DiskTypes[K].HighBound<>Types[K].HighBound) Or
          (DiskTypes[K].Signed<>Types[K].Signed) Then Fail(72,'Types standard TPU incompatibles');
      If K<=7 Then TypeMap[K]:=K
      Else Begin
        NewIndex:=0;
        If DiskTypes[K].Typ=ttEnum Then
          For TIndex:=8 To TypeCount Do
            If (Types[TIndex].Typ=ttEnum) And (Types[TIndex].Base=TIndex) And
              (Types[TIndex].IdentityUnit=DiskTypes[K].IdentityUnit) And
              (Types[TIndex].IdentityName=DiskTypes[K].IdentityName) And
              (Types[TIndex].IdentityName<>'') Then NewIndex:=TIndex;
        If NewIndex=0 Then Begin
          NewIndex:=NewType(DiskTypes[K].Typ,DiskTypes[K].Width,DiskTypes[K].Capacity,
            DiskTypes[K].Signed,DiskTypes[K].LowBound,DiskTypes[K].HighBound,0);
          Types[NewIndex].IdentityUnit:=DiskTypes[K].IdentityUnit;
          Types[NewIndex].IdentityName:=DiskTypes[K].IdentityName;
        End;
        TypeMap[K]:=NewIndex;
      End;
    End;
    For K:=1 To DiskCount Do Begin
      TIndex:=DiskTypes[K].Base;
      If (DiskTypes[TIndex].Base<>TIndex) Or (DiskTypes[TIndex].Typ<>DiskTypes[K].Typ) Then
        Fail(72,'Graphe des types TPU incoherent');
    End;
    For K:=8 To DiskCount Do Types[TypeMap[K]].Base:=TypeMap[DiskTypes[K].Base];
    DictBounds(MetaPos,2); MetaCount:=ReadWord(MetaPos); Inc(MetaPos,2);
    If MetaCount>MaxSymbols Then Fail(72,'Trop de metadonnees de symboles');
    DictBounds(MetaPos,Longint(MetaCount)*4);
    For K:=1 To MetaCount Do Begin
      A:=ReadWord(MetaPos); TIndex:=ReadWord(MetaPos+2); Inc(MetaPos,4);
      W:=SymbolStub(A);
      If (TIndex=0) Or (TIndex>DiskCount) Then Fail(72,'Identite de type TPU invalide');
      Name:=Upper(ReadString(A+3)); I:=FindOwnSymbol(Name);
      If I=0 Then Fail(72,'Metadonnees de symbole TPU inconnues');
      ApplyType(I,TypeMap[TIndex]);
    End;
    If H.Reserved[2]>=3 Then Begin
     DictBounds(MetaPos,2); MetaCount:=ReadWord(MetaPos); Inc(MetaPos,2);
     If MetaCount>MaxSymbols Then Fail(72,'Trop de signatures TPU');
     For K:=1 To MetaCount Do Begin
      DictBounds(MetaPos,8); A:=ReadWord(MetaPos); W:=SymbolStub(A);
      Name:=Upper(ReadString(A+3)); I:=FindOwnSymbol(Name);
      If (I=0) Or (Symbols[I].Kind<>skProc) Then Fail(72,'Signature TPU hors procedure');
      ParamN:=ReadWord(MetaPos+2);
      If ParamN>MaxNativeParams Then Fail(72,'Signature TPU trop longue');
      Symbols[I].ParamCount:=ParamN; Symbols[I].ParamBytes:=ReadWord(MetaPos+4);
      If ReadWord(MetaPos+6)>1 Then Fail(72,'Distance de routine TPU invalide');
      Symbols[I].FarRoutine:=ReadWord(MetaPos+6)=1; Inc(MetaPos,8);
      DictBounds(MetaPos,Longint(ParamN)*4); MapSum:=0;
      For J:=1 To ParamN Do Begin
       TIndex:=ReadWord(MetaPos); W:=ReadWord(MetaPos+2); Inc(MetaPos,4);
       If (TIndex=0) Or (TIndex>DiskCount) Or Not (W In [2,6]) Then Fail(72,'Parametre TPU invalide');
       TIndex:=TypeMap[TIndex];
       If Not (Types[TIndex].Typ In [ttInteger,ttBoolean,ttChar,ttEnum]) Then Fail(72,'Type parametre TPU');
       Symbols[I].ParamTypeIds[J]:=TIndex; Symbols[I].ParamFlags[J]:=W;
       Symbols[I].ParamTypes[J]:=Types[TIndex].Typ; Symbols[I].ParamWidths[J]:=Types[TIndex].Width;
       If W=6 Then Inc(MapSum,4) Else Inc(MapSum,2);
      End;
      If MapSum<>Symbols[I].ParamBytes Then Fail(72,'Taille parametres TPU incoherente');
     End;
    End;
  End;
  Units[U].InterfaceReady:=True;
  If IsLocal And (InterfaceChecksumMode(U,H.Reserved[2]>=2,H.Reserved[2]>=3)<>Units[U].Checksum) Then Begin
    { L'ordre des buckets differe de l'ordre des declarations: le checksum
      est verifie par la representation canonique triee ci-dessous. }
  Fail(72,'Checksum d''interface TPU invalide');
 End;
 RefCount:=0; X:=H.Units;
 While X<H.Sources Do Begin
  If RefCount>MaxUnits+1 Then Fail(72,'Trop de references TPU');
  Bounds(X,3); Name:=Upper(ReadString(X+2));
  If (Length(Name)=0) Or (Length(Name)>63) Or (X+3+Length(Name)>H.Sources) Then      Fail(
  72,'Liste de dependances TPU invalide');
  RefOffsets[RefCount]:=X-H.Units;
  RefChecks[RefCount]:=CheckForUnit(Name);
  If Name=Units[U].Name Then RefUnits[RefCount]:=U Else
  If Name='SYSTEM' Then RefUnits[RefCount]:=0
   Else
  Begin
   RequireUnit(Name,V); RefUnits[RefCount]:=V;
   Units[U].Dependencies:=Units[U].Dependencies+[V];
   Units[U].DependencyChecks[V]:=RefChecks[RefCount];
   If Not Units[V].FromSource And (RefChecks[RefCount]<>0) And
   (RefChecks[RefCount]<>Units[V].Checksum) Then Fail(70,Name);
  End;
  Inc(RefCount); Inc(X,3+Length(Name));
 End;
 If IsLocal Then Begin
  For I:=1 To H.CodeFixupSize Div 8 Do Begin
   X:=RelStart+(Longint(I)-1)*8; Bounds(X,8);
   R:=ReadWord(X); Map:=ReadWord(X+2); Target:=ReadWord(X+4); A:=ReadWord(X+6);
   If Longint(A)+2>H.CodeSize Then Fail(72,'Fixup TPU hors code');
   J:=0;
   While (J<RefCount) And (RefOffsets[J]<>(R And $0FFF)) Do Inc(J);
   If J=RefCount Then Fail(72,'Reference d''unite TPU invalide');
   V:=RefUnits[J]; A:=A+Units[U].CodeBase;
   If R And $F000=$8000 Then Begin
    If (V=0) Or (Map<>0) Then Fail(72,'Fixup de donnees TPU invalide');
    Target:=GlobalOffset(Target,V,False);
    If (Target>=DataSize) Or (DataOwners[Target]<>V) Then Fail(72,
    'Cible de donnees TPU invalide');
    If FixupCount=MaxFixups Then Unsupported('trop de fixups TPU');
    Inc(FixupCount); Fixups[FixupCount].Position:=A;
    Fixups[FixupCount].DataOffset:=Target; PatchWord(A,0);
   End Else If R And $F000=$4000 Then Begin
    If (V=0) And (Map=$FFFF) Then Target:=RuntimeAddress(Target)
     Else
    Begin
     If (V=0) Or (Map<>0) Then Fail(72,'Fixup de code TPU invalide');
     Target:=GlobalOffset(Target,V,True);
     If Target>CodeSize Then Fail(72,'Cible de code TPU invalide');
    End;
    PatchJump(A,Target);
   End Else Fail(72,'Nature de fixup TPU inconnue');
  End;
 End;
 If IsLocal And (H.Reserved[2]>=4) Then Begin
  X:=H.Reserved[6]; DictBounds(X,2); MetaCount:=ReadWord(X); Inc(X,2);
  If MetaCount>MaxUnits Then Fail(72,'Trop de dependances natives TPU');
  For K:=1 To MetaCount Do Begin
   DictBounds(X,1); Name:=Upper(ReadString(X));
   If (Length(Name)=0) Or (Length(Name)>63) Then Fail(72,'Nom de dependance native TPU invalide');
   DictBounds(X,Length(Name)+3); Inc(X,Length(Name)+1); W:=ReadWord(X); Inc(X,2);
   RequireUnit(Name,V);
   If NativeBuffers[V]=Nil Then Fail(72,'Dependance native TPU non Borland');
   If W<>Units[V].Checksum Then Fail(70,Name);
   Units[U].NativeDependencies:=Units[U].NativeDependencies+[V];
   NativeNeeded:=True; ActivateNative(V);
  End;
  DictBounds(X,2); MetaCount:=ReadWord(X); Inc(X,2);
  If MetaCount>MaxNativeRefs-NativeRefCount Then Fail(72,'Trop de references natives TPU');
  For K:=1 To MetaCount Do Begin
   DictBounds(X,3); A:=ReadWord(X); Inc(X,2); Name:=Upper(ReadString(X));
   If (Length(Name)=0) Or (Length(Name)>63) Then Fail(72,'Nom de cible native TPU invalide');
   DictBounds(X,Length(Name)+9); Inc(X,Length(Name)+1);
   W:=ReadWord(X); R:=ReadWord(X+2); Map:=ReadWord(X+4); Target:=ReadWord(X+6); Inc(X,8);
   If (Longint(A)+2>H.CodeSize) Or Not (R In [1,2,3]) Then Fail(72,'Reference native TPU invalide');
   RequireUnit(Name,V);
   If (NativeBuffers[V]=Nil) Or Not (V In Units[U].NativeDependencies) Then
    Fail(72,'Cible native TPU non declaree');
   If W<>Units[V].Checksum Then Fail(70,Name);
   Inc(NativeRefCount); NativeRefs[NativeRefCount].Position:=Units[U].CodeBase+A;
   NativeRefs[NativeRefCount].U:=V; NativeRefs[NativeRefCount].Kind:=R;
   NativeRefs[NativeRefCount].Map:=Map; NativeRefs[NativeRefCount].Target:=Target;
   PatchWord(Units[U].CodeBase+A,0);
  End;
  DictBounds(X,2); MetaCount:=ReadWord(X); Inc(X,2);
  If MetaCount>MaxNativeRefs-RelocationCount Then Fail(72,'Trop de relocalisations natives TPU');
  DictBounds(X,Longint(MetaCount)*4);
  For K:=1 To MetaCount Do Begin
   A:=ReadWord(X); W:=ReadWord(X+2); Inc(X,4);
   If (Longint(A)+2>H.CodeSize) Or (W>1) Then Fail(72,'Relocalisation native TPU invalide');
   AddSegmentRelocation(Units[U].CodeBase+A,W); PatchWord(Units[U].CodeBase+A,0);
  End;
 End;
 If IsLocal And (H.Reserved[2]>=5) Then Begin
  X:=H.Reserved[7]; DictBounds(X,2); MetaCount:=ReadWord(X); Inc(X,2);
  If MetaCount>MaxSymbols-ObjectCallCount Then Fail(72,'Trop de references OBJ TPU');
  For K:=1 To MetaCount Do Begin
   DictBounds(X,3); A:=ReadWord(X); Inc(X,2); Name:=ReadString(X);
   If (Length(Name)=0) Or (Length(Name)>63) Or (Longint(A)+4>H.CodeSize) Then
    Fail(72,'Reference OBJ TPU invalide');
   DictBounds(X,Length(Name)+1); Inc(X,Length(Name)+1);
   Inc(ObjectCallCount); ObjectCalls[ObjectCallCount].Name:=Upper(Name);
   ObjectCalls[ObjectCallCount].Position:=Units[U].CodeBase+A;
  End;
  X:=Align16(H.EndTrace)+Align16(H.CodeSize)+Align16(H.ConstSize)+Align16(H.CodeFixupSize);
  Bounds(X,2); MetaCount:=ReadWord(X); Inc(X,2);
  If MetaCount>MaxObjects-ObjectCount Then Fail(72,'Trop de fichiers OBJ TPU');
  For K:=1 To MetaCount Do Begin
   Bounds(X,5); Value:=ReadWord(X)+Longint(ReadWord(X+2))*65536; Inc(X,4);
   If (Value<4) Or (Value>SizeOf(TBinaryBuffer)) Then Fail(72,'Taille OBJ TPU invalide');
   Name:=ReadString(X); Bounds(X,Length(Name)+1); Inc(X,Length(Name)+1);
   Bounds(X,Value); Inc(ObjectCount); ObjectFiles[ObjectCount].Owner:=U;
   ObjectFiles[ObjectCount].Path:=Name; ObjectFiles[ObjectCount].Length:=Value;
   New(ObjectFiles[ObjectCount].Bytes);
   Move(B^[X],ObjectFiles[ObjectCount].Bytes^,Value); Inc(X,Value);
  End;
  If (Align16(X)<>Size) Or (UnitFileSize(H)<>Size) Then Fail(72,'Payload OBJ TPU incoherent');
 End;
 Units[U].State:=2;
 If Units[U].HasInit Then Begin
  Inc(InitCount); InitOrder[InitCount]:=U
 End;
 If Not Quiet Then Begin
  Write('Loaded unit ',Units[U].Name,': ',Path);
  If ProjectForeign Then Write(' (ABI Borland: scalaires et appels far)');
  WriteLn;
 End;
 If IsLocal Then Dispose(B);
 RestoreParser(P);
End;

Procedure ImportLibrarySystem;
Var
 U: Byte;
Begin
 If FindLibraryUnit('SYSTEM')=0 Then Exit;
 If (CurrentUnit<>0) And (Units[CurrentUnit].Name='SYSTEM') Then Exit;
 RequireUnit('SYSTEM',U); AddImport(U);
End;

Function NativeWord(U: Byte; P: Longint): Word;Begin
 If (NativeBuffers[U]=Nil) Or (P<0) Or (P+2>UnitFileSize(NativeHeaders[U])) Then    Fail(
 72,'Reference native hors unite');
 NativeWord:=NativeBuffers[U]^[P]+Word(NativeBuffers[U]^[P+1])*256;
End;

Function DecodeNativeType(U: Byte; Offset: Word): Word;
Var B: PBinaryBuffer; H: TUnitHeader; T,I,BaseId: Word; Typ,Width,Capacity,Modifier: Byte;
  L,R: Longint; Signed: Boolean; S: TShortString;
Begin
 DecodeNativeType:=0;
 If NativeBuffers[U]=Nil Then Unsupported('type provenant d''une unite non native');
 H:=NativeHeaders[U]; B:=NativeBuffers[U];
 If (Offset<80) Or (Longint(Offset)+6>H.ProcMap) Then Fail(72,'Descripteur Borland hors dictionnaire');
 For I:=8 To TypeCount Do
  If (NativeTypeOwners[I]=U) And (NativeTypeOffsets[I]=Offset) Then Begin DecodeNativeType:=I; Exit End;
 Typ:=B^[Offset]; Modifier:=B^[Offset+1]; T:=NativeWord(U,Offset+2);
 Signed:=(Modifier And 1)<>0; Capacity:=0;
 If Typ=ttString Then Begin
  If (T<2) Or (T>256) Then Fail(72,'Taille string Borland invalide');
  If T=256 Then Begin DecodeNativeType:=7; Exit End;
  Width:=0; Capacity:=T-1; L:=0; R:=Capacity; BaseId:=7;
 End Else If Typ In [ttInteger,ttBoolean,ttChar,ttEnum] Then Begin
  If Not (T In [1,2,4]) Then Fail(72,'Taille ordinale Borland invalide');
  If (Typ<>ttInteger) And (T>2) Then Fail(72,'Taille ordinale Borland non entiere');
  If Longint(Offset)+18>H.ProcMap Then Fail(72,'Bornes ordinales Borland tronquees');
  Width:=T; Move(B^[Offset+6],L,4); Move(B^[Offset+10],R,4);
  If L>R Then Fail(72,'Bornes ordinales Borland inversees');
  If (T=1) And ((L<-128) Or (R>255)) Then Fail(72,'Bornes Borland hors octet');
  If (T=2) And ((L<-32768) Or (R>65535)) Then Fail(72,'Bornes Borland hors mot');
  Case Typ Of
   ttBoolean:Begin
    If (T<>1) Or (L<0) Or (R>1) Then Fail(72,'Descripteur Boolean Borland invalide');
    If (L=0) And (R=1) Then Begin DecodeNativeType:=5; Exit End;
    BaseId:=5;
   End;
   ttChar:Begin
  If (T<>1) Or (L<0) Or (R>255) Then Fail(72,'Descripteur Char Borland invalide');
  If (L=0) And (R=255) Then Begin DecodeNativeType:=6; Exit End;
  BaseId:=6;
   End;
   ttInteger:Begin
  BaseId:=1;
  If (T=1) And (L=0) And (R=255) And Not Signed Then Begin DecodeNativeType:=2; Exit End;
  If (T=1) And (L=-128) And (R=127) And Signed Then Begin DecodeNativeType:=4; Exit End;
  If (T=2) And (L=-32768) And (R=32767) And Signed Then Begin DecodeNativeType:=1; Exit End;
  If (T=2) And (L=0) And (R=65535) And Not Signed Then Begin DecodeNativeType:=3; Exit End;
   End;
   ttEnum:BaseId:=0;
  End;
 End Else Exit; { structure valide mais backend pas encore disponible }
 I:=NewType(Typ,Width,Capacity,Signed,L,R,BaseId);
 NativeTypeOwners[I]:=U; NativeTypeOffsets[I]:=Offset;
 If Typ=ttEnum Then Begin
  Types[I].IdentityUnit:=Units[U].Name; Str(Offset,S); Types[I].IdentityName:='$TPU'+S;
 End;
 DecodeNativeType:=I;
End;

Procedure ActivateNative(U: Byte);
Var
 H: TUnitHeader;
 P: Word;
 S: TShortString;
 I: Integer;
 V: Byte;
Begin
 If NativeActive[U] Then Exit;
 If NativeBuffers[U]=Nil Then Unsupported('dependance native non Borland: '+Units[U].Name)
 ;
 H:=NativeHeaders[U];
 If Units[U].Name='OVERLAY' Then Unsupported('gestion des overlays Borland');
 If H.Flags And 1<>0 Then Unsupported('ABI native 8087');
 NativeActive[U]:=True; P:=H.Units;
 While P<H.Sources Do Begin
  S:='';
  For I:=1 To NativeBuffers[U]^[P+2] Do S:=S+Chr(NativeBuffers[U]^[P+2+I]);
  S:=Upper(S);
  If S<>Units[U].Name Then Begin
   V:=FindBuildUnit(S);
   If V=0 Then RequireUnit(S,V);
   ActivateNative(V);
  End;
  Inc(P,3+Length(S));
 End;
 Inc(NativeInitCount); NativeInitOrder[NativeInitCount]:=U;
End;

Function NativeMapAddress(U, Category: Byte; Map: Word): Word;
Var
 H: TUnitHeader;
 First, Last, P: Word;
 A: Longint;
Begin
 H:=NativeHeaders[U];
 Case Category Of
 0:
 Begin
  First:=H.CodeMap; Last:=H.ConstMap; A:=NativeCodeBases[U]
 End;
 1:
 Begin
  First:=H.DataMap; Last:=H.EndMaps; A:=NativeVarBases[U]
 End;
 2:
 Begin
  First:=H.ConstMap; Last:=H.DataMap; A:=NativeConstBases[U]
 End;
  Else
 Begin
  Fail(72,'Categorie de carte native'); First:=0; Last:=0; A:=0
 End;
End;
If (Map Mod 8<>0) Or (Longint(First)+Map+8>Last) Then Fail(72,
'Index carte native hors unite');
P:=First;
While P<First+Map Do Begin
 Inc(A,NativeWord(U,P+2)); Inc(P,8)
End;
If A>65535 Then Fail(49,'Adresse native trop grande');
NativeMapAddress:=A;
End;

Function NativeProcAddress(U: Byte; Map: Word): Word;
Var
 H: TUnitHeader;
 P, CodeMap, Entry: Word;
Begin
 H:=NativeHeaders[U];
 If (Map Mod 8<>0) Or (Longint(H.ProcMap)+Map+8>H.CodeMap) Then Fail(72,
 'Index procedure native');
 P:=H.ProcMap+Map; CodeMap:=NativeWord(U,P+4); Entry:=NativeWord(U,P+6);
 If CodeMap=$FFFF Then Fail(59,'Procedure native non resolue');
 If Entry>=NativeWord(U,H.CodeMap+CodeMap+2) Then Fail(72,
 'Entree procedure native hors segment');
 NativeProcAddress:=NativeMapAddress(U,0,CodeMap)+Entry;
End;

Procedure NativeDataRelocation(P: Word; Kind: Byte);Begin
 If RelocationCount=MaxNativeRefs Then Unsupported('trop de relocalisations MZ');
 Inc(RelocationCount); Relocations[RelocationCount].Offs:=P;
 Relocations[RelocationCount].Segm:=$FFFF; RelocationKinds[RelocationCount]:=Kind;
End;

Function NativeMapLength(U, Category: Byte; Map: Word): Word;
Var P: Word;
Begin
 P:=NativeMapAddress(U,Category,Map);
 Case Category Of
  0:P:=NativeHeaders[U].CodeMap;
  1:P:=NativeHeaders[U].DataMap;
  2:P:=NativeHeaders[U].ConstMap;
 End;
 NativeMapLength:=NativeWord(U,Longint(P)+Map+2);
End;

Procedure LinkNative;
Var
 U, Sys: Byte;
 I, P, Offset, Value: Word;
 H: TUnitHeader;
 X, CodeStart, ConstStart: Longint;

Function RefUnit(U: Byte; Ref: Word): Byte;
Var
 P: Longint;
 S: TShortString;
 K: Integer;
 V: Byte;
Begin
 P:=NativeHeaders[U].Units; S:='';
    { Ref est un offset dans la liste, pas un numero ordinal. }
 While P<NativeHeaders[U].Sources Do Begin
  If P=NativeHeaders[U].Units+Ref Then Begin
   For K:=1 To NativeBuffers[U]^[P+2] Do S:=S+Chr(NativeBuffers[U]^[P+2+K]);
   V:=FindBuildUnit(Upper(S));
   If V=0 Then Fail(72,'Dependance native non resolue');
   RefUnit:=V;
   Exit;
  End;
  Inc(P,3+NativeBuffers[U]^[P+2]);
 End;
 Fail(72,'Offset reference d''unite native invalide'); RefUnit:=0;
End;

Procedure WriteAt(P: Word; W: Word; InConst: Boolean);Begin
 If InConst Then Begin
  If Longint(P)+2>NativeDataSize Then Fail(72,'Fixup natif hors donnees');
  NativeData[P]:=W And 255; NativeData[P+1]:=W Shr 8;
 End Else
 Begin
  If Longint(P)+2>CodeSize Then Fail(72,'Fixup natif hors code');
  PatchWord(P,W);
 End;
End;

Procedure ResolveMaps(U: Byte; InConst: Boolean);
Var
 H: TUnitHeader;
 M, EndMap, Raw, FixRaw, Posn, Source, L, FS, N: Word;
 R, TM, T, At, W, SG: Word;
 Q: Longint;
 V: Byte;
Begin
 H:=NativeHeaders[U]; Raw:=0; FixRaw:=0;
 If InConst Then Begin
  M:=H.ConstMap; EndMap:=H.DataMap;
  Q:=Align16(H.EndTrace)+Align16(H.CodeSize)+Align16(H.ConstSize)+Align16(H.CodeFixupSize)
  ;
 End Else
 Begin
  M:=H.CodeMap; EndMap:=H.ConstMap;
  Q:=Align16(H.EndTrace)+Align16(H.CodeSize)+Align16(H.ConstSize);
 End;
 While M<EndMap Do Begin
  L:=NativeWord(U,M+2); FS:=NativeWord(U,M+4);
  If FS Mod 8<>0 Then Fail(72,'Taille fixups natifs invalide');
  If InConst Then Source:=NativeConstBases[U]+Raw Else Source:=NativeCodeBases[U]+Raw;
  For N:=1 To FS Div 8 Do Begin
   Posn:=FixRaw+(N-1)*8;
   R:=NativeWord(U,Q+Posn); TM:=NativeWord(U,Q+Posn+2);
   T:=NativeWord(U,Q+Posn+4); At:=NativeWord(U,Q+Posn+6);
   W:=2; If R And $3000=$3000 Then W:=4;
   If Longint(At)+W>L Then Fail(72,'Position de fixup hors carte native');
   V:=RefUnit(U,R And $FFF); SG:=0;
   If R And $8000<>0 Then Begin
    SG:=1;
    If R And $4000<>0 Then Begin
     If (R And $1000<>0) And (T>=NativeMapLength(V,2,TM)) Then Fail(72,'Cible constante hors carte native');
     W:=NativeMapAddress(V,2,TM)+T;
    End Else Begin
     If (R And $1000<>0) And (T>=NativeMapLength(V,1,TM)) Then Fail(72,'Cible donnee hors carte native');
     W:=NativeMapAddress(V,1,TM)+T;
    End;
    End Else If R And $4000<>0 Then Begin
    If (R And $1000<>0) And (T>NativeMapLength(V,0,TM)) Then Fail(72,'Cible code hors carte native');
    W:=NativeMapAddress(V,0,TM)+T;
    End Else W:=NativeProcAddress(V,TM)+T;
    At:=At+Source;
    If R And $1000<>0 Then Begin
     WriteAt(At,W,InConst); Inc(At,2);
    End Else If R And $2000=0 Then Begin
     WriteAt(At,Word(Longint(W)-At-2),InConst);
   End;
   If R And $2000<>0 Then Begin
    WriteAt(At,0,InConst);
    If InConst Then NativeDataRelocation(At,SG) Else AddSegmentRelocation(At,SG);
   End;
  End;
  Inc(Raw,L); Inc(FixRaw,FS); Inc(M,8);
 End;
End;

Procedure FarCallTo(Address: Word);Begin
 Emit($9A); EmitWord(Address); AddSegmentRelocation(CodeSize,0); EmitWord(0)
End;
Begin
 If Not NativeNeeded Then Exit;
 NativeDataSize:=2; FillChar(NativeData,SizeOf(NativeData),0);
 For U:=1 To UnitCount Do If NativeActive[U] Then Begin
  H:=NativeHeaders[U]; NativeCodeBases[U]:=CodeSize;
  CodeStart:=Align16(H.EndTrace);
  If H.CodeSize<>0 Then
  For X:=0 To H.CodeSize-1 Do Emit(NativeBuffers[U]^[CodeStart+X]);
  NativeConstBases[U]:=NativeDataSize;
  If Longint(NativeDataSize)+H.ConstSize>MaxImage Then Fail(49,
  'Constantes natives trop grandes');
  ConstStart:=CodeStart+Align16(H.CodeSize);
  If H.ConstSize<>0 Then Move(NativeBuffers[U]^[ConstStart],NativeData[NativeDataSize],
  H.ConstSize);
  Inc(NativeDataSize,H.ConstSize);
 End;
 For U:=1 To UnitCount Do If NativeActive[U] Then Begin
  NativeVarBases[U]:=NativeDataSize;
  If Longint(NativeDataSize)+NativeHeaders[U].DataSize>MaxImage Then Fail(49,
  'Donnees natives trop grandes');
  Inc(NativeDataSize,NativeHeaders[U].DataSize);
 End;
 For U:=1 To UnitCount Do If NativeActive[U] Then Begin
  ResolveMaps(U,False); ResolveMaps(U,True)
 End;
 For I:=1 To NativeRefCount Do Begin
  U:=NativeRefs[I].U;
  If Not NativeActive[U] Then Fail(72,'Cible native non activee');
  If NativeRefs[I].Kind=3 Then Value:=NativeProcAddress(U,NativeRefs[I].Map)+
  NativeRefs[I].Target
  Else Begin
   If NativeRefs[I].Target>=NativeMapLength(U,NativeRefs[I].Kind,NativeRefs[I].Map) Then
    Fail(72,'Reference native hors carte de donnees');
   Value:=NativeMapAddress(U,NativeRefs[I].Kind,NativeRefs[I].Map)+NativeRefs[I].Target;
  End;
  PatchWord(NativeRefs[I].Position,Value);
 End;
 Sys:=FindBuildUnit('SYSTEM');
 P:=CodeSize; PatchJump(EntryFixup,P);
 Emit($1E); Emit($06); Emit($55);
 SetNativeDS; Emit2($8E,$C2);
 If (Sys<>0) And NativeActive[Sys] Then Begin
    { ES=PSP a l'entree de _InitTurbo; CS principal est le segment de charge. }
  Emit2($8C,$C8); Emit($2D); EmitWord($10); Emit2($8E,$C0);
  FarCallTo(NativeProcAddress(Sys,8));
 End;
 For I:=1 To NativeInitCount Do Begin
  U:=NativeInitOrder[I];
  If U<>Sys Then      If NativeWord(U,NativeHeaders[U].ProcMap+4)<>$FFFF Then FarCallTo(
  NativeProcAddress(U,0));
 End;
 Emit($5D); Emit($07); Emit($1F); JumpTo(MainEntry);
 If (Sys<>0) And NativeActive[Sys] Then Begin
    { _HaltTurbo restitue les vecteurs installees par _InitTurbo. }
  Offset:=RuntimeHalt;
  Image[Offset]:=$BA; PatchWord(Offset+1,0); AddSegmentRelocation(Offset+1,1);
  Image[Offset+3]:=$8E; Image[Offset+4]:=$DA; Image[Offset+5]:=$9A;
  PatchWord(Offset+6,NativeProcAddress(Sys,24)); PatchWord(Offset+8,0);
  AddSegmentRelocation(Offset+8,0);
 End;
End;

Procedure UsesClause;
Var
 Name: TShortString;
 U: Byte;
Begin
 If Token<>tkUses Then Exit;
 NextToken;
 Repeat
 If Token<>tkIdent Then Fail(2,'Nom d''unite attendu');
 Name:=TokenText; NextToken;
 If (Name<>'SYSTEM') Or (FindLibraryUnit('SYSTEM')<>0) Then Begin
  RequireUnit(Name,U);
  AddImport(U);
  If (NativeBuffers[U]<>Nil) And (Name<>'SYSTEM') Then        If (
  NativeHeaders[U].CodeMap-NativeHeaders[U].ProcMap>=8) And
  (NativeWord(U,NativeHeaders[U].ProcMap+4)<>$FFFF) Then Begin
          If CurrentUnit<>0 Then
           Units[CurrentUnit].NativeDependencies:=Units[CurrentUnit].NativeDependencies+[U];
   NativeNeeded:=True; ActivateNative(U);
  End;
 End;
 If Token<>tkComma Then Break;
 NextToken;
 Until False;
 Need(tkSemi);
End;

Procedure EmitRuntime;
Var
 P, Q, LoopStart: Word;
Begin
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
 RuntimeUnsigned:=CodeSize;
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
 Emit($06); Emit($1E); Emit($07); { ES=DS, restaurer l'ES de l'appelant }
 Emit2($31,$C0); Emit($AC); Emit2($39,$C8); Emit2($76,$02);
 Emit2($89,$C8); Emit($AA); Emit2($89,$C1); Emit2($F3,$A4); Emit($07); Emit($C3);
 RuntimeHalt:=CodeSize; Emit2($B4,$4C); Emit2($CD,$21);
 For P:=1 To 16 Do Emit($90);
End;

Procedure CompileProgram;
Var
 I: Word;
Begin
 CodeSize:=0; DataSize:=0; SymbolCount:=0; FixupCount:=0;
 InitTypes; ScopeCount:=0; CurrentScope:=0; FillChar(Dictionary,SizeOf(Dictionary),0);
 FillChar(Scopes,SizeOf(Scopes),0);
 RelativeCount:=0; UnitOutput:=False;
 NativeNeeded:=False; NativeRefCount:=0; RelocationCount:=0; NativeInitCount:=0;
 ObjectCount:=0; ObjectCallCount:=0; ObjectSegmentCount:=0;
 ObjectGroupCount:=0; ObjectPublicCount:=0; ObjectExternalCount:=0; ObjectFixupCount:=0;
 UnitCount:=0; InitCount:=0; CurrentUnit:=0; Imports:=[]; ImportCount:=0;
 InInterface:=False;
  InstallStandardTypes;
 Emit($0E); Emit($1F); Emit($0E); Emit($07); Emit($FC); { DS=ES=CS; cld }
 EntryFixup:=Jump;
 EmitRuntime;
 NextToken;
 If Token=tkUnit Then Begin
  NextToken;
  If Token<>tkIdent Then Fail(2,'Nom d''unite attendu');
  UnitCount:=1; FillChar(Units[1],SizeOf(TBuildUnit),0);
  Units[1].Name:=TokenText; Units[1].State:=1;
  CompileSourceUnit(1,MainSourceName); UnitOutput:=True; Exit;
 End;
 If Token=tkProgram Then Begin
  NextToken; Need(tkIdent);
  If Token=tkLP Then Begin
   NextToken; Need(tkIdent);
   While Token=tkComma Do Begin
    NextToken; Need(tkIdent)
   End;
   Need(tkRP);
  End;
  Need(tkSemi);
 End;
 ImportLibrarySystem;
 UsesClause;
 DeclarationPart;
  For I:=1 To SymbolCount Do If (Symbols[I].Owner=0) And (Symbols[I].Scope=0) And
    (Symbols[I].Kind=skProc) And Not Symbols[I].HasBody Then Fail(59,Symbols[I].Name);
 MainEntry:=CodeSize;
 PatchJump(EntryFixup,CodeSize);
 For I:=1 To InitCount Do CallTo(Units[InitOrder[I]].InitAddress);
 Need(tkBegin); StatementList(tkEnd); Need(tkEnd); Need(tkDot);
 If Token<>tkEOF Then Fail(10,'Texte apres END.');
 LoadImmediate(0); CallTo(RuntimeHalt);
End;

Procedure LoadSource;
Var
 F: File;
 N: Word;
 E: Integer;
Begin
 Assign(F,SourceName); OpenBinaryRead(F,E);
 If E<>0 Then Fail(15,'Fichier introuvable: '+SourceName);
 SourceSize:=FileSize(F);
 If SourceSize>MaxSource Then Begin
  Close(F); Unsupported('source > 60000 octets')
 End;
  {$I-} BlockRead(F,Source,SourceSize,N); E:=IOResult; Close(F);
 If IOResult<>0 Then E:=1; {$I+}
 If (E<>0) Or (N<>SourceSize) Then Fail(15,'Lecture du source impossible');
 SourcePos:=1; Line:=1; Column:=1; CondDepth:=0; Active:=True;
End;

Procedure LinkedWord(P: Longint; W: Word);
Begin
 If (P<0) Or (P+2>LinkedSize) Then Fail(72,'Fixup hors image liee');
 LinkedImage^[P]:=W And 255; LinkedImage^[P+1]:=W Shr 8;
End;

Procedure LinkedRelocation(P: Longint);
Var I: Word;
Begin
 If (P<0) Or (P+2>LinkedSize) Then Fail(72,'Relocalisation hors image liee');
 For I:=1 To RelocationCount Do
  If Longint(Relocations[I].Segm)*16+Relocations[I].Offs=P Then
   Fail(72,'Relocalisation MZ dupliquee');
 If RelocationCount=MaxNativeRefs Then Unsupported('trop de relocalisations MZ');
 Inc(RelocationCount); Relocations[RelocationCount].Segm:=P Div 16;
 Relocations[RelocationCount].Offs:=P Mod 16;
End;

Procedure LoadObjects;
Var I,J: Word; Q: Longint; Duplicate: Boolean;
Begin
 For I:=1 To ObjectCount Do Begin
  Duplicate:=False;
  For J:=1 To I-1 Do If ObjectFiles[J].Length=ObjectFiles[I].Length Then Begin
   Q:=0;
   While (Q<ObjectFiles[I].Length) And
     (ObjectFiles[J].Bytes^[Q]=ObjectFiles[I].Bytes^[Q]) Do Inc(Q);
   If Q=ObjectFiles[I].Length Then Duplicate:=True;
  End;
  If Not Duplicate Then ReadObject(ObjectFiles[I].Path,ObjectFiles[I].Bytes,ObjectFiles[I].Length);
 End;
End;

Procedure LinkObjects;
Var
 I,J,R,G,Pub: Word; P,T,Frame,Value,Addend,Width,Limit: Longint;
 SegmentGroups: Array[1..MaxObjSegments] Of Word;
 Placed: Array[1..MaxObjSegments] Of Boolean;
 ExternalPublics: Array[1..MaxObjNames] Of Word;
 F: TObjectFixup;

Function Aligned(N: Longint; Alignment: Byte): Longint;
Var A: Longint;
Begin
 A:=1;
 Case Alignment Of 2:A:=2; 3:A:=16; 4:A:=256 End;
 Aligned:=(N+A-1) And Not (A-1);
End;
Function FindPublic(Name: TShortString): Word;
Var K: Word;
Begin
 FindPublic:=0;
 For K:=1 To ObjectPublicCount Do If ObjectPublics[K].Name=Name Then Begin
  FindPublic:=K; Exit;
 End;
 Fail(59,'Symbole OBJ non resolu: '+Name);
End;
Function PublicAddress(K: Word): Longint;
Begin
 PublicAddress:=ObjectSegments[ObjectPublics[K].Segment].Base+ObjectPublics[K].Offset;
End;
Function PublicFrame(K: Word): Longint;
Var G,S: Word;
Begin
 G:=ObjectPublics[K].GroupIndex; S:=ObjectPublics[K].Segment;
 If G<>0 Then PublicFrame:=ObjectGroups[G].Base
 Else PublicFrame:=ObjectSegments[ObjectSegments[S].Root].Base And Not Longint(15);
End;
Function TargetAddress(Method: Byte; Index: Word): Longint;
Begin
 Case Method Of
  0:TargetAddress:=ObjectSegments[Index].Base;
  1:TargetAddress:=ObjectGroups[Index].Base;
  2:TargetAddress:=PublicAddress(ExternalPublics[Index]);
 Else Fail(72,'Methode target OBJ invalide'); TargetAddress:=0;
 End;
End;
Function TargetFrame(Method: Byte; Index: Word): Longint;
Begin
 Case Method Of
  0:TargetFrame:=ObjectSegments[ObjectSegments[Index].Root].Base And Not Longint(15);
  1:TargetFrame:=ObjectGroups[Index].Base;
  2:TargetFrame:=PublicFrame(ExternalPublics[Index]);
 Else Fail(72,'Methode frame OBJ invalide'); TargetFrame:=0;
 End;
End;
Procedure PlaceSegment(S: Word);
Begin
 If Placed[S] Then Exit;
 LinkedSize:=Aligned(LinkedSize,ObjectSegments[S].Alignment);
 { Hors groupe, donner une base en paragraphes. Dans un groupe, respecter
   l'alignement declare sans introduire de trous supplementaires. }
 If SegmentGroups[S]=0 Then LinkedSize:=Align16(LinkedSize);
 ObjectSegments[S].Base:=LinkedSize;
 Inc(LinkedSize,ObjectSegments[S].Length);
 If LinkedSize>MaxLinkedImage Then Fail(49,'Image MZ multi-segments trop grande');
 Placed[S]:=True;
End;
Begin
 FillChar(SegmentGroups,SizeOf(SegmentGroups),0);
 FillChar(Placed,SizeOf(Placed),0);
 { PUBLIC/STACK concatene les contributions de meme nom et classe.
   COMMON les superpose. PRIVATE conserve une identite propre. }
 For I:=1 To ObjectSegmentCount Do Begin
  R:=I;
  If ObjectSegments[I].Combine<>0 Then
   For J:=1 To I-1 Do
    If (ObjectSegments[J].Root=J) And
       (ObjectSegments[J].Combine<>0) And
       (ObjectSegments[J].Name=ObjectSegments[I].Name) And
       (ObjectSegments[J].ClassName=ObjectSegments[I].ClassName) Then Begin
     If ObjectSegments[J].Combine<>ObjectSegments[I].Combine Then
      Fail(72,'Combinaisons SEGDEF incompatibles');
     R:=J; Break;
    End;
  ObjectSegments[I].Root:=R;
  If R<>I Then Begin
   If ObjectSegments[I].Combine=6 Then Begin
    If ObjectSegments[I].Length>ObjectSegments[R].Length Then
     ObjectSegments[R].Length:=ObjectSegments[I].Length;
   End Else Begin
    ObjectSegments[I].Contribution:=Aligned(ObjectSegments[R].Length,ObjectSegments[I].Alignment);
    ObjectSegments[R].Length:=ObjectSegments[I].Contribution+ObjectSegments[I].Length;
   End;
   If ObjectSegments[I].Alignment>ObjectSegments[R].Alignment Then
    ObjectSegments[R].Alignment:=ObjectSegments[I].Alignment;
  End;
  If ObjectSegments[R].Length>65536 Then Fail(48,'Segment OBJ combine > 64 Ko');
 End;
 For G:=1 To ObjectGroupCount Do
  For J:=1 To ObjectGroups[G].Count Do Begin
   R:=ObjectSegments[ObjectGroups[G].Members[J]].Root;
   If (SegmentGroups[R]<>0) And (SegmentGroups[R]<>G) Then
    Fail(72,'Segment OBJ dans plusieurs groupes');
   SegmentGroups[R]:=G;
  End;
 For G:=1 To ObjectGroupCount Do Begin
  LinkedSize:=Align16(LinkedSize); ObjectGroups[G].Base:=LinkedSize;
  For J:=1 To ObjectGroups[G].Count Do PlaceSegment(ObjectSegments[ObjectGroups[G].Members[J]].Root);
  If LinkedSize-ObjectGroups[G].Base>65536 Then Fail(49,'Groupe OBJ > 64 Ko');
 End;
 For I:=1 To ObjectSegmentCount Do If ObjectSegments[I].Root=I Then PlaceSegment(I);
 For I:=1 To ObjectSegmentCount Do Begin
  R:=ObjectSegments[I].Root;
  If R<>I Then ObjectSegments[I].Base:=ObjectSegments[R].Base+ObjectSegments[I].Contribution;
  { La longueur de la racine inclut des contributions suivantes, mais son
    tampon ne contient que sa propre contribution. La copie suivante des
    autres contributions remplit ces zones initialement nulles. }
  Move(ObjectSegments[I].Bytes^,LinkedImage^[ObjectSegments[I].Base],ObjectSegments[I].Length);
 End;
 For I:=1 To ObjectPublicCount Do Begin
  G:=ObjectPublics[I].GroupIndex;
  If (G<>0) And (SegmentGroups[ObjectSegments[ObjectPublics[I].Segment].Root]<>G) Then
   Fail(72,'PUBDEF hors GRPDEF');
 End;
 For I:=1 To ObjectExternalCount Do ExternalPublics[I]:=FindPublic(ObjectExternals[I]);
 For I:=1 To ObjectCallCount Do Begin
  Pub:=FindPublic(ObjectCalls[I].Name); P:=ObjectCalls[I].Position;
  Frame:=PublicFrame(Pub); T:=PublicAddress(Pub)-Frame;
  If (T<0) Or (T>65535) Then Fail(48,'Entree OBJ hors segment');
  LinkedWord(P,T); LinkedWord(P+2,Frame Div 16); LinkedRelocation(P+2);
 End;
 For I:=1 To ObjectFixupCount Do Begin
  F:=ObjectFixups[I]; P:=ObjectSegments[F.Segment].Base+F.Offset;
  T:=TargetAddress(F.TargetMethod,F.TargetIndex)+F.Displacement;
  Case F.FrameMethod Of
   0,1,2:Frame:=TargetFrame(F.FrameMethod,F.FrameIndex);
   4:Frame:=TargetFrame(0,F.Segment);
   5:Frame:=TargetFrame(F.TargetMethod,F.TargetIndex);
  Else Fail(72,'Frame OBJ invalide');
  End;
  Width:=2; If F.Location=0 Then Width:=1;
  Addend:=LinkedImage^[P];
  If Width=2 Then Addend:=Addend+Longint(LinkedImage^[P+1])*256;
  If F.Relative Then Begin
   { Une reference near doit rester dans le meme espace CS de 64 Ko. }
   Limit:=TargetFrame(0,F.Segment);
   If (T<Limit) Or (T>=Limit+65536) Then Fail(48,'FIXUPP near inter-segments');
   If Width=1 Then Begin If Addend>=128 Then Dec(Addend,256) End
   Else If Addend>=32768 Then Dec(Addend,65536);
   Value:=T-P-Width+Addend;
   If (Width=1) And ((Value<-128) Or (Value>127)) Then Fail(48,'FIXUPP relatif byte hors portee');
  End Else Value:=T-Frame+Addend;
  If F.Location<>2 Then Begin
   If Not F.Relative And ((Value<0) Or (Value>65535)) Then Fail(49,'Offset FIXUPP hors frame');
   If Width=1 Then LinkedImage^[P]:=Byte(Value) Else LinkedWord(P,Word(Value));
  End;
  If F.Location In [2,3] Then Begin
   If F.Location=3 Then Inc(P,2);
   Addend:=LinkedImage^[P]+Longint(LinkedImage^[P+1])*256;
   Value:=Frame Div 16+Addend;
   If Value>65535 Then Fail(49,'Segment FIXUPP trop grand');
   LinkedWord(P,Value); LinkedRelocation(P);
  End;
 End;
 For I:=1 To ObjectSegmentCount Do Dispose(ObjectSegments[I].Bytes);
 For I:=1 To ObjectCount Do Dispose(ObjectFiles[I].Bytes);
End;

Procedure WriteExecutable;
Var
 H: Array[0..15] Of Word;
 F: File;
 Size, AllocParas, HeaderBytes, Location, Written, Chunk: Longint;
 I, Base, StackSeg, Pad, N: Word;
 E: Integer;
 Path: TShortString;
 NativeSegment: Word;
 Padding: Array[0..15] Of Byte;
 D: DirStr;
 Name: NameStr;
 Ext: ExtStr;
Begin
 Base:=CodeSize;
 If Longint(Base)+DataSize>65520 Then Fail(49,'CS/DS depasse 65520 octets');
 Size:=Longint(CodeSize)+DataSize;
 New(LinkedImage); FillChar(LinkedImage^,SizeOf(TLinkedImage),0);
 For I:=1 To FixupCount Do    PatchWord(Fixups[I].Position,Base+Fixups[I].DataOffset);
 Move(Image,LinkedImage^,CodeSize);
 If DataSize<>0 Then Move(Data,LinkedImage^[Base],DataSize);
 NativeSegment:=0;
 If NativeNeeded Then Begin
  NativeSegment:=Align16(Size) Div 16;
  Size:=Longint(NativeSegment)*16+NativeDataSize;
  Move(NativeData,LinkedImage^[Longint(NativeSegment)*16],NativeDataSize);
  LinkedSize:=Size;
  For I:=1 To RelocationCount Do Begin
   If Relocations[I].Segm=$FFFF Then Relocations[I].Segm:=NativeSegment;
   Location:=Longint(Relocations[I].Segm)*16+Relocations[I].Offs;
   If Location+2>Size Then Fail(72,'Relocalisation MZ hors image');
   If RelocationKinds[I]=1 Then LinkedWord(Location,NativeSegment)
                           Else LinkedWord(Location,0);
  End;
 End;
 LinkedSize:=Size; LinkObjects; Size:=LinkedSize;
 StackSeg:=(Size+15) Div 16;
 Pad:=StackSeg*16-Size;
  { Pile non stockee dans le fichier: e_minalloc la reserve a la charge. }
 AllocParas:=(Longint(StackSize)+Pad+15) Div 16;
 FillChar(H,SizeOf(H),0);
 HeaderBytes:=Align16(32+Longint(RelocationCount)*4);
 H[0]:=$5A4D; H[1]:=(Size+HeaderBytes) Mod 512; H[2]:=(Size+HeaderBytes+511) Div 512;
 H[3]:=RelocationCount; H[4]:=HeaderBytes Div 16; H[5]:=AllocParas+MinHeap;
 If AllocParas+MaxHeap>65535 Then H[6]:=$FFFF
                             Else H[6]:=AllocParas+MaxHeap;
 H[7]:=StackSeg;
 H[8]:=StackSize; H[12]:=32;
 FSplit(SourceName,D,Name,Ext);
 If OutputDir='' Then Path:=D+Name+'.EXE' Else Path:=JoinPath(OutputDir,Name+'.EXE');
 If Upper(Path)=Upper(SourceName) Then CLIError('Sortie identique au source');
 Assign(F,Path); {$I-} Rewrite(F,1); E:=IOResult; {$I+}
 If E<>0 Then Fail(16,'Creation impossible: '+Path);
  {$I-}
 BlockWrite(F,H,32,N); E:=IOResult; If N<>32 Then E:=1;
 If (E=0) And (RelocationCount<>0) Then Begin
  BlockWrite(F,Relocations,RelocationCount*4,N); E:=IOResult;
  If N<>RelocationCount*4 Then E:=1;
 End;
 Pad:=HeaderBytes-32-RelocationCount*4; FillChar(Padding,SizeOf(Padding),0);
 If (E=0) And (Pad<>0) Then Begin
  BlockWrite(F,Padding,Pad,N); E:=IOResult; If N<>Pad Then E:=1
 End;
 Written:=0;
 While (E=0) And (Written<Size) Do Begin
  Chunk:=Size-Written; If Chunk>32768 Then Chunk:=32768;
  BlockWrite(F,LinkedImage^[Written],Chunk,N); E:=IOResult;
  If N<>Chunk Then E:=1; Inc(Written,Chunk);
 End;
 Close(F); If IOResult<>0 Then E:=1;
 If E<>0 Then Begin
  Erase(F); If IOResult<>0 Then E:=1
 End;
  {$I+}
 If E<>0 Then Fail(16,'Ecriture impossible: '+Path);
 Dispose(LinkedImage);
 If Not Quiet Then WriteLn('8086 DOS MZ: ',Path,'; code=',CodeSize,
 ', donnees=',DataSize,', pile=',StackSize);
End;

Procedure InspectTPU;
Var
 H: TUnitHeader;
Begin
 ReadTPUHeader(InspectName,H);
 WriteLn('TPU9: en-tete=',SizeOf(H),' octets; fin dictionnaire=',H.EndTrace);
 WriteLn('Code=',H.CodeSize,' constantes=',H.ConstSize,' donnees=',H.DataSize);
 WriteLn('Fixups code=',H.CodeFixupSize,' constantes=',H.DataFixupSize);
 If (H.Flags=$8000) And (H.Reserved[0]=$5054) And (H.Reserved[1]=$3143) Then    WriteLn(
 'Profil TPC1: ABI locale near/CS=DS, non compatible Borland.')
 Else WriteLn('TPU9 Borland: appels far et donnees ordinales; ABI partielle.');
End;

Procedure InspectLibrary;
Var
 I: Word;
 H: TUnitHeader;
Begin
 ReadLibrary(InspectLibraryName);
 WriteLn('TPL: ',LibraryName,'; unites=',LibraryCount);
 For I:=1 To LibraryCount Do Begin
  H:=LibraryUnits[I].Header;
  Write(LibraryUnits[I].Name,' offset=',LibraryUnits[I].Offset,
  ' taille=',LibraryUnits[I].Size,' code=',H.CodeSize,' constantes=',H.ConstSize);
  If (H.Flags=$8000) And (H.Reserved[0]=$5054) And (H.Reserved[1]=$3143) Then      Write(
  ' profil=TPC1')
  Else If (H.CodeSize<>0) Or (H.ConstSize<>0) Or (H.DataSize<>0) Then      Write(
  ' Borland: ABI ordinale/far')
  Else Write(' TPU9 sans code');
  WriteLn;
 End;
End;

Procedure Help;Begin
 WriteLn('TPC - portage PARTIEL de Turbo Pascal 6, cible DOS 8086');
 WriteLn('TPC fichier.pas [/Erepertoire] [/Urepertoires] [/Dsymboles] [/$X-]');
 WriteLn('/B reconstruit les unites depuis leurs sources (sous-ensemble Pascal).');
 WriteLn('Production/liaison TPU9 profil TPC1; ABI locale, pas ABI Borland.');
 WriteLn('TPU9/TPL Borland: appels far, parametres et globals ordinaux 8/16 bits.');
  WriteLn('Ponts natifs sauvegardes en TPU v4; parametres shortstring Borland.');
 WriteLn('MZ multi-segments; $L/$LINK OBJ OMF86 Use16, routines external Pascal far.');
 WriteLn('TPU v5: OBJ embarques, liaison sans fichiers OBJ ni sources.');
 WriteLn('Signatures avancees, 8087 et overlays restent non implementes.');
 WriteLn('/M reconnu, refuse: reconstruction incrementale non implementee.');
 WriteLn('/Q silencieux; /T repertoires Turbo (TURBO.TPL et TPU).');
 WriteLn('TPL charge automatiquement: repertoire courant, /T, repertoire de TPC.');
 WriteLn('/I, /O, /L, /V, /F, /G reconnus mais refuses: fonctions manquantes.');
 WriteLn('Extension locale: --inspect-tpu=fichier.tpu; --quiet; --help.');
 WriteLn('Extension locale: --inspect-tpl=fichier.tpl.');
 WriteLn('Toutes les chaines internes sont string[255] (longueur en [0]).');
  WriteLn('Types: alias, enums, sous-intervalles, Word/Shortint, string[n].');
  WriteLn('Constantes calculees/typees; procedures imbriquees, locaux ordinaux sur pile.');
  WriteLn('Appels Pascal: parametres valeur/var ordinaux, fonctions, forward, near/far et $F.');
 WriteLn('Pas de compatibilite binaire promise avec le code Borland.');
End;

Procedure ParseArguments;
Var
 I, P: Integer;
 S, Arg, Part: TShortString;
 C: Char;
Begin
 If ParamCount=0 Then Begin
  Help; Halt(0)
 End;
 For I:=1 To ParamCount Do Begin
  S:=ParamStr(I);
  If (S='--help') Or (S='/?') Or (S='-?') Then Begin
   Help; Halt(0)
  End
  Else If S='--quiet' Then Quiet:=True Else
  If Copy(S,1,14)='--inspect-tpu=' Then InspectName:=Copy(S,15,255) Else
  If Copy(S,1,14)='--inspect-tpl=' Then InspectLibraryName:=Copy(S,15,255) Else
  If (Length(S)>0) And (S[1] In ['/','-']) Then Begin
   If Length(S)<2 Then CLIError('Option vide');
   C:=UpCase(S[2]); Arg:=Copy(S,3,255);
   Case C Of
   '$':
   Begin
    If (Length(Arg)>0) And (UpCase(Arg[1])='M') Then            MemoryDirective(Copy(Arg,
    2,255))
    Else SetSwitch(Upper(Arg));
   End;
   'E':
   Begin
    If Arg='' Then CLIError('Repertoire /E manquant'); OutputDir:=Arg
   End;
   'U':
   Begin
    If Arg='' Then CLIError('Repertoire /U manquant'); UnitDirs:=Arg
   End;
   'T':
   Begin
    If Arg='' Then CLIError('Repertoire /T manquant'); TurboDirs:=Arg
   End;
   'Q':
   Begin
    If Arg<>'' Then CLIError('Option /Q incorrecte'); Quiet:=True
   End;
   'D':
   Begin
    Repeat
    P:=Pos(';',Arg);
    If P=0 Then Begin
     Part:=Arg; Arg:=''
    End
     Else
    Begin
     Part:=Copy(Arg,1,P-1); Delete(Arg,1,P)
    End;
    Define(Part);
    Until Arg='';
   End;
   'B':
   Begin
    If Arg<>'' Then CLIError('Option /B incorrecte'); BuildMode:=True
   End;
   'M':
   Begin
    If Arg<>'' Then CLIError('Option /M incorrecte'); MakeMode:=True
   End;
   'I','O','L','V','F','G':Unsupported('parametre '+S);
   Else CLIError('Option inconnue: '+S);
  End;
 End Else
 Begin
  If InputName<>'' Then CLIError('Un seul fichier source attendu'); InputName:=S;
 End;
End;
End;

Procedure CheckLayout;
Var
 Actual: Word;
Begin
 Actual:=SizeOf(TUnitHeader);
 If Actual<>80 Then CLIError('Disposition en-tete TPU incompatible');
 Actual:=SizeOf(TTypeDescriptor);
 If Actual<>6 Then CLIError('Disposition descripteur incompatible');
 Actual:=SizeOf(TSymbolPrefix);
 If Actual<>4 Then CLIError('Disposition symbole incompatible');
 Actual:=SizeOf(TTPUFixup);
 If Actual<>8 Then CLIError('Disposition fixup incompatible');
 Actual:=SizeOf(TShortString);
 If Actual<>256 Then CLIError('Disposition shortstring incompatible');
End;

Var
 D: DirStr;
 N: NameStr;
 E: ExtStr;

BEGIN
  { TP6 structures fixes, verifier avant toute lecture binaire. }
 CheckLayout;
 StackSize:=16384; MinHeap:=0; MaxHeap:=$FFFF;
 OptionBits:=$1411; { sous-ensemble: A+, E+, I+, V+; autres desactives }
 TokenLine:=1; TokenColumn:=1;
 Define('VER60'); Define('MSDOS'); Define('CPU86');
 ParseArguments;
 If InspectName<>'' Then Begin
  SourceName:=InspectName; InspectTPU; Halt(0)
 End;
 If InspectLibraryName<>'' Then Begin
  SourceName:=InspectLibraryName; InspectLibrary; Halt(0)
 End;
 If InputName='' Then CLIError('Fichier source manquant');
 If MakeMode And Not BuildMode Then Unsupported(
 '/M: construction incrementale des unites');
 SourceName:=InputName; FSplit(SourceName,D,N,E);
 If E='' Then SourceName:=SourceName+'.PAS';
 MainSourceName:=SourceName;
 FindAndReadLibrary;
 Move(Defines,InitialDefines,SizeOf(Defines)); InitialDefineCount:=DefineCount;
 InitialOptions:=OptionBits;
 If Not Quiet Then WriteLn('TPC: portage partiel TP6; hote Pascal, cible DOS 8086');
 LoadSource; CompileProgram; LoadObjects; WriteUnits;
 If Not UnitOutput Then Begin
  LinkNative; WriteExecutable
 End;
END.
