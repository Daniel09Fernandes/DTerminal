unit Dinos.Terminal.CmdShell;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Dinos.Terminal.Pty, Dinos.Terminal.ConPtyShell, Dinos.Terminal.ConPtyReader,
  Dinos.Terminal.Debug;

type
  TCmdShellProcess = class(TInterfacedObject, ITerminalProcess)
  private
    FProcess: TProcessInformation;
    FOutputRead: THandle;
    FInputWrite: THandle;
    FReader: TConPtyReader;
    FExitWatcher: TThread;
    FOnOutput: TTerminalOutputEvent;
    FOnProcessExit: TTerminalExitEvent;
    FActive: Boolean;
    FExited: Boolean;
    FTerminating: Boolean;
    procedure InternalStart(const ACommand: string);
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
    procedure Start(const ACommand: string; const ASize: TTerminalSize);
    procedure WriteInput(const AData: string);
    procedure SendInterrupt;
    procedure Resize(const ASize: TTerminalSize);
    procedure Terminate;
    function IsRunning: Boolean;
    function HasForegroundChild: Boolean;
  end;

implementation

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

{ TCmdShellProcess }

constructor TCmdShellProcess.Create;
begin
  inherited Create;
  FActive := False;
  FExited := False;
  FTerminating := False;
  FOutputRead := INVALID_HANDLE_VALUE;
  FInputWrite := INVALID_HANDLE_VALUE;
  FillChar(FProcess, SizeOf(FProcess), 0);
end;

destructor TCmdShellProcess.Destroy;
begin
  Terminate;
  inherited;
end;

procedure TCmdShellProcess.InternalStart(const ACommand: string);
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  ChildStdInRead, ChildStdOutWrite: THandle;
  CmdLine: string;
  LErr: DWORD;
begin
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  ChildStdInRead := 0;
  ChildStdOutWrite := 0;
  FInputWrite := INVALID_HANDLE_VALUE;
  FOutputRead := INVALID_HANDLE_VALUE;

  if not CreatePipe(ChildStdInRead, FInputWrite, @SA, 0) then
    raise Exception.Create('CreatePipe failed for input');

  if not CreatePipe(FOutputRead, ChildStdOutWrite, @SA, 0) then
  begin
    CloseHandle(ChildStdInRead);
    CloseHandle(FInputWrite);
    FInputWrite := INVALID_HANDLE_VALUE;
    raise Exception.Create('CreatePipe failed for output');
  end;

  SetHandleInformation(FInputWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(FOutputRead, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
  SI.wShowWindow := SW_HIDE;
  SI.hStdInput := ChildStdInRead;
  SI.hStdOutput := ChildStdOutWrite;
  SI.hStdError := ChildStdOutWrite;

  CmdLine := ACommand;
  if CmdLine = '' then
    CmdLine := 'cmd.exe';
  UniqueString(CmdLine);

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, SI, FProcess) then
  begin
    LErr := GetLastError;
    CloseHandle(ChildStdInRead);
    CloseHandle(ChildStdOutWrite);
    CloseHandle(FInputWrite);
    CloseHandle(FOutputRead);
    FInputWrite := INVALID_HANDLE_VALUE;
    FOutputRead := INVALID_HANDLE_VALUE;
    FillChar(FProcess, SizeOf(FProcess), 0);
    raise Exception.Create('CreateProcess failed, GetLastError=' + IntToStr(LErr));
  end;

  CloseHandle(ChildStdInRead);
  CloseHandle(ChildStdOutWrite);

  FActive := True;
  Log('TCmdShellProcess.InternalStart: process started, hProcess=' +
    IntToStr(FProcess.hProcess));
end;

procedure TCmdShellProcess.Start(const ACommand: string; const ASize: TTerminalSize);
begin
  Log('TCmdShellProcess.Start: "' + ACommand + '"');
  if FActive then
    Exit;
  FTerminating := False;
  FExited := False;

  InternalStart(ACommand);

  FReader := TConPtyReader.Create(FOutputRead);
  FReader.OnOutput := FOnOutput;
  FReader.OnTerminated := HandleReaderExit;
  StartExitWatcher;
  Log('TCmdShellProcess.Start: done');
end;

procedure TCmdShellProcess.StartExitWatcher;
begin
  FExitWatcher := TProcessExitWatcher.Create(FProcess.hProcess, HandleChildExit);
end;

procedure TCmdShellProcess.WriteInput(const AData: string);
var
  BytesWritten: DWORD;
  Buf: TBytes;
begin
  if FExited or (FInputWrite = INVALID_HANDLE_VALUE) or (AData = '') then
    Exit;
  Buf := TEncoding.UTF8.GetBytes(AData);
  if Length(Buf) > 0 then
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
  if FTerminating then
    Exit;
  FTerminating := True;
  FActive := False;

  if Assigned(FExitWatcher) then
  begin
    FExitWatcher.Terminate;
    FExitWatcher.WaitFor;
    TThread.RemoveQueuedEvents(FExitWatcher);
    FreeAndNil(FExitWatcher);
  end;

  if Assigned(FReader) then
    FReader.Terminate;

  if FProcess.hProcess <> 0 then
  begin
    TerminateProcess(FProcess.hProcess, 0);
    CloseHandle(FProcess.hProcess);
    FProcess.hProcess := 0;
  end;
  if FProcess.hThread <> 0 then
  begin
    CloseHandle(FProcess.hThread);
    FProcess.hThread := 0;
  end;
  if FInputWrite <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FInputWrite);
    FInputWrite := INVALID_HANDLE_VALUE;
  end;
  if FOutputRead <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FOutputRead);
    FOutputRead := INVALID_HANDLE_VALUE;
  end;

  FreeAndNil(FReader);
end;

procedure TCmdShellProcess.HandleReaderExit;
begin
  DoChildExit;
end;

procedure TCmdShellProcess.HandleChildExit;
begin
  DoChildExit;
end;

procedure TCmdShellProcess.DoChildExit;
begin
  if FExited or FTerminating then
    Exit;
  FExited := True;
  FActive := False;
  if Assigned(FOnProcessExit) then
    FOnProcessExit;
end;

function TCmdShellProcess.IsRunning: Boolean;
begin
  Result := FActive and not FExited;
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
  if Assigned(FReader) then
    FReader.OnOutput := AValue;
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
