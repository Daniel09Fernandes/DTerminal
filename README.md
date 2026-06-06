# DTerminal 🦖

**Alpha Version**

**DTerminal** é um terminal de comandos integrado diretamente à IDE do Delphi. Ele permite que você execute comandos e automatize tarefas sem precisar sair do seu ambiente de desenvolvimento, trazendo total compatibilidade com **WSL (Linux)**, **CMD** e **PowerShell**.

---

## 🚀 Funcionalidades

* **Integração Nativa:** Funciona como uma janela acoplável (*Dockable Form*) dentro da IDE do Delphi.
* **Multi-Terminal:** Suporte nativo para WSL, Prompt de Comando (CMD) e PowerShell.
* **Persistência de Layout:** Mantém-se fixo no seu ambiente tanto em modo de design quanto em modo de debug.

---

## 🛠️ Como Instalar e Ativar

Para instalar o plugin na sua IDE, siga os passos abaixo:

1. Abra o projeto do pacote `DinosTerminal.dproj` no seu Delphi.
2. No **Project Manager** (Gerenciador de Projetos), clique com o botão direito sobre o projeto e execute as ações nesta ordem:
   * 🧼 **Clean**
   * 🔨 **Build**
   * ⚡ **Install**
3. Após a instalação, um novo menu chamado **DinosTools** aparecerá na barra superior da IDE.
4. Clique em `DinosTools -> DinosTerminal` para abrir a janela do terminal.

---

## 📐 Configuração Recomendada de Layout (Docking)

Como o Delphi gerencia layouts de forma separada para codificação e depuração, siga esta sugestão para que o seu terminal nunca suma da tela:

1. **Layout Padrão (Design):**
   * Abra o terminal pelo menu.
   * Arraste e **acople (dock)** a janela no local de sua preferência (ex: junto à aba de mensagens inferior).
   * Vá no menu superior da IDE: `View -> Desktops -> Save Desktop...`
   * Selecione ou digite **Default Layout** e salve.

2. **Layout de Depuração (Debug):**
   * Inicie o debug de qualquer projeto (**F9**). O layout da IDE vai mudar.
   * Se o terminal sumir, vá novamente em `DinosTools -> DinosTerminal` (ele abrirá imediatamente).
   * Posicione e acople o terminal onde deseja que ele fique enquanto você debuga.
   * Vá no menu superior da IDE: `View -> Desktops -> Save Desktop...`
   * Selecione ou digite **Debug Layout** e salve.

Pronto! Agora o terminal se moverá e se adaptará automaticamente sempre que você alternar entre codificar e debugar.

---

## 📸 Demonstração


<img width="1358" height="722" alt="TerminalDelphi" src="https://github.com/user-attachments/assets/7ffc1a57-4288-44b3-b424-59f89af83c57" />


---

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.
