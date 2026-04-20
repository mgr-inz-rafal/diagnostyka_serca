
Program Srakoli;

Uses Graph, Joystick, Crt, Rmt;

const
  RMT_PLAYER_ADDRESS = $7000;
  RMT_MODULE_ADDRESS = $7800;
  COLREG_OBSTACLE_A = $A6;
  COLREG_FLUID_A    = $53;
  COLREG_PLAYER_A   = $EE;
  COLREG_OBSTACLE_B = $A1;
  COLREG_FLUID_B    = $22;
  COLREG_PLAYER_B   = $10;

var
  msx: TRMT;
  zx: Byte;
  zy: Byte;
  shakeCooldown: Integer;
  btnWasPressed: Boolean;
  colObs: array[0..39] of Byte;
  indCol: Byte;
  moldCooldown: LongInt;
  growX: array[0..359] of Byte;
  growY: array[0..359] of Byte;
  growCount: Integer;
  moldTotal: Integer;
  indColor: Byte;
  text_y: byte absolute 656;
  text_x: byte absolute 657;
  punkty: Word;
  s: String;
  gameMode: Char;
  gameRunning: Boolean;
  upGrowTimer: Byte;
  OBSTACLE_COLOR: Byte;
  FLUID_COLOR:    Byte;
  PLAYER_COLOR:   Byte;

{$r 'main.rc'}

Procedure MemPrint(address: word; s: String);

Var 
  i, c: byte;
Begin
  For i := 1 To Length(s) Do
    Begin
      c := Byte(s[i]);
      Poke(address + (i-1), c);
    End;
End;

procedure vbl;interrupt;
begin
asm { phr ; store registers };
    msx.Play;
asm {
    plr ; restore registers
    jmp $E462 ; jump to system VBL handler
    };
end;

Procedure Rura;
Begin
  SetColor(OBSTACLE_COLOR);
  Line(0, 5, 39, 5);
  Line(0, 15, 39, 15);
End;

Procedure Szlaka;
var
  r: TRect;
Begin
  SetColor(FLUID_COLOR);
  r.left := 0;
  r.right := 39;
  r.top := 6;
  r.bottom := 14;
  FillRect(r);
End;

Procedure Zator;
Begin
  PutPixel(zx, zy, PLAYER_COLOR);
End;

Procedure GenObstacles;
var
  n, i: Byte;
Begin
  n := 15 + Random(11);
  for i := 1 to n do
    PutPixel(Random(32), 6 + Random(9), OBSTACLE_COLOR);
End;

Procedure CalcColObs;
var
  x, y: Byte;
Begin
  for x := 0 to 39 do
  Begin
    colObs[x] := 0;
    for y := 6 to 14 do
      if GetPixel(x, y) <> FLUID_COLOR then
        colObs[x] := colObs[x] + 1;
  End;
End;

Procedure ShowOpening;
var
  x: Byte;
  maxObs: Byte;
  maxCol: Byte;
Begin
  text_x := 3;
  text_y := 2;
  write('Skuteczne przetykania: ', punkty);
  maxObs := 0;
  maxCol := 0;
  for x := 0 to 39 do
    if colObs[x] > maxObs then
    Begin
      maxObs := colObs[x];
      maxCol := x;
    End;
  text_x := 3;
  text_y := 1;
  if gameMode = 'A' then
    write('Promien swiatla aorty: ', (100 - maxObs * 100 div 9)-10, 'mm ')
  else
    write('Promien swiatla jelita: ', (100 - maxObs * 100 div 9)-10, 'mm ');
  if indCol <> 255 then PutPixel(indCol, 3, 0);
  indCol := maxCol;
  if indColor >= 3 then indColor := 1 else indColor := indColor + 1;
  PutPixel(indCol, 3, indColor);
End;

Procedure AddGrowable(x, y: Byte);
Begin
  if growCount < 360 then
  Begin
    growX[growCount] := x;
    growY[growCount] := y;
    growCount := growCount + 1;
  End;
End;

Procedure RemoveGrowable(idx: Integer);
Begin
  growCount := growCount - 1;
  growX[idx] := growX[growCount];
  growY[idx] := growY[growCount];
End;

Function FreeNeighborCount(x, y: Byte): Byte;
var
  n: Byte;
Begin
  n := 0;
  if (y < 14) and (GetPixel(x, y+1) = FLUID_COLOR) then n := n + 1;
  if (x > 0)  and (GetPixel(x-1, y) = FLUID_COLOR) then n := n + 1;
  if (x < 39) and (GetPixel(x+1, y) = FLUID_COLOR) then n := n + 1;
  if (y > 6)  and (GetPixel(x, y-1) = FLUID_COLOR) then n := n + 1;
  FreeNeighborCount := n;
End;

Procedure GameOver;
Begin
  text_x := 1;
  text_y := 1;
  write('  Zbyt maly promien swiatla naczynia');
  text_x := 1;
  text_y := 2;
  if gameMode = 'A' then
    write('     pacjent umar na zawal SERCA    ')
  else
    write('     pacjent umar na zawal DUPY    ');
