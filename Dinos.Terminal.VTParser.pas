unit Dinos.Terminal.VTParser;

interface

uses
  System.SysUtils, System.Classes, Dinos.Terminal.ScreenBuffer;

type
  TVTParserState = (vpsNormal, vpsEscape, vpsCSI, vpsOSC, vpsOSCEsc, vpsCharset);

  TTitleChangedEvent = procedure(const ATitle: string) of object;

  TVTParser = class
  private
    FScreen: TScreenBuffer;
    FState: TVTParserState;
    FParams: TArray<Integer>;
    FParamCount: Integer;
    FOSBuffer: string;
    FPrivateMode: Boolean;
    FOnTitleChanged: TTitleChangedEvent;
    procedure DispatchCSI;
    procedure DispatchOSC(const AText: string);
    procedure HandleSGR;
    procedure HandleC0(ACh: Char);
    function GetParam(AIndex: Integer; ADefault: Integer): Integer;
    procedure ResetParams;
  public
    constructor Create(AScreen: TScreenBuffer);
    procedure Parse(const AText: string);
    procedure Reset;
    property OnTitleChanged: TTitleChangedEvent read FOnTitleChanged write FOnTitleChanged;
  end;

implementation

const
  VT_ESC = #27;
  VT_CSI = '[';
  VT_OSC = ']';
  VT_BEL = #7;
  VT_BS = #8;
  VT_TAB = #9;
  VT_LF = #10;
  VT_CR = #13;
  VT_DEL = #127;

{ TVTParser }

constructor TVTParser.Create(AScreen: TScreenBuffer);
begin
  inherited Create;
  FScreen := AScreen;
  FState := vpsNormal;
  ResetParams;
end;

procedure TVTParser.Reset;
begin
  FState := vpsNormal;
  ResetParams;
  FOSBuffer := '';
end;

procedure TVTParser.ResetParams;
begin
  SetLength(FParams, 0);
  FParamCount := 0;
  FPrivateMode := False;
end;

function TVTParser.GetParam(AIndex: Integer; ADefault: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex <= FParamCount) and (AIndex < Length(FParams)) and (FParams[AIndex] > 0) then
    Result := FParams[AIndex]
  else
    Result := ADefault;
end;

procedure TVTParser.HandleC0(ACh: Char);
begin
  case ACh of
    VT_BEL: ; // bell
    VT_BS: FScreen.Backspace;
    VT_TAB: FScreen.Tab;
    VT_LF, #11, #12: FScreen.LineFeed;
    VT_CR: FScreen.CarriageReturn;
  end;
end;

procedure TVTParser.Parse(const AText: string);
var
  I: Integer;
  Ch: Char;
  Len: Integer;
