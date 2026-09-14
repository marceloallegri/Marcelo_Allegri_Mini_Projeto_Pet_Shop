# Marcelo_Allegri_Mini_Projeto_Pet_Shop
Pata Amiga - Modelagem Dimensional e ETL em MySQL

Este repositório junta três bases que não conversam entre si (a plataforma de e-commerce, o cadastro de lojas do franchising e a planilha de praças de atendimento) em um único modelo dimensional, e usa esse modelo para responder as cinco perguntas da diretoria.

Resumo do que eu achei: o gargalo da entrega não está na transportadora, está entre a emissão da nota fiscal e o despacho, que sozinho consome 4,11 dos 9,00 dias do processo. Nas lojas de porte Pequeno essa mesma etapa leva 8,53 dias e o processo inteiro vai para 15,16. No mapa, o Vale do Itajaí concentra 35,34% do faturamento com 17,29% dos domicílios com pet, e Foz do Itajaí faz o contrário: 8,64% dos domicílios e só 2,61% do faturamento.

## 1. O caso

A Pata Amiga é uma rede catarinense de pet shops com 32 lojas, de Itapoá a São Miguel do Oeste. Entre 01/09/2023 e 31/03/2024 a operação de pedidos com entrega (app, site, telefone, WhatsApp e loja física) registrou 4.044 pedidos.

Os dados vieram em três tabelas de staging, com todas as colunas em texto e os nomes fora de snake_case, o que obriga a escrever `` `Cod Loja` ``, `` `QTD.Itens` `` e `` `ValorLiquidoPedido(R$)` `` entre crases. Não alterei nenhuma das tabelas `stg_`: não existe UPDATE nem ALTER em nenhum script daqui. Todo o tratamento acontece nos INSERT das dimensões e da fato.

| Tabela | O que é | Linhas |
|---|---|---:|
| stg_pedido | pedidos e os 4 marcos do processo de entrega | 4.044 |
| stg_loja | cadastro das 32 lojas, a foto de hoje | 32 |
| stg_loja_praca | loja x praça de atendimento, com o % do público | 48 |

## 2. Como reproduzir o banco do zero

Precisa de MySQL 8.0. A collation padrão dele (`utf8mb4_0900_ai_ci`) ignora acento e caixa, e o modelo conta com isso.

```bash
mysql -u root -p --default-character-set=utf8mb4 < scripts/01-carga-staging.sql
mysql -u root -p --default-character-set=utf8mb4 < scripts/02-dimensoes-prontas.sql
mysql -u root -p --default-character-set=utf8mb4 < scripts/03-dimensoes.sql
mysql -u root -p --default-character-set=utf8mb4 < scripts/04-fato.sql
mysql -u root -p --default-character-set=utf8mb4 < scripts/05-perguntas.sql
```

A ordem importa, cada arquivo depende do anterior:

| # | Arquivo | O que faz |
|---|---|---|
| 01 | 01-carga-staging.sql | cria o banco dw_pata_amiga e carrega as três tabelas de origem (veio pronto) |
| 02 | 02-dimensoes-prontas.sql | dim_tempo e dim_loja já carregadas, mais o CREATE TABLE das outras quatro (veio pronto) |
| 03 | 03-dimensoes.sql | preenche dim_categoria, dim_praca e bridge_loja_praca |
| 04 | 04-fato.sql | preenche fato_pedido, um único INSERT ... SELECT, 4.044 linhas |
| 05 | 05-perguntas.sql | as cinco consultas de negócio |
| 00 | 00-conferencia.sql | conferência de cada etapa (não faz parte da entrega) |

Uma observação que me custou tempo: o `--default-character-set=utf8mb4` não é enfeite. Sem ele o cliente lê o arquivo como latin1, "Ração" vira `RaÃ§Ã£o` e a contagem de grafias distintas de categoria sobe de 18 para 23. Levei um tempo até entender por que meu número não batia com o do enunciado.

## 3. Diagnóstico da origem

Fiz isso antes de escrever qualquer INSERT, só com SELECT em cima das três `stg_`. Foi esse levantamento que decidiu o resto do projeto.

### 3.1 As contagens pedidas

