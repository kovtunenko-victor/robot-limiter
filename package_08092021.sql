CREATE OR REPLACE PACKAGE ROBOT_LIMITER_UTILS AS
  FUNCTION GET_EXTERNAL_BALANCE_ROBOT_LIMITER (contract_number in string, use_coefficient integer DEFAULT 0, seq in string DEFAULT '1') RETURN number;
  PROCEDURE SET_EXTERNAL_BALANCE_ROBOT_LIMITER(external_balance number, contract_number in string, seq in string DEFAULT '1');
END ROBOT_LIMITER_UTILS;


CREATE OR REPLACE PACKAGE BODY ROBOT_LIMITER_UTILS is

/* Функция для получения доступного "внешнего" баланса
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
use_coefficient - применять коэффицент для баланса, по умолчанию выключен (0)
seq - последоввательный номер "внешнего" баланса, по умолчанию первый ('1')
*/
FUNCTION GET_EXTERNAL_BALANCE_ROBOT_LIMITER (contract_number in string, use_coefficient integer DEFAULT 0, seq in string DEFAULT '1') 
RETURN number IS
n_balance number(18,0) := 0;
n_coefficient number(18,2) := 0;

BEGIN
  SELECT
    nvl(hb.ID_FILTER2, 0), nvl(decode(use_coefficient, 1, hb.INT_FILTER / 100, 1), 0) INTO n_balance, n_coefficient
  FROM ows.sy_handbook hb
  WHERE
      hb.AMND_STATE = 'A'
  AND hb.GROUP_CODE = 'EXTERNAL_BALANCE_ROBOT_LIMITER'
  AND hb.FILTER = contract_number
  AND hb.filter2 = seq;

  RETURN n_balance * n_coefficient;

EXCEPTION
  WHEN OTHERS THEN
  RETURN -1;

END GET_EXTERNAL_BALANCE_ROBOT_LIMITER;

/*Процедура для установки доступного "внешнего" баланса
external_balance - сумма внешнего баланса
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" баланса, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20000: External balance configuration for contract [%contract_number] not found)
*/
PROCEDURE SET_EXTERNAL_BALANCE_ROBOT_LIMITER(external_balance number, contract_number in string, seq in string DEFAULT '1') is
  process_id dtype.recordid %TYPE;
  is_exists number(18,0) := 0;
BEGIN
  ows.sy_process.start_process('SET_EXTERNAL_BALANCE_ROBOT_LIMITER', '#external_balance = ' || external_balance ||
                                                                 ' #contract_number = ' || contract_number ||
                                                                 ' #seq = ' || seq,
                            ows.sy_process.uninotunique, process_id);
  ows.sy_process.process_message1(process_id, ows.sy_process.information, 'Strat set external balance');
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
  
  ows.sy_process.process_message1(process_id, ows.sy_process.information, 'End set external balance');
  COMMIT;
  
  sy_process.finish_process(process_id, stnd.yes);
  COMMIT;
  
EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    ows.sy_process.process_message1(process_id, ows.sy_process.error, 'Error when set external balance. Balance configuration not found');
    sy_process.finish_process(process_id, stnd.yes);
    COMMIT;
    
    RAISE_APPLICATION_ERROR(-20000,'External balance configuration for contract [' || contract_number || '] not found');
  WHEN OTHERS THEN
  ows.sy_process.process_message1(process_id, ows.sy_process.error, 'Error when set external balance');
  sy_process.finish_process(process_id, stnd.yes);
  COMMIT;
  
END SET_EXTERNAL_BALANCE_ROBOT_LIMITER;

END ROBOT_LIMITER_UTILS;