begin
  Len := Length(AText);
  I := 1;

  while I <= Len do
  begin
    Ch := AText[I];

    case FState of
      vpsNormal:
      begin
        if Ch = VT_ESC then
          FState := vpsEscape
        else if Ch < #32 then
          HandleC0(Ch)
        else
          FScreen.PutChar(Ch);
      end;

      vpsEscape:
      begin
        case Ch of
          VT_CSI:
          begin
            FState := vpsCSI;
            ResetParams;
          end;
          VT_OSC:
          begin
            FState := vpsOSC;
            FOSBuffer := '';
          end;
          'D': begin FScreen.LineFeed; FState := vpsNormal; end;
          'M': begin FScreen.ScrollDown(1); FState := vpsNormal; end;
          'E': begin FScreen.LineFeed; FScreen.CarriageReturn; FState := vpsNormal; end;
          '7': begin FScreen.SaveCursor; FState := vpsNormal; end;
          '8': begin FScreen.RestoreCursor; FState := vpsNormal; end;
          '(', ')', '*', '+': begin FState := vpsCharset; end;
        else
          FState := vpsNormal;
        end;
      end;

      vpsCSI:
      begin
        case Ch of
          #48..#57:
          begin
            SetLength(FParams, FParamCount + 1);
            FParams[FParamCount] := FParams[FParamCount] * 10 + (Ord(Ch) - 48);
          end;
          #59:
          begin
            Inc(FParamCount);
            SetLength(FParams, FParamCount + 1);
            FParams[FParamCount] := 0;
          end;
          #63:
          begin
            // '?' private mode prefix (DEC) - not a final byte
            FPrivateMode := True;
          end;
          #60..#62, #64..#126:
          begin
            if (FParamCount = 0) and (Length(FParams) = 0) then
            begin
              SetLength(FParams, 1);
              FParams[0] := 0;
              FParamCount := 1;
            end;
            Inc(FParamCount);
            SetLength(FParams, FParamCount + 1);
            FParams[FParamCount] := Ord(Ch);
            DispatchCSI;
            FState := vpsNormal;
          end;
        else
          FState := vpsNormal;
        end;
      end;

      vpsOSC:
      begin
        if Ch = VT_BEL then
        begin
          DispatchOSC(FOSBuffer);
          FState := vpsNormal;
        end
        else if Ch = VT_ESC then
          FState := vpsOSCEsc
        else
          FOSBuffer := FOSBuffer + Ch;
      end;

      vpsOSCEsc:
      begin
        if Ch = '\' then
        begin
          DispatchOSC(FOSBuffer);
          FState := vpsNormal;
        end
        else
        begin
          FOSBuffer := FOSBuffer + VT_ESC + Ch;
          FState := vpsOSC;
        end;
      end;

      vpsCharset:
      begin
        FState := vpsNormal;
      end;
    end;

    Inc(I);
  end;
end;

procedure TVTParser.DispatchCSI;
var
  FinalByte: Char;
  I: Integer;
begin
  if FParamCount < 0 then
    FParamCount := 0;

  FinalByte := Chr(FParams[FParamCount] + 48);

  if Length(FParams) = 0 then
    Exit;

  FinalByte := #0;
  for I := Length(FParams) - 1 downto 0 do
  begin
    if FParams[I] in [64..126] then
    begin
      FinalByte := Chr(FParams[I]);
      SetLength(FParams, I);
      FParamCount := I - 1;
      Break;
    end;
  end;

  if FinalByte = #0 then
    Exit;

  case FinalByte of
    'A': FScreen.MoveCursorUp(GetParam(0, 1));
    'B': FScreen.MoveCursorDown(GetParam(0, 1));
    'C': FScreen.MoveCursorForward(GetParam(0, 1));
    'D': FScreen.MoveCursorBackward(GetParam(0, 1));
    'E': begin FScreen.CarriageReturn; FScreen.MoveCursorDown(GetParam(0, 1)); end;
    'F': begin FScreen.CarriageReturn; FScreen.MoveCursorUp(GetParam(0, 1)); end;
    'G': FScreen.SetCursorPos(GetParam(0, 1) - 1, FScreen.CursorY);
    'H', 'f': FScreen.SetCursorXY(GetParam(1, 1), GetParam(0, 1));
    'J': case GetParam(0, 0) of
           0: FScreen.ClearToEndOfScreen;
           1: FScreen.ClearToStartOfScreen;
           2: FScreen.ClearEntireScreen;
           3: begin FScreen.ClearEntireScreen; FScreen.ClearScrollback; end;
         end;
    'K': case GetParam(0, 0) of
           0: FScreen.ClearToEndOfLine;
           1: FScreen.ClearToStartOfLine;
           2: begin FScreen.CarriageReturn; FScreen.ClearToEndOfLine; end;
         end;
    'L': FScreen.InsertLines(GetParam(0, 1));
    'M': FScreen.DeleteLines(GetParam(0, 1));
    'P': FScreen.DeleteChars(GetParam(0, 1));
    'S': FScreen.ScrollUp(GetParam(0, 1));
    'T': FScreen.ScrollDown(GetParam(0, 1));
    'X': FScreen.EraseChars(GetParam(0, 1));
    '@': FScreen.InsertChars(GetParam(0, 1));
    'd': FScreen.SetCursorPos(FScreen.CursorX, GetParam(0, 1) - 1);
    'm': HandleSGR;
    'r': FScreen.SetScrollRegion(GetParam(0, 1) - 1, GetParam(1, FScreen.Rows) - 1);
    'h', 'l':
    begin
      if FPrivateMode then
      begin
        case GetParam(0, 0) of
          25:
            if FinalByte = 'l' then
              FScreen.CursorVisibility := cvHidden
            else
              FScreen.CursorVisibility := cvNormal;
          47, 1047, 1049:
            if FinalByte = 'h' then
              FScreen.EnterAltScreen
            else
              FScreen.ExitAltScreen;
          1048:
            if FinalByte = 'h' then
              FScreen.SaveCursor;
          1000, 1002, 1003, 1006:
            FScreen.MouseEnabled := (FinalByte = 'h');
        end;
      end;
    end;
    'n', 'c': ; // Device status reports - ignore
  end;