| Diagnóstico | Valor |
|---|---:|
| Grafias distintas de nome de loja (`Loja-Nome`) | 50 |
| Grafias distintas de categoria (`CategoriaProduto`) | 18 |
| Pedidos sem `Cod Loja` preenchido | 1.575 (38,95%) |
| Pedidos sem nome de loja | 3 |
| Marcos em branco: separação / nota / despacho / entrega | 1.077 / 1.338 / 1.665 / 1.953 |

Esses são os números do MySQL, cuja collation ignora acento e caixa. Se a comparação for byte a byte (`BINARY`), aparece a bagunça real da origem:

| Campo | Distintos no MySQL | Distintos byte a byte |
|---|---:|---:|
| `Loja-Nome` | 50 | 128 |
| `CategoriaProduto` | 18 | 37 |
| `HouveDesconto` | 12 | 17 |
| `CanalPedido` | 8 | 20 |

### 3.2 Os problemas, um a um

| Problema | Onde | O que ele exige |
|---|---|---|
| Todas as colunas em texto | as três stg_ | staging separada da área de apresentação |
| Nomes fora de snake_case | `Cod Loja`, `QTD.Itens` | identificador entre crase |
| Dois formatos de data na mesma tabela | stg_pedido | a máscara certa por coluna |
| 18 grafias para 7 categorias | `CategoriaProduto` | a dimensão guarda a grafia crua |
| "Ração Medicamentosa" não é ração | `CategoriaProduto` | a ordem do CASE importa |
| 50 grafias de loja (128 byte a byte) | `Loja-Nome` | padronizar antes do lookup |
| `Cod Loja` vazio em 39% das linhas | stg_pedido | resolver pelo nome |
| 3 pedidos sem loja identificada | stg_pedido | linha -1, nunca FK nula |
| Sim/não escrito de 17 maneiras | `HouveDesconto` | padronizar na carga da fato |
| Canal escrito de 20 maneiras | `CanalPedido` | padronizar, WHATS antes de APP |
| Números em formatos misturados | colunas numéricas | a regra dos números |
| Loja em mais de uma praça | stg_loja_praca | tabela ponte com fator |
| Cadastro só com a foto de hoje | stg_loja | o passado foi sobrescrito (limite da P5) |
| 2 datas por pedido na fato | stg_pedido | role-playing dimension |
| Marco em branco = processo aberto | stg_pedido | FK para -1 e NULL nos dias |
| Número do pedido sem atributos | `NumeroPedido` | dimensão degenerada |

### 3.3 A armadilha da data

Rodei as duas máscaras lado a lado antes de escrever a fato:

```sql
SELECT SUM(STR_TO_DATE(`DtHoraPedido`,'%m/%d/%Y %h:%i %p') IS NOT NULL) AS mascara_americana_ok,
       SUM(STR_TO_DATE(`DtHoraPedido`,'%d/%m/%Y %h:%i %p') IS NOT NULL) AS mascara_brasileira_ok
FROM stg_pedido;
```

| máscara americana ok | máscara brasileira ok |
|---:|---:|
| 4.044 | 1.556 |

O detalhe perigoso é que a máscara brasileira não dá erro. Ela converte 1.556 linhas, que são justamente aquelas em que o dia é menor ou igual a 12, e nessas o dia e o mês saem trocados. Nas outras 2.488 ela devolve NULL, em silêncio. Por isso a máscara usada é `'%m/%d/%Y %h:%i %p'`.

### 3.4 Buracos nas métricas

| Coluna | Vazio ou '-' |
|---|---:|
| `QTD.Itens` | 257 (6,36%) |
| `ValorLiquidoPedido(R$)` | 121 (2,99%) |

Os dois casos viram NULL, nunca 0.

## 4. O modelo dimensional

![Modelo estrela](diagrama/modelo-estrela.png)

O arquivo fonte do diagrama está em `diagrama/modelo-estrela.dot` (Graphviz, que o draw.io importa em Arrange > Insert > Advanced > Graphviz) e também em SVG.

Uma fato, quatro dimensões e uma ponte:

| Tabela | Grão | Linhas |
|---|---|---:|
| fato_pedido | 1 linha = 1 pedido | 4.044 |
| dim_tempo (pronta) | 1 dia | 236 (235 + a -1) |
| dim_loja (pronta) | 1 loja | 33 (32 + a -1) |
| dim_categoria | 1 grafia da origem | 19 (18 + a -1) |
| dim_praca | 1 praça de atendimento | 13 (12 + a -1) |
| bridge_loja_praca | 1 loja x 1 praça | 48 |

