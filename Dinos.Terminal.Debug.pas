unit Dinos.Terminal.Debug;

interface

uses
  System.Classes, System.SyncObjs, SysUtils;

Var LogTerminalDebugIsActive: Boolean;

procedure Log(const AMsg: string);
procedure LogException(const AScope: string; E: Exception);
procedure InstallExceptionHandler;

implementation

type
  TExceptProc = procedure(E: Exception; Base: Exception);

var
  LogFile: string;
  OldExceptionHandler: TExceptProc;
  LogLock: TCriticalSection;

procedure Log(const AMsg: string);
var
  F: TextFile;
begin
  if not LogTerminalDebugIsActive then Exit;
  
  try
    LogLock.Enter;
    try
      if LogFile = '' then
        LogFile := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'DinosTerminal.log';
      AssignFile(F, LogFile);
      if FileExists(LogFile) then
        Append(F)
      else
        Rewrite(F);
      try
        WriteLn(F, FormatDateTime('hh:nn:ss.zzz', Now) + ' | ' + AMsg);
      finally
        CloseFile(F);
      end;
    finally
      LogLock.Leave;
    end;
  except
  end;
end;

procedure LogException(const AScope: string; E: Exception);
var
  Msg: string;
begin
  if E <> nil then
    Msg := E.ClassName + ': ' + E.Message
  else
    Msg := 'Unknown exception';
  Log('EXCEPTION in ' + AScope + ' | ' + Msg);
end;

procedure DinosTerminalExceptionHandler(E: Exception; Base: Exception);
begin
  LogException('GlobalHandler', E);
  if Assigned(OldExceptionHandler) then
    OldExceptionHandler(E, Base);
end;

procedure InstallExceptionHandler;
begin
  OldExceptionHandler := TExceptProc(ExceptProc);
  ExceptProc := @DinosTerminalExceptionHandler;
  Log('Global exception handler installed');
end;

initialization
  LogFile := '';
  LogLock := TCriticalSection.Create;
  Log('=== DinosTerminal BPL loaded ===');
  InstallExceptionHandler;

finalization
  Log('=== DinosTerminal BPL unloaded ===');
  LogLock.Free;

end.
