# Changelog — Placar

## Versão 0.3.1

### Novidades

- Modo de placar **Quem está sacando**: ordem da narração sacador → receptor, com pergunta inicial de quem saca (tela e Bluetooth).
- Estilo de fala **Completa** ou **Reduzida** nas configurações de voz.
- No tênis, **indicador visual do lado do saque** (direita/igualdade vs esquerda/vantagem) com barras laterais nos cards dos times.
- Site atualizado: logo, link da Play Store e destaque ao controle por **smartwatch**.

### Melhorias

- Narração no vôlei atualiza o sacador **antes** de falar o ponto (placar do sacador primeiro na hora).
- Ao abrir “Quem inicia o saque?”, o TTS pergunta **“Quem inicia sacando?”**.
- No tênis, ao terminar um game, anuncia quem saca no próximo (`… saca!`).
- Em **vantagem**, a voz diz só **“Vantagem para [time]!”** (completa e reduzida), sem “vantagem a 40”.
- Badges **WAKELOCK** / **AGUARDANDO BT** deixam de sumir em telas baixas (HUD com altura natural + modo compacto).
- Sliders de velocidade e tom não fazem mais o modal de vozes rolar para o topo.
- Versão do app alinhada ao `pyproject.toml` (`__version__.py`); Fast push também sincroniza o `build_number`.

### Correções

- Fala reduzida com **Maior pontuação** ordenava sempre A→B (ex.: “0 a 15”); agora lê a maior pontuação primeiro.
- Splash/ícone Android passam a regenerar a partir de `src/assets` (cache antigo deixava logo velha na abertura).
