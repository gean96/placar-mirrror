# 🏆 Placar Remoto Flet

O **Placar** é uma aplicação interativa e multiplataforma desenvolvida em Python utilizando o framework **Flet** (baseado em Flutter). Projetado especialmente para quadras, arenas ou jogos casuais, o aplicativo permite gerenciar pontuações de partidas em tempo real e oferece controle remoto via Bluetooth e narração automatizada.

---

## ✨ Principais Recursos

*   **🎮 Controle Remoto via Bluetooth (BT):**
    *   Suporte a botões remotos Bluetooth de 3 botões (como botões de selfie ou controles de mídia).
    *   **Botão Next:** Pontuação para o Time B (Time Rosa).
    *   **Botão Prev:** Pontuação para o Time A (Time Azul).
    *   **Botão Click:** Alterna entre Play e Pause no cronômetro/partida.
    *   **Botão Play:** Confirma ações ou reinicia a partida.
    *   *Badge* dinâmico de status indicando se o Bluetooth está pareado ou aguardando sinal.
*   **🗣️ Narração por Voz (Text-to-Speech - TTS):**
    *   Anuncia pontuações e eventos de jogo por voz em tempo real.
    *   Controle total de velocidade da fala, tom de voz (pitch) e seleção do sintetizador nativo do dispositivo.
    *   Opção de recuperar automaticamente o foco de mídia para garantir que as narrações não sejam interrompidas.
*   **📊 Histórico Local de Partidas:**
    *   Gravação automática do resultado das partidas finalizadas no arquivo `matches_history.json`.
    *   Salvamento 100% off-line e focado na privacidade do usuário.
*   **⚙️ Painel de Configurações:**
    *   Personalização completa dos nomes dos times.
    *   Configurações persistentes salvas localmente no arquivo `app_settings.json`.
*   **📱 Multiplataforma:**
    *   Funciona de forma responsiva em Celulares (Android, iOS), Computadores (Windows, macOS, Linux) e Web.

---

## 🛠️ Requisitos e Configuração

Esta aplicação utiliza o gerenciador de pacotes moderno **uv** para gerenciar dependências de forma rápida e isolada.

### Pré-requisitos
*   **Python:** versão `3.10` ou superior.
*   **uv:** Gerenciador de dependências instalado. (Se não possuir o `uv`, instale-o seguindo as instruções oficiais ou utilize o `pip`).

---

## 🚀 Como Executar o Aplicativo

### 1. Clonar o repositório e navegar até a pasta:
```bash
git clone https://github.com/geanferreira96/placar.git
cd placar
```

### 2. Executar como Aplicativo Desktop:
```bash
uv run flet run
```

### 3. Executar como Aplicação Web:
```bash
uv run flet run --web
```

---

## 📦 Como Compilar/Gerar Pacotes de Distribuição

O Flet permite compilar seu aplicativo de forma nativa para todas as principais plataformas. Utilize os comandos abaixo conforme a sua necessidade:

### 🤖 Android (Gera o arquivo `.apk` ou `.aab`)
```bash
flet build apk -v
```
*Consulte o [Guia de Empacotamento Android](https://flet.dev/docs/publish/android/) para assinar seu APK de produção.*

### 🍏 iOS
```bash
flet build ipa -v
```
*Consulte o [Guia de Empacotamento iOS](https://flet.dev/docs/publish/ios/) para detalhes de provisionamento.*

### 💻 Windows
```bash
flet build windows -v
```

### 🍎 macOS
```bash
flet build macos -v
```

### 🐧 Linux
```bash
flet build linux -v
```

### 🌐 Web
```bash
flet build web -v
```

---

## 🔒 Política de Privacidade

O aplicativo Placar segue uma política estrita de privacidade local e off-line. Detalhes completos sobre o tratamento de dados (como o uso do Bluetooth e do armazenamento local) estão disponíveis no documento **[Política de Privacidade](privacy.html)** localizado na raiz do projeto.

---

## 🛡️ Licença e Direitos Autorais

*   **Desenvolvedor:** Gean Ferreira (gean.marcos96@gmail.com)
*   **Copyright:** Copyright (C) 2023-2026 por Flet / GF Solutions. Todos os direitos reservados.
