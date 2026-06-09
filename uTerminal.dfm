object Terminal: TTerminal
  Left = 0
  Top = 0
  BorderStyle = bsNone
  Caption = 'Terminal'
  ClientHeight = 446
  ClientWidth = 638
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  FormStyle = fsMDIForm
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object RTerm: TRichEdit
    Left = 0
    Top = 0
    Width = 638
    Height = 446
    Align = alClient
    Font.Charset = ANSI_CHARSET
    Font.Color = clWindowText
    Font.Height = 14
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    PlainText = True
    TabOrder = 0
    OnKeyDown = RTermKeyDown
    OnKeyPress = RTermKeyPress
  end
  object tmrLoad: TTimer
    OnTimer = tmrLoadTimer
    Left = 400
    Top = 240
  end
end
