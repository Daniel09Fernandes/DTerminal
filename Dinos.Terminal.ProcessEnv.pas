unit Dinos.Terminal.ProcessEnv;

interface

function CreateUserEnvironmentBlock: string;
function GetFreshUserPath: string;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Win.Registry,
  Dinos.Terminal.Debug;

function ExpandEnv(const AValue: string): string;
var
  Len: DWORD;
begin
  Result := AValue;
  if AValue = '' then
    Exit;
  Len := ExpandEnvironmentStrings(PChar(AValue), nil, 0);
  if Len = 0 then
    Exit;
  SetLength(Result, Len);
  Len := ExpandEnvironmentStrings(PChar(AValue), PChar(Result), Len);
  if Len > 0 then
    SetLength(Result, Len - 1)
  else
    Result := AValue;
end;

function ReadRegistryPath(ARoot: HKEY; const AKey: string): string;
var
  R: TRegistry;
begin
  Result := '';
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := ARoot;
    if not R.OpenKeyReadOnly(AKey) then
      Exit;
    if R.ValueExists('Path') then
      Result := R.ReadString('Path')
    else if R.ValueExists('PATH') then
      Result := R.ReadString('PATH');
  finally
    R.Free;
  end;
end;

procedure AddPathEntries(ADest: TStringList; const APath: string);
var
  Rest, Entry: string;
  P: Integer;
begin
  Rest := APath;
  while Rest <> '' do
  begin
    P := Pos(';', Rest);
    if P > 0 then
    begin
      Entry := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 1, MaxInt);
    end
    else
    begin
      Entry := Rest;
      Rest := '';
    end;
    Entry := ExpandEnv(Trim(Entry));
    if (Length(Entry) > 1) and (Entry[Length(Entry)] = '\') then
      Entry := ExcludeTrailingPathDelimiter(Entry);
    if (Entry <> '') and (ADest.IndexOf(Entry) < 0) then
      ADest.Add(Entry);
  end;
end;

function GetFreshUserPath: string;
var
  List: TStringList;
  UserPath, MachinePath: string;
begin
  List := TStringList.Create;
  try
    List.CaseSensitive := False;
    UserPath := ExpandEnv(ReadRegistryPath(HKEY_CURRENT_USER, 'Environment'));
    MachinePath := ExpandEnv(ReadRegistryPath(HKEY_LOCAL_MACHINE,
      'System\CurrentControlSet\Control\Session Manager\Environment'));
    AddPathEntries(List, UserPath);
    AddPathEntries(List, MachinePath);
    if List.Count = 0 then
      AddPathEntries(List, GetEnvironmentVariable('PATH'));
    List.StrictDelimiter := True;
    List.Delimiter := ';';
    Result := List.DelimitedText;
  finally
    List.Free;
  end;
end;

function CreateUserEnvironmentBlock: string;
var
  Env: PWideChar;
  P: PWideChar;
  Pair, Name, FreshPath: string;
  EqPos, OrigLen: Integer;
  HasPath: Boolean;
begin
  Result := '';
  HasPath := False;
  FreshPath := GetFreshUserPath;
  Log('ProcessEnv PATH=' + FreshPath);

  Env := GetEnvironmentStringsW;
  if Env = nil then
    Exit;

  try
    P := Env;
    while P^ <> #0 do
    begin
      Pair := P;
      OrigLen := Length(Pair);
      EqPos := Pos('=', Pair);
      if EqPos = 1 then
        Result := Result + Pair + #0
      else if EqPos > 1 then
      begin
        Name := Copy(Pair, 1, EqPos - 1);
        if SameText(Name, 'PATH') then
        begin
          Pair := 'PATH=' + FreshPath;
          HasPath := True;
        end;
        Result := Result + Pair + #0;
      end;
      Inc(P, OrigLen + 1);
    end;
    if not HasPath then
      Result := Result + 'PATH=' + FreshPath + #0;
    Result := Result + #0;
  finally
    FreeEnvironmentStringsW(Env);
  end;
end;

end.
