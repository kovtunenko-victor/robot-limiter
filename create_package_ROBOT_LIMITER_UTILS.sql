CREATE OR REPLACE PACKAGE ROBOT_LIMITER_UTILS AS
  FUNCTION GET_EXTERNAL_BALANCE_ROBOT_LIMITER (contract_number in string, seq in string DEFAULT '1') RETURN number;
  PROCEDURE SET_EXTERNAL_BALANCE_ROBOT_LIMITER(external_balance number, contract_number in string, seq in string DEFAULT '1');
  PROCEDURE SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER(external_balance number, last_operation_date date, contract_number in string, seq in string DEFAULT '1');
  FUNCTION GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER (contract_number in string, account_type in string DEFAULT 'ORG_ACC', seq in string DEFAULT '1') RETURN string;
END ROBOT_LIMITER_UTILS;