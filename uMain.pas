unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, System.Generics.Collections,
  Vcl.Menus, Clipbrd,
  Dinos.Terminal.Frame, Dinos.Terminal.ScreenBuffer,
  Dinos.Terminal.ConPtyShell, Dinos.Terminal.Pty,
  Dinos.Terminal.Interrupt,
  Dinos.Terminal.Debug,
  DesignIntf, ToolsAPI, DockForm, Vcl.ActnList, Vcl.ImgList, System.IniFiles,
  Vcl.AppEvnts, ShellAPI;

type
  TTypeTerminal = (tWSL, tCMD, tPowerShell);

  TManangerTerminal = class(TDockableForm, INTACustomDockableForm)
    PgTerminal: TPageControl;
    TabDefault: TTabSheet;
    PopTerminal: TPopupMenu;
    NewTerminal: TMenuItem;
    CMD1: TMenuItem;
    WSL1: TMenuItem;
    PowerShell1: TMenuItem;
    Renomear1: TMenuItem;
    Excluir1: TMenuItem;
    Copy1: TMenuItem;
    Past1: TMenuItem;
    N1: TMenuItem;
    N2: TMenuItem;
    EnableLogs1: TMenuItem;
    OpenLogFile1: TMenuItem;
    procedure FormShow(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure CMD1Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Excluir1Click(Sender: TObject);
    procedure Renomear1Click(Sender: TObject);
    procedure TabDefaultEnter(Sender: TObject);
    procedure Copy1Click(Sender: TObject);
    procedure Past1Click(Sender: TObject);
    procedure EnableLogs1Click(Sender: TObject);
    procedure OpenLogFile1Click(Sender: TObject);
  private
    FTerminals: TObjectList<TTerminalFrame>;
    FActivePosition: Integer;
    FActiveProcess: ITerminalProcess;
    FInterruptInstalled: Boolean;
    FStatusBar: TStatusBar;
    procedure AddTerminal(ATabParent: TTabSheet; ATypeTerminal: TTypeTerminal);
    procedure StartProcessForFrame(AFrame: TTerminalFrame; ATypeTerminal: TTypeTerminal);
    procedure InstallInterruptHook;
    procedure UninstallInterruptHook;
    procedure DoInterrupt;
    procedure UpdateStatus;
    function GetTerminalTypeName(ATypeTerminal: TTypeTerminal): string;
  protected
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolBarActionList: TCustomActionList;
    function GetToolBarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
  public
    class function CreateDocked(const Identifier: string): TManangerTerminal;
    class procedure New;
    class procedure FreeMemory;
  end;

var
  ManangerTerminal: TManangerTerminal;

procedure Register;

implementation

uses
  DeskUtil;

{$R *.dfm}

procedure Register;
begin
  if @RegisterDesktopFormClass <> nil then
    RegisterDesktopFormClass(TManangerTerminal, 'FrmDinosTerminalAssistant', 'FrmDinosTerminalAssistant');
  if @RegisterFieldAddress <> nil then
    RegisterFieldAddress('FrmDinosTerminalAssistant', @ManangerTerminal);
end;

{ TManangerTerminal }

class function TManangerTerminal.CreateDocked(const Identifier: string): TManangerTerminal;
var
  LINTAServices: INTAServices;
begin
  Result := TManangerTerminal.Create(nil);
  Result.Name := 'FrmDinosTerminalAssistant';
  Result.KeyPreview := True;

  if Supports(BorlandIDEServices, INTAServices, LINTAServices) then
    LINTAServices.RegisterDockableForm(Result);
end;

class procedure TManangerTerminal.New;
var
  I: Integer;
  FormAntigo: TCustomForm;
  LINTAServices: INTAServices;
begin
  FormAntigo := nil;

  for I := 0 to Screen.CustomFormCount - 1 do
  begin
    if Assigned(Screen.CustomForms[I]) and (Screen.CustomForms[I].ClassName = 'TManangerTerminal') then
    begin
      FormAntigo := Screen.CustomForms[I];
      Break;
    end;
  end;

  if Assigned(FormAntigo) and (not Winapi.Windows.IsWindow(FormAntigo.Handle)) then
  begin
    try
      FormAntigo.Free;
    except
    end;
    FormAntigo := nil;
    ManangerTerminal := nil;
  end;

  if (FormAntigo = nil) or (not Assigned(ManangerTerminal)) then
    ManangerTerminal := CreateDocked('DinosTerminalAssistant')
  else
    ManangerTerminal := TManangerTerminal(FormAntigo);

  if Assigned(ManangerTerminal) then
  begin
    try
      if ManangerTerminal.Parent = nil then
      begin
        ManangerTerminal.HandleNeeded;
        ManangerTerminal.ManualFloat(Rect(150, 150, 650, 500));
      end;

      if Supports(BorlandIDEServices, INTAServices, LINTAServices) then
      begin
        try
          LINTAServices.RegisterDockableForm(ManangerTerminal);
        except
        end;
      end;

      ManangerTerminal.ForceShow;
      ManangerTerminal.Visible := True;
      ManangerTerminal.Show;
      ManangerTerminal.BringToFront;

      if ManangerTerminal.Enabled then
        ManangerTerminal.SetFocus;
    except
    end;
  end;
end;

procedure TManangerTerminal.OpenLogFile1Click(Sender: TObject);
var
  LogFile: string;
begin
  LogFile := System.SysUtils.GetEnvironmentVariable('TEMP') + '\DinosTerminal.log';
  ShellExecute(0, 'open', PChar(LogFile), nil, nil, SW_SHOWNORMAL);
end;

procedure TManangerTerminal.Past1Click(Sender: TObject);
begin
  if FTerminals.Count > 0 then
  begin
    var Frame := FTerminals[FActivePosition];
    if Clipboard.HasFormat(CF_TEXT) and Assigned(Frame.Process) and Frame.Process.IsRunning then
      Frame.Process.WriteInput(Clipboard.AsText);
  end;
end;

procedure TManangerTerminal.Renomear1Click(Sender: TObject);
var
  lName: string;
begin
  if FActivePosition > 0 then
  begin
    lName := InputBox('Terminal name:', 'New terminal name', '');
    if not lName.Trim.IsEmpty then
      TTabSheet(FTerminals[FActivePosition].Parent).Caption := lName;
  end
  else
    ShowMessage('It is not possible to rename the Default Terminal.');
end;

class procedure TManangerTerminal.FreeMemory;
var
  LINTAServices: INTAServices;
begin
  if Assigned(ManangerTerminal) then
  begin
    if Supports(BorlandIDEServices, INTAServices, LINTAServices) then
      LINTAServices.UnRegisterDockableForm(ManangerTerminal);
    FreeAndNil(ManangerTerminal);
  end;
end;

procedure TManangerTerminal.FormCreate(Sender: TObject);
begin
  //Log in this path %TEMP%\DinosTerminal.log
  LogTerminalDebugIsActive := False;

  FTerminals := TObjectList<TTerminalFrame>.Create(True);
  Self.Name := 'FrmDinosTerminalAssistant';
  FActivePosition := 0;
  DeskSection := 'FrmDinosTerminalAssistant';
  AutoSave := True;
  SaveStateNecessary := True;

  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.SimplePanel := True;
  FStatusBar.SimpleText := 'Terminal: - | Ctrl+Break interrompe o comando em execucao';
  FStatusBar.Hint := 'Pressione Ctrl+Break (ou Ctrl+Pause) para interromper o comando em ' +
                     'execucao, equivalente a Ctrl+C no prompt. Ex.: ping -t 10.0.0.1.';
  FStatusBar.ShowHint := True;

  Log('Criei o form principal');
end;

procedure TManangerTerminal.FormDestroy(Sender: TObject);
var
  LINTAServices: INTAServices;
begin
  UninstallInterruptHook;
  if Supports(BorlandIDEServices, INTAServices, LINTAServices) then
  begin
    try
      LINTAServices.UnRegisterDockableForm(Self);
    except
    end;
  end;

  FreeAndNil(FTerminals);

  if ManangerTerminal = Self then
    ManangerTerminal := nil;
end;

procedure TManangerTerminal.InstallInterruptHook;
begin
  if FInterruptInstalled then Exit;
  TInterruptManager.Instance.OnInterrupt := DoInterrupt;
  TInterruptManager.Instance.Install;
  FInterruptInstalled := TInterruptManager.Instance.Enabled;
  if FInterruptInstalled then
    Log('Keyboard interrupt hook installed (Ctrl+Break)')
  else
    Log('Keyboard interrupt hook FAILED to install');
end;

procedure TManangerTerminal.UninstallInterruptHook;
begin
  if not FInterruptInstalled then Exit;
  TInterruptManager.Instance.Uninstall;
  FInterruptInstalled := False;
end;

procedure TManangerTerminal.DoInterrupt;
begin
  if (FActivePosition >= 0) and (FActivePosition < FTerminals.Count) then
  begin
    FTerminals[FActivePosition].CancelInput;
    if Assigned(FActiveProcess) and FActiveProcess.IsRunning then
      FActiveProcess.SendInterrupt;
    Log('Keyboard interrupt: Ctrl+Break sent #3');
  end;
end;

procedure TManangerTerminal.FormShow(Sender: TObject);
begin
  InstallInterruptHook;
  if FTerminals.Count = 0 then
    AddTerminal(TabDefault, tCMD);
  UpdateStatus;
end;

procedure TManangerTerminal.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caHide;
end;

procedure TManangerTerminal.CMD1Click(Sender: TObject);
var
  BtMenu: TMenuItem;
  lNewTab: TTabSheet;
begin
  if Sender is TMenuItem then
  begin
    BtMenu := TMenuItem(Sender);
    lNewTab := TTabSheet.Create(PgTerminal);
    lNewTab.PageControl := PgTerminal;
    lNewTab.Parent := PgTerminal;
    lNewTab.Caption := GetTerminalTypeName(TTypeTerminal(BtMenu.Tag)) +' '+
      IntToStr(FTerminals.Count);
    lNewTab.Tag := FTerminals.Count;
    lNewTab.OnEnter := TabDefaultEnter;
    PgTerminal.ActivePage := lNewTab;
    AddTerminal(lNewTab, TTypeTerminal(BtMenu.Tag));
  end;
end;

procedure TManangerTerminal.Copy1Click(Sender: TObject);
begin
  if (FActivePosition >= 0) and (FActivePosition < FTerminals.Count) then
  begin
    var Frame := FTerminals[FActivePosition];
    if Frame.View.HasSelection then
      Clipboard.AsText := Frame.View.GetSelectedText
    else
      Clipboard.AsText := Frame.Screen.GetPlainText;
  end;
end;

function TManangerTerminal.GetTerminalTypeName(ATypeTerminal: TTypeTerminal): string;
begin
   case ATypeTerminal of
    tWSL:        Result := 'WSL';
    tCMD:        Result := 'CMD';
    tPowerShell: Result := 'PowerShell';
  end;
end;

procedure TManangerTerminal.AddTerminal(ATabParent: TTabSheet; ATypeTerminal: TTypeTerminal);
var
  NewFrame: TTerminalFrame;
begin
  Log('Iniciei a adicao do terminal');
  NewFrame := TTerminalFrame.Create(ATabParent);
  NewFrame.Parent := ATabParent;
  NewFrame.Align := alClient;
  NewFrame.Visible := True;

  FTerminals.Add(NewFrame);
  Log('Adicionei no dicionario');

  NewFrame.ShellTypeName := GetTerminalTypeName(ATypeTerminal);

  try
    StartProcessForFrame(NewFrame, ATypeTerminal);
    Sleep(100);
  except
    on E:Exception do
    begin
        Log('Falhou no StartProcessForFrame: '+ E.Message);
        raise;
    end;
  end;

  UpdateStatus;
end;

procedure TManangerTerminal.StartProcessForFrame(AFrame: TTerminalFrame; ATypeTerminal: TTypeTerminal);
var
  CmdLine: string;
  Shell: ITerminalProcess;
  Size: TTerminalSize;
begin
  case ATypeTerminal of
    tWSL:        CmdLine := 'wsl.exe';
    tCMD:        CmdLine := 'cmd.exe /Q /K';
    tPowerShell: CmdLine := 'powershell.exe -NoLogo';
  end;

  Log('StartProcessForFrame: ' + CmdLine);

  try
    Shell := TConPtyShell.Create;
    Size.Cols := 120;
    Size.Rows := 40;

    AFrame.SetProcess(Shell);
    Shell.Start(CmdLine, Size);
    AFrame.ResizeProcessToView;
    FActiveProcess := Shell;
    InstallInterruptHook;
    Log('StartProcessForFrame done');
  except
    on E: Exception do
    begin
      Log('StartProcessForFrame EXCEPTION: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

function TManangerTerminal.GetCaption: string;
begin
  Result := 'Dinos Terminal';
end;

function TManangerTerminal.GetIdentifier: string;
begin
  Result := 'DinosTerminalAssistant';
end;

function TManangerTerminal.GetFrameClass: TCustomFrameClass;
begin
  Result := nil;
end;

procedure TManangerTerminal.FrameCreated(AFrame: TCustomFrame);
begin
  DockSite := False;
  AutoScroll := True;
end;

procedure TManangerTerminal.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

procedure TManangerTerminal.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

function TManangerTerminal.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure TManangerTerminal.EnableLogs1Click(Sender: TObject);
const
  ENABLE_LOG = '✔ Enable Log';
  DISABLE_LOG = 'Enable Log';
begin
  LogTerminalDebugIsActive := not LogTerminalDebugIsActive;

  if LogTerminalDebugIsActive then
    EnableLogs1.Caption := ENABLE_LOG
  else
    EnableLogs1.Caption := DISABLE_LOG;
end;

procedure TManangerTerminal.Excluir1Click(Sender: TObject);
begin
  if FActivePosition > 0 then
    FTerminals[FActivePosition].Parent.Free
  else
    ShowMessage('It is not possible to delete the Default Terminal.');
end;

function TManangerTerminal.GetEditState: TEditState;
begin
  Result := [];
end;

function TManangerTerminal.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TManangerTerminal.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

function TManangerTerminal.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TManangerTerminal.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TManangerTerminal.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

procedure TManangerTerminal.SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
begin
end;

procedure TManangerTerminal.TabDefaultEnter(Sender: TObject);
begin
  if Sender is TTabSheet then
    FActivePosition := TTabSheet(Sender).Tag;
  UpdateStatus;
end;

procedure TManangerTerminal.UpdateStatus;
var
  LType: string;
begin
  if not Assigned(FStatusBar) then Exit;
  LType := '';
  if (FActivePosition >= 0) and (FActivePosition < FTerminals.Count) then
    LType := FTerminals[FActivePosition].ShellTypeName;
  if LType = '' then
    LType := '?';
  FStatusBar.SimpleText := '  Terminal: ' + LType + '    | Ctrl+Break interrompe o comando em execucao   ';
end;

initialization

finalization
  if @UnregisterFieldAddress <> nil then
    UnregisterFieldAddress(@ManangerTerminal);
end.
