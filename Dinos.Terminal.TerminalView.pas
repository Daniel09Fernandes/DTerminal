unit Dinos.Terminal.TerminalView;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Math, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Dinos.Terminal.ScreenBuffer;

type
  TTerminalColors = record
    Foreground: TColor;
    Background: TColor;
    class function Default: TTerminalColors; static;
  end;

  TViewSizeChangedEvent = procedure(Sender: TObject; ACols, ARows: Integer) of object;
  TViewSendDataEvent = procedure(const AData: string) of object;

  TTerminalView = class(TCustomControl)
  private
    FBuffer: TScreenBuffer;
    FFont: TFont;
    FCellWidth: Integer;
    FCellHeight: Integer;
    FColors: TTerminalColors;
    FOnKeyDownEvent: TKeyEvent;
    FOnKeyPressEvent: TKeyPressEvent;
    FOnViewSizeChanged: TViewSizeChangedEvent;
    FScrollOffset: Integer;
    FLastCols: Integer;
    FLastRows: Integer;
    FSelecting: Boolean;
    FMoved: Boolean;
    FAnchorCol: Integer;
    FAnchorRow: Integer;
    FCurrentCol: Integer;
    FCurrentRow: Integer;
    FBackBuffer: TBitmap;
    FOnSendData: TViewSendDataEvent;
    procedure PaintLine(ACanvas: TCanvas; AScreenRow: Integer);
    procedure PaintCursor(ACanvas: TCanvas);
    procedure ResolveCellColors(const ACell: TTerminalCell;
      out AFgColor, ABgColor: TColor; ASelected: Boolean);
    function IsSelected(ACol, AScreenRow: Integer): Boolean;
    function CellRect(ACol, AScreenRow: Integer): TRect;
    function StreamTop: Integer;
    function MaxScrollOffset: Integer;
    function AltOrigin: Integer;
    function ResolveCell(AScreenRow, ACol: Integer): TTerminalCell;
    function CellColAt(X: Integer): Integer;
    function CellRowAt(Y: Integer): Integer;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure WMGetDlgCode(var Msg: TMessage); message WM_GETDLGCODE;
    procedure WMEraseBkgnd(var Msg: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure WMVScroll(var Msg: TWMVScroll); message WM_VSCROLL;
    procedure CMDMouseWheel(var Msg: TCMMouseWheel); message CM_MOUSEWHEEL;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RefreshAll;
    procedure UpdateView;
    procedure UpdateMetrics;
    procedure AssignScreen(AScreen: TScreenBuffer);
    function VisibleCols: Integer;
    function VisibleRows: Integer;
    function HasSelection: Boolean;
    function GetSelectedText: string;
    procedure ClearSelection;
    property OnKeyDownEvent: TKeyEvent read FOnKeyDownEvent write FOnKeyDownEvent;
    property OnKeyPressEvent: TKeyPressEvent read FOnKeyPressEvent write FOnKeyPressEvent;
    property OnViewSizeChanged: TViewSizeChangedEvent read FOnViewSizeChanged write FOnViewSizeChanged;
    property OnSendData: TViewSendDataEvent read FOnSendData write FOnSendData;
  end;

implementation

{ TTerminalColors }

class function TTerminalColors.Default: TTerminalColors;
begin
  Result.Foreground := $00F2F8F8;
  Result.Background := clBlack;
end;

function XTermPaletteColor(AIndex: Byte): TColor;
const
  XTermPalette: array[0..255] of TColor = (
    $000000, $000080, $008000, $008080, $800000, $800080, $808000, $C0C0C0,
    $808080, $0000FF, $00FF00, $00FFFF, $FF0000, $FF00FF, $FFFF00, $FFFFFF,
    $000000, $00005F, $000087, $0000AF, $0000D7, $0000FF, $005F00, $005F5F,
    $005F87, $005FAF, $005FD7, $005FFF, $008700, $00875F, $008787, $0087AF,
    $0087D7, $0087FF, $00AF00, $00AF5F, $00AF87, $00AFAF, $00AFD7, $00AFFF,
    $00D700, $00D75F, $00D787, $00D7AF, $00D7D7, $00D7FF, $00FF00, $00FF5F,
    $00FF87, $00FFAF, $00FFD7, $00FFFF, $5F0000, $5F005F, $5F0087, $5F00AF,
    $5F00D7, $5F00FF, $5F5F00, $5F5F5F, $5F5F87, $5F5FAF, $5F5FD7, $5F5FFF,
    $5F8700, $5F875F, $5F8787, $5F87AF, $5F87D7, $5F87FF, $5FAF00, $5FAF5F,
    $5FAF87, $5FAFAF, $5FAFD7, $5FAFFF, $5FD700, $5FD75F, $5FD787, $5FD7AF,
    $5FD7D7, $5FD7FF, $5FFF00, $5FFF5F, $5FFF87, $5FFFAF, $5FFFD7, $5FFFFF,
    $870000, $87005F, $870087, $8700AF, $8700D7, $8700FF, $875F00, $875F5F,
    $875F87, $875FAF, $875FD7, $875FFF, $878700, $87875F, $878787, $8787AF,
    $8787D7, $8787FF, $87AF00, $87AF5F, $87AF87, $87AFAF, $87AFD7, $87AFFF,
    $87D700, $87D75F, $87D787, $87D7AF, $87D7D7, $87D7FF, $87FF00, $87FF5F,
    $87FF87, $87FFAF, $87FFD7, $87FFFF, $AF0000, $AF005F, $AF0087, $AF00AF,
    $AF00D7, $AF00FF, $AF5F00, $AF5F5F, $AF5F87, $AF5FAF, $AF5FD7, $AF5FFF,
    $AF8700, $AF875F, $AF8787, $AF87AF, $AF87D7, $AF87FF, $AFAF00, $AFAF5F,
    $AFAF87, $AFAFAF, $AFAFD7, $AFAFFF, $AFD700, $AFD75F, $AFD787, $AFD7AF,
    $AFD7D7, $AFD7FF, $AFFF00, $AFFF5F, $AFFF87, $AFFFAF, $AFFFD7, $AFFFFF,
    $D70000, $D7005F, $D70087, $D700AF, $D700D7, $D700FF, $D75F00, $D75F5F,
    $D75F87, $D75FAF, $D75FD7, $D75FFF, $D78700, $D7875F, $D78787, $D787AF,
    $D787D7, $D787FF, $D7AF00, $D7AF5F, $D7AF87, $D7AFAF, $D7AFD7, $D7AFFF,
    $D7D700, $D7D75F, $D7D787, $D7D7AF, $D7D7D7, $D7D7FF, $D7FF00, $D7FF5F,
    $D7FF87, $D7FFAF, $D7FFD7, $D7FFFF, $FF0000, $FF005F, $FF0087, $FF00AF,
    $FF00D7, $FF00FF, $FF5F00, $FF5F5F, $FF5F87, $FF5FAF, $FF5FD7, $FF5FFF,
    $FF8700, $FF875F, $FF8787, $FF87AF, $FF87D7, $FF87FF, $FFAF00, $FFAF5F,
    $FFAF87, $FFAFAF, $FFAFD7, $FFAFFF, $FFD700, $FFD75F, $FFD787, $FFD7AF,
    $FFD7D7, $FFD7FF, $FFFF00, $FFFF5F, $FFFF87, $FFFFAF, $FFFFD7, $FFFFFF,
    $080808, $121212, $1C1C1C, $262626, $303030, $3A3A3A, $444444, $4E4E4E,
    $585858, $626262, $6C6C6C, $767676, $808080, $8A8A8A, $949494, $9E9E9E,
    $A8A8A8, $B2B2B2, $BCBCBC, $C6C6C6, $D0D0D0, $DADADA, $E4E4E4, $EEEEEE
  );
begin
  Result := XTermPalette[AIndex];
end;

{ TTerminalView }

constructor TTerminalView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csCaptureMouse];
  FFont := TFont.Create;
  FFont.Name := 'Cascadia Mono';
  FFont.Size := 11;
  FFont.Style := [];
  FColors := TTerminalColors.Default;
  FScrollOffset := 0;
  FLastCols := -1;
  FLastRows := -1;
  FAnchorCol := -1;
  FAnchorRow := -1;
  FCurrentCol := -1;
  FCurrentRow := -1;
  FBackBuffer := TBitmap.Create;
  FBackBuffer.PixelFormat := pfDevice;
  DoubleBuffered := False;