O que o diagrama mostra:

1. A fato_pedido no centro, com o grão escrito ao lado.
2. As dimensões em volta, ligadas direto à fato: dim_tempo, dim_loja e dim_categoria.
3. A dim_tempo ligada duas vezes. É a mesma tabela em dois papéis, `sk_tempo_pedido` (quando o cliente pediu) e `sk_tempo_entrega` (quando chegou). Isso se chama role-playing dimension. Como a chave é a própria data em número (20231116), a fato monta as duas FKs por cálculo, sem JOIN.
4. A dim_praca ligada à dim_loja pela bridge_loja_praca, e não direto à fato. É o único caminho indireto do modelo.

### Três decisões que eu preciso justificar

O grão da dim_categoria é a grafia, não a categoria. Cada uma das 18 grafias cruas virou uma linha, guardando ao lado o nome padronizado. Com isso a fato acha a linha certa com um JOIN de uma linha só (`dc.categoria_origem = p.CategoriaProduto`), sem subconsulta e sem repetir o de-para dentro dela. Se a limpeza morasse na fato, qualquer grafia nova obrigaria a recarregar as 4.044 linhas.

Desconto e canal ficaram na própria fato. São dois domínios de pouquíssimos valores e sem nada pendurado neles. Uma dimensão só com a PK e o nome não acrescenta informação e ainda cobra um JOIN em toda consulta.

Só uma coluna de dinheiro entrou. A stg_pedido também traz valor bruto, desconto em reais, unidades devolvidas, itens cancelados, peso e frete, e nenhuma das cinco perguntas usa nada disso. Decidir o que fica de fora também é modelagem.

Por fim, não gravei nenhum percentual nem taxa dentro da fato. Percentual e "itens por mil habitantes" não são aditivos, somar dois deles não significa nada. Eles são calculados na consulta, no arquivo 05. Na fato só entraram medidas aditivas (`qt_itens` e `vl_liquido`) e os lags em dias.

## 5. Decisões de tratamento

### 5.1 Datas

| Onde | Como vem | Como converti |
|---|---|---|
| `DtHoraPedido`, `DtHoraIntegracaoERP` | 11/16/2023 02:30 PM | `STR_TO_DATE(col, '%m/%d/%Y %h:%i %p')` |
| Os 4 marcos da entrega | 2023-11-16 | `DATE(col)` |
| A chave da dim_tempo | vira 20231116 | `CAST(DATE_FORMAT(data,'%Y%m%d') AS SIGNED)` |

### 5.2 A regra dos números

| Se o valor for | O que fiz |
|---|---|
| vazio ou '-' | gravei NULL, nunca 0 |
| 'R$ 1.850,00' | tirei o R$ e o espaço, tirei o ponto de milhar, troquei a vírgula por ponto |
| '1850.00' | já está pronto, só converter |
| '1.200' | tirei o ponto antes de converter |

O motivo de nunca usar zero: AVG ignora NULL mas soma o zero. Um zero no lugar de "não aconteceu" faria o gargalo da P1 parecer mais rápido do que é, e diluiria o ticket médio da P3.

### 5.3 O de-para das categorias, e por que a ordem importa

"Ração Medicamentosa" contém RA. Se eu testasse RA antes de MED, esses itens iriam para Ração e a P2 sairia com o número trocado, justamente na categoria campeã.

| Ordem | Se contém | nome_categoria | grupo_categoria |
|---:|---|---|---|
| 1 | MED | Medicamento | Saude e Higiene |
| 2 | PETISC | Petisco | Alimentacao |
| 3 | RA | Racao | Alimentacao |
| 4 | HIG | Higiene | Saude e Higiene |
| 5 | BRINQ | Brinquedo | Bem-estar |
| 6 | ACESS | Acessorio | Bem-estar |
| 7 | SERV | Servico | Bem-estar |
| - | nenhum dos acima | Nao Informado | Nao Informado |

Todo trecho testado é sem acento e em UPPER, para o resultado não depender da instalação. Os valores gravados também vão sem acento (Racao, Alimentacao, Servico, Nao Informado).

