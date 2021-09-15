CREATE OR REPLACE PACKAGE ROBOT_LIMITER_UTILS AS
  FUNCTION GET_EXTERNAL_BALANCE_ROBOT_LIMITER (contract_number in string, use_coefficient integer DEFAULT 0, seq in string DEFAULT '1') RETURN number;
  PROCEDURE SET_EXTERNAL_BALANCE_ROBOT_LIMITER(external_balance number, contract_number in string, seq in string DEFAULT '1');
END ROBOT_LIMITER_UTILS;


CREATE OR REPLACE PACKAGE BODY ROBOT_LIMITER_UTILS is

/* Функция для получения доступного "внешнего" сальдо
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" сальдо, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
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
  SET hb.ID_FILTER2 = external_balance 
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

END ROBOT_LIMITER_UTILS;