End;


Procedure FallAndDie;
Begin
  Poke(712, $0E);
  Pause(10);
  Poke(712, 0);
  while (zy < 14) and (GetPixel(zx, zy + 1) = FLUID_COLOR) do
  Begin
    PutPixel(zx, zy, FLUID_COLOR);
    zy := zy + 1;
    PutPixel(zx, zy, PLAYER_COLOR);
    Pause(8);
  End;
  if moldTotal < 380 then AddGrowable(zx, zy);
  moldTotal := moldTotal + 1;
  colObs[zx] := colObs[zx] + 1;
  ShowOpening;
  if colObs[zx] >= 9 then
  Begin
    GameOver;
    Repeat
      if KeyPressed then if ReadKey = #27 then gameRunning := false;
    Until not gameRunning;
    Exit;
  End;
  zx := 39;
  zy := 6;
  while (zy < 14) and (GetPixel(zx, zy) <> FLUID_COLOR) do zy := zy + 1;
  if GetPixel(zx, zy) <> FLUID_COLOR then zy := 7;
  shakeCooldown := 0;
  btnWasPressed := false;
  PutPixel(zx, zy, PLAYER_COLOR);
End;

Procedure GrowMold;
var
  i, srcIdx, dIdx, hIdx, uIdx: Integer;
  x, y, fc: Byte;
  tx, ty, dTx, dTy, hTx, hTy, uTx, uTy: Byte;
  hasDown, hasH, hasUp: Boolean;
Begin
  if moldCooldown > 0 then
  Begin
    moldCooldown := moldCooldown - 1;
    Exit;
  End;
  moldCooldown := (5000 + Random(Word(15000))) * (1 + Random(Byte(4)));
  if (growCount = 0) or (moldTotal >= 380) then Exit;
  hasDown := false; hasH := false; hasUp := false;
  dIdx := 0; hIdx := 0; uIdx := 0;
  dTx := 0; dTy := 0; hTx := 0; hTy := 0; uTx := 0; uTy := 0;
  i := 0;
  while (i < growCount) and not (hasDown and hasH and hasUp) do
  Begin
    x := growX[i]; y := growY[i];
    if not hasDown and (y < 14) and (GetPixel(x, y+1) = FLUID_COLOR) then
      Begin dIdx := i; dTx := x; dTy := y+1; hasDown := true; End;
    if not hasH then
    Begin
      fc := 0;
      if (x > 0)  and (GetPixel(x-1, y) = FLUID_COLOR) then fc := fc + 1;
      if (x < 39) and (GetPixel(x+1, y) = FLUID_COLOR) then fc := fc + 1;
      if fc > 0 then
      Begin
        hIdx := i;
        if (fc = 2) and (Random(2) = 0) then Begin hTx := x+1; hTy := y; End
        else if (x > 0) and (GetPixel(x-1, y) = FLUID_COLOR) then Begin hTx := x-1; hTy := y; End
        else Begin hTx := x+1; hTy := y; End;
        hasH := true;
      End;
    End;
    if not hasUp and (y > 6) and (GetPixel(x, y-1) = FLUID_COLOR) then
      Begin uIdx := i; uTx := x; uTy := y-1; hasUp := true; End;
    i := i + 1;
  End;
  upGrowTimer := upGrowTimer + 1;
  if (upGrowTimer >= 7) and hasUp then
  Begin
    tx := uTx; ty := uTy; srcIdx := uIdx;
    upGrowTimer := 0;
  End
  else Begin
    if upGrowTimer >= 7 then upGrowTimer := 0;
    if hasDown then      Begin tx := dTx; ty := dTy; srcIdx := dIdx; End
    else if hasH then    Begin tx := hTx; ty := hTy; srcIdx := hIdx; End
    else if hasUp then   Begin tx := uTx; ty := uTy; srcIdx := uIdx; End
    else                 Begin growCount := 0; Exit; End;
  End;
  PutPixel(tx, ty, PLAYER_COLOR);
  moldTotal := moldTotal + 1;
  colObs[tx] := colObs[tx] + 1;
  ShowOpening;
  if colObs[tx] >= 9 then Begin
    GameOver;
    Repeat
      if KeyPressed then if ReadKey = #27 then gameRunning := false;
    Until not gameRunning;
    Exit;
  End;
  if FreeNeighborCount(tx, ty) > 0 then AddGrowable(tx, ty);
  x := growX[srcIdx]; y := growY[srcIdx];
  if FreeNeighborCount(x, y) = 0 then RemoveGrowable(srcIdx);
End;

Procedure BlinkIndicator;
Begin
  if indCol = 255 then Exit;
  if indColor >= 3 then indColor := 1 else indColor := indColor + 1;
  PutPixel(indCol, 3, indColor);
End;