Conferindo: as 18 grafias caem em 7 categorias mais a linha -1, o que dá 8 valores distintos de `nome_categoria`, e a consulta que procura grafia não classificada volta vazia.

### 5.4 O nome da loja, padronizado antes do lookup

A parte mecânica é REPLACE para tirar o sufixo `/SC` e o espaço duplo, com TRIM e UPPER fechando.

A parte que exigiu decisão foi o resto. Erro de digitação, apelido e abreviação não saem com REPLACE. Depois da limpeza mecânica sobraram exatamente três, que resolvi com um CASE escrito à mão:

| Grafia na origem | Deve virar | Tipo |
|---|---|---|
| PATA AMIGA BLUMENAL CENTRO | PATA AMIGA BLUMENAU CENTRO | erro de digitação |
| PATA AMIGA FLORIPA NORTE | PATA AMIGA FLORIANOPOLIS NORTE | apelido |
| PATA AMIGA JGUA DO SUL | PATA AMIGA JARAGUA DO SUL | abreviação |

Não normalizei acento nem caixa porque não precisa: `SELECT 'Timbo' = 'TIMBO';` devolve 1 na collation padrão do MySQL.

O lookup é pelo nome, e não pelo `Cod Loja`, que seria o caminho óbvio. O código está vazio em 1.575 linhas, 39% do total. Depois da limpeza, todos os nomes encontram par na dim_loja e sobram só os 3 pedidos sem nome nenhum, que vão para a linha -1.

### 5.5 Desconto e canal

O desconto chega de 17 jeitos e cai em três valores. Comparei em UPPER e com TRIM nas pontas:

| Se o valor for | Grave |
|---|---|
| S, SIM, 1, X, TRUE, V | Sim |
| N, NAO, 0, FALSE, F | Nao |
| vazio, ou qualquer outra coisa | Nao Informado |

No canal a ordem do CASE importa de novo, porque WHATSAPP contém APP. Testar APP antes de WHATS jogaria os 414 pedidos de WhatsApp para dentro do App e a P3 sairia errada.

| Ordem | Se contém | Grave |
|---:|---|---|
| 1 | WHATS | WhatsApp |
| 2 | APP | App |
| 3 | SITE | Site |
| 4 | LOJA | Loja Fisica |
| 5 | TEL | Telefone |
| - | nenhum | Nao Informado |

### 5.6 Os cinco lags

| Coluna | Marco de início | Marco de fim |
|---|---|---|
| dias_integracao_separacao | DtHoraIntegracaoERP | Dt Separacao Estoque |
| dias_separacao_nota | Dt Separacao Estoque | DtNotaFiscal |
| dias_nota_despacho | DtNotaFiscal | Dt_Despacho_Transportadora |
| dias_despacho_entrega | Dt_Despacho_Transportadora | DtEntregaCliente |
| dias_total_ate_entrega | DtHoraIntegracaoERP | DtEntregaCliente |

A última linha não é um intervalo do processo, é o processo inteiro, e é ela que responde a P1. Quando o marco de fim vem em branco eu gravo NULL, usando `NULLIF(TRIM(col),'')`, que o DATEDIFF propaga sozinho.

### 5.7 A ponte e o fator de rateio

Uma loja entrega em mais de uma praça, e uma FK só comporta um valor. Se a `sk_praca` ficasse dentro da dim_loja, ou dentro da fato, eu teria que escolher uma praça e perder as outras. Por isso a ligação N:N ficou em tabela própria, com o `fator_publico` dentro. Os fatores de uma loja somam 1,00 em todas as 32, conferi.

A ponte liga pelo `cod_loja`, que é a chave natural, e não pela `sk_loja`. Assim ela continua válida se a dim_loja for recarregada.

Na P4 eu multiplico o faturamento da loja pelo fator antes de somar por praça. Sem isso, quem atende duas praças seria contado duas vezes e a soma estouraria o total da rede.

## 6. As cinco respostas

Todos os números saem do `scripts/05-perguntas.sql`, rodado sobre a fato de 4.044 linhas. O faturamento total da rede é R$ 1.793.309.

### P1. Onde está o gargalo da entrega?

O processo inteiro leva 9,00 dias em média, do pedido entrar no ERP até chegar na casa do cliente. A base são os 2.091 pedidos já entregues, porque os outros 1.953 ainda estavam em aberto no fim da janela e entram como NULL.