end;

destructor TTerminalView.Destroy;
begin
  FBackBuffer.Free;
  FFont.Free;
  inherited;
end;

procedure TTerminalView.AssignScreen(AScreen: TScreenBuffer);
begin
  FBuffer := AScreen;
  UpdateMetrics;
  RefreshAll;
end;

procedure TTerminalView.UpdateMetrics;
var
  BM: TBitmap;
  TM: TTextMetric;
  NewCols, NewRows: Integer;
begin
  BM := TBitmap.Create;
  try
    BM.Width := 1;
    BM.Height := 1;
    BM.Canvas.Font.Assign(FFont);
    GetTextMetrics(BM.Canvas.Handle, TM);
    FCellWidth := TM.tmAveCharWidth;
    FCellHeight := TM.tmHeight;
  finally
    BM.Free;
  end;

  NewCols := VisibleCols;
  NewRows := VisibleRows;
  if (NewCols <> FLastCols) or (NewRows <> FLastRows) then
  begin
    FLastCols := NewCols;
    FLastRows := NewRows;
    if Assigned(FOnViewSizeChanged) then
      FOnViewSizeChanged(Self, NewCols, NewRows);
  end;
end;

procedure TTerminalView.Resize;
begin
  inherited Resize;
  UpdateMetrics;
