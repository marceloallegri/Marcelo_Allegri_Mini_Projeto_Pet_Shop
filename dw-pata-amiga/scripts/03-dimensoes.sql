-- ------------------------------------------------------------------
-- ARQUIVO 3: dim_categoria, dim_praca e bridge_loja_praca
-- Rodar depois do 01 e do 02. As tabelas ja existem vazias.
-- As stg_ nao sao alteradas: nada de UPDATE nem ALTER.
-- ------------------------------------------------------------------

USE dw_pata_amiga;

-- ------------------------------------------------------------------
-- DIM_CATEGORIA   grao: uma grafia da origem
-- ------------------------------------------------------------------
-- Guardo a grafia crua em categoria_origem. E por ela que a fato acha
-- a linha, com um JOIN de uma linha so. A linha -1 entra antes do
-- INSERT ... SELECT, para nenhuma FK da fato ficar nula.

INSERT INTO dim_categoria (sk_categoria, categoria_origem, nome_categoria, grupo_categoria)
VALUES (-1, 'N/I', 'Nao Informado', 'Nao Informado');

-- A ordem do CASE importa: "Racao Medicamentosa" contem RA, entao MED
-- tem que ser testado antes. Ordem: MED, PETISC, RA, HIG, BRINQ, ACESS, SERV.
-- Comparo em UPPER e com trechos sem acento.

INSERT INTO dim_categoria (categoria_origem, nome_categoria, grupo_categoria)
SELECT DISTINCT
       p.`CategoriaProduto`,
       CASE
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%MED%'    THEN 'Medicamento'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%PETISC%' THEN 'Petisco'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%RA%'     THEN 'Racao'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%HIG%'    THEN 'Higiene'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%BRINQ%'  THEN 'Brinquedo'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%ACESS%'  THEN 'Acessorio'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%SERV%'   THEN 'Servico'
           ELSE 'Nao Informado'
       END,
       CASE
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%MED%'    THEN 'Saude e Higiene'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%PETISC%' THEN 'Alimentacao'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%RA%'     THEN 'Alimentacao'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%HIG%'    THEN 'Saude e Higiene'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%BRINQ%'  THEN 'Bem-estar'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%ACESS%'  THEN 'Bem-estar'
           WHEN UPPER(p.`CategoriaProduto`) LIKE '%SERV%'   THEN 'Bem-estar'
           ELSE 'Nao Informado'
       END
FROM stg_pedido p;

-- ------------------------------------------------------------------
-- DIM_PRACA   grao: uma praca de atendimento
-- ------------------------------------------------------------------
-- A stg_loja_praca tem 48 linhas porque a praca se repete por loja.
-- GROUP BY por CodPraca colapsa em 12. As colunas de fora do GROUP BY
-- precisam de agregacao e MAX serve, porque o valor e o mesmo.
-- domicilios_com_pet vem como '148.000': o ponto e milhar e sai antes
-- do CAST, senao viraria 148.

INSERT INTO dim_praca (sk_praca, cod_praca, nome_praca, regional, domicilios_com_pet)
VALUES (-1, 'N/I', 'Nao Informado', 'Nao Informado', NULL);

INSERT INTO dim_praca (cod_praca, nome_praca, regional, domicilios_com_pet)
SELECT TRIM(lp.`CodPraca`),
       MAX(TRIM(lp.`NomePraca`)),
       MAX(TRIM(lp.`Regional`)),
       MAX(CAST(REPLACE(lp.`DomiciliosComPet`, '.', '') AS SIGNED))
FROM stg_loja_praca lp
GROUP BY TRIM(lp.`CodPraca`);

-- ------------------------------------------------------------------
-- BRIDGE_LOJA_PRACA   grao: uma loja x uma praca
-- ------------------------------------------------------------------
-- Ligacao N:N, com o fator de rateio dentro (os fatores de uma loja
-- somam 1,00). A ponte usa o cod_loja, e nao a sk_loja, para nao
-- quebrar se a dim_loja for recarregada.
-- Na P4 o faturamento e multiplicado pelo fator antes de somar por
-- praca, senao quem atende duas pracas seria contado duas vezes.

INSERT INTO bridge_loja_praca (cod_loja, sk_praca, fator_publico)
SELECT TRIM(lp.`CodLoja`),
       dp.sk_praca,
       CAST(lp.`PercentualPublico` AS DECIMAL(6,4))
FROM stg_loja_praca lp
JOIN dim_praca dp ON dp.cod_praca = TRIM(lp.`CodPraca`);

-- Esperado: dim_categoria 19, dim_praca 13, bridge 48,
-- nome_categoria distintos = 8, soma do fator por loja = 1,00.
