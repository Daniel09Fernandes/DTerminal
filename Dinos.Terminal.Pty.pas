unit Dinos.Terminal.Pty;

interface

uses
  Winapi.Windows, WinAPI.ConPty, System.NetEncoding;

type
  TTerminalSize = record
    Cols: SmallInt;
    Rows: SmallInt;
  end;

  TConPty = class
  private
    FhPC: HPCON;
    FInputWrite: THandle;
    FOutputRead: THandle;
    FProcessInfo: TProcessInformation;
    FIsRunning: Boolean;
    FSize: TCoord;
    FJob: THandle;
    function BuildStartupInfo(out ASI: TStartupInfoExW): Boolean;
    procedure FreeStartupInfo(var ASI: TStartupInfoExW);
  public
    constructor Create;
    destructor Destroy; override;

    function Start(const ACommandLine, AWorkDir: string; const ASize: TTerminalSize): Boolean;
    function Resize(const ASize: TTerminalSize): Boolean;
    function ActiveProcessCount: Integer;

    procedure WriteInput(const AData: string);
    procedure Close;

    property InputWrite: THandle read FInputWrite;
    property OutputRead: THandle read FOutputRead;
    property ProcessHandle: THandle read FProcessInfo.hProcess;
    property IsRunning: Boolean read FIsRunning;
    property JobHandle: THandle read FJob;
  end;

const
  DefaultTerminalSize: TTerminalSize = (Cols: 80; Rows: 24);

implementation

uses
  System.SysUtils, Dinos.Terminal.Debug;

constructor TConPty.Create;
begin
  inherited Create;
  FInputWrite := INVALID_HANDLE_VALUE;
  FOutputRead := INVALID_HANDLE_VALUE;
  FIsRunning := False;
  FJob := 0;
  FillChar(FProcessInfo, SizeOf(FProcessInfo), 0);
end;

destructor TConPty.Destroy;
begin
  Close;
  inherited;
end;

function TConPty.BuildStartupInfo(out ASI: TStartupInfoExW): Boolean;
var
  LSize: SIZE_T;
begin
  Result := False;
  ZeroMemory(@ASI, SizeOf(ASI));
  ASI.StartupInfo.cb := SizeOf(TStartupInfoExW);

  LSize := 0;
  ConPtyAPI.InitializeProcThreadAttributeList(nil, 1, 0, @LSize);
  if LSize = 0 then
  begin
    Log('TConPty.BuildStartupInfo: first InitializeProcThreadAttributeList returned LSize=0, GetLastError=' + IntToStr(GetLastError));
    Exit;
  end;
  Log('TConPty.BuildStartupInfo: required attribute list size=' + IntToStr(LSize));

  ASI.lpAttributeList := AllocMem(LSize);
  if not Assigned(ASI.lpAttributeList) then
  begin
    Log('TConPty.BuildStartupInfo: AllocMem FAILED');
    Exit;
  end;

  if not ConPtyAPI.InitializeProcThreadAttributeList(ASI.lpAttributeList, 1, 0, @LSize) then
  begin
    Log('TConPty.BuildStartupInfo: second InitializeProcThreadAttributeList FAILED, GetLastError=' + IntToStr(GetLastError));
    FreeMem(ASI.lpAttributeList);
    ASI.lpAttributeList := nil;
    Exit;
  end;

  Log('TConPty.BuildStartupInfo: UpdateProcThreadAttribute hPC=' + IntToStr(FhPC) + ' hPC size=' + IntToStr(SizeOf(FhPC)));
  if not ConPtyAPI.UpdateProcThreadAttribute(
    ASI.lpAttributeList, 0,
    PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
    Pointer(FhPC), SizeOf(FhPC), nil, nil) then
  begin
    Log('TConPty.BuildStartupInfo: UpdateProcThreadAttribute FAILED, GetLastError=' + IntToStr(GetLastError));
    ConPtyAPI.DeleteProcThreadAttributeList(ASI.lpAttributeList);
    FreeMem(ASI.lpAttributeList);
    ASI.lpAttributeList := nil;
    Exit;
  end;

  Result := True;
  Log('TConPty.BuildStartupInfo: OK');
end;

procedure TConPty.FreeStartupInfo(var ASI: TStartupInfoExW);
begin
  if Assigned(ASI.lpAttributeList) then
  begin
    ConPtyAPI.DeleteProcThreadAttributeList(ASI.lpAttributeList);
    FreeMem(ASI.lpAttributeList);
    ASI.lpAttributeList := nil;
  end;
end;

function TConPty.Start(const ACommandLine, AWorkDir: string; const ASize: TTerminalSize): Boolean;
var
  LPtyInputRead, LPtyOutputWrite: THandle;
  LSI: TStartupInfoExW;
  LCmd: string;
  LWorkDir: PChar;
  LResult: HRESULT;
  LJobInfo: TJobObjectExtendedLimitInformation;
  LErr: DWORD;
  LExitCode: DWORD;
  LAlive: BOOL;
  LPipeAvail: DWORD;
  LPipeTotal: DWORD;
  LBuf: TBytes;
  LPeekRead: DWORD;
  LPeekText: string;
