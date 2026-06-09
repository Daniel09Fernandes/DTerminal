unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, System.Generics.Collections, uTerminal,
  Vcl.Menus,
  // Componentes e Serviços da IDE (ToolsAPI)
  DesignIntf, ToolsAPI, DockForm, Vcl.ActnList, Vcl.ImgList, System.IniFiles;

type
  TManangerTerminal = class(TDockableForm,  INTACustomDockableForm)
    PgTerminal: TPageControl;
    TabDefault: TTabSheet;
    PopTerminal: TPopupMenu;
    NewTerminal: TMenuItem;
    CMD1: TMenuItem;
    WSL1: TMenuItem;
    PowerShell1: TMenuItem;
    Renomear1: TMenuItem;
    Excluir1: TMenuItem;
    procedure FormShow(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure CMD1Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Excluir1Click(Sender: TObject);
    procedure Renomear1Click(Sender: TObject);
    procedure TabDefaultEnter(Sender: TObject);
  private
    FTerminals: TObjectList<TTerminal>;
    FActivePosition: Integer;
    procedure AddTerminal(ATabParent: TTabSheet; ATypeTerminal: TTypeTerminal);
  protected
    { Métodos Obrigatórios da Interface INTACustomDockableForm }
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

  if Supports(BorlandIDEServices, INTAServices, LINTAServices) then
  begin
    // Registra na ToolsAPI para habilitar o encaixe (Docking)
    LINTAServices.RegisterDockableForm(Result);
  end;
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
  begin
    ManangerTerminal := CreateDocked('DinosTerminalAssistant');
  end
  else
  begin
    ManangerTerminal := TManangerTerminal(FormAntigo);
  end;

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

procedure TManangerTerminal.Renomear1Click(Sender: TObject);
var
  BtMenu: TMenuItem;
  lName: string;
begin
  if FActivePosition > 0 then
  begin
    lName := InputBox('Terminal name:','New terminal name','');
    if not lName.Trim.IsEmpty then
      TTabSheet(FTerminals.Items[FActivePosition].Parent).Caption := lName;
  end;
end;

class procedure TManangerTerminal.FreeMemory;
var
  LINTAServices: INTAServices;
begin
  if Assigned(ManangerTerminal) then
  begin
    if Supports(BorlandIDEServices, INTAServices, LINTAServices) then
    begin
      LINTAServices.UnRegisterDockableForm(ManangerTerminal);
    end;
    FreeAndNil(ManangerTerminal);
  end;
end;

procedure TManangerTerminal.FormCreate(Sender: TObject);
begin
  FTerminals := TObjectList<TTerminal>.Create(True);
  Self.Name := 'FrmDinosTerminalAssistant';

  DeskSection := 'FrmDinosTerminalAssistant';
  AutoSave := True;
  SaveStateNecessary := True;
end;

procedure TManangerTerminal.FormDestroy(Sender: TObject);
var
  LINTAServices: INTAServices;
begin
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

procedure TManangerTerminal.FormShow(Sender: TObject);
begin
  if FTerminals.Count = 0 then
    AddTerminal(TabDefault, tCMD);
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
    lNewTab.Caption := 'Terminal ' + IntToStr(FTerminals.Count);
    lNewTab.Tag := (FTerminals.Count);
    lNewTab.OnEnter := TabDefaultEnter;

    PgTerminal.ActivePage := lNewTab;
    AddTerminal(lNewTab, TTypeTerminal(BtMenu.Tag));
  end;
end;

procedure TManangerTerminal.AddTerminal(ATabParent: TTabSheet; ATypeTerminal: TTypeTerminal);
var
  NewTerm: TTerminal;
begin
  NewTerm := TTerminal.Create(ATabParent);
  NewTerm.Parent := ATabParent;
  NewTerm.Align := alClient;
  NewTerm.BorderStyle := bsNone;
  NewTerm.TerminalType := ATypeTerminal;
  NewTerm.Visible := True;

  FTerminals.Add(NewTerm);
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

procedure TManangerTerminal.Excluir1Click(Sender: TObject);
var
  BtMenu: TMenuItem;
begin
  if FActivePosition > 0 then
  begin
    FTerminals.Items[FActivePosition].Parent.Free;
  end;
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
  if (Sender is TTabSheet) then
    FActivePosition := TTabSheet(Sender).Tag;
end;

initialization
finalization
  if @UnregisterFieldAddress <> nil then
    UnregisterFieldAddress(@ManangerTerminal);
end.
