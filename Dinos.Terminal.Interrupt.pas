unit Dinos.Terminal.Interrupt;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils,
  Dinos.Terminal.Debug;

const
  LLKHF_CONTROL = $0008;

type
  TKBDLLHOOKSTRUCT = record
    vkCode: DWORD;
    scanCode: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: ULONG_PTR;
  end;
  PKBDLLHOOKSTRUCT = ^TKBDLLHOOKSTRUCT;

  TInterruptProc = procedure of object;

  TInterruptManager = class
  private
    FHook: HHOOK;
    FEnabled: Boolean;
    FOnInterrupt: TInterruptProc;
    class var FInstance: TInterruptManager;
    class function LowLevelKeyboardProc(nCode: Integer; wParam: WPARAM;
      lParam: LPARAM): LRESULT; stdcall; static;
    procedure DoInterrupt;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Install;
    procedure Uninstall;
    property Enabled: Boolean read FEnabled;
    property OnInterrupt: TInterruptProc read FOnInterrupt write FOnInterrupt;
    class function Instance: TInterruptManager;
  end;

implementation

class function TInterruptManager.LowLevelKeyboardProc(nCode: Integer; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  Kbd: PKBDLLHOOKSTRUCT;
  CtrlDown: Boolean;
begin
  Result := CallNextHookEx(0, nCode, wParam, lParam);
  if nCode = HC_ACTION then
  begin
    Kbd := PKBDLLHOOKSTRUCT(lParam);
    if (wParam = WM_KEYDOWN) or (wParam = WM_SYSKEYDOWN) or
       (wParam = WM_KEYUP) or (wParam = WM_SYSKEYUP) then
    begin
      if (Kbd.vkCode = VK_PAUSE) or (Kbd.vkCode = VK_CANCEL) or
         (Kbd.vkCode = VK_SCROLL) then
      begin
        CtrlDown := (Kbd.flags and LLKHF_CONTROL) <> 0;
        Log('HookKey: vk=' + IntToHex(Kbd.vkCode, 2) +
            ' ctrl=' + BoolToStr(CtrlDown, True) +
            ' flags=' + IntToHex(Kbd.flags, 8) +
            ' msg=' + IntToHex(wParam, 4));
        if ((Kbd.vkCode = VK_PAUSE) or (Kbd.vkCode = VK_CANCEL)) and
           CtrlDown then
        begin
          if Assigned(FInstance) then
            FInstance.DoInterrupt;
          Result := 1;
        end
        else if Kbd.vkCode = VK_CANCEL then
        begin
          if Assigned(FInstance) then
            FInstance.DoInterrupt;
          Result := 1;
        end;
      end;
    end;
  end;
end;

constructor TInterruptManager.Create;
begin
  inherited Create;
  FHook := 0;
  FEnabled := False;
end;

destructor TInterruptManager.Destroy;
begin
  Uninstall;
  if FInstance = Self then
    FInstance := nil;
  inherited;
end;

procedure TInterruptManager.DoInterrupt;
begin
  if Assigned(FOnInterrupt) then
    FOnInterrupt;
end;

procedure TInterruptManager.Install;
begin
  if FEnabled then Exit;
  if FInstance = nil then
    FInstance := Self
  else if FInstance <> Self then
    Exit;
  FHook := SetWindowsHookEx(WH_KEYBOARD_LL, @TInterruptManager.LowLevelKeyboardProc,
                            GetModuleHandle(nil), 0);
  if FHook <> 0 then
  begin
    FEnabled := True;
    Log('KeyHook installed OK, handle=' + IntToStr(NativeInt(FHook)));
  end
  else
    Log('KeyHook FAILED, error=' + IntToStr(GetLastError));
end;

procedure TInterruptManager.Uninstall;
begin
  if not FEnabled then Exit;
  if FHook <> 0 then
  begin
    UnhookWindowsHookEx(FHook);
    FHook := 0;
  end;
  FEnabled := False;
  if FInstance = Self then
    FInstance := nil;
end;

class function TInterruptManager.Instance: TInterruptManager;
begin
  if FInstance = nil then
    FInstance := TInterruptManager.Create;
  Result := FInstance;
end;

initialization

finalization
  FreeAndNil(TInterruptManager.FInstance);

end.