end;

function TTerminalView.VisibleCols: Integer;
begin
  if FCellWidth > 0 then
    Result := ClientWidth div FCellWidth
  else
    Result := 80;
end;

function TTerminalView.VisibleRows: Integer;
begin
  if FCellHeight > 0 then
    Result := ClientHeight div FCellHeight
  else
    Result := 24;
end;

procedure TTerminalView.RefreshAll;
begin
  Invalidate;
end;

procedure TTerminalView.UpdateView;
begin
  if not Assigned(FBuffer) then Exit;
  if FScrollOffset > MaxScrollOffset then
    FScrollOffset := MaxScrollOffset;
  Invalidate;
end;

function TTerminalView.MaxScrollOffset: Integer;
begin
  Result := 0;
  if not Assigned(FBuffer) then Exit;
  if FBuffer.AltScreenActive then
    Result := Max(0, FBuffer.Rows - VisibleRows)
  else
    Result := Max(0, FBuffer.ScrollbackLines.Count + FBuffer.Rows - 1);
end;

function TTerminalView.StreamTop: Integer;
begin
  Result := MaxScrollOffset - (VisibleRows - 1) - FScrollOffset;
  if Result < 0 then
    Result := 0;
end;

function TTerminalView.AltOrigin: Integer;
var
  MaxOrigin: Integer;
begin
  Result := 0;
  if not Assigned(FBuffer) then Exit;
  MaxOrigin := FBuffer.Rows - VisibleRows;
  if MaxOrigin < 0 then
    MaxOrigin := 0;
  Result := MaxOrigin - FScrollOffset;
  if Result < 0 then
    Result := 0;
end;

function TTerminalView.ResolveCell(AScreenRow, ACol: Integer): TTerminalCell;
var
  S, RB: Integer;
begin
  Result := TTerminalCell.DefaultCell;
  if not Assigned(FBuffer) then Exit;

  if FBuffer.AltScreenActive then
  begin
    RB := AScreenRow + AltOrigin;
    if (RB >= 0) and (RB < FBuffer.Rows) and
       (ACol >= 0) and (ACol < FBuffer.Cols) then
      Result := FBuffer.Cells[ACol, RB];
    Exit;
  end;

  S := StreamTop + AScreenRow;
  if S < 0 then Exit;

  if S < FBuffer.ScrollbackLines.Count then
  begin
    if ACol < Length(FBuffer.ScrollbackLines[S]) then
      Result := FBuffer.ScrollbackLines[S][ACol];
  end
  else
  begin
    RB := S - FBuffer.ScrollbackLines.Count;
    if (RB >= 0) and (RB < FBuffer.Rows) and (ACol >= 0) and (ACol < FBuffer.Cols) then
      Result := FBuffer.Cells[ACol, RB];
  end;
end;

procedure TTerminalView.Paint;
var
  W, H: Integer;
  Canvas: TCanvas;
  Row: Integer;
