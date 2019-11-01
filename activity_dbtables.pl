CREATE DATABASE activity;

CREATE USER 'activity'@'localhost' IDENTIFIED BY 'sdcrqewirxs';
GRANT ALL ON activity.* TO 'activity'@'localhost';

use activity;

CREATE TABLE CURRENCY_BAL
 (
 account_name      VARCHAR(13) NOT NULL,
 contract          VARCHAR(13) NOT NULL,
 currency          VARCHAR(8) NOT NULL,
 amount            DOUBLE PRECISION NOT NULL
) ENGINE=InnoDB;

CREATE UNIQUE INDEX CURRENCY_BAL_I01 ON CURRENCY_BAL (account_name, contract, currency);


CREATE TABLE ACCOUNTS
(
 account_name      VARCHAR(13) NOT NULL PRIMARY KEY
) ENGINE=InnoDB;



CREATE TABLE AUTH_COUNTER
 (
 account_name      VARCHAR(13) NOT NULL PRIMARY KEY,
 auth_c            BIGINT NOT NULL
) ENGINE=InnoDB;



