program Terminal;

uses
  Vcl.Forms,
  uTerminal in 'uTerminal.pas' {Terminal},
  uMain in 'uMain.pas' {ManangerTerminal};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TManangerTerminal, ManangerTerminal);
  Application.Run;
end.
