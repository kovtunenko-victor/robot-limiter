CREATE OR REPLACE PACKAGE ROBOT_LIMITER_UTILS AS
  FUNCTION GET_BIC(p_account in string) RETURN string;
  FUNCTION GET_ACCOUNT(p_account in string) return string;
  
  FUNCTION GET_EXTERNAL_BALANCE_ROBOT_LIMITER (contract_number in string, seq in string DEFAULT '1') RETURN number;
  PROCEDURE SET_EXTERNAL_BALANCE_ROBOT_LIMITER(external_balance number, contract_number in string, seq in string DEFAULT '1');
  PROCEDURE SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER(external_balance number, last_operation_date date, contract_number in string, seq in string DEFAULT '1');
  FUNCTION GET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER (contract_number in string, seq in string DEFAULT '1', time_interval in string DEFAULT '7200') RETURN number;
  FUNCTION GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER (contract_number in string, account_type in string DEFAULT 'MAIN', seq in string DEFAULT '1') RETURN string;
  PROCEDURE SAVE_EXTERNAL_BALANCE_PER_DATE (external_balance number, external_balance_date date, contract_number in string DEFAULT '-', seq in string DEFAULT '1');
  PROCEDURE APPROVE_EXTERNAL_BALANCE_PER_DATE (external_balance_date date, contract_number in string DEFAULT '-', seq in string DEFAULT '1');
  FUNCTION GET_EXTERNAL_BALANCE_PER_DATE (external_balance_date date, contract_number in string DEFAULT '-', seq in string DEFAULT '1') RETURN number;
  FUNCTION GET_ENTRY_COUNT(contract_number in string, for_date in date, c_org_account in string) RETURN number;

  PROCEDURE CALCULATE_AUTHORIZATION_LIMIT(contract_number in string, n_amount_on_account out number);
END ROBOT_LIMITER_UTILS;