begin
  Result := False;
  if FIsRunning then
  begin
    Log('TConPty.Start: already running, abort');
    Exit;
  end;

  Log('TConPty.Start: cmdline="' + ACommandLine + '" workdir="' + AWorkDir + '"');
  Log('TConPty.Start: size cols=' + IntToStr(ASize.Cols) + ' rows=' + IntToStr(ASize.Rows));

  if not ConPtyAPI.Initialize then
  begin
    Log('TConPty.Start: ConPtyAPI.Initialize FAILED, GetLastError=' + IntToStr(GetLastError));
    Exit;
  end;
  Log('TConPty.Start: ConPtyAPI.Initialize OK');

  FSize.X := ASize.Cols;
  FSize.Y := ASize.Rows;

  FInputWrite := INVALID_HANDLE_VALUE;
  FOutputRead := INVALID_HANDLE_VALUE;

  if not CreatePipe(LPtyInputRead, FInputWrite, nil, 0) then
  begin
    Log('TConPty.Start: CreatePipe(INPUT) FAILED, GetLastError=' + IntToStr(GetLastError));
    Exit;
  end;
  Log('TConPty.Start: CreatePipe(INPUT) OK, ptyRead=' + IntToStr(LPtyInputRead) + ' inputWrite=' + IntToStr(FInputWrite));

  if not CreatePipe(FOutputRead, LPtyOutputWrite, nil, 0) then
  begin
    Log('TConPty.Start: CreatePipe(OUTPUT) FAILED, GetLastError=' + IntToStr(GetLastError));
    CloseHandle(LPtyInputRead);
    CloseHandle(FInputWrite);
    FInputWrite := INVALID_HANDLE_VALUE;
    Exit;
  end;
  Log('TConPty.Start: CreatePipe(OUTPUT) OK, outputRead=' + IntToStr(FOutputRead) + ' ptyWrite=' + IntToStr(LPtyOutputWrite));

  LResult := ConPtyAPI.CreatePseudoConsole(FSize, LPtyInputRead, LPtyOutputWrite, 0, FhPC);
  Log('TConPty.Start: CreatePseudoConsole HR=' + IntToHex(NativeUInt(LResult), 8) + ' hPC=' + IntToStr(FhPC));

  CloseHandle(LPtyInputRead);
  CloseHandle(LPtyOutputWrite);
  Log('TConPty.Start: closed pty-side handles');

  if Failed(LResult) then
  begin
    Log('TConPty.Start: CreatePseudoConsole FAILED, cleaning up');
    CloseHandle(FInputWrite);
    CloseHandle(FOutputRead);
    FInputWrite := INVALID_HANDLE_VALUE;
    FOutputRead := INVALID_HANDLE_VALUE;
    FhPC := 0;
    Exit;
  end;

  if not BuildStartupInfo(LSI) then
  begin
    Log('TConPty.Start: BuildStartupInfo FAILED, GetLastError=' + IntToStr(GetLastError));
    Close;
    Exit;
  end;
  Log('TConPty.Start: BuildStartupInfo OK');

  LCmd := ACommandLine;
  UniqueString(LCmd);
  if AWorkDir <> '' then
    LWorkDir := PChar(AWorkDir)
  else
    LWorkDir := nil;

  FJob := CreateJobObject(nil, nil);
  Log('TConPty.Start: CreateJobObject handle=' + IntToStr(FJob));
  if FJob <> 0 then
  begin
    ZeroMemory(@LJobInfo, SizeOf(LJobInfo));
    LJobInfo.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(FJob, JobObjectExtendedLimitInformation, @LJobInfo, SizeOf(LJobInfo));
  end;

  Result := CreateProcess(
    nil,
    PChar(LCmd),
    nil, nil,
    False,
    EXTENDED_STARTUPINFO_PRESENT or CREATE_SUSPENDED,
    nil,
    LWorkDir,
    LSI.StartupInfo,
    FProcessInfo
  );

  LErr := GetLastError;
  FreeStartupInfo(LSI);

  if Result then
  begin
    Log('TConPty.Start: CreateProcess OK, hProcess=' + IntToStr(FProcessInfo.hProcess) + ' hThread=' + IntToStr(FProcessInfo.hThread));
    if FJob <> 0 then
    begin
      if not AssignProcessToJobObject(FJob, FProcessInfo.hProcess) then
        Log('TConPty.Start: AssignProcessToJobObject FAILED, GetLastError=' + IntToStr(GetLastError))
      else
        Log('TConPty.Start: AssignProcessToJobObject OK');
    end;
    ResumeThread(FProcessInfo.hThread);
    Log('TConPty.Start: ResumeThread called, FIsRunning=True');
    FIsRunning := True;

    Sleep(500);
    LAlive := GetExitCodeProcess(FProcessInfo.hProcess, LExitCode);
    Log('TConPty.Start: after 500ms, alive=' + BoolToStr(LAlive, True) + ' exitCode=' + IntToStr(LExitCode));
    LPipeAvail := 0;
    LPipeTotal := 0;
    LPeekRead := 0;
    SetLength(LBuf, 4096);
    PeekNamedPipe(FOutputRead, @LBuf[0], Length(LBuf), @LPeekRead, @LPipeAvail, @LPipeTotal);
    Log('TConPty.Start: after 500ms, peekRead=' + IntToStr(LPeekRead) + ' available=' + IntToStr(LPipeAvail) + ' total=' + IntToStr(LPipeTotal));
    if LPeekRead > 0 then
    begin
      LPeekText := TEncoding.UTF8.GetString(LBuf, 0, LPeekRead);
      Log('TConPty.Start: after 500ms, peeked=' + IntToStr(LPeekRead) + ' bytes: "' + LPeekText + '"');
    end;
  end
  else
  begin
    Log('TConPty.Start: CreateProcess FAILED, GetLastError=' + IntToStr(LErr));
    Close;
  end;
