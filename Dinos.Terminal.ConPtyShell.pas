unit Dinos.Terminal.ConPtyShell;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Dinos.Terminal.Pty, Dinos.Terminal.ConPtyReader, Dinos.Terminal.Debug;

type
  TTerminalOutputEvent = procedure(const AText: string) of object;
  TTerminalExitEvent = procedure of object;

  ITerminalProcess = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    procedure Start(const ACommand, AWorkDir: string; const ASize: TTerminalSize);
    procedure WriteInput(const AData: string);
    procedure SendInterrupt;
    procedure Resize(const ASize: TTerminalSize);
    procedure Terminate;
    function IsRunning: Boolean;
    function HasForegroundChild: Boolean;
    function GetOnOutput: TTerminalOutputEvent;
    procedure SetOnOutput(const AValue: TTerminalOutputEvent);
    function GetOnProcessExit: TTerminalExitEvent;
    procedure SetOnProcessExit(const AValue: TTerminalExitEvent);
    property OnOutput: TTerminalOutputEvent read GetOnOutput write SetOnOutput;
    property OnProcessExit: TTerminalExitEvent read GetOnProcessExit write SetOnProcessExit;
  end;

  TConPtyShell = class(TInterfacedObject, ITerminalProcess)
  private
    FPty: TConPty;
    FReader: TConPtyReader;
    FExitWatcher: TThread;
    FOnOutput: TTerminalOutputEvent;
    FOnProcessExit: TTerminalExitEvent;
    FExited: Boolean;
    FTerminating: Boolean;
    procedure HandleReaderExit;
    procedure HandleChildExit;
    procedure DoChildExit;
    procedure StartExitWatcher;
    function GetOnOutput: TTerminalOutputEvent;
    procedure SetOnOutput(const AValue: TTerminalOutputEvent);
    function GetOnProcessExit: TTerminalExitEvent;
    procedure SetOnProcessExit(const AValue: TTerminalExitEvent);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const ACommand, AWorkDir: string; const ASize: TTerminalSize);
    procedure WriteInput(const AData: string);
    procedure SendInterrupt;
    procedure Resize(const ASize: TTerminalSize);
    procedure Terminate;
    function IsRunning: Boolean;
    function HasForegroundChild: Boolean;
  end;

implementation

uses
  Math;

type
  TProcessExitWatcher = class(TThread)
  private
    FProcessHandle: THandle;
    FOnExit: TThreadMethod;
  protected
    procedure Execute; override;
  public
    constructor Create(AProcessHandle: THandle; const AOnExit: TThreadMethod);
  end;

constructor TProcessExitWatcher.Create(AProcessHandle: THandle; const AOnExit: TThreadMethod);
begin
  FProcessHandle := AProcessHandle;
  FOnExit := AOnExit;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TProcessExitWatcher.Execute;
begin
  while not Terminated do
  begin
    if WaitForSingleObject(FProcessHandle, 100) = WAIT_OBJECT_0 then
    begin
      if not Terminated then
        Queue(FOnExit);
      Break;
    end;
  end;
end;

{ TConPtyShell }

constructor TConPtyShell.Create;
begin
  inherited Create;
  FPty := TConPty.Create;
  FExited := False;
  FTerminating := False;
end;

destructor TConPtyShell.Destroy;
begin
  Terminate;
  inherited;
end;

procedure TConPtyShell.Start(const ACommand, AWorkDir: string; const ASize: TTerminalSize);
begin
  Log('TConPtyShell.Start: "' + ACommand + '" workdir="' + AWorkDir + '"');
  if FPty.IsRunning then
    Exit;
  FTerminating := False;
  FExited := False;

  if not FPty.Start(ACommand, AWorkDir, ASize) then
    raise Exception.Create('ConPTY session failed to start');

  Log('TConPtyShell.Start: creating reader, OutputRead=' + IntToStr(FPty.OutputRead));
  FReader := TConPtyReader.Create(FPty.OutputRead);
  FReader.OnOutput := FOnOutput;
  FReader.OnTerminated := HandleReaderExit;
  Log('TConPtyShell.Start: reader OnOutput assigned, Assigned(OnOutput)=' + BoolToStr(Assigned(FOnOutput), True));

  StartExitWatcher;
  Log('TConPtyShell.Start: done');
end;

procedure TConPtyShell.StartExitWatcher;
begin
  FExitWatcher := TProcessExitWatcher.Create(FPty.ProcessHandle, HandleChildExit);
end;

procedure TConPtyShell.WriteInput(const AData: string);
var
  LBytes: TBytes;
  I: Integer;
  HexStr: string;
begin
  if not FExited then
  begin
    LBytes := TEncoding.UTF8.GetBytes(AData);
    HexStr := '';
    for I := 0 to Min(Length(LBytes) - 1, 15) do
      HexStr := HexStr + IntToHex(LBytes[I], 2) + ' ';
    Log(Format('TConPtyShell.WriteInput: %d bytes [%s]', [Length(LBytes), HexStr]));
    FPty.WriteInput(AData);
  end
  else
    Log('TConPtyShell.WriteInput: skipped (FExited=True)');
end;

procedure TConPtyShell.SendInterrupt;
begin
  WriteInput(#3);
end;

procedure TConPtyShell.Resize(const ASize: TTerminalSize);
begin
  FPty.Resize(ASize);
end;

procedure TConPtyShell.Terminate;
begin
  if FTerminating then
    Exit;
  FTerminating := True;

  if Assigned(FExitWatcher) then
  begin
    FExitWatcher.Terminate;
    FExitWatcher.WaitFor;
    TThread.RemoveQueuedEvents(FExitWatcher);
    FreeAndNil(FExitWatcher);
  end;

  if Assigned(FReader) then
    FReader.Terminate;

  FPty.Close;
  FreeAndNil(FReader);
end;

procedure TConPtyShell.HandleReaderExit;
begin
  DoChildExit;
end;

procedure TConPtyShell.HandleChildExit;
begin
  DoChildExit;
end;

procedure TConPtyShell.DoChildExit;
begin
  if FExited or FTerminating then
    Exit;
  FExited := True;
  if Assigned(FOnProcessExit) then
    FOnProcessExit;
end;

function TConPtyShell.IsRunning: Boolean;
begin
  Result := FPty.IsRunning and not FExited;
end;

function TConPtyShell.HasForegroundChild: Boolean;
begin
  Result := FPty.IsRunning and (FPty.ActiveProcessCount > 1);
end;

function TConPtyShell.GetOnOutput: TTerminalOutputEvent;
begin
  Result := FOnOutput;
end;

procedure TConPtyShell.SetOnOutput(const AValue: TTerminalOutputEvent);
begin
  FOnOutput := AValue;
end;

function TConPtyShell.GetOnProcessExit: TTerminalExitEvent;
begin
  Result := FOnProcessExit;
end;

procedure TConPtyShell.SetOnProcessExit(const AValue: TTerminalExitEvent);
begin
  FOnProcessExit := AValue;
end;

end.
