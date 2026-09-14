-- ------------------------------------------------------------------
-- ARQUIVO 5: as cinco perguntas de negocio
-- Rodar depois do 04.
-- Subconsulta so aqui, para trazer o total da rede como denominador.
-- Percentual e taxa sao calculados na consulta, nunca gravados na fato,
-- porque nao sao aditivos.
-- ------------------------------------------------------------------

USE dw_pata_amiga;

-- ------------------------------------------------------------------
-- P1. Onde esta o gargalo da entrega?
-- ------------------------------------------------------------------
-- AVG dos quatro intervalos ja calculados na carga. AVG ignora NULL,
-- por isso a etapa nao cumprida foi gravada como NULL e nao como 0.
-- dias_total_ate_entrega e o processo inteiro, nao um dos intervalos.

-- P1.a rede inteira
SELECT 'REDE' AS porte,
       COUNT(*)                                AS pedidos,
       ROUND(AVG(dias_integracao_separacao),2) AS d1_integracao_separacao,
       ROUND(AVG(dias_separacao_nota),2)       AS d2_separacao_nota,
       ROUND(AVG(dias_nota_despacho),2)        AS d3_nota_despacho,
       ROUND(AVG(dias_despacho_entrega),2)     AS d4_despacho_entrega,
       ROUND(AVG(dias_total_ate_entrega),2)    AS total_erp_ate_cliente
FROM fato_pedido;

-- P1.b por porte de loja
SELECT l.porte,
       COUNT(*)                                  AS pedidos,
       ROUND(AVG(f.dias_integracao_separacao),2) AS d1_integracao_separacao,
       ROUND(AVG(f.dias_separacao_nota),2)       AS d2_separacao_nota,
       ROUND(AVG(f.dias_nota_despacho),2)        AS d3_nota_despacho,
       ROUND(AVG(f.dias_despacho_entrega),2)     AS d4_despacho_entrega,
       ROUND(AVG(f.dias_total_ate_entrega),2)    AS total_erp_ate_cliente
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
GROUP BY l.porte
ORDER BY total_erp_ate_cliente DESC;

-- ------------------------------------------------------------------
-- P2. Qual categoria concentra o faturamento?
-- ------------------------------------------------------------------
-- Agrupa pelo nome_categoria padronizado, nunca pela grafia crua.
-- O percentual usa subconsulta com o total da rede no denominador.
-- No MySQL a divisao ja devolve decimal, nao precisa de CAST.