end;

procedure TVTParser.HandleSGR;
var
  I, P: Integer;
begin
  I := 0;
  while I <= FParamCount do
  begin
    P := GetParam(I, 0);

    case P of
      0: begin
        FScreen.CurrentFg := TCellColor.Default;
        FScreen.CurrentBg := TCellColor.Default;
        FScreen.CurrentStyle := [];
      end;
      1: FScreen.CurrentStyle := FScreen.CurrentStyle + [csfBold];
      3: FScreen.CurrentStyle := FScreen.CurrentStyle + [csfItalic];
      4: FScreen.CurrentStyle := FScreen.CurrentStyle + [csfUnderline];
      7: FScreen.CurrentStyle := FScreen.CurrentStyle + [csfInverse];
      22: FScreen.CurrentStyle := FScreen.CurrentStyle - [csfBold];
      23: FScreen.CurrentStyle := FScreen.CurrentStyle - [csfItalic];
      24: FScreen.CurrentStyle := FScreen.CurrentStyle - [csfUnderline];
      27: FScreen.CurrentStyle := FScreen.CurrentStyle - [csfInverse];

      30..37: FScreen.CurrentFg := TCellColor.Indexed(P - 30);
      38:
      begin
        if (I + 1 <= FParamCount) and (GetParam(I + 1, -1) = 5) then
        begin
          FScreen.CurrentFg := TCellColor.Indexed(GetParam(I + 2, 0));
          Inc(I, 2);
        end
        else if (I + 1 <= FParamCount) and (GetParam(I + 1, -1) = 2) then
        begin
          FScreen.CurrentFg := TCellColor.RGBColor(
            GetParam(I + 2, 0), GetParam(I + 3, 0), GetParam(I + 4, 0));
          Inc(I, 4);
        end;
      end;
      39: FScreen.CurrentFg := TCellColor.Default;

      40..47: FScreen.CurrentBg := TCellColor.Indexed(P - 40);
      48:
      begin
        if (I + 1 <= FParamCount) and (GetParam(I + 1, -1) = 5) then
        begin
          FScreen.CurrentBg := TCellColor.Indexed(GetParam(I + 2, 0));
          Inc(I, 2);
        end
        else if (I + 1 <= FParamCount) and (GetParam(I + 1, -1) = 2) then
        begin
          FScreen.CurrentBg := TCellColor.RGBColor(
            GetParam(I + 2, 0), GetParam(I + 3, 0), GetParam(I + 4, 0));
          Inc(I, 4);
        end;
      end;
      49: FScreen.CurrentBg := TCellColor.Default;

      90..97: FScreen.CurrentFg := TCellColor.Indexed(P - 90 + 8);
      100..107: FScreen.CurrentBg := TCellColor.Indexed(P - 100 + 8);
    end;

    Inc(I);
  end;
end;

procedure TVTParser.DispatchOSC(const AText: string);
var
  SpacePos: Integer;
  Title: string;
  Num: Integer;
begin
  SpacePos := Pos(';', AText);
  if SpacePos > 0 then
  begin
    Num := StrToIntDef(Copy(AText, 1, SpacePos - 1), -1);
    if (Num = 0) or (Num = 2) then
    begin
      Title := Copy(AText, SpacePos + 1, MaxInt);
      if Assigned(FOnTitleChanged) then
        FOnTitleChanged(Title);
    end;
  end;
end;

end.
