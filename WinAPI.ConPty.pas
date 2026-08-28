unit WinAPI.ConPty;

interface

uses
  WinAPI.Windows;

const
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = $00020016;
  PSEUDOCONSOLE_INHERIT_CURSOR = $00000001;
  CONPTY_MIN_BUILD = 18362;

{$IF not Declared(EXTENDED_STARTUPINFO_PRESENT)}
  EXTENDED_STARTUPINFO_PRESENT = $00080000;
{$IFEND}

type
  HPCON = THandle;
  PHPCON = ^HPCON;
  LPPROC_THREAD_ATTRIBUTE_LIST = type Pointer;
  PSIZE_T = ^SIZE_T;

  PStartupInfoExW = ^TStartupInfoExW;
  TStartupInfoExW = record
    StartupInfo: TStartupInfoW;
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST;
  end;

  TCreatePseudoConsoleFunc = function(size: TCoord; hInput, hOutput: THandle;
    dwFlags: DWORD; out phPC: HPCON): HRESULT; stdcall;
  TResizePseudoConsoleFunc = function(hPC: HPCON; size: TCoord): HRESULT; stdcall;
  TClosePseudoConsoleFunc = procedure(hPC: HPCON); stdcall;
  TInitializeProcThreadAttributeListFunc = function(
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST;
    dwAttributeCount: DWORD; dwFlags: DWORD;
    lpSize: PSIZE_T): BOOL; stdcall;
  TUpdateProcThreadAttributeFunc = function(
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST;
    dwFlags: DWORD; dwAttribute: DWORD_PTR;
    lpValue: Pointer; cbSize: SIZE_T;
    lpPreviousValue: Pointer; lpReturnSize: PSIZE_T): BOOL; stdcall;
  TDeleteProcThreadAttributeListFunc = procedure(
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST); stdcall;

  TConPtyAPI = record
    CreatePseudoConsole: TCreatePseudoConsoleFunc;
    ResizePseudoConsole: TResizePseudoConsoleFunc;
    ClosePseudoConsole: TClosePseudoConsoleFunc;
    InitializeProcThreadAttributeList: TInitializeProcThreadAttributeListFunc;
    UpdateProcThreadAttribute: TUpdateProcThreadAttributeFunc;
    DeleteProcThreadAttributeList: TDeleteProcThreadAttributeListFunc;
    function Initialize: Boolean;
    function IsAvailable: Boolean;
  end;

function ConPtyBuildSupported(ABuildNumber: DWORD): Boolean;
function GetWindowsBuildNumber: DWORD;

{$IF not Declared(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)}
const
  JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $00002000;
  JobObjectExtendedLimitInformation = 9;

type
  TIOCounters = record
    ReadOperationCount: UInt64;
    WriteOperationCount: UInt64;
    OtherOperationCount: UInt64;
    ReadTransferCount: UInt64;
    WriteTransferCount: UInt64;
    OtherTransferCount: UInt64;
  end;

  TJobObjectBasicLimitInformation = record
    PerProcessUserTimeLimit: Int64;
    PerJobUserTimeLimit: Int64;
    LimitFlags: DWORD;
    MinimumWorkingSetSize: SIZE_T;
    MaximumWorkingSetSize: SIZE_T;
    ActiveProcessLimit: DWORD;
    Affinity: ULONG_PTR;
    PriorityClass: DWORD;
    SchedulingClass: DWORD;
  end;

  TJobObjectExtendedLimitInformation = record
    BasicLimitInformation: TJobObjectBasicLimitInformation;
    IoInfo: TIOCounters;
    ProcessMemoryLimit: SIZE_T;
    JobMemoryLimit: SIZE_T;
    PeakProcessMemoryUsed: SIZE_T;
    PeakJobMemoryUsed: SIZE_T;
  end;

function CreateJobObject(lpJobAttributes: PSecurityAttributes; lpName: PWideChar): THandle; stdcall; external kernel32 name 'CreateJobObjectW';
function SetInformationJobObject(hJob: THandle; JobObjectInfoClass: DWORD; lpJobObjectInfo: Pointer; cbJobObjectInfoLength: DWORD): BOOL; stdcall; external kernel32 name 'SetInformationJobObject';
function AssignProcessToJobObject(hJob, hProcess: THandle): BOOL; stdcall; external kernel32 name 'AssignProcessToJobObject';
{$IFEND}

var
  ConPtyAPI: TConPtyAPI;

implementation

function RtlGetVersion(lpVersionInformation: pointer): NTSTATUS; stdcall;
  external 'ntdll.dll' name 'RtlGetVersion';

type
  RTL_OSVERSIONINFOW = record
    dwOSVersionInfoSize: DWORD;
    dwMajorVersion: DWORD;
    dwMinorVersion: DWORD;
    dwBuildNumber: DWORD;
    dwPlatformId: DWORD;
    szCSDVersion: array[0..127] of WideChar;
  end;

function GetWindowsBuildNumber: DWORD;
var
  osvi: RTL_OSVERSIONINFOW;
begin
  FillChar(osvi, SizeOf(osvi), 0);
  osvi.dwOSVersionInfoSize := SizeOf(osvi);
  if RtlGetVersion(@osvi) = 0 then
    Result := osvi.dwBuildNumber
  else
    Result := 0;
end;

function ConPtyBuildSupported(ABuildNumber: DWORD): Boolean;
begin
  Result := ABuildNumber >= CONPTY_MIN_BUILD;
end;

{ TConPtyAPI }

function TConPtyAPI.Initialize: Boolean;
var
  hKernel: HMODULE;
begin
  if IsAvailable then
    Exit(True);

  if not ConPtyBuildSupported(GetWindowsBuildNumber) then
    Exit(False);

  hKernel := GetModuleHandle('kernel32.dll');
  if hKernel = 0 then
    Exit(False);

  @CreatePseudoConsole := GetProcAddress(hKernel, 'CreatePseudoConsole');
  @ResizePseudoConsole := GetProcAddress(hKernel, 'ResizePseudoConsole');
  @ClosePseudoConsole := GetProcAddress(hKernel, 'ClosePseudoConsole');
  @InitializeProcThreadAttributeList := GetProcAddress(hKernel, 'InitializeProcThreadAttributeList');
  @UpdateProcThreadAttribute := GetProcAddress(hKernel, 'UpdateProcThreadAttribute');
  @DeleteProcThreadAttributeList := GetProcAddress(hKernel, 'DeleteProcThreadAttributeList');

  Result := IsAvailable;
end;

function TConPtyAPI.IsAvailable: Boolean;
begin
  Result := Assigned(CreatePseudoConsole) and
            Assigned(ResizePseudoConsole) and
            Assigned(ClosePseudoConsole) and
            Assigned(InitializeProcThreadAttributeList) and
            Assigned(UpdateProcThreadAttribute) and
            Assigned(DeleteProcThreadAttributeList);
end;

end.