begin
  W := ClientWidth;
  H := ClientHeight;
  if (W <= 0) or (H <= 0) then Exit;

  if (FBackBuffer.Width <> W) or (FBackBuffer.Height <> H) then
  begin
    FBackBuffer.Width := W;
    FBackBuffer.Height := H;
  end;

  Canvas := FBackBuffer.Canvas;
  Canvas.Font.Assign(FFont);
  Canvas.Brush.Color := FColors.Background;
  Canvas.FillRect(Rect(0, 0, W, H));

  if Assigned(FBuffer) then
  begin
    for Row := 0 to VisibleRows - 1 do
      PaintLine(Canvas, Row);

    if (FBuffer.CursorVisibility = cvNormal) and (FScrollOffset = 0) then
      PaintCursor(Canvas);
  end;

  BitBlt(Self.Canvas.Handle, 0, 0, W, H, Canvas.Handle, 0, 0, SRCCOPY);
end;

procedure TTerminalView.WMEraseBkgnd(var Msg: TWMEraseBkgnd);
begin
  Msg.Result := 1;
end;

procedure TTerminalView.PaintLine(ACanvas: TCanvas; AScreenRow: Integer);
var
  Col, RunStart, RunLen: Integer;
  RunFg, RunBg: TColor;
  RunBold, RunItalic, RunUnderline: Boolean;
  CurrFg, CurrBg: TColor;
  CurrBold, CurrItalic, CurrUnderline: Boolean;
  Cell: TTerminalCell;
  Text: string;
begin
  RunStart := -1;
  RunFg := 0;
  RunBg := 0;
  RunBold := False;
  RunItalic := False;
  RunUnderline := False;
  Text := '';

  for Col := 0 to VisibleCols - 1 do
  begin
    Cell := ResolveCell(AScreenRow, Col);
    ResolveCellColors(Cell, CurrFg, CurrBg, IsSelected(Col, AScreenRow));
    CurrBold := csfBold in Cell.Style;
    CurrItalic := csfItalic in Cell.Style;
    CurrUnderline := csfUnderline in Cell.Style;

    if (RunStart = -1) or
       (CurrFg <> RunFg) or (CurrBg <> RunBg) or
       (CurrBold <> RunBold) or (CurrItalic <> RunItalic) or
       (CurrUnderline <> RunUnderline) then
    begin
      if RunStart <> -1 then
      begin
        RunLen := Col - RunStart;
        ACanvas.Font.Color := RunFg;
        ACanvas.Brush.Color := RunBg;
        ACanvas.Font.Style := [];
        if RunBold then ACanvas.Font.Style := ACanvas.Font.Style + [fsBold];
        if RunItalic then ACanvas.Font.Style := ACanvas.Font.Style + [fsItalic];
        if RunUnderline then ACanvas.Font.Style := ACanvas.Font.Style + [fsUnderline];
        ACanvas.TextOut(RunStart * FCellWidth, AScreenRow * FCellHeight, Text);
      end;
      RunStart := Col;
      RunFg := CurrFg;
      RunBg := CurrBg;
      RunBold := CurrBold;
      RunItalic := CurrItalic;
      RunUnderline := CurrUnderline;
      Text := '';
    end;

    Text := Text + Cell.Ch;
  end;

  if RunStart <> -1 then
  begin
    ACanvas.Font.Color := RunFg;
    ACanvas.Brush.Color := RunBg;
    ACanvas.Font.Style := [];
    if RunBold then ACanvas.Font.Style := ACanvas.Font.Style + [fsBold];
    if RunItalic then ACanvas.Font.Style := ACanvas.Font.Style + [fsItalic];
    if RunUnderline then ACanvas.Font.Style := ACanvas.Font.Style + [fsUnderline];
    ACanvas.TextOut(RunStart * FCellWidth, AScreenRow * FCellHeight, Text);
  end;
end;

procedure TTerminalView.PaintCursor(ACanvas: TCanvas);
var
  CursorStream, ScreenRow: Integer;
  CursorRect: TRect;
  UnderlineHeight: Integer;
