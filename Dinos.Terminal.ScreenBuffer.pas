unit Dinos.Terminal.ScreenBuffer;

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections;

type
  TCellColorKind = (cckDefault, cckIndexed, cckRGB);

  TCellColor = record
    Kind: TCellColorKind;
    Index: Byte;
    RGB: Cardinal;
    class function Default: TCellColor; static;
    class function Indexed(AIndex: Byte): TCellColor; static;
    class function RGBColor(AR, AG, AB: Byte): TCellColor; static;
  end;

  TCellStyle = set of (csfBold, csfItalic, csfUnderline, csfInverse);

  TTerminalCell = record
    Ch: Char;
    Foreground: TCellColor;
    Background: TCellColor;
    Style: TCellStyle;
    class function DefaultCell: TTerminalCell; static;
  end;

  TCursorVisibility = (cvNormal, cvHidden);

  TScreenBuffer = class
  private
    FCols: Integer;
    FRows: Integer;
    FCells: TArray<TTerminalCell>;
    FMainCells: TArray<TTerminalCell>;
    FScrollback: TList<TArray<TTerminalCell>>;
    FScrollbackLimit: Integer;
    FCursorX: Integer;
    FCursorY: Integer;
    FSavedCursorX: Integer;
    FSavedCursorY: Integer;
    FCurrentFg: TCellColor;
    FCurrentBg: TCellColor;
    FCurrentStyle: TCellStyle;
    FScrollTop: Integer;
    FScrollBottom: Integer;
    FCursorVisibility: TCursorVisibility;
    FWrapPending: Boolean;
    FAltScreenActive: Boolean;
    FMouseEnabled: Boolean;
    FDirty: TArray<Boolean>;
    FDirtyAny: Boolean;
    procedure AllocateGrid;
    function GetCell(ACol, ARow: Integer): TTerminalCell;
    procedure SetCell(ACol, ARow: Integer; const ACell: TTerminalCell);
    procedure MarkRowDirty(ARow: Integer);
  public
    constructor Create(ACols, ARows: Integer);
    destructor Destroy; override;
    procedure Resize(ACols, ARows: Integer);
    procedure Clear;
    procedure ClearToEndOfLine;
    procedure ClearToStartOfLine;
    procedure ClearToEndOfScreen;
    procedure ClearToStartOfScreen;
    procedure ClearEntireScreen;
    procedure ScrollUp(ALines: Integer);
    procedure InsertLines(ALines: Integer);
    procedure DeleteLines(ALines: Integer);
    procedure InsertChars(ACount: Integer);
    procedure DeleteChars(ACount: Integer);
    procedure EraseChars(ACount: Integer);
    procedure PutChar(ACh: Char);
    procedure SetCursorPos(ACol, ARow: Integer);
    procedure SetCursorXY(AX, AY: Integer);
    procedure MoveCursorUp(ALines: Integer);
    procedure MoveCursorDown(ALines: Integer);
    procedure MoveCursorForward(ALines: Integer);
    procedure MoveCursorBackward(ALines: Integer);
    procedure Backspace;
    procedure CarriageReturn;
    procedure LineFeed;
    procedure Tab;
    procedure SaveCursor;
    procedure RestoreCursor;
    procedure EnterAltScreen;
    procedure ExitAltScreen;
    procedure SetScrollRegion(ATop, ABottom: Integer);
    procedure ScrollDown(ALines: Integer);
    procedure ClearScrollback;
    function RowToString(ARow: Integer): string;
    function GetPlainText: string;
    function IsRowDirty(ARow: Integer): Boolean;
    procedure ResetDirty;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property Cells[ACol, ARow: Integer]: TTerminalCell read GetCell write SetCell; default;
    property CursorX: Integer read FCursorX;
    property CursorY: Integer read FCursorY;
    property CurrentFg: TCellColor read FCurrentFg write FCurrentFg;
    property CurrentBg: TCellColor read FCurrentBg write FCurrentBg;
    property CurrentStyle: TCellStyle read FCurrentStyle write FCurrentStyle;
    property CursorVisibility: TCursorVisibility read FCursorVisibility write FCursorVisibility;
    property ScrollbackLines: TList<TArray<TTerminalCell>> read FScrollback;
    property AltScreenActive: Boolean read FAltScreenActive;
    property MouseEnabled: Boolean read FMouseEnabled write FMouseEnabled;
    property DirtyAny: Boolean read FDirtyAny;
  end;