| Intervalo | Dias (média) |
|---|---:|
| Integração até Separação | 2,13 |
| Separação até Nota | 0,64 |
| Nota até Despacho | 4,11 |
| Despacho até Entrega | 2,14 |
| Total, ERP até cliente | 9,00 |

O gargalo é o intervalo entre a nota e o despacho, com 4,11 dias. A transportadora leva 2,14. Ou seja, o pedido passa 46% do processo parado dentro de casa, numa etapa que não depende de ninguém de fora.

Por porte de loja:

| Porte | Pedidos | Integr/Sep | Sep/Nota | Nota/Despacho | Desp/Entrega | Total |
|---|---:|---:|---:|---:|---:|---:|
| Grande | 1.763 | 1,96 | 0,64 | 3,32 | 2,01 | 7,93 |
| Média | 1.663 | 1,98 | 0,62 | 3,34 | 2,03 | 7,95 |
| Pequena | 615 | 3,02 | 0,69 | 8,53 | 2,86 | 15,16 |

A etapa culpada é a mesma nos três portes, então a resposta é sim, o gargalo é o mesmo. O que muda é o tamanho: nas lojas Pequenas ele passa de 8,5 dias, mais que o dobro das outras, e puxa o processo inteiro para 15,16 dias. Grande e Média são praticamente iguais entre si (7,93 contra 7,95).

Os 3 pedidos sem loja identificada aparecem na consulta como porte "Nao Informado" e não mudam nada, são 3 linhas.

### P2. Qual categoria concentra o faturamento?

Agrupado pelo nome padronizado, nunca pela grafia crua.

| Categoria | Grupo | Pedidos | Itens | Faturamento (R$) | % do total |
|---|---|---:|---:|---:|---:|
| Racao | Alimentacao | 1.387 | 9.457 | 1.076.202,55 | 60,01% |
| Medicamento | Saude e Higiene | 667 | 4.331 | 305.904,03 | 17,06% |
| Petisco | Alimentacao | 759 | 4.835 | 128.590,16 | 7,17% |
| Servico | Bem-estar | 269 | 809 | 94.001,37 | 5,24% |
| Higiene | Saude e Higiene | 507 | 2.965 | 92.314,45 | 5,15% |
| Acessorio | Bem-estar | 263 | 818 | 64.661,39 | 3,61% |
| Brinquedo | Bem-estar | 192 | 578 | 31.634,56 | 1,76% |
| Total | | 4.044 | | 1.793.309 | 100% |

Ração sozinha sustenta 60% do faturamento. Com Petisco junto, o grupo Alimentação chega a 67,18%. Um detalhe que vale reparar: Ração tem 1.387 pedidos, que são 34% do total de pedidos, mas 60% da receita. É a categoria de ticket alto, não só de volume.

A campeã é a mesma nos três portes: Ração lidera em Grande (R$ 468.186,60), Média (R$ 443.131,62) e Pequena (R$ 164.197,55). A ordem das sete categorias é igual nos três, com uma única troca, Higiene passando Serviço nas lojas Pequenas.

O item que exigiu cuidado aqui foi "Racao Medicamentosa", com 89 pedidos. Com o CASE na ordem errada, eles iriam para Ração e distorceriam exatamente a categoria mais importante.

### P3. O desconto funciona igual em todo canal?

| Canal | Pedidos | Faturamento (R$) | % do fat. | Ticket com desc. | Ticket sem desc. | Diferença |
|---|---:|---:|---:|---:|---:|---:|
| App | 1.273 | 552.134,43 | 30,79% | 488,04 | 167,63 | +320,41 |
| Site | 1.032 | 450.569,37 | 25,13% | 501,92 | 189,68 | +312,23 |
| Loja Fisica | 824 | 360.677,22 | 20,11% | 494,04 | 197,55 | +296,49 |
| WhatsApp | 414 | 188.678,63 | 10,52% | 514,33 | 179,26 | +335,07 |
| Telefone | 264 | 123.419,29 | 6,88% | 514,02 | 195,23 | +318,79 |
| Nao Informado | 237 | 117.829,57 | 6,57% | 561,59 | 206,95 | +354,64 |

