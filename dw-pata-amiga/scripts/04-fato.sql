-- ------------------------------------------------------------------
-- ARQUIVO 4: fato_pedido
-- Rodar depois do 03. A tabela ja existe vazia.
-- Um unico INSERT ... SELECT, 4.044 linhas, sem subconsulta.
-- A limpeza fica nas dimensoes; aqui a fato so procura a linha certa.
-- Nenhuma FK fica nula: quando falta o dado, aponta para a -1.
-- ------------------------------------------------------------------

USE dw_pata_amiga;

INSERT INTO fato_pedido (
    numero_pedido,
    sk_tempo_pedido,
    sk_tempo_entrega,
    sk_loja,
    sk_categoria,
    houve_desconto,
    canal_pedido,
    dt_pedido,
    qt_itens,
    vl_liquido,
    dias_integracao_separacao,
    dias_separacao_nota,
    dias_nota_despacho,
    dias_despacho_entrega,
    dias_total_ate_entrega
)
SELECT
    -- dimensao degenerada: o numero do pedido nao tem atributo nenhum
    TRIM(p.`NumeroPedido`),

    -- as duas FKs de tempo: a mesma dim_tempo em dois papeis.
    -- A chave e a data em numero (AAAAMMDD), entao monto por calculo.
    -- A data do pedido vem no formato americano. Com '%d/%m/%Y' o MySQL
    -- nao da erro, devolve NULL e datas trocadas em silencio.
    CAST(DATE_FORMAT(STR_TO_DATE(p.`DtHoraPedido`, '%m/%d/%Y %h:%i %p'), '%Y%m%d') AS SIGNED),

    -- entrega em branco nao e erro, e processo em aberto (1.953 pedidos)
    CASE WHEN TRIM(p.`DtEntregaCliente`) = '' THEN -1
         ELSE CAST(DATE_FORMAT(DATE(p.`DtEntregaCliente`), '%Y%m%d') AS SIGNED)
    END,

    -- FKs que vem de LEFT JOIN: se nao achou par, -1
    CASE WHEN l.sk_loja       IS NULL THEN -1 ELSE l.sk_loja       END,
    CASE WHEN dc.sk_categoria IS NULL THEN -1 ELSE dc.sk_categoria END,

    -- desconto: 17 grafias caem em 3 valores. Sem dimensao, dominio
    -- pequeno e sem atributos, entao fica aqui mesmo.
    CASE
        WHEN UPPER(TRIM(p.`HouveDesconto`)) IN ('S','SIM','1','X','TRUE','V') THEN 'Sim'
        WHEN UPPER(TRIM(p.`HouveDesconto`)) IN ('N','NAO','0','FALSE','F')    THEN 'Nao'
        ELSE 'Nao Informado'
    END,

    -- canal: a ordem importa, WHATSAPP contem APP. Testando APP antes,
    -- os 414 pedidos de WhatsApp iriam parar dentro do App.
    CASE
        WHEN UPPER(TRIM(p.`CanalPedido`)) LIKE '%WHATS%' THEN 'WhatsApp'
        WHEN UPPER(TRIM(p.`CanalPedido`)) LIKE '%APP%'   THEN 'App'
        WHEN UPPER(TRIM(p.`CanalPedido`)) LIKE '%SITE%'  THEN 'Site'
        WHEN UPPER(TRIM(p.`CanalPedido`)) LIKE '%LOJA%'  THEN 'Loja Fisica'
        WHEN UPPER(TRIM(p.`CanalPedido`)) LIKE '%TEL%'   THEN 'Telefone'
        ELSE 'Nao Informado'
    END,

    STR_TO_DATE(p.`DtHoraPedido`, '%m/%d/%Y %h:%i %p'),

    -- metricas aditivas. Vazio e '-' viram NULL, nunca 0.
    CASE WHEN TRIM(p.`QTD.Itens`) IN ('', '-') THEN NULL
         ELSE CAST(TRIM(p.`QTD.Itens`) AS SIGNED)
    END,

    -- 'R$ 1.850,00', '1850.00', '1.200', '-' e vazio na mesma coluna
    CASE WHEN TRIM(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$','')) IN ('','-') THEN NULL
         WHEN p.`ValorLiquidoPedido(R$)` LIKE '%,%'
              THEN CAST(REPLACE(REPLACE(REPLACE(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$',''),' ',''),'.',''),',','.')
                   AS DECIMAL(15,2))
         ELSE CAST(REPLACE(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$',''),' ','') AS DECIMAL(15,2))
    END,

    -- os cinco lags, calculados uma vez aqui. Marco de fim em branco
    -- vira NULL (NULLIF), e o DATEDIFF propaga. AVG ignora NULL, mas
    -- somaria o zero, o que faria o gargalo parecer menor do que e.
    -- So a integracao no ERP vem com hora e no formato americano.
    DATEDIFF(DATE(NULLIF(TRIM(p.`Dt Separacao Estoque`),'')),
             DATE(STR_TO_DATE(p.`DtHoraIntegracaoERP`, '%m/%d/%Y %h:%i %p'))),

    DATEDIFF(DATE(NULLIF(TRIM(p.`DtNotaFiscal`),'')),
             DATE(NULLIF(TRIM(p.`Dt Separacao Estoque`),''))),

    DATEDIFF(DATE(NULLIF(TRIM(p.`Dt_Despacho_Transportadora`),'')),
             DATE(NULLIF(TRIM(p.`DtNotaFiscal`),''))),

    DATEDIFF(DATE(NULLIF(TRIM(p.`DtEntregaCliente`),'')),
             DATE(NULLIF(TRIM(p.`Dt_Despacho_Transportadora`),''))),

    -- esta ultima nao e um intervalo, e o processo inteiro. Responde a P1.
    DATEDIFF(DATE(NULLIF(TRIM(p.`DtEntregaCliente`),'')),
             DATE(STR_TO_DATE(p.`DtHoraIntegracaoERP`, '%m/%d/%Y %h:%i %p')))

FROM stg_pedido p

-- Loja: a padronizacao acontece aqui no ON, antes do lookup.
-- REPLACE tira o '/SC' e o espaco duplo. O que sobra sao 3 grafias que
-- REPLACE nao resolve: BLUMENAL (digitacao), FLORIPA (apelido) e JGUA
-- (abreviacao). Acento e caixa nao precisam: 'Timbo' = 'TIMBO' da 1.
-- O lookup e pelo nome porque o Cod Loja esta vazio em 39% das linhas.
LEFT JOIN dim_loja l
       ON l.chave_loja =
          CASE UPPER(TRIM(REPLACE(REPLACE(p.`Loja-Nome`, '/SC', ''), '  ', ' ')))
               WHEN 'PATA AMIGA BLUMENAL CENTRO' THEN 'PATA AMIGA BLUMENAU CENTRO'
               WHEN 'PATA AMIGA FLORIPA NORTE'   THEN 'PATA AMIGA FLORIANOPOLIS NORTE'
               WHEN 'PATA AMIGA JGUA DO SUL'     THEN 'PATA AMIGA JARAGUA DO SUL'
               ELSE UPPER(TRIM(REPLACE(REPLACE(p.`Loja-Nome`, '/SC', ''), '  ', ' ')))
          END

-- Categoria: JOIN de uma linha so, pela grafia crua guardada no 03.
LEFT JOIN dim_categoria dc
       ON dc.categoria_origem = p.`CategoriaProduto`;

-- Esperado: 4.044 linhas, 0 FK nula ou orfa, 3 pedidos na linha -1 de
-- loja, 1.953 entregas em aberto, WhatsApp com 414 pedidos, periodo de
-- 2023-09-01 a 2024-03-31 e nenhum dia negativo.