begin
  if not Assigned(FBuffer) then Exit;
  if (FBuffer.CursorX < 0) or (FBuffer.CursorX >= VisibleCols) then Exit;

  if FBuffer.AltScreenActive then
    ScreenRow := FBuffer.CursorY - AltOrigin
  else
  begin
    CursorStream := FBuffer.ScrollbackLines.Count + FBuffer.CursorY;
    ScreenRow := CursorStream - StreamTop;
  end;
  if (ScreenRow < 0) or (ScreenRow >= VisibleRows) then Exit;

  CursorRect := CellRect(FBuffer.CursorX, ScreenRow);

  UnderlineHeight := Max(2, FCellHeight div 5);
  ACanvas.Brush.Color := FColors.Foreground;
  ACanvas.FillRect(Rect(CursorRect.Left, CursorRect.Bottom - UnderlineHeight,
    CursorRect.Right, CursorRect.Bottom));
  ACanvas.Brush.Style := bsSolid;
end;

procedure TTerminalView.ResolveCellColors(const ACell: TTerminalCell;
  out AFgColor, ABgColor: TColor; ASelected: Boolean);
var
  Temp: TColor;

  function ResolveColor(const AColor: TCellColor; ADefault: TColor): TColor;
  begin
    case AColor.Kind of
      cckDefault: Result := ADefault;
      cckIndexed: Result := XTermPaletteColor(AColor.Index);
      cckRGB: Result := RGB(
        (AColor.RGB shr 16) and $FF,
        (AColor.RGB shr 8) and $FF,
        AColor.RGB and $FF);
    else
      Result := ADefault;
    end;
  end;

begin
  AFgColor := ResolveColor(ACell.Foreground, FColors.Foreground);
  ABgColor := ResolveColor(ACell.Background, FColors.Background);

  if csfInverse in ACell.Style then
  begin
    Temp := AFgColor;
    AFgColor := ABgColor;
    ABgColor := Temp;
  end;

  if ASelected then
  begin
    Temp := AFgColor;
    AFgColor := ABgColor;
    ABgColor := Temp;
  end;
end;

function TTerminalView.CellRect(ACol, AScreenRow: Integer): TRect;
begin
  Result := Rect(ACol * FCellWidth, AScreenRow * FCellHeight,
    (ACol + 1) * FCellWidth, (AScreenRow + 1) * FCellHeight);
end;

function TTerminalView.CellColAt(X: Integer): Integer;
begin
  if FCellWidth > 0 then
    Result := X div FCellWidth
  else
    Result := 0;
  if Result < 0 then Result := 0;
  if Result >= VisibleCols then Result := VisibleCols - 1;
end;

function TTerminalView.CellRowAt(Y: Integer): Integer;
begin
  if FCellHeight > 0 then
    Result := Y div FCellHeight
  else
    Result := 0;
  if Result < 0 then Result := 0;
  if Result >= VisibleRows then Result := VisibleRows - 1;
end;

function TTerminalView.IsSelected(ACol, AScreenRow: Integer): Boolean;
var
  MinR, MaxR, MinC, MaxC: Integer;
begin
  Result := False;
  if not (FSelecting or HasSelection) then Exit;

  MinR := Min(FAnchorRow, FCurrentRow);
  MaxR := Max(FAnchorRow, FCurrentRow);
  MinC := Min(FAnchorCol, FCurrentCol);
  MaxC := Max(FAnchorCol, FCurrentCol);

  if (AScreenRow < MinR) or (AScreenRow > MaxR) then Exit;

  if MinR = MaxR then
    Result := (ACol >= MinC) and (ACol <= MaxC)
  else if AScreenRow = MinR then
    Result := ACol >= MinC
  else if AScreenRow = MaxR then
    Result := ACol <= MaxC
  else
    Result := True;
end;

function TTerminalView.HasSelection: Boolean;
begin
  Result := FMoved and (FAnchorCol >= 0) and (FAnchorRow >= 0);
end;

function TTerminalView.GetSelectedText: string;
var
  MinR, MaxR, MinC, MaxC, R, C, C0, C1: Integer;
  Line: string;
  SB: TStringBuilder;
begin
  Result := '';
  if not HasSelection then Exit;

  MinR := Min(FAnchorRow, FCurrentRow);
  MaxR := Max(FAnchorRow, FCurrentRow);
  MinC := Min(FAnchorCol, FCurrentCol);
  MaxC := Max(FAnchorCol, FCurrentCol);

  SB := TStringBuilder.Create;
  try
    for R := MinR to MaxR do
    begin
      if R > MinR then
        C0 := 0
      else
        C0 := MinC;

      if R < MaxR then
        C1 := FBuffer.Cols - 1
      else
        C1 := MaxC;

      Line := '';
      for C := C0 to C1 do
        Line := Line + ResolveCell(R, C).Ch;
      Line := TrimRight(Line);

      if R > MinR then
        SB.Append(sLineBreak);
      SB.Append(Line);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TTerminalView.ClearSelection;
