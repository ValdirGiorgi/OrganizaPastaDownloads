# Organiza Downloads

CLI em Dart para analisar itens diretos de uma pasta de downloads e separar arquivos/pastas em quarentena e auto-organizados.

Por padrao o programa nao move nem apaga arquivos. Ele imprime um resumo no console e gera um CSV e um log.
Quando `--csv` ou `--log` nao sao informados, ambos sao salvos em `<pasta analisada>/_auto_organizado/logs`. Use `--csv`/`--log` (ou as opcoes 4/5 do menu) para escolher outro lugar.
Durante a execucao, o terminal mostra uma barra de progresso para varredura, classificacao, duplicatas e gravacao do CSV.

A historia do projeto, o prompt usado na classificacao e o passo a passo completo no Linux e no Windows estao neste artigo: [Minha pasta Downloads virou um deposito](https://blog.valdir.dev.br/minha-pasta-downloads).

## Uso

Uso principal por menu:

```bash
dart pub get
dart run bin/organiza_downloads.dart
```

O menu abre direto com a acao principal:

```text
1. Executar agora
2. Modo
3. Pasta
4. Pasta do relatorio CSV
5. Pasta de log
6. Duplicatas por hash
7. Detalhes no final
8. Regras
9. Analise
10. Modelo IA
11. Categorias IA
12. Tamanho lote IA
13. Debug IA
14. Reavaliar organizados
15. Sair
```

Enter executa a opcao `1` com os valores atuais. Para mudar algo, escolha apenas o item desejado; depois o menu volta com o novo valor.

Modo `cold`: analisa arquivos e pastas do primeiro nivel, mostra resumo e gera CSV, sem mover nada.

Modo `real`: cria `_organiza_quarentena` e `_auto_organizado` dentro da pasta analisada. Arquivos classificados como `quarantine` vao para quarentena; todos os demais vao para `_auto_organizado`, separados por tema previamente classificado. Pastas do primeiro nivel sao movidas inteiras pela categoria escolhida.

Modo `IA`: pede a chave DeepSeek a cada execucao, nao salva a chave e envia somente nomes dos itens diretos. Categorias podem ser as padrao, texto separado por `;`, ou um JSON no formato `{"categories":["casa","trabalho"]}` ou `["casa","trabalho"]`.

O tamanho do lote IA e configuravel no menu. O padrao e `150` nomes unicos por chamada, com limite aceito entre `20` e `500`.

Com `Debug IA` ligado, o programa cria uma pasta `debug/` na pasta de execucao e salva os prompts, respostas e erros de cada lote. Os arquivos iniciam com data/hora, por exemplo `20260526_113000_batch_001_prompt.txt`. A chave DeepSeek nao e gravada; o header de autorizacao fica como `<redacted>`.

Ao final do modo `real`, subpastas vazias sao removidas. A pasta analisada deve ficar somente com `_organiza_quarentena` e `_auto_organizado`, salvo arquivos/pastas que nao puderem ser movidos por permissao ou por mudanca externa durante a execucao.

O modo antigo por parametro segue disponivel para automacao:

```bash
dart run bin/organiza_downloads.dart scan ~/Downloads --mode cold --hash-duplicates
```

```bash
dart run bin/organiza_downloads.dart scan ~/Downloads --mode real --hash-duplicates
```

Para escolher a pasta onde o CSV sera salvo por parametro:

```bash
dart run bin/organiza_downloads.dart scan ~/Downloads --mode cold --hash-duplicates --csv ./relatorios
```

O nome base do arquivo do relatorio e `organiza_downloads_relatorio.csv`, sempre prefixado com data/hora para evitar sobrescrita, por exemplo `20260526_113000_organiza_downloads_relatorio.csv`.

`--apply` continua aceito como atalho legado para `--mode real`.

Com regras customizadas:

```bash
dart run bin/organiza_downloads.dart scan ~/Downloads --config organiza_rules.example.json
```

Classificacao via IA sem menu interativo, passando a chave por parametro ou pela variavel de ambiente `DEEPSEEK_API_KEY`:

```bash
dart run bin/organiza_downloads.dart scan ~/Downloads --mode real --ai --api-key SUA_CHAVE
```

Para reclassificar itens que ja foram organizados (varre de uma vez todas as subpastas de categoria dentro de `_organiza_quarentena`/`_auto_organizado` e so move o que mudou de categoria):

```bash
dart run bin/organiza_downloads.dart reavaliar ~/Downloads --mode real --ai
```

## Modelo De Regras

Use [organiza_rules.example.json](organiza_rules.example.json) como base para customizar a organizacao:

- `quarantineDirectoryName`: pasta dos arquivos candidatos a descarte.
- `autoOrganizedDirectoryName`: pasta dos arquivos mantidos ou para revisao.
- `importantKeywords`: palavras no nome que indicam documentos importantes.
- `quarantineKeywords`: palavras no nome que sugerem temporario/instalador/cache.
- `temporaryExtensions`: extensoes temporarias que vao para quarentena.
- `installerExtensions`: instaladores que vao para quarentena.
- `model3dExtensions`, `documentExtensions`, `imageExtensions`, `videoAudioExtensions`, `backupExtensions`, `codeExtensions`: extensoes usadas para classificar temas dentro de `_auto_organizado`.

## Build

Linux:

```bash
./scripts/build_linux.sh
```

Windows, em uma maquina Windows:

```powershell
.\scripts\build_windows.ps1
```

O Dart SDK precisa estar instalado e no `PATH`.

Tambem existe um workflow em `.github/workflows/build.yml` para gerar os artefatos Linux e Windows pelo GitHub Actions.

## Rotina Automatica

Linux. O script `scripts/organizar_arquivos.sh` roda em modo real na pasta de downloads e na area de trabalho (resolvidas por `xdg-user-dir`), guarda os logs em `~/.local/share/organiza_downloads/logs`, os relatorios em `~/.local/share/organiza_downloads/relatorios` e avisa por `notify-send` no final. Argumentos extras sao repassados ao binario:

```bash
./scripts/organizar_arquivos.sh --ai
```

Para rodar a cada login, crie `~/.config/autostart/organizar-arquivos.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Organizar arquivos (login)
Exec=/caminho/do/projeto/scripts/organizar_arquivos.sh --ai
Icon=folder
Terminal=false
X-GNOME-Autostart-enabled=true
```

Para rodar so quando quiser, use `scripts/organizar_arquivos_launcher.sh` em um atalho: ele chama o script com `--pause --ai` e espera Enter antes de fechar o terminal.

Windows. O equivalente e `scripts/organizar_arquivos.ps1`, com o mesmo comportamento: resolve as pastas Downloads e Desktop pelo registro (respeita redirecionamento do OneDrive), grava logs e relatorios em `%LOCALAPPDATA%\organiza_downloads` e aceita argumentos extras.

```powershell
.\scripts\organizar_arquivos.ps1 --ai
```

Para rodar no logon:

```powershell
$acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\caminho\scripts\organizar_arquivos.ps1" --ai'
$gatilho = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'Organizar Downloads' -Action $acao -Trigger $gatilho
```

Para um atalho manual, use `-Pause` para o terminal esperar Enter antes de fechar.

## Chave Da API

A chave nunca e gravada em disco pelo programa, nao aparece em log e e redigida como `<redacted>` nos arquivos de debug. Ela vem de `--api-key` ou da variavel de ambiente `DEEPSEEK_API_KEY`; sem nenhuma das duas, o modo interativo pede a chave com digitacao mascarada.

Linux, para as execucoes automaticas da sessao grafica:

```bash
mkdir -p ~/.config/environment.d
# edite o arquivo em um editor e coloque a linha DEEPSEEK_API_KEY=...
# nao use echo: a chave ficaria gravada no historico do shell
chmod 600 ~/.config/environment.d/deepseek.conf
```

Windows:

```powershell
$chave = Read-Host 'Cole a chave da API'
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', $chave, 'User')
Remove-Variable chave
```

## Seguranca

- Nao existe comando de exclusao definitiva nesta versao.
- A analise nao entra nas subpastas; pastas diretas sao movidas inteiras.
- As pastas `_organiza_quarentena`, `_auto_organizado` e `debug` sao ignoradas em novas varreduras.
- `--mode cold` e o padrao e nao move arquivos.
- `--mode real` exige permissao de escrita na pasta analisada para criar as pastas de saida e mover arquivos.
- Duplicatas confirmadas por `--hash-duplicates` vencem a classificacao da IA: a primeira copia e mantida e as demais vao para quarentena.
- Itens diretos com nome de copia, como `arquivo (1).pdf` ou `pasta (1)`, tambem vao para `duplicados` como duplicata provavel, sem exclusao definitiva.

## Licenca

MIT. Veja [LICENSE](LICENSE).
