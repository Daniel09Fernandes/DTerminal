unit Dinos.Terminal.Frame;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.Clipbrd,
  Dinos.Terminal.ScreenBuffer, Dinos.Terminal.VTParser,
  Dinos.Terminal.TerminalView, Dinos.Terminal.KeyInput,
  Dinos.Terminal.ConPtyShell, Dinos.Terminal.Pty, Dinos.Terminal.Debug;

type
  TTerminalFrame = class(TFrame)
  private
    FScreen: TScreenBuffer;
    FParser: TVTParser;
    FView: TTerminalView;
    FKeyInput: TKeyToVT;
    FProcess: ITerminalProcess;
    FOnTitleChanged: TTitleChangedEvent;
    FOnProcessExit: TNotifyEvent;
    FLastSize: TTerminalSize;
    FShellTypeName: string;
    FInputActive: Boolean;
    FInputText: string;
    FInputStartCol: Integer;
    FInputStartRow: Integer;
    procedure HandleKeyDownEvent(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleKeyPressEvent(Sender: TObject; var Key: Char);
    procedure HandleSendInput(const AData: string);
    procedure HandleTitleChanged(const ATitle: string);
    procedure HandleProcessOutput(const AText: string);
    procedure HandleProcessTerminated;
    procedure HandleViewSizeChanged(Sender: TObject; ACols, ARows: Integer);
    procedure ApplyProcessSize;
    procedure LayoutView;
    function IsShellPromptAtCursor: Boolean;
    procedure StartLocalInput;
    procedure AppendLocalChar(const ACh: Char);
    procedure BackspaceLocalInput;
    procedure EnterLocalInput;
    procedure CancelLocalInput;
    procedure EraseLocalRegion;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure FeedData(const AData: string);
    procedure Clear;
    procedure CancelInput;
    procedure SetProcess(AProcess: ITerminalProcess);
    procedure ResizeProcessToView;
    procedure FocusView;
    property Screen: TScreenBuffer read FScreen;
    property View: TTerminalView read FView;
    property Process: ITerminalProcess read FProcess write FProcess;
    property ShellTypeName: string read FShellTypeName write FShellTypeName;
    property OnTitleChanged: TTitleChangedEvent read FOnTitleChanged write FOnTitleChanged;
    property OnProcessExit: TNotifyEvent read FOnProcessExit write FOnProcessExit;
  end;

implementation

{$R *.dfm}

{ TTerminalFrame }

uses
  Math;

const
  MinBufferCols = 120;
  MinBufferRows = 40;

constructor TTerminalFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 800;
  Height := 600;

  FScreen := TScreenBuffer.Create(80, 24);
  FLastSize.Cols := 120;
  FLastSize.Rows := 40;
  FScreen.Resize(FLastSize.Cols, FLastSize.Rows);

  FParser := TVTParser.Create(FScreen);
  FParser.OnTitleChanged := HandleTitleChanged;

  FView := TTerminalView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.AssignScreen(FScreen);
  FView.OnKeyDownEvent := HandleKeyDownEvent;
  FView.OnKeyPressEvent := HandleKeyPressEvent;
  FView.OnViewSizeChanged := HandleViewSizeChanged;

  FKeyInput := TKeyToVT.Create;
  FKeyInput.OnSendInput := HandleSendInput;

  FInputActive := False;
  FInputText := '';
  FInputStartCol := 0;
  FInputStartRow := 0;
end;

destructor TTerminalFrame.Destroy;
begin
  FKeyInput.Free;
  FParser.Free;
  FScreen.Free;
  inherited;
end;

procedure TTerminalFrame.FeedData(const AData: string);
begin
  FParser.Parse(AData);
  FView.UpdateView;
end;

procedure TTerminalFrame.Clear;
begin
  FScreen.Clear;
  FView.RefreshAll;
end;

procedure TTerminalFrame.CancelInput;
begin
  CancelLocalInput;
  FView.ClearSelection;
end;

procedure TTerminalFrame.SetProcess(AProcess: ITerminalProcess);
begin
  FProcess := AProcess;
  if Assigned(FProcess) then
  begin
    FProcess.OnOutput := HandleProcessOutput;
    FProcess.OnProcessExit := HandleProcessTerminated;
    Log('TTerminalFrame.SetProcess: OnOutput assigned');
  end;
  FView.UpdateMetrics;
end;

procedure TTerminalFrame.FocusView;
begin
  if Assigned(FView) then
    FView.SetFocus;
end;

procedure TTerminalFrame.HandleProcessOutput(const AText: string);
var
  HexStr: string;
  I: Integer;
begin
  if Length(AText) > 0 then
  begin
    HexStr := '';
    for I := 1 to Min(Length(AText), 8192) do
    begin
      if AText[I] >= ' ' then
        HexStr := HexStr + AText[I]
      else
        HexStr := HexStr + '#' + IntToHex(Ord(AText[I]), 2);
    end;
    Log(Format('HandleProcessOutput: %d chars: %s', [Length(AText), HexStr]));
  end;
  if FInputActive then
    CancelLocalInput;
  FeedData(AText);
end;

procedure TTerminalFrame.HandleProcessTerminated;
begin
  FProcess := nil;
end;

procedure TTerminalFrame.ApplyProcessSize;
begin
  if Assigned(FProcess) and FProcess.IsRunning then
    FProcess.Resize(FLastSize);
end;

procedure TTerminalFrame.HandleViewSizeChanged(Sender: TObject; ACols, ARows: Integer);
begin
  CancelLocalInput;
  FLastSize.Cols := ACols;
  FLastSize.Rows := ARows;
  if FLastSize.Rows < MinBufferRows then
    FLastSize.Rows := MinBufferRows;
  if FLastSize.Cols < MinBufferCols then
    FLastSize.Cols := MinBufferCols;
  FScreen.Resize(FLastSize.Cols, FLastSize.Rows);
  ApplyProcessSize;
end;

procedure TTerminalFrame.ResizeProcessToView;
begin
  CancelLocalInput;
  FLastSize.Cols := FView.VisibleCols;
  FLastSize.Rows := FView.VisibleRows;
  if FLastSize.Rows < MinBufferRows then
    FLastSize.Rows := MinBufferRows;
  if FLastSize.Cols < MinBufferCols then
    FLastSize.Cols := MinBufferCols;
  FScreen.Resize(FLastSize.Cols, FLastSize.Rows);
  ApplyProcessSize;
end;

procedure TTerminalFrame.HandleKeyDownEvent(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ssCtrl in Shift) and (Key in [Ord('C'), Ord('c')]) and FView.HasSelection then
  begin
    Clipboard.AsText := FView.GetSelectedText;
    Key := 0;
    Exit;
  end;

  if FInputActive then
  begin
    if Key = VK_RETURN then
    begin
      Key := 0;
      Exit;
    end;
    if Key = VK_BACK then
    begin
      Key := 0;
      BackspaceLocalInput;
      Exit;
    end;
    if (Key in [VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_HOME, VK_END,
                VK_PRIOR, VK_NEXT, VK_INSERT, VK_DELETE]) or
       (Key in [VK_F1..VK_F12]) or (Key = VK_TAB) or (ssCtrl in Shift) then
      CancelLocalInput
    else
      Exit;
  end
  else if Key = VK_BACK then
  begin
    if IsShellPromptAtCursor then
    begin
      Key := 0;
      Exit;
    end;
  end;

  if FInputActive then
    Exit;

  FKeyInput.HandleKeyDown(Key, Shift);
end;

procedure TTerminalFrame.HandleKeyPressEvent(Sender: TObject; var Key: Char);
begin
  if FInputActive then
  begin
    if Key = #13 then
    begin
      Key := #0;
      EnterLocalInput;
      Exit;
    end;
    if (Key = #8) or (Key = #3) then
    begin
      Key := #0;
      Exit;
    end;
    if Key >= #32 then
    begin
      AppendLocalChar(Key);
      Key := #0;
      Exit;
    end;
    CancelLocalInput;
  end
  else if Key >= #32 then
  begin
    if IsShellPromptAtCursor then
    begin
      StartLocalInput;
      AppendLocalChar(Key);
      Key := #0;
      Exit;
    end;
  end;

  if (Key = #8) or (Key = #3) then
    Key := #0
  else
    FKeyInput.HandleKeyPress(Key);
end;

function TTerminalFrame.IsShellPromptAtCursor: Boolean;
var
  Y, X, I: Integer;
  LineText: string;
begin
  Result := False;
  if not Assigned(FScreen) then Exit;
  Y := FScreen.CursorY;
  X := FScreen.CursorX;
  if (Y < 0) or (Y >= FScreen.Rows) then Exit;
  for I := X to FScreen.Cols - 1 do
    if FScreen.Cells[I, Y].Ch <> ' ' then Exit;
  LineText := FScreen.RowToString(Y);
  if LineText = '' then Exit;
  if X >= Length(LineText) then
    case LineText[Length(LineText)] of
      '>', '$', '#', '%', ':', ']': Result := True;
    end;
end;

procedure TTerminalFrame.StartLocalInput;
begin
  FInputActive := True;
  FInputStartCol := FScreen.CursorX;
  FInputStartRow := FScreen.CursorY;
  FInputText := '';
end;

procedure TTerminalFrame.AppendLocalChar(const ACh: Char);
begin
  FInputText := FInputText + ACh;
  FScreen.PutChar(ACh);
  FView.UpdateView;
end;

procedure TTerminalFrame.BackspaceLocalInput;
begin
  if FInputText = '' then Exit;
  Delete(FInputText, Length(FInputText), 1);
  if FScreen.CursorX > 0 then
    FScreen.Backspace
  else if FScreen.CursorY > FInputStartRow then
  begin
    FScreen.MoveCursorUp(1);
    FScreen.SetCursorPos(FScreen.Cols - 1, FScreen.CursorY);
    FScreen.Cells[FScreen.Cols - 1, FScreen.CursorY] := TTerminalCell.DefaultCell;
  end;
  FView.UpdateView;
end;

procedure TTerminalFrame.EnterLocalInput;
var
  Line: string;
begin
  if not FInputActive then Exit;
  FInputActive := False;
  Line := FInputText;
  FInputText := '';
  EraseLocalRegion;
  FView.UpdateView;
  HandleSendInput(Line + #13);
end;

procedure TTerminalFrame.CancelLocalInput;
begin
  if not FInputActive then Exit;
  FInputActive := False;
  FInputText := '';
  EraseLocalRegion;
  FView.UpdateView;
end;

procedure TTerminalFrame.EraseLocalRegion;
var
  J, Col0, Col1, I: Integer;
begin
  for J := FInputStartRow to FScreen.CursorY do
  begin
    if J = FInputStartRow then
      Col0 := FInputStartCol
    else
      Col0 := 0;
    if J = FScreen.CursorY then
      Col1 := FScreen.CursorX
    else
      Col1 := FScreen.Cols;
    for I := Col0 to Col1 - 1 do
      FScreen.Cells[I, J] := TTerminalCell.DefaultCell;
  end;

  FScreen.SetCursorPos(FInputStartCol, FInputStartRow);
end;

procedure TTerminalFrame.HandleSendInput(const AData: string);
begin
  try
    if Assigned(FProcess) and FProcess.IsRunning then
    begin
      if FView.HasSelection then
        FView.ClearSelection;
      FProcess.WriteInput(AData);
    end;
  except
  end;
end;

procedure TTerminalFrame.HandleTitleChanged(const ATitle: string);
begin
  if Assigned(FOnTitleChanged) then
    FOnTitleChanged(ATitle);
end;

procedure TTerminalFrame.LayoutView;
begin
  if Assigned(FView) then
    FView.UpdateMetrics;
end;

end.