implementation

{ TCellColor }

class function TCellColor.Default: TCellColor;
begin
  Result.Kind := cckDefault;
  Result.Index := 0;
  Result.RGB := 0;
end;

class function TCellColor.Indexed(AIndex: Byte): TCellColor;
begin
  Result.Kind := cckIndexed;
  Result.Index := AIndex;
  Result.RGB := 0;
end;

class function TCellColor.RGBColor(AR, AG, AB: Byte): TCellColor;
begin
  Result.Kind := cckRGB;
  Result.Index := 0;
  Result.RGB := (AR shl 16) or (AG shl 8) or AB;
end;

{ TTerminalCell }

class function TTerminalCell.DefaultCell: TTerminalCell;
begin
  Result.Ch := ' ';
  Result.Foreground := TCellColor.Default;
  Result.Background := TCellColor.Default;
  Result.Style := [];
end;

{ TScreenBuffer }

constructor TScreenBuffer.Create(ACols, ARows: Integer);
begin
  inherited Create;
  FScrollbackLimit := 1000;
  FScrollback := TList<TArray<TTerminalCell>>.Create;
  FCurrentFg := TCellColor.Default;
  FCurrentBg := TCellColor.Default;
  FCurrentStyle := [];
  FCursorVisibility := cvNormal;
  FWrapPending := False;
  FAltScreenActive := False;
  FMouseEnabled := False;
  FScrollTop := 0;
  FCols := ACols;
  FRows := ARows;
  AllocateGrid;
  Clear;
end;

destructor TScreenBuffer.Destroy;
begin
  FScrollback.Free;
  inherited;
end;

procedure TScreenBuffer.AllocateGrid;
var
  I: Integer;
begin
  SetLength(FCells, FRows * FCols);
  SetLength(FDirty, FRows);
  for I := 0 to FRows * FCols - 1 do
    FCells[I] := TTerminalCell.DefaultCell;
  for I := 0 to FRows - 1 do
    FDirty[I] := True;
  FDirtyAny := True;
  FScrollBottom := FRows - 1;
  FScrollTop := 0;
end;

function TScreenBuffer.GetCell(ACol, ARow: Integer): TTerminalCell;
begin
  if (ACol >= 0) and (ACol < FCols) and (ARow >= 0) and (ARow < FRows) then
    Result := FCells[ARow * FCols + ACol]
  else
    Result := TTerminalCell.DefaultCell;
end;

procedure TScreenBuffer.SetCell(ACol, ARow: Integer; const ACell: TTerminalCell);
begin
  if (ACol >= 0) and (ACol < FCols) and (ARow >= 0) and (ARow < FRows) then
  begin
    FCells[ARow * FCols + ACol] := ACell;
    MarkRowDirty(ARow);
  end;
end;

procedure TScreenBuffer.MarkRowDirty(ARow: Integer);
begin
  if (ARow >= 0) and (ARow < FRows) then
  begin
    FDirty[ARow] := True;
    FDirtyAny := True;
  end;
end;

procedure TScreenBuffer.Resize(ACols, ARows: Integer);
var
  NewCells: TArray<TTerminalCell>;
  CopyCols, CopyRows, I, J: Integer;
begin
  if (ACols = FCols) and (ARows = FRows) then Exit;

  SetLength(NewCells, ARows * ACols);
  for I := 0 to ARows * ACols - 1 do
    NewCells[I] := TTerminalCell.DefaultCell;

  CopyCols := Min(ACols, FCols);
  CopyRows := Min(ARows, FRows);

  for J := 0 to CopyRows - 1 do
    for I := 0 to CopyCols - 1 do
      NewCells[J * ACols + I] := FCells[J * FCols + I];

  FCells := NewCells;
  FMainCells := nil;
  SetLength(FDirty, ARows);
  for I := 0 to ARows - 1 do
    FDirty[I] := True;
  FDirtyAny := True;

  FCols := ACols;
  FRows := ARows;
  FScrollTop := 0;
  FScrollBottom := FRows - 1;

  if FCursorX >= FCols then FCursorX := FCols - 1;
  if FCursorY >= FRows then FCursorY := FRows - 1;
