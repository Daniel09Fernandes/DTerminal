unit Dinos.Terminal.CmdShell;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Dinos.Terminal.Pty, Dinos.Terminal.ConPtyShell;

type
  TCmdShellProcess = class(TInterfacedObject, ITerminalProcess)
  private
    FProcess: TProcessInformation;
    FOutputRead: THandle;
    FInputWrite: THandle;
    FOnOutput: TTerminalOutputEvent;
    FOnProcessExit: TTerminalExitEvent;
    FActive: Boolean;
    procedure InternalStart(const ACommand: string; const ASize: TTerminalSize);
    function GetOnOutput: TTerminalOutputEvent;
    procedure SetOnOutput(const AValue: TTerminalOutputEvent);
    function GetOnProcessExit: TTerminalExitEvent;
    procedure SetOnProcessExit(const AValue: TTerminalExitEvent);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const ACommand: string; const ASize: TTerminalSize);
    procedure WriteInput(const AData: string);
    procedure SendInterrupt;
    procedure Resize(const ASize: TTerminalSize);
    procedure Terminate;
    function IsRunning: Boolean;
    function HasForegroundChild: Boolean;
  end;

implementation

{ TCmdShellProcess }

constructor TCmdShellProcess.Create;
begin
  inherited Create;
  FActive := False;
  FillChar(FProcess, SizeOf(FProcess), 0);
end;

destructor TCmdShellProcess.Destroy;
begin
  Terminate;
  inherited;
end;

procedure TCmdShellProcess.InternalStart(const ACommand: string; const ASize: TTerminalSize);
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  piProcess: TProcessInformation;
  hOutputReadTmp, hInputWriteTmp: THandle;
  CmdLine: string;
begin
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(hOutputReadTmp, FInputWrite, @SA, 0) then
    raise Exception.Create('CreatePipe failed for input');

  if not CreatePipe(FOutputRead, hInputWriteTmp, @SA, 0) then
    raise Exception.Create('CreatePipe failed for output');

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
  SI.wShowWindow := SW_HIDE;
  SI.hStdInput := hOutputReadTmp;
  SI.hStdOutput := hInputWriteTmp;
  SI.hStdError := hInputWriteTmp;

  CmdLine := 'cmd.exe';
  if ACommand <> '' then
    CmdLine := ACommand;

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, SI, piProcess) then
    raise Exception.Create('CreateProcess failed');

  CloseHandle(hOutputReadTmp);
  CloseHandle(hInputWriteTmp);

  FProcess := piProcess;
  FActive := True;
end;

procedure TCmdShellProcess.Start(const ACommand: string; const ASize: TTerminalSize);
begin
  InternalStart(ACommand, ASize);
end;

procedure TCmdShellProcess.WriteInput(const AData: string);
var
  BytesWritten: DWORD;
  Buf: TBytes;
begin
  if not FActive then Exit;
  Buf := TEncoding.UTF8.GetBytes(AData);
  WriteFile(FInputWrite, Buf[0], Length(Buf), BytesWritten, nil);
end;

procedure TCmdShellProcess.SendInterrupt;
begin
  WriteInput(#3);
end;

procedure TCmdShellProcess.Resize(const ASize: TTerminalSize);
begin
end;

procedure TCmdShellProcess.Terminate;
begin
  if not FActive then Exit;
  FActive := False;

  if FProcess.hProcess <> 0 then
  begin
    TerminateProcess(FProcess.hProcess, 0);
    CloseHandle(FProcess.hProcess);
  end;
  if FProcess.hThread <> 0 then
    CloseHandle(FProcess.hThread);
  if FOutputRead <> 0 then
    CloseHandle(FOutputRead);
  if FInputWrite <> 0 then
    CloseHandle(FInputWrite);

  FillChar(FProcess, SizeOf(FProcess), 0);
  FOutputRead := 0;
  FInputWrite := 0;
end;

function TCmdShellProcess.IsRunning: Boolean;
begin
  Result := FActive;
end;

function TCmdShellProcess.HasForegroundChild: Boolean;
begin
  Result := False;
end;

function TCmdShellProcess.GetOnOutput: TTerminalOutputEvent;
begin
  Result := FOnOutput;
end;

procedure TCmdShellProcess.SetOnOutput(const AValue: TTerminalOutputEvent);
begin
  FOnOutput := AValue;
end;

function TCmdShellProcess.GetOnProcessExit: TTerminalExitEvent;
begin
  Result := FOnProcessExit;
end;

procedure TCmdShellProcess.SetOnProcessExit(const AValue: TTerminalExitEvent);
begin
  FOnProcessExit := AValue;
end;

end.