Funciona igual, sim, e o resultado é o contrário do que eu esperava. Em todos os cinco canais o ticket médio com desconto é de 2,5 a 2,9 vezes maior que o sem desconto, e a diferença fica numa faixa bem estreita, de 296 a 335 reais. Não achei nenhum canal em que a política se comporte de outro jeito.

Só que a leitura não pode ser "o desconto aumenta o ticket". O mais provável é o inverso: o desconto está atrelado ao tamanho do pedido, pedido grande ganha desconto e pedido pequeno não. A estabilidade da diferença entre os cinco canais reforça isso, porque indica uma regra comercial única aplicada na rede toda, e não cinco políticas diferentes.

Sobre a participação de cada canal, o digital (App mais Site) responde por 55,92% do faturamento, contra 20,11% da loja física.

### P4. Qual praça concentra o faturamento?

Faturamento rateado pelo `fator_publico` da ponte. A base são 856.000 domicílios com pet nas 12 praças.

| Praça | Regional | Domicílios c/ pet | Faturamento rateado (R$) | % do fat. | % dos domicílios | R$/domicílio |
|---|---|---:|---:|---:|---:|---:|
| Vale do Itajai | Leste | 148.000 | 633.746,09 | 35,34% | 17,29% | 4,28 |
| Grande Florianopolis | Leste | 132.000 | 283.546,75 | 15,81% | 15,42% | 2,15 |
| Norte Industrial | Norte | 96.000 | 175.431,90 | 9,78% | 11,21% | 1,83 |
| Litoral Sul | Sul | 58.000 | 137.051,20 | 7,64% | 6,78% | 2,36 |
| Litoral Norte | Norte | 61.000 | 128.872,75 | 7,19% | 7,13% | 2,11 |
| Extremo Oeste | Oeste | 63.000 | 98.359,18 | 5,48% | 7,36% | 1,56 |
| Carbonifera | Sul | 67.000 | 88.707,42 | 4,95% | 7,83% | 1,32 |
| Serra Catarinense | Oeste | 44.000 | 80.477,64 | 4,49% | 5,14% | 1,83 |
| Meio-Oeste | Oeste | 51.000 | 58.955,63 | 3,29% | 5,96% | 1,16 |
| Foz do Itajai | Leste | 74.000 | 46.749,72 | 2,61% | 8,64% | 0,63 |
| Planalto Norte | Norte | 33.000 | 31.100,84 | 1,73% | 3,86% | 0,94 |
| Planalto Serrano | Oeste | 29.000 | 29.323,10 | 1,64% | 3,39% | 1,01 |

A conferência fecha: R$ 1.792.322 de soma rateada mais R$ 986 dos 3 pedidos sem loja, que não têm praça, dá exatamente R$ 1.793.309, o total da rede. A diferença é zero.

O Vale do Itajaí concentra 35,34% do faturamento com 17,29% dos domicílios com pet, o dobro do que a base de público justificaria, e R$ 4,28 por domicílio contra a média de R$ 2,10 da rede. Não é coincidência: 12 das 32 lojas atendem essa praça, e foi ali que a rede começou, em 2009.

O extremo oposto é Foz do Itajaí, com 8,64% dos domicílios e 2,61% do faturamento, o que dá R$ 0,63 por domicílio, um terço da média e o pior índice das 12 praças. E é a única praça que nenhuma loja atende de forma dedicada: quatro lojas mandam pedaços do seu público para lá (Brusque com 30%, São José Kobrasol com 20%, Itajaí Praia com 15% e Gaspar com 10%), e nenhuma delas dedica mais de 30%.

### P5. Onde abrir a próxima loja, e o que os dados não permitem afirmar

**(a) Ranking por itens vendidos por mil habitantes.** O denominador é a população da cidade da loja e o numerador são os itens da fato. A taxa é calculada na consulta, não está gravada na fato, porque taxa não é aditiva.

Os seis menores índices, que são onde sobra espaço para crescer:

| Loja | Cidade | Porte | População | Itens | Itens/mil hab. | Dias médios de entrega |
|---|---|---|---:|---:|---:|---:|
| Florianopolis Norte | Florianópolis | Grande | 537.213 | 1.426 | 2,65 | 8,02 |
| Itajai Praia | Itajaí | Grande | 264.054 | 798 | 3,02 | 7,98 |
| Joinville Sul | Joinville | Grande | 597.658 | 1.888 | 3,16 | 7,83 |
| Chapeco | Chapecó | Grande | 254.235 | 824 | 3,24 | 7,85 |
| Sao Jose Kobrasol | São José | Grande | 250.181 | 929 | 3,71 | 8,01 |
| Lages | Lages | Media | 158.846 | 593 | 3,73 | 7,69 |

