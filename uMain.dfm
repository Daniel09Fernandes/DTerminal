object ManangerTerminal: TManangerTerminal
  Left = 0
  Top = 0
  Caption = 'Mananger Terminal'
  ClientHeight = 441
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object PgTerminal: TPageControl
    Left = 0
    Top = 0
    Width = 624
    Height = 441
    ActivePage = TabDefault
    Align = alClient
    PopupMenu = PopTerminal
    TabOrder = 0
    object TabDefault: TTabSheet
      Caption = 'Default Terminal'
      OnEnter = TabDefaultEnter
    end
  end
  object PopTerminal: TPopupMenu
    Left = 96
    Top = 24
    object NewTerminal: TMenuItem
      Caption = 'New Terminal'
      object CMD1: TMenuItem
        Tag = 1
        Caption = 'CMD'
        OnClick = CMD1Click
      end
      object WSL1: TMenuItem
        Caption = 'WSL'
        OnClick = CMD1Click
      end
      object PowerShell1: TMenuItem
        Tag = 2
        Caption = 'PowerShell'
        OnClick = CMD1Click
      end
    end
    object Renomear1: TMenuItem
      Caption = 'Renomear'
      OnClick = Renomear1Click
    end
    object Excluir1: TMenuItem
      Caption = 'Excluir'
      OnClick = Excluir1Click
    end
  end
end
