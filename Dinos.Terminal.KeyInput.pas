unit Dinos.Terminal.KeyInput;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Clipbrd;

type
  TSendInputEvent = procedure(const AData: string) of object;

  TKeyToVT = class
  private
    FOnSendInput: TSendInputEvent;
    function ShiftStateToModifiers(AShift: TShiftState): Integer;
  public
    constructor Create;
    procedure HandleKeyDown(AKey: Word; AShift: TShiftState);
    procedure HandleKeyPress(AKey: Char);
    procedure HandlePaste(const AText: string);
    property OnSendInput: TSendInputEvent read FOnSendInput write FOnSendInput;
  end;

implementation

const
  VKPrior = $21;
  VKNext  = $22;
  VKEnd   = $23;
  VKHome  = $24;
  VKLeft  = $25;
  VKUp    = $26;
  VKRight = $27;
  VKDown  = $28;
  VKInsert = $2D;
  VKDelete = $2E;

{ TKeyToVT }

constructor TKeyToVT.Create;
begin
  inherited Create;
end;

function TKeyToVT.ShiftStateToModifiers(AShift: TShiftState): Integer;
begin
  Result := 0;
  if ssShift in AShift then Result := Result or 1;
  if ssAlt in AShift then Result := Result or 2;
  if ssCtrl in AShift then Result := Result or 4;
end;

procedure TKeyToVT.HandleKeyDown(AKey: Word; AShift: TShiftState);
var
  Modifiers: Integer;
  Seq: string;
  IsCtrl: Boolean;
  IsShift: Boolean;
  IsAlt: Boolean;

  function ModSuffix: string;
  begin
    if Modifiers > 0 then
      Result := '1;' + IntToStr(Modifiers + 1)
    else
      Result := '';
  end;

  function NumSuffix: string;
  begin
    if Modifiers > 0 then
      Result := ';' + IntToStr(Modifiers + 1)
    else
      Result := '';
  end;

begin
  IsCtrl := ssCtrl in AShift;
  IsShift := ssShift in AShift;
  IsAlt := ssAlt in AShift;
  Modifiers := ShiftStateToModifiers(AShift);

  if IsCtrl and (AKey in [Ord('C'), Ord('c')]) then
  begin
    if Assigned(FOnSendInput) then
      FOnSendInput(#3);
    Exit;
  end;

  if IsCtrl and (AKey in [Ord('V'), Ord('v')]) then
  begin
    if Clipboard.HasFormat(CF_TEXT) then
      HandlePaste(Clipboard.AsText);
    Exit;
  end;

  if IsCtrl and (AKey in [Ord('Z'), Ord('z')]) then
  begin
    if Assigned(FOnSendInput) then
      FOnSendInput(#26);
    Exit;
  end;

  case AKey of
    VK_UP:    Seq := #27'['+ModSuffix+'A';
    VK_DOWN:  Seq := #27'['+ModSuffix+'B';
    VK_RIGHT: Seq := #27'['+ModSuffix+'C';
    VK_LEFT:  Seq := #27'['+ModSuffix+'D';
    VK_HOME:  Seq := #27'['+ModSuffix+'H';
    VKEnd:    Seq := #27'['+ModSuffix+'F';
    VKPrior:  Seq := #27'[5'+NumSuffix+'~';
    VKNext:   Seq := #27'[6'+NumSuffix+'~';
    VKInsert: Seq := #27'[2'+NumSuffix+'~';
    VKDelete: Seq := #27'[3'+NumSuffix+'~';
    VK_F1:    Seq := #27'OP';
    VK_F2:    Seq := #27'OQ';
    VK_F3:    Seq := #27'OR';
    VK_F4:    Seq := #27'OS';
    VK_F5:    Seq := #27'[15'+NumSuffix+'~';
    VK_F6:    Seq := #27'[17'+NumSuffix+'~';
    VK_F7:    Seq := #27'[18'+NumSuffix+'~';
    VK_F8:    Seq := #27'[19'+NumSuffix+'~';
    VK_F9:    Seq := #27'[20'+NumSuffix+'~';
    VK_F10:   Seq := #27'[21'+NumSuffix+'~';
    VK_F11:   Seq := #27'[23'+NumSuffix+'~';
    VK_F12:   Seq := #27'[24'+NumSuffix+'~';
    VK_TAB:
    begin
      if IsCtrl then
        Seq := #27'[Z'
      else
        Exit;
    end;
    VK_BACK:
      Seq := #8;
  else
    Exit;
  end;

  if Assigned(FOnSendInput) and (Seq <> '') then
    FOnSendInput(Seq);
end;

procedure TKeyToVT.HandleKeyPress(AKey: Char);
begin
  if AKey = #8 then
    Exit;
  if Assigned(FOnSendInput) then
    FOnSendInput(AKey);
end;

procedure TKeyToVT.HandlePaste(const AText: string);
var
  I: Integer;
  Ch: Char;
  Buf: string;
begin
  if AText = '' then Exit;
  Buf := '';
  for I := 1 to Length(AText) do
  begin
    Ch := AText[I];
    if Ch = #13 then
      Buf := Buf + #13
    else if Ch = #10 then
      Buf := Buf + #10
    else if Ch >= #32 then
      Buf := Buf + Ch;
  end;
  if Assigned(FOnSendInput) and (Buf <> '') then
    FOnSendInput(Buf);
end;

end.
