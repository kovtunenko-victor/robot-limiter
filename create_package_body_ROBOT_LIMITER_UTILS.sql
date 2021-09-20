CREATE OR REPLACE PACKAGE BODY ROBOT_LIMITER_UTILS is

/* Функция для получения доступного "внешнего" сальдо
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" сальдо, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20007: Error when get external balance)
*/
FUNCTION GET_EXTERNAL_BALANCE_ROBOT_LIMITER (contract_number in string, seq in string DEFAULT '1') 
RETURN number IS
n_balance number(18,0) := 0;

BEGIN
  SELECT
    nvl(hb.ID_FILTER2, 0) INTO n_balance
  FROM ows.sy_handbook hb
  WHERE
      hb.AMND_STATE = 'A'
  AND hb.GROUP_CODE = 'EXTERNAL_BALANCE_ROBOT_LIMITER'
  AND hb.FILTER = contract_number
  AND hb.filter2 = seq;

  RETURN n_balance;

EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    RAISE_APPLICATION_ERROR(-20006,'External balance configuration for contract [' || contract_number || '] not found');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20007,'Error when get external balance');

END GET_EXTERNAL_BALANCE_ROBOT_LIMITER;

/*Процедура для установки доступного "внешнего" сальдо
external_balance - сумма внешнего сальдо
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" сальдо, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20007: Error when set external balance)
*/
PROCEDURE SET_EXTERNAL_BALANCE_ROBOT_LIMITER(external_balance number, contract_number in string, seq in string DEFAULT '1') is
  is_exists number(18,0) := 0;
  counter number;
BEGIN
  counter := ows.stnd.process_start('SET_EXTERNAL_BALANCE_ROBOT_LIMITER', '#external_balance = ' || external_balance ||
                                                                 ' #contract_number = ' || contract_number ||
                                                                 ' #seq = ' || seq,
                            ows.sy_process.uninotunique);
  ows.stnd.process_message(ows.sy_process.information, 'Strat set external balance');
  COMMIT;
  
  SELECT COUNT(1) INTO is_exists
  FROM ows.sy_handbook hb
  WHERE 
      hb.AMND_STATE = 'A'
  and hb.GROUP_CODE = 'EXTERNAL_BALANCE_ROBOT_LIMITER' 
  and hb.FILTER = contract_number 
  and hb.FILTER2 = seq;
  
  IF (is_exists = 0) THEN 
    raise NO_DATA_FOUND;
  END IF;
  
  UPDATE ows.sy_handbook hb 
  SET hb.AMND_DATE = sysdate, hb.ID_FILTER2 = external_balance 
  WHERE 
      hb.AMND_STATE = 'A'
  and hb.GROUP_CODE = 'EXTERNAL_BALANCE_ROBOT_LIMITER' 
  and hb.FILTER = contract_number 
  and hb.FILTER2 = seq;
  
  ows.stnd.process_message(ows.sy_process.information, 'End set external balance');
  COMMIT;
  
  ows.stnd.process_end();
  COMMIT;
  
EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    ows.stnd.process_message(ows.sy_process.error, 'External balance configuration for contract [' || contract_number || '] not found');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20006,'External balance configuration for contract [' || contract_number || '] not found');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when set external balance');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20007,'Error when set external balance');
END SET_EXTERNAL_BALANCE_ROBOT_LIMITER;

/*Процедура для установки текущего остатка и даты и времени последней операции по "внешнему" счету организации
external_balance - сумма остатка на счете
last_operation_date - дата и время последней операции зачисления или списания на "внешней" счет
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" счета организации, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
если передан last_operation_date равынй NULL будет вызвано исключение:
(ORA-20008: last_operation_date is null)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20007: Error when set external account)
*/
PROCEDURE SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER(external_balance number, last_operation_date date, contract_number in string, seq in string DEFAULT '1') is
  is_exists number(18,0) := 0;
  counter number;
