unit Dinos.Terminal.ConPtyReader;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Dinos.Terminal.Debug;

type
  TConPtyOutputEvent = procedure(const AText: string) of object;
  TConPtyTerminatedEvent = procedure of object;

  TConPtyReader = class(TThread)
  private
    FOutputRead: THandle;
    FOnOutput: TConPtyOutputEvent;
    FOnTerminated: TConPtyTerminatedEvent;
    FBuffer: TBytes;
    procedure DoOutput(const AText: string);
    procedure DoTerminated;
  protected
    procedure Execute; override;
  public
    constructor Create(AOutputRead: THandle);
    property OnOutput: TConPtyOutputEvent read FOnOutput write FOnOutput;
    property OnTerminated: TConPtyTerminatedEvent read FOnTerminated write FOnTerminated;
  end;

implementation

const
  READ_BUFFER_SIZE = 4096;

{ TConPtyReader }

constructor TConPtyReader.Create(AOutputRead: THandle);
begin
  FOutputRead := AOutputRead;
  SetLength(FBuffer, READ_BUFFER_SIZE);
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TConPtyReader.DoOutput(const AText: string);
begin
  if Assigned(FOnOutput) then
    FOnOutput(AText);
end;

procedure TConPtyReader.DoTerminated;
begin
  if Assigned(FOnTerminated) then
    FOnTerminated;
end;

function CompleteUtf8Count(const ABytes: TBytes): Integer;
var
  I, Expected: Integer;
begin
  Result := Length(ABytes);
  if Result = 0 then Exit;

  I := Result - 1;
  while (I >= 0) and ((ABytes[I] and $C0) = $80) do
    Dec(I);

  if I < 0 then
  begin
    Result := 0;
    Exit;
  end;

  if ABytes[I] < $80 then Exit;

  if (ABytes[I] and $F8) = $F0 then
    Expected := 4
  else if (ABytes[I] and $F0) = $E0 then
    Expected := 3
  else if (ABytes[I] and $E0) = $C0 then
    Expected := 2
  else
    Exit;

  if Result - I < Expected then
    Result := I;
end;

procedure TConPtyReader.Execute;
var
  BytesRead: DWORD;
  TextOut: string;
  Combined: TBytes;
  CompleteCount: Integer;
  PrevTail: TBytes;
  TailCount: Integer;
  ChunkCount: Integer;
  LPipeAvail: DWORD;
  LPipeTotal: DWORD;
begin
  Log('TConPtyReader.Execute: started, handle=' + IntToStr(FOutputRead));
  ChunkCount := 0;
  PrevTail := nil;
  try
    while not Terminated do
    begin
      if ReadFile(FOutputRead, FBuffer[0], READ_BUFFER_SIZE, BytesRead, nil) and (BytesRead > 0) then
      begin
        Inc(ChunkCount);
        Log(Format('TConPtyReader.Execute: chunk %d, %d bytes', [ChunkCount, BytesRead]));
        if ChunkCount <= 5 then
        begin
          LPipeAvail := 0;
          LPipeTotal := 0;
          PeekNamedPipe(FOutputRead, nil, 0, nil, @LPipeAvail, @LPipeTotal);
          Log(Format('TConPtyReader.Execute: pipe state after chunk %d: available=%d total=%d', [ChunkCount, LPipeAvail, LPipeTotal]));
        end;

        TailCount := Length(PrevTail);
        SetLength(Combined, TailCount + BytesRead);
        if TailCount > 0 then
          Move(PrevTail[0], Combined[0], TailCount);
        if BytesRead > 0 then
          Move(FBuffer[0], Combined[TailCount], BytesRead);

        CompleteCount := CompleteUtf8Count(Combined);

        if CompleteCount > 0 then
        begin
          TextOut := TEncoding.UTF8.GetString(Combined, 0, CompleteCount);
          if TextOut <> '' then
            TThread.Synchronize(nil, procedure begin DoOutput(TextOut); end);
        end;

        SetLength(PrevTail, Length(Combined) - CompleteCount);
        if Length(PrevTail) > 0 then
          Move(Combined[CompleteCount], PrevTail[0], Length(PrevTail));
      end
      else
      begin
        if not Terminated then
        begin
          Log(Format('TConPtyReader.Execute: ReadFile EOF, GetLastError=%d', [GetLastError]));
          if Length(PrevTail) > 0 then
          begin
            TextOut := TEncoding.UTF8.GetString(PrevTail, 0, Length(PrevTail));
            PrevTail := nil;
            TThread.Synchronize(nil, procedure begin DoOutput(TextOut); end);
          end;
          TThread.Synchronize(nil, procedure begin DoTerminated; end);
        end;
        Break;
      end;
    end;
  finally
  end;
end;

end.