Os cinco maiores, onde o mercado local já está bem coberto:

| Loja | Cidade | Porte | População | Itens | Itens/mil hab. | Dias médios de entrega |
|---|---|---|---:|---:|---:|---:|
| Rio dos Cedros | Rio dos Cedros | Pequena | 11.322 | 474 | 41,87 | 14,24 |
| Presidente Getulio | Presidente Getúlio | Pequena | 16.359 | 570 | 34,84 | 14,16 |
| Ibirama | Ibirama | Pequena | 18.613 | 597 | 32,07 | 15,39 |
| Itapoa | Itapoá | Pequena | 20.586 | 534 | 25,94 | 15,39 |
| Santo Amaro da Imperatriz | Santo Amaro | Pequena | 22.357 | 530 | 23,71 | 15,88 |

Cruzando com o tempo de entrega aparece um padrão claro. As lojas com maior penetração per capita são justamente as mais lentas, de 14 a 16 dias, contra 7,6 a 8,7 nas demais. São as mesmas lojas Pequenas que a P1 apontou com 8,53 dias entre nota e despacho. Elas já ganharam o mercado local e agora estão travadas na operação, não na demanda.

**(b) Faturamento por faixa de franquia, e por que ele não responde o que parece responder.**

| Faixa (hoje) | Lojas | Pedidos | Faturamento (R$) | % do total |
|---|---:|---:|---:|---:|
| Ouro | 15 | 2.316 | 1.011.264,38 | 56,39% |
| Diamante | 5 | 818 | 382.209,74 | 21,31% |
| Prata | 8 | 719 | 314.812,03 | 17,55% |
| Bronze | 4 | 188 | 84.036,06 | 4,69% |
| Nao Informado | 1 | 3 | 986,30 | 0,05% |

Esses números não respondem "quanto veio de lojas que já eram Ouro na data do pedido". A stg_loja é um cadastro operacional: cada loja tem uma linha só, com a faixa de hoje e uma única DtUltimaAtualizacao, todas em 31/03/2024. Se uma loja subiu de Prata para Ouro em janeiro, o registro antigo foi sobrescrito e não existe em lugar nenhum da base.

O que a tabela diz de verdade é que 56,39% dos pedidos dos últimos sete meses vieram de lojas que hoje são Ouro. Atribuir esse faturamento à condição de Ouro seria anacronismo, porque parte dele foi gerada quando a loja ainda era Prata. E tem a possibilidade de a loja ter virado Ouro por causa desse faturamento, que é o mesmo problema de causa invertida da P3.

Para responder a pergunta original seria preciso guardar histórico, com uma dim_loja do tipo 2 (slowly changing dimension), com data_inicio, data_fim e uma linha nova a cada mudança de faixa. A fato apontaria para a versão da loja vigente na data do pedido. Isso não existe nesta base e não dá para reconstruir depois.

**(c) O que ficou de fora.**

| Item | Pedidos | % dos 4.044 |
|---|---:|---:|
| Entregas ainda não concluídas | 1.953 | 48,29% |
| Pedidos sem quantidade de itens | 257 | 6,36% |
| Pedidos sem canal informado | 237 | 5,86% |
| Pedidos sem informação de desconto | 198 | 4,90% |
| Pedidos sem valor líquido | 121 | 2,99% |
| Pedidos sem loja identificada (linha -1) | 3 | 0,07% |

## 7. O que os dados não permitem afirmar

A P1 fala de pouco mais da metade da base. Os 9,00 dias vêm de 2.091 pedidos entregues, e os outros 1.953 ainda estavam abertos no fim da janela. Se os pedidos que demoram mais são exatamente os que ainda não foram entregues, e essa é a hipótese mais provável, então 9,00 dias é um piso e não a média real. O gargalo entre nota e despacho provavelmente é maior que 4,11 dias.

Não dá para dizer que o desconto aumenta o ticket. O que os dados mostram é correlação, com o ticket com desconto 2,5 vezes maior. A explicação mais simples é a inversa, com a política concedendo desconto a partir de certo valor. Separar as duas coisas exigiria a regra comercial ou um teste A/B, e nenhum dos dois está na base.

