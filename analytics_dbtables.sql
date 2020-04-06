

CREATE TABLE EOSIO_TRANSFERS
(
 seq         BIGINT UNSIGNED PRIMARY KEY,
 block_num   BIGINT NOT NULL,
 block_time  DATETIME NOT NULL,
 trx_id      VARCHAR(64) NOT NULL,
 contract    VARCHAR(13) NOT NULL,
 currency    VARCHAR(8) NOT NULL,
 amount      DOUBLE PRECISION NOT NULL,
 tx_from     VARCHAR(13) NULL,
 tx_to       VARCHAR(13) NOT NULL,
 memo        TEXT
)  ENGINE=InnoDB;


CREATE INDEX EOSIO_TRANSFERS_I01 ON EOSIO_TRANSFERS (block_num);
CREATE INDEX EOSIO_TRANSFERS_I02 ON EOSIO_TRANSFERS (block_time);
CREATE INDEX EOSIO_TRANSFERS_I06 ON EOSIO_TRANSFERS (tx_from, contract, currency, block_num);
CREATE INDEX EOSIO_TRANSFERS_I07 ON EOSIO_TRANSFERS (tx_to, contract, currency, block_num);
CREATE INDEX EOSIO_TRANSFERS_I08 ON EOSIO_TRANSFERS (tx_to, block_num);
CREATE INDEX EOSIO_TRANSFERS_I09 ON EOSIO_TRANSFERS (tx_from, block_num);
CREATE INDEX EOSIO_TRANSFERS_I10 ON EOSIO_TRANSFERS (contract, block_num);



CREATE TABLE EOSIO_VOTES
(
 seq         BIGINT UNSIGNED NOT NULL,
 block_num   BIGINT NOT NULL,
 block_time  DATETIME NOT NULL,
 trx_id      VARCHAR(64) NOT NULL,
 voter       VARCHAR(13) NOT NULL,
 bp          VARCHAR(13) NULL
)  ENGINE=InnoDB;

CREATE UNIQUE INDEX EOSIO_VOTES_U01 ON EOSIO_VOTES (seq, bp);
CREATE INDEX EOSIO_VOTES_I01 ON EOSIO_VOTES (block_num);
CREATE INDEX EOSIO_VOTES_I02 ON EOSIO_VOTES (block_time);
CREATE INDEX EOSIO_VOTES_I04 ON EOSIO_VOTES (voter, block_num);
CREATE INDEX EOSIO_VOTES_I05 ON EOSIO_VOTES (bp, block_num);



CREATE TABLE EOSIO_PROXY_VOTES
(
 seq         BIGINT UNSIGNED NOT NULL,
 block_num   BIGINT NOT NULL,
 block_time  DATETIME NOT NULL,
 trx_id      VARCHAR(64) NOT NULL,
 voter       VARCHAR(13) NOT NULL,
 proxy       VARCHAR(13) NULL
)  ENGINE=InnoDB;

CREATE UNIQUE INDEX EOSIO_PROXY_VOTES_U01 ON EOSIO_PROXY_VOTES (seq);
CREATE INDEX EOSIO_PROXY_VOTES_I01 ON EOSIO_PROXY_VOTES (block_num);
CREATE INDEX EOSIO_PROXY_VOTES_I02 ON EOSIO_PROXY_VOTES (block_time);
CREATE INDEX EOSIO_PROXY_VOTES_I04 ON EOSIO_PROXY_VOTES (voter, block_num);
CREATE INDEX EOSIO_PROXY_VOTES_I05 ON EOSIO_PROXY_VOTES (proxy, block_num);



CREATE TABLE EOSIO_DELEGATEBW
(
 seq         BIGINT UNSIGNED PRIMARY KEY,
 block_num   BIGINT NOT NULL,
 block_time  DATETIME NOT NULL,
 trx_id      VARCHAR(64) NOT NULL,
 owner       VARCHAR(13) NOT NULL,
 receiver    VARCHAR(13) NULL,
 delegate    TINYINT,            /* 1=delegatebw, 0=undelegatebw */
 transfer    TINYINT,
 cpu         DOUBLE PRECISION NOT NULL,
 net         DOUBLE PRECISION NOT NULL
)  ENGINE=InnoDB;

CREATE INDEX EOSIO_DELEGATEBW_I01 ON EOSIO_DELEGATEBW (block_num);
CREATE INDEX EOSIO_DELEGATEBW_I02 ON EOSIO_DELEGATEBW (block_time);
CREATE INDEX EOSIO_DELEGATEBW_I04 ON EOSIO_DELEGATEBW (owner, block_num);
CREATE INDEX EOSIO_DELEGATEBW_I05 ON EOSIO_DELEGATEBW (receiver, block_num);