SELECT c.nome_categoria,
       c.grupo_categoria,
       COUNT(*)                    AS pedidos,
       SUM(f.qt_itens)             AS itens,
       ROUND(SUM(f.vl_liquido), 2) AS faturamento,
       ROUND(100 * SUM(f.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2)
                                   AS pct_do_total
FROM fato_pedido f
JOIN dim_categoria c ON c.sk_categoria = f.sk_categoria
GROUP BY c.nome_categoria, c.grupo_categoria
ORDER BY faturamento DESC;

-- P2.b a campea e a mesma nos tres portes?
SELECT l.porte,
       c.nome_categoria,
       ROUND(SUM(f.vl_liquido), 2) AS faturamento
FROM fato_pedido f
JOIN dim_categoria c ON c.sk_categoria = f.sk_categoria
JOIN dim_loja l      ON l.sk_loja      = f.sk_loja
GROUP BY l.porte, c.nome_categoria
ORDER BY l.porte, faturamento DESC;

-- ------------------------------------------------------------------
-- P3. O desconto funciona igual em todo canal?
-- ------------------------------------------------------------------
-- Sem JOIN: desconto e canal foram padronizados na carga e moram na
-- propria fato. Se o WhatsApp nao aparecer, o CASE do 04 testou APP
-- antes de WHATS.

SELECT canal_pedido,
       COUNT(*)                                                AS pedidos,
       ROUND(SUM(vl_liquido), 2)                               AS faturamento,
       ROUND(100 * SUM(vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2)
                                                               AS pct_do_faturamento,
       SUM(CASE WHEN houve_desconto = 'Sim' THEN 1 ELSE 0 END) AS pedidos_com_desc,
       ROUND(AVG(CASE WHEN houve_desconto = 'Sim' THEN vl_liquido END), 2)
                                                               AS ticket_com_desconto,
       ROUND(AVG(CASE WHEN houve_desconto = 'Nao' THEN vl_liquido END), 2)
                                                               AS ticket_sem_desconto,
       ROUND(AVG(CASE WHEN houve_desconto = 'Sim' THEN vl_liquido END)
           - AVG(CASE WHEN houve_desconto = 'Nao' THEN vl_liquido END), 2)
                                                               AS diferenca_rs
FROM fato_pedido
GROUP BY canal_pedido
ORDER BY faturamento DESC;

-- ------------------------------------------------------------------
-- P4. Qual praca concentra o faturamento?
-- ------------------------------------------------------------------
-- Caminho: fato -> dim_loja -> bridge -> dim_praca (a ponte entra pelo
-- cod_loja). O JOIN com a ponte duplica a linha do pedido, uma por
-- praca, e isso esta certo. Multiplico por fator_publico para o
-- faturamento nao ser contado duas vezes.

SELECT pr.nome_praca,
       pr.regional,
       pr.domicilios_com_pet,
       ROUND(SUM(f.vl_liquido * b.fator_publico), 2) AS faturamento_rateado,
       ROUND(100 * SUM(f.vl_liquido * b.fator_publico)
                 / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS pct_do_total,
       ROUND(SUM(f.vl_liquido * b.fator_publico) / pr.domicilios_com_pet, 2)
                                                     AS rs_por_domicilio_com_pet
FROM fato_pedido f
JOIN dim_loja l          ON l.sk_loja   = f.sk_loja
JOIN bridge_loja_praca b ON b.cod_loja  = l.cod_loja
JOIN dim_praca pr        ON pr.sk_praca = b.sk_praca
GROUP BY pr.nome_praca, pr.regional, pr.domicilios_com_pet
ORDER BY faturamento_rateado DESC;

-- ------------------------------------------------------------------
-- P5. Onde abrir a proxima loja?
-- ------------------------------------------------------------------

-- P5.a itens por mil habitantes (numerador na fato, denominador na
-- dimensao), calculado aqui e nunca gravado, cruzado com o tempo medio.
SELECT l.nome_loja,
       l.cidade,
       l.porte,
       l.populacao_cidade,
       SUM(f.qt_itens)                                      AS itens_vendidos,
       ROUND(1000 * SUM(f.qt_itens) / l.populacao_cidade, 2) AS itens_por_mil_hab,
       ROUND(SUM(f.vl_liquido), 2)                          AS faturamento,
       ROUND(AVG(f.dias_total_ate_entrega), 2)              AS dias_medios_entrega
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
WHERE l.sk_loja <> -1
GROUP BY l.nome_loja, l.cidade, l.porte, l.populacao_cidade
ORDER BY itens_por_mil_hab ASC;

-- P5.b faturamento pela faixa de franquia ATUAL. Nao responde "quanto
-- veio de lojas que JA ERAM Ouro na data do pedido": o cadastro so tem
-- a foto de hoje, o passado foi sobrescrito. Para isso seria preciso
-- uma dim_loja tipo 2, com data_inicio e data_fim.
SELECT l.faixa_franquia,
       COUNT(DISTINCT l.cod_loja)  AS lojas,
       COUNT(*)                    AS pedidos,
       ROUND(SUM(f.vl_liquido), 2) AS faturamento,
       ROUND(100 * SUM(f.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2)
                                   AS pct_do_total
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
GROUP BY l.faixa_franquia
ORDER BY faturamento DESC;

-- P5.c o que ficou de fora
SELECT 'pedidos sem loja identificada (linha -1)' AS item,
       COUNT(*) AS pedidos,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM fato_pedido), 2) AS pct
FROM fato_pedido WHERE sk_loja = -1
UNION ALL SELECT 'entregas ainda nao concluidas', COUNT(*),
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM fato_pedido), 2)
FROM fato_pedido WHERE sk_tempo_entrega = -1
UNION ALL SELECT 'pedidos sem quantidade de itens', COUNT(*),
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM fato_pedido), 2)
FROM fato_pedido WHERE qt_itens IS NULL
UNION ALL SELECT 'pedidos sem valor liquido', COUNT(*),
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM fato_pedido), 2)
FROM fato_pedido WHERE vl_liquido IS NULL
UNION ALL SELECT 'pedidos sem canal informado', COUNT(*),
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM fato_pedido), 2)
FROM fato_pedido WHERE canal_pedido = 'Nao Informado'
UNION ALL SELECT 'pedidos sem informacao de desconto', COUNT(*),
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM fato_pedido), 2)
FROM fato_pedido WHERE houve_desconto = 'Nao Informado';