end;

procedure TScreenBuffer.Clear;
var
  I: Integer;
begin
  for I := 0 to FRows * FCols - 1 do
    FCells[I] := TTerminalCell.DefaultCell;
  for I := 0 to FRows - 1 do
  begin
    FDirty[I] := True;
  end;
  FDirtyAny := True;
  FCursorX := 0;
  FCursorY := 0;
  FWrapPending := False;
end;

procedure TScreenBuffer.ClearToEndOfLine;
var
  I: Integer;
begin
  for I := FCursorX to FCols - 1 do
    SetCell(I, FCursorY, TTerminalCell.DefaultCell);
end;

procedure TScreenBuffer.ClearToStartOfLine;
var
  I: Integer;
begin
  for I := 0 to FCursorX do
    SetCell(I, FCursorY, TTerminalCell.DefaultCell);
end;

procedure TScreenBuffer.ClearToEndOfScreen;
var
  I, J: Integer;
begin
  ClearToEndOfLine;
  for J := FCursorY + 1 to FRows - 1 do
    for I := 0 to FCols - 1 do
      SetCell(I, J, TTerminalCell.DefaultCell);
end;

procedure TScreenBuffer.ClearToStartOfScreen;
var
  I, J: Integer;
begin
  ClearToStartOfLine;
  for J := 0 to FCursorY - 1 do
    for I := 0 to FCols - 1 do
      SetCell(I, J, TTerminalCell.DefaultCell);
end;

procedure TScreenBuffer.ClearEntireScreen;
begin
  Clear;
end;

procedure TScreenBuffer.ScrollUp(ALines: Integer);
var
  I, J: Integer;
  DepartingLine: TArray<TTerminalCell>;
begin
  for I := 0 to ALines - 1 do
  begin
    if FScrollTop = 0 then
    begin
      SetLength(DepartingLine, FCols);
      for J := 0 to FCols - 1 do
        DepartingLine[J] := FCells[I * FCols + J];
      FScrollback.Add(DepartingLine);
      while FScrollback.Count > FScrollbackLimit do
        FScrollback.Delete(0);
    end;

    for J := 0 to FCols - 1 do
      FCells[(FScrollTop) * FCols + J] := TTerminalCell.DefaultCell;
  end;

  if ALines >= (FScrollBottom - FScrollTop + 1) then
  begin
    for J := FScrollTop to FScrollBottom do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end
  else
  begin
    for J := FScrollTop to FScrollBottom - ALines do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := FCells[(J + ALines) * FCols + I];

    for J := FScrollBottom - ALines + 1 to FScrollBottom do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end;

  for J := FScrollTop to FScrollBottom do
    MarkRowDirty(J);
end;

procedure TScreenBuffer.ScrollDown(ALines: Integer);
var
  I, J: Integer;
begin
  if ALines >= (FScrollBottom - FScrollTop + 1) then
  begin
    for J := FScrollTop to FScrollBottom do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end
  else
  begin
    for J := FScrollBottom downto FScrollTop + ALines do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := FCells[(J - ALines) * FCols + I];

    for J := FScrollTop to FScrollTop + ALines - 1 do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end;

  for J := FScrollTop to FScrollBottom do
    MarkRowDirty(J);
end;

procedure TScreenBuffer.InsertLines(ALines: Integer);
var
  I, J: Integer;
begin
  if (FCursorY < FScrollTop) or (FCursorY > FScrollBottom) then Exit;

  if FCursorY + ALines > FScrollBottom then
  begin
    for J := FCursorY to FScrollBottom do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end
  else
  begin
    for J := FScrollBottom downto FCursorY + ALines do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := FCells[(J - ALines) * FCols + I];

    for J := FCursorY to FCursorY + ALines - 1 do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end;

  for J := FScrollTop to FScrollBottom do
    MarkRowDirty(J);