end;

function TConPty.Resize(const ASize: TTerminalSize): Boolean;
var
  LSize: TCoord;
begin
  Result := False;
  if (FhPC = 0) or (not Assigned(ConPtyAPI.ResizePseudoConsole)) then
  begin
    Log('TConPty.Resize: skipped (no hPC / no api)');
    Exit;
  end;
  if (ASize.Cols = FSize.X) and (ASize.Rows = FSize.Y) then
    Exit;
  Log('TConPty.Resize: cols=' + IntToStr(ASize.Cols) + ' rows=' + IntToStr(ASize.Rows));
  LSize.X := ASize.Cols;
  LSize.Y := ASize.Rows;
  Result := Succeeded(ConPtyAPI.ResizePseudoConsole(FhPC, LSize));
  if Result then
    FSize := LSize;
end;

function TConPty.ActiveProcessCount: Integer;
var
  Count: DWORD;
  BytesReturned: DWORD;
begin
  Result := -1;
  if FJob = 0 then Exit;
  Count := 0;
  BytesReturned := 0;
  if QueryInformationJobObject(FJob, JobObjectBasicProcessIdList, @Count, SizeOf(Count), @BytesReturned) then
    Result := Count
  else
    Result := -1;
end;

procedure TConPty.WriteInput(const AData: string);
var
  LBytes: TBytes;
  LWritten: DWORD;
  LSuccess: BOOL;
begin
  if (FInputWrite = INVALID_HANDLE_VALUE) or (AData = '') then
    Exit;
  LBytes := TEncoding.UTF8.GetBytes(AData);
  if Length(LBytes) > 0 then
  begin
    LSuccess := WriteFile(FInputWrite, LBytes[0], Length(LBytes), LWritten, nil);
    Log('TConPty.WriteInput: ' + IntToStr(Length(LBytes)) + ' bytes, written=' + IntToStr(LWritten) + ' ok=' + BoolToStr(LSuccess, True));
  end;
end;

procedure TConPty.Close;
var
  LWaitResult: DWORD;
begin
  Log('TConPty.Close: beginning shutdown');
  FIsRunning := False;

  if FInputWrite <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FInputWrite);
    FInputWrite := INVALID_HANDLE_VALUE;
    Log('TConPty.Close: closed InputWrite');
  end;

  if FhPC <> 0 then
  begin
    if Assigned(ConPtyAPI.ClosePseudoConsole) then
      ConPtyAPI.ClosePseudoConsole(FhPC);
    FhPC := 0;
    Log('TConPty.Close: closed PseudoConsole');
  end;

  if FOutputRead <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FOutputRead);
    FOutputRead := INVALID_HANDLE_VALUE;
    Log('TConPty.Close: closed OutputRead');
  end;

  if FJob <> 0 then
  begin
    CloseHandle(FJob);
    FJob := 0;
    Log('TConPty.Close: closed Job');
  end;

  if FProcessInfo.hProcess <> 0 then
  begin
    LWaitResult := WaitForSingleObject(FProcessInfo.hProcess, 5000);
    Log('TConPty.Close: WaitForProcess=' + IntToStr(LWaitResult));
    if LWaitResult <> WAIT_OBJECT_0 then
      TerminateProcess(FProcessInfo.hProcess, 0);
    CloseHandle(FProcessInfo.hProcess);
    FProcessInfo.hProcess := 0;
  end;
  if FProcessInfo.hThread <> 0 then
  begin
    CloseHandle(FProcessInfo.hThread);
    FProcessInfo.hThread := 0;
  end;
  Log('TConPty.Close: done');
end;

end.
