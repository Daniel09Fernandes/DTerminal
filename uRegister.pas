unit uRegister;

interface

uses
  VCL.Menus, ToolsAPI, uMain, classes;

type
  TOTAMenuWizar = class(TNotifierObject, IOTAWizard)
  published
  private
   FMenuItem: TMenuItem;
   FMenuTextInteraction: TMenuItem;
   procedure OnMenuItemClick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;

    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

implementation

{ TOTAMenuWizar }

uses
  SysUtils, VCL.Dialogs, Vcl.Forms;

constructor TOTAMenuWizar.Create;
const
  MENU_PERSONALIZADO = 'DinosTools';
var
  MenuDelphi: TMainMenu;
  ToolsMenuDelphi: TMenuItem;
  IndexMenuPersonalizado: Integer;
begin
  inherited Create;

  MenuDelphi := (BorlandIDEServices as INTAServices).MainMenu;

  if not Assigned(MenuDelphi) then
    Exit;

  FMenuItem := TMenuItem.Create(nil);
  IndexMenuPersonalizado := -1;

  if Assigned(MenuDelphi.Items.Find(MENU_PERSONALIZADO)) then
    IndexMenuPersonalizado := MenuDelphi.Items.Find(MENU_PERSONALIZADO).MenuIndex;

  if IndexMenuPersonalizado < 0 then
  begin
    FMenuItem.Caption := MENU_PERSONALIZADO;
    MenuDelphi.Items.Add(FMenuItem);
   //MenuDelphi.Items.Delete(IndexMenuPersonalizado);
  end;

  ToolsMenuDelphi := MenuDelphi.Items.Find(MENU_PERSONALIZADO);

  if Assigned(ToolsMenuDelphi) then
  begin
    FMenuTextInteraction := TMenuItem.Create(nil);
    FMenuTextInteraction.Caption := 'Dinos Termenial';
    FMenuTextInteraction.OnClick := OnMenuItemClick;
    ToolsMenuDelphi.Add(FMenuTextInteraction);
  end;
end;

destructor TOTAMenuWizar.Destroy;
begin
  FreeAndNil(FMenuTextInteraction);
  FreeAndNil(FMenuItem);
  TManangerTerminal.FreeMemory;
  inherited Destroy;
end;

procedure TOTAMenuWizar.Execute;
begin
  TManangerTerminal.New;
end;

function TOTAMenuWizar.GetIDString: string;
begin
  Result := 'Dinos.WizardMenu';
end;

function TOTAMenuWizar.GetName: string;
begin
   Result := 'OTA Menu Wizard';
end;

function TOTAMenuWizar.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TOTAMenuWizar.OnMenuItemClick(Sender: TObject);
begin
  Execute;
end;

initialization
  RegisterPackageWizard(TOTAMenuWizar.Create);

end.