end;

procedure TScreenBuffer.DeleteLines(ALines: Integer);
var
  I, J: Integer;
begin
  if (FCursorY < FScrollTop) or (FCursorY > FScrollBottom) then Exit;

  if FCursorY + ALines > FScrollBottom then
  begin
    for J := FCursorY to FScrollBottom do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end
  else
  begin
    for J := FCursorY to FScrollBottom - ALines do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := FCells[(J + ALines) * FCols + I];

    for J := FScrollBottom - ALines + 1 to FScrollBottom do
      for I := 0 to FCols - 1 do
        FCells[J * FCols + I] := TTerminalCell.DefaultCell;
  end;

  for J := FScrollTop to FScrollBottom do
    MarkRowDirty(J);
end;

procedure TScreenBuffer.InsertChars(ACount: Integer);
var
  I, J: Integer;
begin
  if ACount <= 0 then Exit;

  for J := FCursorY to FCursorY do
  begin
    for I := FCols - 1 downto FCursorX + ACount do
      SetCell(I, J, GetCell(I - ACount, J));
    for I := FCursorX to Min(FCursorX + ACount - 1, FCols - 1) do
      SetCell(I, J, TTerminalCell.DefaultCell);
  end;
end;

procedure TScreenBuffer.DeleteChars(ACount: Integer);
var
  I, J: Integer;
begin
  if ACount <= 0 then Exit;

  J := FCursorY;
  for I := FCursorX to FCols - 1 - ACount do
    SetCell(I, J, GetCell(I + ACount, J));
  for I := Max(FCursorX, FCols - ACount) to FCols - 1 do
    SetCell(I, J, TTerminalCell.DefaultCell);
end;

procedure TScreenBuffer.EraseChars(ACount: Integer);
var
  I: Integer;
begin
  for I := FCursorX to Min(FCursorX + ACount - 1, FCols - 1) do
    SetCell(I, FCursorY, TTerminalCell.DefaultCell);
end;

procedure TScreenBuffer.PutChar(ACh: Char);
var
  Cell: TTerminalCell;
