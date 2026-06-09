unit uTerminal;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.ComCtrls, System.RegularExpressions, Winapi.UxTheme, ShellApi;

type
  TTypeTerminal = (tWSL, tCMD, tPowerShell);

  TTerminal = class(TForm)
    tmrLoad: TTimer;
    RTerm: TRichEdit;
    procedure tmrLoadTimer(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure RTermKeyPress(Sender: TObject; var Key: Char);
    procedure RTermKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
  private
    FWritePipe: THandle;  
    FReadPipe: THandle;   
    FProcessInfo: TProcessInformation;
    FTerminalType: TTypeTerminal;
    FInputStartPos: Integer;

    FHistorico: TStringList;
    FIdxHistorico: Integer;
    FComandoAtual: string;

    procedure SendToPipe(const AData: string);
    procedure EstilizarRichEdit;
    procedure LimparLinhaDigitada;
    procedure TratarEnter;
  public
    procedure WriteToXTerm(const AText: string);
    procedure StartTerminalProcess(const ACommand: string);

    property TerminalType: TTypeTerminal read FTerminalType write FTerminalType;
  end;

  TReaderThread = class(TThread)
  private
    FReadPipe: THandle;
    FForm: TTerminal;
  protected
    procedure Execute; override;
  public
    constructor Create(AReadPipe: THandle; AForm: TTerminal);
  end;

implementation

{$R *.dfm}

{ TTerminal }

procedure TTerminal.EstilizarRichEdit;
const
  EM_SETBKGNDCOLOR = WM_USER + 67;
begin
  rTerm.Align := alClient;
  rTerm.BorderStyle := bsNone;

  SetWindowTheme(rTerm.Handle, '', '');

  //Dracula (#282a36)
  rTerm.Color := $00362A28;
  SendMessage(rTerm.Handle, EM_SETBKGNDCOLOR, 0, $00362A28);

  //Branco/Cinza Dracula (#f8f8f2)
  rTerm.DefAttributes.Color := $00F2F8F8; 
  rTerm.DefAttributes.Name  := 'Consolas';
  rTerm.DefAttributes.Size  := 16;
  rTerm.DefAttributes.Style := [];

  rTerm.Font.Assign(rTerm.DefAttributes);
  rTerm.ScrollBars := ssVertical;
  rTerm.WordWrap := True;

  SendMessage(rTerm.Handle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLong(10, 10));
end;

procedure TTerminal.tmrLoadTimer(Sender: TObject);
begin
  tmrLoad.Enabled := False;
  EstilizarRichEdit;

  case TerminalType of
    tWSL:        StartTerminalProcess('wsl.exe -e /bin/bash -il');
    tCMD:        StartTerminalProcess('cmd.exe /Q /K');
    tPowerShell: StartTerminalProcess('powershell.exe -NoLogo');
  end;
end;

procedure TTerminal.StartTerminalProcess(const ACommand: string);
var
  SA: TSecurityAttributes;
  StartInfo: TStartupInfo;
  ReadPipeWriteEnd, WritePipeReadEnd: THandle;
  CommandLine: string;
begin
  SA.nLength := SizeOf(TSecurityAttributes);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(FReadPipe, ReadPipeWriteEnd, @SA, 0) then Exit;
  if not CreatePipe(WritePipeReadEnd, FWritePipe, @SA, 0) then
  begin
    CloseHandle(FReadPipe);
    CloseHandle(ReadPipeWriteEnd);
    Exit;
  end;

  SetHandleInformation(FReadPipe, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(FWritePipe, HANDLE_FLAG_INHERIT, 0);

  FillChar(StartInfo, SizeOf(TStartupInfo), 0);
  StartInfo.cb := SizeOf(TStartupInfo);
  StartInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  StartInfo.wShowWindow := SW_HIDE;

  StartInfo.hStdOutput := ReadPipeWriteEnd;
  StartInfo.hStdError := ReadPipeWriteEnd;
  StartInfo.hStdInput := WritePipeReadEnd;

  CommandLine := ACommand;
  UniqueString(CommandLine);

  if CreateProcess(nil, PChar(CommandLine), nil, nil, True, 0, nil, nil, StartInfo, FProcessInfo) then
  begin
    TReaderThread.Create(FReadPipe, Self);
    Sleep(300);
    
    if TerminalType = tWSL then SendToPipe(#10) else SendToPipe(#13);
  end;

  if ReadPipeWriteEnd <> 0 then CloseHandle(ReadPipeWriteEnd);
  if WritePipeReadEnd <> 0 then CloseHandle(WritePipeReadEnd);
end;

procedure TTerminal.SendToPipe(const AData: string);
var
  BytesWritten: DWORD;
  RawBytes: TBytes;
begin
  if (FWritePipe <> 0) and (AData <> '') then
  begin
    RawBytes := TEncoding.ANSI.GetBytes(AData);
    if Length(RawBytes) > 0 then
    begin
      WriteFile(FWritePipe, RawBytes[0], Length(RawBytes), BytesWritten, nil);
      FlushFileBuffers(FWritePipe);
    end;
  end;
end;

procedure TTerminal.TratarEnter;
var
  ComandoReal: string;
begin
  if RTerm.Lines.Count = 0 then Exit;

  RTerm.SelStart := FInputStartPos;
  RTerm.SelLength := Length(RTerm.Text);
  ComandoReal := RTerm.SelText;

  RTerm.SelStart := Length(RTerm.Text);
  RTerm.SelLength := 0;

  if not ComandoReal.Trim.IsEmpty then
  begin
    FHistorico.Add(ComandoReal.Trim);
    FIdxHistorico := -1;
  end;

  RTerm.SelAttributes.Color := $00F2F8F8;
  RTerm.SelAttributes.Style := [];
//  RTerm.SelText := sLineBreak;

  FInputStartPos := RTerm.SelStart;

  case FTerminalType of
    tWSL:        SendToPipe(ComandoReal + #10);   // Linux usa LF puro
    tCMD:        SendToPipe(ComandoReal + #13#10); // CMD exige CRLF completo
    tPowerShell: SendToPipe(ComandoReal + #13);   // PowerShell processa bem com CR
  end;
end;

procedure TTerminal.RTermKeyPress(Sender: TObject; var Key: Char);
begin
  if not Assigned(FHistorico) then 
    FHistorico := TStringList.Create;

  // 1. Impedir que o usuário digite atrás do prompt ativo
  if RTerm.SelStart < FInputStartPos then
  begin
    Key := #0;
    Exit;
  end;

  if Key = #13 then
  begin
    Key := #0;
    TratarEnter;
  end;
end;

procedure TTerminal.RTermKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  ComandoSelecionado: string;
  UltimaLinhaIdx, PromptPos: Integer;
  VLocalTerminalType: TTypeTerminal;
  VLocalReadPipe, VLocalWritePipe: THandle;
begin
  if (Key = Ord('C')) and (ssCtrl in Shift) then
  begin
    Key := 0; 

    VLocalTerminalType := FTerminalType;
    VLocalReadPipe     := FReadPipe;
    VLocalWritePipe    := FWritePipe;

    TThread.CreateAnonymousThread(procedure
    begin
      if VLocalReadPipe <> 0 then 
        CancelIo(VLocalReadPipe); 
      
      if VLocalWritePipe <> 0 then
      begin
        PurgeComm(VLocalWritePipe, PURGE_TXCLEAR or PURGE_RXCLEAR);
        CancelIo(VLocalWritePipe);
      end;

      if VLocalTerminalType <> tWSL then
      begin
        ShellExecute(0, 'open', 'cmd.exe', '/c taskkill /F /IM ping.exe', nil, SW_HIDE);
      end;
    end).Start;

    RTerm.Lines.BeginUpdate;
    try
      RTerm.SelStart := Length(RTerm.Text);
      RTerm.SelLength := 0;
      RTerm.SelAttributes.Color := $00F2F8F8;
      RTerm.SelText := '^C' + sLineBreak;
    finally
      RTerm.Lines.EndUpdate;
    end;
    
    SendMessage(RTerm.Handle, WM_VSCROLL, SB_BOTTOM, 0);
    Exit;
  end;

  if (Key = VK_BACK) or (Key = VK_LEFT) then
  begin
    if RTerm.SelStart <= FInputStartPos then
    begin
      Key := 0;
      Exit;
    end;
  end;

  if Key = VK_DELETE then
  begin
    if RTerm.SelStart < FInputStartPos then
    begin
      Key := 0;
      Exit;
    end;
  end;

  if RTerm.SelStart < FInputStartPos then
  begin
    if not (Key in [VK_UP, VK_DOWN, VK_RIGHT]) then
      RTerm.SelStart := Length(RTerm.Text);
  end;

  if (not Assigned(FHistorico)) or (FHistorico.Count = 0) then Exit;

  if Key = VK_UP then
  begin
    Key := 0; 
    if FIdxHistorico = -1 then
      FIdxHistorico := FHistorico.Count - 1
    else if FIdxHistorico > 0 then
      Dec(FIdxHistorico);

    LimparLinhaDigitada;
    ComandoSelecionado := FHistorico[FIdxHistorico];
    
    RTerm.SelStart := Length(RTerm.Text);
    RTerm.SelLength := 0;
    RTerm.SelAttributes.Color := $00FDE98B;
    RTerm.SelText := ComandoSelecionado;
    Exit;
  end;

  if Key = VK_DOWN then
  begin
    Key := 0; 
    if FIdxHistorico <> -1 then
    begin
      if FIdxHistorico < FHistorico.Count - 1 then
      begin
        Inc(FIdxHistorico);
        LimparLinhaDigitada;
        ComandoSelecionado := FHistorico[FIdxHistorico];
        
        RTerm.SelStart := Length(RTerm.Text);
        RTerm.SelLength := 0;
        RTerm.SelAttributes.Color := $00FDE98B;
        RTerm.SelText := ComandoSelecionado;
      end
      else
      begin
        FIdxHistorico := -1;
        LimparLinhaDigitada;
      end;
    end;
    Exit;
  end;
end;

procedure TTerminal.LimparLinhaDigitada;
begin
  if Length(rTerm.Text) > FInputStartPos then
  begin
    rTerm.SelStart := FInputStartPos;
    rTerm.SelLength := Length(rTerm.Text) - FInputStartPos;
    rTerm.SelText := '';
  end;
end;

procedure TTerminal.WriteToXTerm(const AText: string);
var
  CleanText, UltimoComando, UltimaLinha , Linha: string;
  StringListLinhas: TStringList;
  IsPromptCompleto, IsHeaderLs: Boolean;
begin
  CleanText := AText;

  CleanText := TRegEx.Replace(CleanText, '\x1B\]0;.*?\x07', '');
  CleanText := TRegEx.Replace(CleanText, '\x1B\]0;.*?\x0A', '');
  CleanText := TRegEx.Replace(CleanText, '\x1B\[[0-9;]*[a-zA-Z]', '');
  CleanText := CleanText.Replace(#7, '');

  while CleanText.StartsWith(#13) or CleanText.StartsWith(#10) do
  begin
    if CleanText.StartsWith(#13#10) then
      CleanText := Copy(CleanText, 3, MaxInt)
    else
      CleanText := Copy(CleanText, 2, MaxInt);
  end;

  while CleanText.EndsWith(#13) or CleanText.EndsWith(#10) do
  begin
    if CleanText.EndsWith(#13#10) then CleanText := Copy(CleanText, 1, Length(CleanText) - 2)
    else CleanText := Copy(CleanText, 1, Length(CleanText) - 1);
  end;

  if CleanText = '' then Exit;

  UltimaLinha := RTerm.Lines[RTerm.Lines.Count - 1];

  if (FTerminalType in [tPowerShell, tWSL]) then
  begin
    if (CleanText.Trim = UltimaLinha.Trim) then Exit;
  end;

  if (FTerminalType <> tWSL) and Assigned(FHistorico) and (FHistorico.Count > 0) then
  begin
    UltimoComando := FHistorico[FHistorico.Count - 1].Trim;
    if (CleanText.Trim = UltimoComando) or
       (CleanText.Trim = UltimoComando + #13) then
      Exit;
  end;

  StringListLinhas := TStringList.Create;
  try
    StringListLinhas.Text := CleanText;

    RTerm.Lines.BeginUpdate;
    try
      for var Idx := 0 to StringListLinhas.Count -1 do
      begin
        Linha := StringListLinhas[Idx];

        if Assigned(FHistorico) and (FHistorico.Count > 0) then
        begin
          if Linha.Trim = FHistorico[FHistorico.Count - 1].Trim then
            Continue;
        end;

        if RTerm.Lines.Count > 0 then
          UltimaLinha := RTerm.Lines[RTerm.Lines.Count - 1].Trim
        else
          UltimaLinha := '';

        if (Linha.Trim <> '') and (Linha.Trim = UltimaLinha) then
          Continue;

        if Linha.Trim = '' then
        begin
         if (RTerm.Lines.Count > 0) and (RTerm.Lines[RTerm.Lines.Count - 1].Trim = '') then
            Continue;

          RTerm.SelStart := Length(RTerm.Text);
          RTerm.SelLength := 0;
          RTerm.SelAttributes.Color := $00F2F8F8;
          //RTerm.SelText := sLineBreak;
          Continue;
        end;

        RTerm.SelStart := Length(RTerm.Text);
        RTerm.SelLength := 0;

        case FTerminalType of
          tWSL:
          begin
            IsPromptCompleto := Linha.Contains('@') or Linha.Trim.EndsWith('#') or Linha.Trim.EndsWith('$');
            
            if IsPromptCompleto then
            begin
              RTerm.SelAttributes.Color := $007BFA50; // Verde Dracula (#50fa7b)
              RTerm.SelAttributes.Style := [fsBold];
            end
            else
            begin
              RTerm.SelAttributes.Color := $00F2F8F8;
              RTerm.SelAttributes.Style := [];
            end;
          end;

          tCMD, tPowerShell:
          begin
            IsPromptCompleto := (Linha.Trim.StartsWith('PS ') and Linha.Contains('>')) or 
                                (TRegEx.IsMatch(Linha, '^[A-Za-z]:\\') and Linha.Contains('>')); 
                                
            IsHeaderLs := Linha.Contains('Diretório:') or Linha.Contains('Diretorio:') or
                          TRegEx.IsMatch(Linha, '^-+\s+-+');

            if IsPromptCompleto or IsHeaderLs then
            begin
              RTerm.SelAttributes.Color := $00F993BD; // Roxo Dracula (#bd93f9)
              RTerm.SelAttributes.Style := [fsBold];
            end
            else
            begin
              RTerm.SelAttributes.Color := $00FDE98B; // Ciano/Azul Dados (#8be9fd)
              RTerm.SelAttributes.Style := [];
            end;
          end;
        end;

//        if Idx < StringListLinhas.Count - 1 then
//        begin
//          RTerm.SelText := Linha + sLineBreak;
//        end
//        else if CleanText.EndsWith(#10) or CleanText.EndsWith(#13) then
//          RTerm.SelText := Linha + sLineBreak
//        else
//          RTerm.SelText := Linha;

        if Idx = StringListLinhas.Count - 1 then
          RTerm.SelText := Linha
        else
          RTerm.SelText := Linha + sLineBreak;

      end;
    finally
      RTerm.Lines.EndUpdate;
    end;

  finally
    StringListLinhas.Free;
  end;
  
  SendMessage(RTerm.Handle, WM_VSCROLL, SB_BOTTOM, 0);
  RTerm.SelStart := Length(RTerm.Text)-1;
  RTerm.SelLength := 0;
  FInputStartPos := RTerm.SelStart;
end;

procedure TTerminal.FormDestroy(Sender: TObject);
begin
  FHistorico.Free;

  if FProcessInfo.hProcess <> 0 then
  begin
    TerminateProcess(FProcessInfo.hProcess, 0);
    CloseHandle(FProcessInfo.hProcess);
    CloseHandle(FProcessInfo.hThread);
  end;
  if FReadPipe <> 0 then CloseHandle(FReadPipe);
  if FWritePipe <> 0 then CloseHandle(FWritePipe);
end;

procedure TTerminal.FormShow(Sender: TObject);
begin
  FHistorico := TStringList.Create;
  FIdxHistorico := -1;
  FComandoAtual := '';
  FInputStartPos := 0;
end;

{ TReaderThread }

constructor TReaderThread.Create(AReadPipe: THandle; AForm: TTerminal);
begin
  inherited Create(False);
  FReadPipe := AReadPipe;
  FForm := AForm;
  FreeOnTerminate := True;
end;

procedure TReaderThread.Execute;
var
  Buffer: array[0..4095] of AnsiChar;
  BytesRead, TotalBytesAvail, BytesLeftThisMessage: DWORD;
  TextOut, LastTextOut: string;
begin
  LastTextOut := '';

  while not Terminated do
  begin
    if PeekNamedPipe(FReadPipe, nil, 0, nil, @TotalBytesAvail, nil) then
    begin
      if TotalBytesAvail > 0 then
      begin
        if ReadFile(FReadPipe, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then
        begin
          if BytesRead > 0 then
          begin
            Buffer[BytesRead] := #0;
            TextOut := AnsiToUtf8(Buffer);

            if (TextOut <> LastTextOut) or (FForm.TerminalType = tCMD) then
            begin
              LastTextOut := TextOut;

              TThread.Queue(nil, procedure
              begin
                FForm.WriteToXTerm(TextOut);
              end);
            end;
          end;
        end
        else
        begin
          Self.Terminate;
          Break;
        end;
      end;
    end;

    Sleep(500);
  end;
end;

end.