Não dá para dizer nada sobre o passado da faixa de franquia, pelo motivo que expliquei na P5.

Não dá para medir demanda não atendida. A base só tem pedido feito. Cliente que procurou e não achou, carrinho abandonado, gente que desistiu por causa do prazo, nada disso aparece. "Itens por mil habitantes" mede a penetração atual, não o potencial do mercado.

A população usada é a da cidade da loja, não a da área que ela atende de fato. Uma loja em Blumenau atende gente de fora de Blumenau, então o índice per capita subestima as lojas de cidade grande e superestima as de cidade pequena que têm região no entorno.

Os fator_publico da ponte são uma estimativa do time de expansão, não um dado medido de origem do cliente. A P4 herda essa incerteza. A coluna `Bairro Entrega` existe na stg_pedido e daria para validar o rateio com ela, mas não usei. Fica como próximo passo.

Sete meses não mostram sazonalidade. A janela pega Natal e férias de verão e não fecha um ciclo completo, então comparar praças de perfil turístico (Litoral Norte, Foz do Itajaí) com as do interior está contaminado por isso.

Os NULL não são aleatórios. Os 257 pedidos sem quantidade e os 121 sem valor foram simplesmente ignorados pelas médias. Se esses buracos se concentram em alguma loja ou canal específico, as comparações estão enviesadas, e não consegui testar isso com o que tem na base.

## 8. Recomendação final

Minha recomendação é abrir a próxima loja em Foz do Itajaí, no eixo Itajaí, Balneário Camboriú e Navegantes.

| | Foz do Itajaí | Média da rede |
|---|---:|---:|
| % dos domicílios com pet | 8,64% | - |
| % do faturamento | 2,61% | - |
| R$ por domicílio com pet | 0,63 | 2,10 |

É a maior distância entre público e faturamento de toda a rede. A praça captura um terço do que a média captura por domicílio. E é a única praça sem loja dedicada, com quatro lojas mandando pedaços do público para lá e nenhuma delas passando de 30%. Uma loja própria converteria um público já mapeado, de 74.000 domicílios com pet, que hoje é atendido pelas beiradas.

Reforça o argumento o fato de a loja mais próxima, a Itajaí Praia, ter o segundo menor índice de penetração da rede (3,02 itens por mil habitantes) sendo porte Grande numa cidade de 264 mil habitantes. Não parece falta de mercado, parece falta de cobertura.

Como segunda opção eu colocaria a Grande Florianópolis. A loja Florianópolis Norte tem a menor penetração de toda a rede, 2,65 itens por mil habitantes numa cidade de 537 mil, o que sugere uma capital sub-coberta por uma loja só. Ficou em segundo porque, no recorte de praça, a Grande Florianópolis já está alinhada com o seu público, com 15,81% do faturamento para 15,42% dos domicílios. A folga existe, mas é menor que a de Foz do Itajaí.

Antes de abrir qualquer loja, porém, eu consertaria o intervalo entre nota e despacho. Uma loja nova vai entrar num processo que hoje leva 9 dias, ou 15 se for porte Pequeno. Os 4,11 dias entre nota emitida e despacho são 46% do processo inteiro, numa etapa interna, que não depende de transportadora e não precisa de investimento em ponto físico. Reduzir isso ao patamar das lojas Grandes já devolveria dias de prazo na rede toda, com um retorno que provavelmente supera o da loja nova e sem CAPEX.

E não usaria a faixa de franquia para embasar essa decisão. Os 56,39% de faturamento das lojas Ouro descrevem a foto de hoje, não o histórico, e a base não sustenta nenhuma leitura temporal dessa coluna.

## Estrutura do repositório

```
.
├── README.md
├── scripts/
│   ├── 01-carga-staging.sql
│   ├── 02-dimensoes-prontas.sql
│   ├── 03-dimensoes.sql
│   ├── 04-fato.sql
│   └── 05-perguntas.sql
├── diagrama/
│   ├── modelo-estrela.png
│   ├── modelo-estrela.svg
│   └── modelo-estrela.dot
└── dados/
    ├── stg_pedido.csv
    ├── stg_loja.csv
    └── stg_loja_praca.csv
```