begin
  if FWrapPending then
  begin
    FWrapPending := False;
    FCursorX := 0;
    if FCursorY >= FScrollBottom then
      ScrollUp(1)
    else
      Inc(FCursorY);
  end;

  if (FCursorX >= FCols) then
  begin
    FCursorX := 0;
    if FCursorY >= FScrollBottom then
      ScrollUp(1)
    else
      Inc(FCursorY);
  end;

  if ACh = #13 then
  begin
    FCursorX := 0;
    Exit;
  end;

  if ACh = #10 then
  begin
    if FCursorY >= FScrollBottom then
      ScrollUp(1)
    else
      Inc(FCursorY);
    Exit;
  end;

  if ACh = #9 then
  begin
    Tab;
    Exit;
  end;

  if (ACh < #32) or (ACh = #127) then
    Exit;

  Cell.Ch := ACh;
  Cell.Foreground := FCurrentFg;
  Cell.Background := FCurrentBg;
  Cell.Style := FCurrentStyle;

  SetCell(FCursorX, FCursorY, Cell);

  if FCursorX >= FCols - 1 then
    FWrapPending := True
  else
    Inc(FCursorX);
end;

procedure TScreenBuffer.SetCursorPos(ACol, ARow: Integer);
begin
  FCursorX := Min(Max(ACol, 0), FCols - 1);
  FCursorY := Min(Max(ARow, 0), FRows - 1);
end;

procedure TScreenBuffer.SetCursorXY(AX, AY: Integer);
begin
  SetCursorPos(AX - 1, AY - 1);
end;

procedure TScreenBuffer.MoveCursorUp(ALines: Integer);
begin
  FCursorY := Max(FCursorY - ALines, FScrollTop);
end;

procedure TScreenBuffer.MoveCursorDown(ALines: Integer);
begin
  FCursorY := Min(FCursorY + ALines, FScrollBottom);
end;

procedure TScreenBuffer.MoveCursorForward(ALines: Integer);
begin
  FCursorX := Min(FCursorX + ALines, FCols - 1);
end;

procedure TScreenBuffer.MoveCursorBackward(ALines: Integer);
begin
  FCursorX := Max(FCursorX - ALines, 0);
end;

procedure TScreenBuffer.Backspace;
begin
  if FCursorX > 0 then
  begin
    Dec(FCursorX);
    SetCell(FCursorX, FCursorY, TTerminalCell.DefaultCell);
  end;
end;

procedure TScreenBuffer.CarriageReturn;
begin
  FCursorX := 0;
end;

procedure TScreenBuffer.LineFeed;
begin
  if FCursorY >= FScrollBottom then
    ScrollUp(1)
  else
    Inc(FCursorY);
end;

procedure TScreenBuffer.Tab;
begin
  FCursorX := Min(((FCursorX div 8) + 1) * 8, FCols - 1);
end;

procedure TScreenBuffer.SaveCursor;
begin
  FSavedCursorX := FCursorX;
  FSavedCursorY := FCursorY;
end;

procedure TScreenBuffer.RestoreCursor;
begin
  FCursorX := Min(FSavedCursorX, FCols - 1);
  FCursorY := Min(FSavedCursorY, FRows - 1);
end;

procedure TScreenBuffer.EnterAltScreen;
var
  I: Integer;
begin
  if FAltScreenActive then Exit;
  FAltScreenActive := True;

  SetLength(FMainCells, FRows * FCols);
  Move(FCells[0], FMainCells[0], SizeOf(TTerminalCell) * FRows * FCols);
  FSavedCursorX := FCursorX;
  FSavedCursorY := FCursorY;

  Clear;
end;

procedure TScreenBuffer.ExitAltScreen;
var
  I, J, CopyCount: Integer;
begin
  if not FAltScreenActive then Exit;
  FAltScreenActive := False;

  CopyCount := Min(Length(FMainCells), FRows * FCols);
  for I := 0 to CopyCount - 1 do
    FCells[I] := FMainCells[I];
  for I := CopyCount to FRows * FCols - 1 do
    FCells[I] := TTerminalCell.DefaultCell;
  FMainCells := nil;

  FCursorX := Min(FSavedCursorX, FCols - 1);
  FCursorY := Min(FSavedCursorY, FRows - 1);

  for J := 0 to FRows - 1 do
    MarkRowDirty(J);
end;

procedure TScreenBuffer.SetScrollRegion(ATop, ABottom: Integer);
begin
  FScrollTop := Max(0, Min(ATop, FRows - 1));
  FScrollBottom := Max(FScrollTop, Min(ABottom, FRows - 1));
end;

function TScreenBuffer.RowToString(ARow: Integer): string;
var
  I: Integer;
  LastNonSpace: Integer;
begin
  if (ARow < 0) or (ARow >= FRows) then Exit('');
  Result := '';
  LastNonSpace := -1;

  for I := 0 to FCols - 1 do
  begin
    var Cell := GetCell(I, ARow);
    if Cell.Ch <> ' ' then
      LastNonSpace := I;
  end;

  for I := 0 to LastNonSpace do
    Result := Result + GetCell(I, ARow).Ch;
end;

function TScreenBuffer.GetPlainText: string;
var
  I: Integer;
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    for I := 0 to FRows - 1 do
      Lines.Add(RowToString(I));
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function TScreenBuffer.IsRowDirty(ARow: Integer): Boolean;
begin
  if (ARow >= 0) and (ARow < FRows) then
    Result := FDirty[ARow]
  else
    Result := False;
end;

procedure TScreenBuffer.ResetDirty;
var
  I: Integer;
begin
  for I := 0 to FRows - 1 do
    FDirty[I] := False;
  FDirtyAny := False;
end;

procedure TScreenBuffer.ClearScrollback;
begin
  FScrollback.Clear;
end;

end.