Procedure ShakeZator;
Begin
  if shakeCooldown > 0 then
  Begin
    shakeCooldown := shakeCooldown - 1;
    Exit;
  End;
  PutPixel(zx, zy, FLUID_COLOR);
  if Random(2) = 0 then
  Begin
    if (zy > 6) and (GetPixel(zx, zy - 1) = FLUID_COLOR) then zy := zy - 1;
  End
  Else
  Begin
    if (zy < 14) and (GetPixel(zx, zy + 1) = FLUID_COLOR) then zy := zy + 1;
  End;
  PutPixel(zx, zy, PLAYER_COLOR);
  BlinkIndicator;
  shakeCooldown := 2783 + Random(13501);
End;

Procedure BorgMiniGame;
var
  a, b: Byte;
  k: Char;
Begin
  InitGraph(0);
  Repeat
    a := 1 + Random(3);
    b := 1 + Random(3);
    WriteLn;
    WriteLn(a, ' + ', b, ' = ?');
    k := ReadKey;
    if k = #27 then Begin gameRunning := false; Exit; End;
    WriteLn(k);
    if Byte(k) - 48 = a + b then
      WriteLn('Poprawnie!')
    else
      WriteLn('Zle! Odpowiedz: ', a + b);
  Until not gameRunning;
End;

procedure TitleScreen;
var
  k: Char;
begin
  InitGraph(2);
  CursorOff;

  s := 'PROFILAKTYKA'~;
  MemPrint($BE70+1, s); 
  s := '   zawalu'~;
  MemPrint($BE70+1+20, s); 
  s := '   SERCA'~;
  MemPrint($BE70+1+40, s); 
  Pause(100);
  s := ' albo DUPY'~;
  MemPrint($BE70+1+60, s); 
  Pause(100);

  text_x := 2;
  text_y := 2;
  write('wcisnij guzik joysticka');

  repeat until strig0 = 0;

  InitGraph(0);
  WriteLn('Kredity dot tej gry na Grawitacje ''26'*);
  WriteLn;
  WriteLn('mgr inz. Rafal:'*);
  WriteLn(' - wybitny pomysl, super kod');
  WriteLn;
  WriteLn('miker'*);
  WriteLn(' - nietuzinkowa muzyka');
  WriteLn;
  WriteLn('bocianu, Salmax'*);
  WriteLn(' - konsultacje technologiczne');
  WriteLn;
  WriteLn;
  WriteLn('Aby rozpoczac gre wdus klawisz:');
  WriteLn('[A] - Diagnostyka AORTY');
  WriteLn('[B] - Diagnostyka JELITA');
  WriteLn('[C] - To wdus jak jestes Borg');

  Pause(100);

  repeat
    k := ReadKey;
    k := UpCase(k);
  until (k = 'A') or (k = 'B') or (k = 'C');

  gameMode := k;
end;

Begin
  msx.player := pointer(RMT_PLAYER_ADDRESS);
  msx.modul := pointer(RMT_MODULE_ADDRESS);
  msx.init(0);
  SetIntVec(iVBL,@vbl);

  Repeat
    TitleScreen;

    gameRunning := true;

    if gameMode = 'C' then
      BorgMiniGame
    else Begin
      InitGraph(3);
      CursorOff;

      OBSTACLE_COLOR := 1;
      FLUID_COLOR    := 2;
      PLAYER_COLOR   := 3;

      if gameMode = 'A' then Begin
        Poke(708, COLREG_OBSTACLE_A);
        Poke(709, COLREG_FLUID_A);
        Poke(710, COLREG_PLAYER_A);
      End Else Begin
        Poke(708, COLREG_OBSTACLE_B);
        Poke(709, COLREG_FLUID_B);
        Poke(710, COLREG_PLAYER_B);
      End;

      Rura;
      Szlaka;
      GenObstacles;
      CalcColObs;

      indCol := 255;
      indColor := 1;

      zx := 39;
      zy := 7;
      shakeCooldown := 0;
      moldCooldown := 0;
      growCount := 0;
      moldTotal := 0;
      upGrowTimer := 0;
      punkty := 0;
      btnWasPressed := false;

      ShowOpening;
      Zator;

      Repeat
        ShakeZator;
        GrowMold;
        if KeyPressed then if ReadKey = #27 then gameRunning := false;
        if strig0 = 0 then Begin
          if not btnWasPressed then Begin
            if zx = 0 then
            Begin
              PutPixel(zx, zy, FLUID_COLOR);
              zx := 39;
              zy := 6;
              Inc(punkty);
              ShowOpening;
              while (zy < 14) and (GetPixel(zx, zy) <> FLUID_COLOR) do zy := zy + 1;
              if GetPixel(zx, zy) <> FLUID_COLOR then zy := 7;
              shakeCooldown := 0;
              PutPixel(zx, zy, PLAYER_COLOR);
            End
            Else if GetPixel(zx - 1, zy) <> FLUID_COLOR then
              FallAndDie
            Else Begin
              PutPixel(zx, zy, FLUID_COLOR);
              zx := zx - 1;
              PutPixel(zx, zy, PLAYER_COLOR);
            End;
            btnWasPressed := true;
          End;
        End
        Else
          btnWasPressed := false;
      Until not gameRunning;
    End;
  Until false;
End.