begin
  FSelecting := False;
  FMoved := False;
  FAnchorCol := -1;
  FAnchorRow := -1;
  FCurrentCol := -1;
  FCurrentRow := -1;
  Invalidate;
end;

procedure TTerminalView.WMGetDlgCode(var Msg: TMessage);
begin
  Msg.Result := DLGC_WANTARROWS or DLGC_WANTCHARS or DLGC_WANTALLKEYS;
end;

procedure TTerminalView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Assigned(FOnKeyDownEvent) then
    FOnKeyDownEvent(Self, Key, Shift);
end;

procedure TTerminalView.KeyPress(var Key: Char);
begin
  if Assigned(FOnKeyPressEvent) then
    FOnKeyPressEvent(Self, Key);
end;

procedure TTerminalView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  SetFocus;
  if Button = mbLeft then
  begin
    FSelecting := True;
    FMoved := False;
    FAnchorCol := CellColAt(X);
    FAnchorRow := CellRowAt(Y);
    FCurrentCol := FAnchorCol;
    FCurrentRow := FAnchorRow;
    Invalidate;
  end;
end;

procedure TTerminalView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  C, R: Integer;
begin
  inherited;
  if FSelecting then
  begin
    C := CellColAt(X);
    R := CellRowAt(Y);
    if (C <> FCurrentCol) or (R <> FCurrentRow) then
    begin
      FCurrentCol := C;
      FCurrentRow := R;
      FMoved := True;
      Invalidate;
    end;
  end;
end;

procedure TTerminalView.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  if (Button = mbLeft) and FSelecting then
  begin
    FSelecting := False;
    if not FMoved then
      ClearSelection
    else
      Invalidate;
  end;
end;

procedure TTerminalView.WMVScroll(var Msg: TWMVScroll);
var
  MaxScroll: Integer;
begin
  MaxScroll := MaxScrollOffset;
  case Msg.ScrollCode of
    SB_LINEUP: FScrollOffset := Min(FScrollOffset + 1, MaxScroll);
    SB_LINEDOWN: FScrollOffset := Max(FScrollOffset - 1, 0);
    SB_PAGEUP: FScrollOffset := Min(FScrollOffset + VisibleRows, MaxScroll);
    SB_PAGEDOWN: FScrollOffset := Max(FScrollOffset - VisibleRows, 0);
    SB_THUMBTRACK, SB_THUMBPOSITION: FScrollOffset := Max(0, Min(Msg.Pos, MaxScroll));
    SB_BOTTOM: FScrollOffset := 0;
    SB_TOP: FScrollOffset := MaxScroll;
  end;
  Invalidate;
end;

procedure TTerminalView.CMDMouseWheel(var Msg: TCMMouseWheel);
var
  Btn: Integer;
  X, Y: Integer;
  P: TPoint;
  S: string;
  MaxScroll: Integer;
begin
  if Assigned(FBuffer) and FBuffer.AltScreenActive and FBuffer.MouseEnabled and
     Assigned(FOnSendData) then
  begin
    P := ScreenToClient(Mouse.CursorPos);
    X := P.X div FCellWidth + 1;
    Y := P.Y div FCellHeight + 1;
    if X < 1 then X := 1;
    if Y < 1 then Y := 1;
    if Msg.WheelDelta > 0 then
      Btn := 64
    else
      Btn := 65;
    S := Format(#27'[<%d;%d;%dM', [Btn, X, Y]);
    FOnSendData(S);
    Msg.Result := 1;
    Exit;
  end;

  MaxScroll := MaxScrollOffset;
  if Msg.WheelDelta > 0 then
    FScrollOffset := Min(FScrollOffset + 3, MaxScroll)
  else if Msg.WheelDelta < 0 then
    FScrollOffset := Max(FScrollOffset - 3, 0);
  Invalidate;
  Msg.Result := 1;
end;

end.