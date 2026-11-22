# PACE

Aplicativo Android (Flutter) de corrida de rua: grava corridas por GPS (inclusive com a tela bloqueada), importa o histórico de outros apps (.tcx/.gpx) e mostra histórico, parciais e evolução com dados reais.

## Baixar no celular

Abra a Release **ultima** do repositório e baixe o `pace.apk`:
https://github.com/Julio1021/Pace./releases/tag/ultima

## Assinatura (uma vez só)

Para que as atualizações instalem por cima sem apagar as corridas, todas as versões precisam da mesma chave. Ela fica nos **Secrets** do repositório (nunca no código):

- `PACE_KEYSTORE_B64` — o arquivo da chave (.jks) em base64
- `PACE_KEYSTORE_PASSWORD` — a senha da chave

Configure em **Settings › Secrets and variables › Actions › New repository secret**. Sem eles, o APK sai com uma assinatura temporária (funciona, mas cada versão exige desinstalar a anterior). Guarde uma cópia da chave e da senha em local seguro: sem elas não dá para atualizar o app instalado.

## Como gerar uma nova versão

Qualquer envio (push) para a branch `main` dispara o GitHub Actions (`.github/workflows/build.yml`), que:

1. gera as pastas nativas com `flutter create` e aplica a configuração de `tool/setup_platforms.py` (permissões, assinatura, minSdk 26);
2. roda a análise do código e os testes;
3. gera prints das telas na branch `saida`;
4. compila o APK e publica na Release `ultima`.

Também dá para rodar manualmente em **Actions › Compilar app › Run workflow**.

## Estrutura

- `lib/core` — tema e formatação (pt-BR, métrico, 24 h)
- `lib/domain` — modelos e cálculos puros (distância, filtro de GPS, pausa automática, pace, parciais, elevação, estatísticas)
- `lib/data` — banco SQLite, importação TCX/GPX, exportação GPX/TCX e backup
- `lib/services/recorder.dart` — gravação da corrida (serviço em primeiro plano, salvamento contínuo e recuperação)
- `lib/ui` — telas e componentes
- `test` — testes de cálculo e importação (com corridas reais do NRC em `test/fixtures`, com a longitude deslocada para não expor o local)

## Regras de cálculo

- GPS: descarta precisão pior que 20 m, saltos acima de 9 m/s e deslocamentos menores que 3 m.
- Pausa automática: abaixo de 0,8 m/s por 8 s; retoma acima de 1,2 m/s.
- Pace atual: janela móvel de 30 s; pace médio = tempo em movimento ÷ distância; arredondado ao segundo.
- Parciais: tempo de passagem de cada km interpolado entre os pontos vizinhos.
- Calorias (estimativa): 1,0 kcal × peso (kg) × km.
- Elevação: média móvel de 5 pontos e histerese de 2 m.
- Importação: totais vêm do resumo (`Lap`) do TCX; se o GPS cobre menos de 90% da distância, a corrida é marcada como "GPS parcial" e não mostra parciais.
- Duplicadas: mesmo início (até 2 min) e distância (até 3%).