BEGIN
  counter := ows.stnd.process_start('SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER', '#external_balance = ' || external_balance ||
                                                                 ' #last_operation_date = ' || to_char(last_operation_date) ||
                                                                 ' #contract_number = ' || contract_number ||
                                                                 ' #seq = ' || seq,
                            ows.sy_process.uninotunique);
  ows.stnd.process_message(ows.sy_process.information, 'Strat set external account balance');
  COMMIT;
  
  SELECT COUNT(1) INTO is_exists
  FROM ows.sy_handbook hb
  WHERE 
      hb.AMND_STATE = 'A'
  and hb.GROUP_CODE = 'EXTERNAL_ACCOUNTS_ROBOT_LIMITER' 
  and hb.FILTER = contract_number 
  and hb.NAME = seq;
  
  IF (is_exists = 0) THEN 
    raise NO_DATA_FOUND;
  END IF;
  
  IF (last_operation_date is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;
  
  UPDATE ows.sy_handbook hb 
  SET hb.AMND_DATE = sysdate, hb.ID_FILTER2 = external_balance, hb.CODE = to_char(last_operation_date, 'dd-MM-yyyy hh:mi:ss')
  WHERE 
      hb.AMND_STATE = 'A'
  and hb.GROUP_CODE = 'EXTERNAL_ACCOUNTS_ROBOT_LIMITER' 
  and hb.FILTER = contract_number 
  and hb.NAME = seq;
  
  ows.stnd.process_message(ows.sy_process.information, 'End set external account balance');
  COMMIT;
  
  ows.stnd.process_end();
  COMMIT;
  
EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    ows.stnd.process_message(ows.sy_process.error, 'External account configuration for contract [' || contract_number || '] not found');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20006,'External account configuration for contract [' || contract_number || '] not found');
  WHEN ACCESS_INTO_NULL THEN 
    RAISE_APPLICATION_ERROR(-20008,'last_operation_date is null');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when set external account');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20007,'Error when set external account');
END SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER;

/* Функция для получения "внешнего" счета огранизации в АБС
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
account_type - тип номера счета который хотим получить из настройки. Возможные варианты:
               ORG_ACC - внешний счет организации
			   OCT - дополнительный счет, для определения последнего зачисления
			   AFT - дополнительный счет, для определения последнего зачисления
			   ECOM - дополнительный счет, для определения последнего зачисления
seq - последоввательный номер "внешнего" счета организации, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
если передан не существующий account_type будет вызвано исключение:
(ORA-20008: account_type [%account_type] not found)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20007: Error when get external account)
*/
FUNCTION GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER (contract_number in string, account_type in string DEFAULT 'ORG_ACC', seq in string DEFAULT '1') 
RETURN string IS
c_account_number varchar2(25) := 'DEFAULT_VALUE';

BEGIN
  SELECT
   CASE WHEN account_type = 'ORG_ACC' THEN hb.FILTER3
        WHEN account_type = 'OCT' THEN hb.FILTER4
        WHEN account_type = 'AFT' THEN hb.FILTER5
        WHEN account_type = 'ECOM' THEN hb.FILTER2 END INTO c_account_number
  FROM ows.sy_handbook hb
  WHERE
      hb.AMND_STATE = 'A'
  AND hb.GROUP_CODE = 'EXTERNAL_ACCOUNTS_ROBOT_LIMITER'
  AND hb.FILTER = contract_number
  AND hb.NAME = seq;
  
  IF (c_account_number is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;

  RETURN c_account_number;

EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    RAISE_APPLICATION_ERROR(-20006,'External account configuration for contract [' || contract_number || '] not found');
  WHEN ACCESS_INTO_NULL THEN 
    RAISE_APPLICATION_ERROR(-20008,'account_type [' || account_type || '] not found');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20007,'Error when get external account');

END GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER;

END ROBOT_LIMITER_UTILS;

grant EXECUTE, DEBUG on "PROC"."ROBOT_LIMITER_UTILS" to "OWS" ;