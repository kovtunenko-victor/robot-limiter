CREATE OR REPLACE PACKAGE BODY ROBOT_LIMITER_UTILS is

/*
Функция для извлечения номера БИК из строки настройки
Взята из пакета acqinfo_q (bic)
*/
FUNCTION GET_BIC(p_account in string) RETURN string IS
BEGIN
    IF p_account IS NULL THEN
      RETURN NULL;
    END IF;
    IF (p_account NOT LIKE '%/%') THEN
      RETURN '044525297';
    END IF;
    RETURN SUBSTR(p_account,INSTR(p_account,'/')+1);
END;

/*
Функция для извлечения номера счета из настройки
Взята из пакета acqinfo_q (acc)
*/
FUNCTION GET_ACCOUNT(p_account in string) return string is
BEGIN
    IF p_account IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN SUBSTR(p_account,1,20);
END;

/* Функция для получения доступного "внешнего" сальдо
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" сальдо, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20100: External balance configuration for contract [%contract_number] not found)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20200: Error when get external balance)
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
    RAISE_APPLICATION_ERROR(-20100,'External balance configuration for contract [' || contract_number || '] not found');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20200,'Error when get external balance');

END GET_EXTERNAL_BALANCE_ROBOT_LIMITER;

/*Процедура для установки доступного "внешнего" сальдо
external_balance - сумма внешнего сальдо
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" сальдо, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20101: External balance configuration for contract [%contract_number] not found)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20201: Error when set external balance)
*/
PROCEDURE SET_EXTERNAL_BALANCE_ROBOT_LIMITER(external_balance number, contract_number in string, seq in string DEFAULT '1') is
  is_exists number(18,0) := 0;
BEGIN
  ows.stnd.process_message(ows.sy_process.information, 'SET_EXTERNAL_BALANCE_ROBOT_LIMITER #external_balance = ' || external_balance ||
                                                                 ' #contract_number = ' || contract_number ||
                                                                 ' #seq = ' || seq);						
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
  
EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    ows.stnd.process_message(ows.sy_process.error, 'External balance configuration for contract [' || contract_number || '] not found');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20101,'External balance configuration for contract [' || contract_number || '] not found');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when set external balance');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20201,'Error when set external balance');
END SET_EXTERNAL_BALANCE_ROBOT_LIMITER;

/*Процедура для установки текущего остатка и даты и времени его получения по "внешнему" счету организации
external_balance - сумма остатка на счете
last_operation_date - дата и время получения остатка 
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" счета организации, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20102: External balance configuration for contract [%contract_number] not found)
если передан last_operation_date равынй NULL будет вызвано исключение:
(ORA-20103: last_operation_date is null)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20202: Error when set external account)
*/
PROCEDURE SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER(external_balance number, last_operation_date date, contract_number in string, seq in string DEFAULT '1') is
  is_exists number(18,0) := 0;
BEGIN
  ows.stnd.process_message(ows.sy_process.information, 'SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER #external_balance = ' || external_balance ||
                                                                 ' #last_operation_date = ' || to_char(last_operation_date) ||
                                                                 ' #contract_number = ' || contract_number ||
                                                                 ' #seq = ' || seq); 
  ows.stnd.process_message(ows.sy_process.information, 'Strat set external account balance');
  COMMIT;
  
  SELECT COUNT(1) INTO is_exists
  FROM ows.sy_handbook hb
  WHERE 
      hb.AMND_STATE = 'A'
  and hb.GROUP_CODE = 'EXTERNAL_ACCOUNTS_ROBOT_LIMITER' 
  and hb.FILTER = contract_number 
  and hb.FILTER2 = seq;
  
  IF (is_exists = 0) THEN 
    raise NO_DATA_FOUND;
  END IF;
  
  IF (last_operation_date is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;
  
  UPDATE ows.sy_handbook hb 
  SET hb.AMND_DATE = sysdate, hb.ID_FILTER2 = external_balance, hb.CODE = to_char(last_operation_date, 'dd-MM-yyyy hh24:mi:ss')
  WHERE 
      hb.AMND_STATE = 'A'
  and hb.GROUP_CODE = 'EXTERNAL_ACCOUNTS_ROBOT_LIMITER' 
  and hb.FILTER = contract_number 
  and hb.FILTER2 = seq;
  
  ows.stnd.process_message(ows.sy_process.information, 'End set external account balance');
  COMMIT;
  
EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    ows.stnd.process_message(ows.sy_process.error, 'External account configuration for contract [' || contract_number || '] not found');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20102,'External account configuration for contract [' || contract_number || '] not found');
  WHEN ACCESS_INTO_NULL THEN 
    ows.stnd.process_message(ows.sy_process.error, 'last_operation_date is null');
    ows.stnd.process_reject();
    RAISE_APPLICATION_ERROR(-20103,'last_operation_date is null');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when set external account');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20202,'Error when set external account');
END SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER;

/* Функция для получения сохраненного остатка "внешнему" счету организации
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
seq - последоввательный номер "внешнего" счета организации, по умолчанию первый ('1')
time_interval - индервал в минутах сколько сохраненный остаток сохраняет актуальность, по умолчанию 7200

если настройка по контракту не была найдена вызовет исключение:
(ORA-20104: External balance configuration for contract [%contract_number] not found)
если передан срок действия сохраненного остатка выйдет за указанный интервал time_interval будет вызвано исключение:
(ORA-20105: Balance has expired)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20203: Error when get external balance per date in history)
*/
FUNCTION GET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER (contract_number in string, seq in string DEFAULT '1', time_interval in string DEFAULT '7200') 
RETURN number IS
n_balance NUMBER(18,2) := 0;
is_valid number(18,0) := 0;

BEGIN
  SELECT 
    case when to_date(hb.code, 'dd-mm-yyyy hh24:mi:ss') >= sysdate - NUMTODSINTERVAL(time_interval, 'MINUTE') then 1 else 0 end as is_valid
  , ID_FILTER2 INTO is_valid, n_balance
  FROM ows.sy_handbook hb
  WHERE hb.GROUP_CODE = 'EXTERNAL_ACCOUNTS_ROBOT_LIMITER' and hb.FILTER = contract_number and hb.FILTER2 = seq;

  IF(is_valid = 0) THEN
	raise ACCESS_INTO_NULL;
  END IF;

  RETURN n_balance;

EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    RAISE_APPLICATION_ERROR(-20104,'External account configuration for contract [' || contract_number || '] not found');
  WHEN ACCESS_INTO_NULL THEN 
    RAISE_APPLICATION_ERROR(-20105,'Balance has expired');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20203,'Error when get external balance per date in history');

END GET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER;

/* Функция для получения "внешнего" счета огранизации в АБС
contract_number - номер контракта (связь с Custom Handbooks AUTH_LIM)
account_type - тип номера счета который хотим получить из настройки. Возможные варианты:
               MAIN - внешний счет организации
			   OPPOSITE - оппозитный внешний счет
seq - последоввательный номер "внешнего" счета организации, по умолчанию первый ('1')

если настройка по контракту не была найдена вызовет исключение:
(ORA-20106: External balance configuration for contract [%contract_number] not found)
если передан не существующий account_type будет вызвано исключение:
(ORA-20107: account_type [%account_type] not found)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20204: Error when get external account)
*/
FUNCTION GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER (contract_number in string, account_type in string DEFAULT 'MAIN', seq in string DEFAULT '1') 
RETURN string IS
c_account_number varchar2(25) := 'DEFAULT_VALUE';

BEGIN
  SELECT
   CASE WHEN account_type = 'MAIN' THEN hb.FILTER3
        WHEN account_type = 'OPPOSITE' THEN hb.FILTER4 END INTO c_account_number
  FROM ows.sy_handbook hb
  WHERE
      hb.AMND_STATE = 'A'
  AND hb.GROUP_CODE = 'EXTERNAL_ACCOUNTS_ROBOT_LIMITER'
  AND hb.FILTER = contract_number
  AND hb.FILTER2 = seq;
  
  IF (c_account_number is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;

  RETURN c_account_number;

EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    RAISE_APPLICATION_ERROR(-20106,'External account configuration for contract [' || contract_number || '] not found');
  WHEN ACCESS_INTO_NULL THEN 
    RAISE_APPLICATION_ERROR(-20107,'account_type [' || account_type || '] not found');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20204,'Error when get external account');

END GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER;

/*Процедура для сохранения значения "внешнего" сальдо за оконченные дни
external_balance - значение "внешнего" сальдо
external_balance_date - дата за которую передано "внешнее" сальдо

если передан external_balance или external_balance_date равный NULL будет вызвано исключение:
(ORA-20108: external_balance or external_balance_date is null)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20205: Error when save external balance per date in history)
*/
PROCEDURE SAVE_EXTERNAL_BALANCE_PER_DATE(external_balance number, external_balance_date date, contract_number in string DEFAULT '-', seq in string DEFAULT '1') is
  is_exists number(18,0) := 0;
BEGIN
  ows.stnd.process_message(ows.sy_process.information, 'SAVE_EXTERNAL_BALANCE_PER_DATE #external_balance = ' || external_balance ||
                                                                 ' #external_balance_date = ' || to_char(external_balance_date));						   
  ows.stnd.process_message(ows.sy_process.information, 'Strat save external balance per date in history');
  COMMIT;
  
  IF (external_balance is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;
  
  IF (external_balance_date is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;
  
  SELECT COUNT(1) INTO is_exists 
  FROM proc.EXTERNAL_BALANCE_HISTORY 
  WHERE BALANCE_DATE = to_date(external_balance_date);
  
  IF (is_exists = 0) THEN 
    INSERT INTO proc.EXTERNAL_BALANCE_HISTORY (BALANCE, BALANCE_DATE) VALUES (external_balance, to_date(external_balance_date));
  ELSE
    UPDATE proc.EXTERNAL_BALANCE_HISTORY SET AMND_DATE = sysdate, BALANCE = external_balance WHERE BALANCE_DATE = to_date(external_balance_date);
  END IF;

  ows.stnd.process_message(ows.sy_process.information, 'End save external balance per date in history');
  COMMIT;
  
EXCEPTION
  WHEN ACCESS_INTO_NULL THEN 
    ows.stnd.process_message(ows.sy_process.error, 'external_balance or external_balance_date is null');
    ows.stnd.process_reject();
    RAISE_APPLICATION_ERROR(-20108,'external_balance or external_balance_date is null');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when save external balance per date in historyt');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20205,'Error when save external balance per date in history');
END SAVE_EXTERNAL_BALANCE_PER_DATE;

/*Процедура для сохранения информации о проведении проводок по файлу М для сохранённых значений 
"внешнего" сальдо за оконченные дни
external_balance_date - дата за которую были проводки по файлу М

если не найдена запись в таблице EXTERNAL_BALANCE_HISTORY с днем равным external_balance_date будет вызвано исключение:
(ORA-20109: Day [%external_balance_date%] not found  in table proc.EXTERNAL_BALANCE_HISTORY)
если передан external_balance_date равный NULL будет вызвано исключение:
(ORA-20110: external_balance_date is null)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20206: Error when approve external balance per date in history)
*/

PROCEDURE APPROVE_EXTERNAL_BALANCE_PER_DATE(external_balance_date date, contract_number in string DEFAULT '-', seq in string DEFAULT '1') is
  is_exists number(18,0) := 0;
BEGIN
  ows.stnd.process_message(ows.sy_process.information, 'APPROVE_EXTERNAL_BALANCE_PER_DATE #external_balance_date = ' || to_char(external_balance_date));
  ows.stnd.process_message(ows.sy_process.information, 'Strat approve external balance per date in history');
  COMMIT;
  
  IF (external_balance_date is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;
  
  SELECT COUNT(1) INTO is_exists 
  FROM proc.EXTERNAL_BALANCE_HISTORY 
  WHERE BALANCE_DATE = to_date(external_balance_date);
  
  IF (is_exists = 0) THEN 
    raise NO_DATA_FOUND;
  END IF;
  
  UPDATE proc.EXTERNAL_BALANCE_HISTORY SET AMND_DATE = sysdate, ENTRY_EXISISTS = 'Y' WHERE BALANCE_DATE = to_date(external_balance_date);
  
  ows.stnd.process_message(ows.sy_process.information, 'End approve external balance per date in history');
  COMMIT;
  
EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    ows.stnd.process_message(ows.sy_process.error, 'Day [' || to_char(external_balance_date, 'dd.mm.yyyy') || '] not found  in table proc.EXTERNAL_BALANCE_HISTORY');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20109,'Day [' || to_char(external_balance_date, 'dd.mm.yyyy') || '] not found  in table proc.EXTERNAL_BALANCE_HISTORY');
  WHEN ACCESS_INTO_NULL THEN 
    ows.stnd.process_message(ows.sy_process.error, 'external_balance_date is null');
    ows.stnd.process_reject();
    RAISE_APPLICATION_ERROR(-20110,'external_balance_date is null');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when save external balance per date in historyt');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20206,'Error when approve external balance per date in history');
END APPROVE_EXTERNAL_BALANCE_PER_DATE;

/* Функция для получения сохранненных значений "внешнего" сальдо за оконченные дни, сумирует сальдо всех дат без подтверждения 
external_balance_date - отправная дата за которую были проводки по файлу М

если не найдена запись в таблице EXTERNAL_BALANCE_HISTORY с днем равным external_balance_date будет вызвано исключение:
(ORA-20111: Day [%external_balance_date%] not found  in table proc.EXTERNAL_BALANCE_HISTORY)
если передан external_balance_date равный NULL будет вызвано исключение:
(ORA-20112: external_balance_date is null)
При возникновении любого другого исключения при выполнении будет вызвано исключение:
(ORA-20207: Error when get external balance per date in history)
*/
FUNCTION GET_EXTERNAL_BALANCE_PER_DATE (external_balance_date date, contract_number in string DEFAULT '-', seq in string DEFAULT '1') 
RETURN number IS
n_balance NUMBER(18,2) := 0;
n_first_row number := 1;
d_balance_date_start date;
d_balance_date_end date;

BEGIN
  IF (external_balance_date is null) THEN 
    raise ACCESS_INTO_NULL;
  END IF;
  
  FOR item in (SELECT ID, AMND_DATE, BALANCE_DATE, BALANCE, ENTRY_EXISISTS 
               FROM EXTERNAL_BALANCE_HISTORY 
               WHERE BALANCE_DATE <= (to_date(external_balance_date)) 
               ORDER BY BALANCE_DATE DESC)
  LOOP
    IF(n_first_row = 1) THEN
      n_first_row := 0;
      d_balance_date_end := item.BALANCE_DATE;
    END IF;
    
    exit when item.ENTRY_EXISISTS = 'Y';
    d_balance_date_start := item.BALANCE_DATE;
  END LOOP;
  
  SELECT SUM(BALANCE) INTO n_balance 
  FROM EXTERNAL_BALANCE_HISTORY 
  WHERE BALANCE_DATE BETWEEN d_balance_date_start and d_balance_date_end;
  
  IF(n_balance IS NULL) THEN
    raise NO_DATA_FOUND;
  END IF;
  
  RETURN n_balance;

EXCEPTION
   WHEN NO_DATA_FOUND THEN 
    RAISE_APPLICATION_ERROR(-20111,'Day [' || to_char(external_balance_date, 'dd.mm.yyyy') || '] not found  in table proc.EXTERNAL_BALANCE_HISTORY');
  WHEN ACCESS_INTO_NULL THEN 
    RAISE_APPLICATION_ERROR(-20112,'external_balance_date is null');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20207,'Error when get external balance per date in history');

END GET_EXTERNAL_BALANCE_PER_DATE;

/* Функция для расчета лимита авторизации клиенту
contract_number - контракт по которому проводим расчет
*/
PROCEDURE CALCULATE_AUTHORIZATION_LIMIT(contract_number in string, n_amount_on_account out number) is 
  counter number;
  temp number;
  
  c_org_account varchar2(25);
  
  c_visa_account varchar2(25);
  c_visa_account_oppo varchar2(25);
  
  c_mc_account varchar2(25);
  c_mc_account_oppo varchar2(25);
  
  c_mir_account varchar2(25);
  c_mir_account_oppo varchar2(25);
  
  n_amount_on_account_local number(18,2);
  n_limit number(18,2);
  n_limit_bfko number(18,2) := 0;
  n_entry_count number(18,0);
  n_balance_per_period number(18,2);
  n_balance_now number(18,2);
  
  b_entrys_exists boolean := false;
  
  
BEGIN
  counter := ows.stnd.process_start('CALCULATE_AUTHORIZATION_LIMIT', '#contract_number = ' || contract_number, ows.sy_process.uninotunique);
  ows.stnd.process_message(ows.sy_process.information, 'Strat calculate auth limit');
  COMMIT;
  
  ows.stnd.process_message(ows.sy_process.information, 'Get accounts numbers');
  c_org_account := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER(contract_number, 'MAIN', 'ORG');
  ows.stnd.process_message(ows.sy_process.information, 'Organization account is [' || c_org_account || ']');
  
  c_visa_account := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER(contract_number, 'MAIN', 'VISA');
  ows.stnd.process_message(ows.sy_process.information, 'Visa account is [' || c_visa_account || ']');
  c_visa_account_oppo := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER(contract_number, 'OPPOSITE', 'VISA');
  ows.stnd.process_message(ows.sy_process.information, 'Visa opposite account is [' || c_visa_account_oppo || ']');
  
  c_mc_account := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER(contract_number, 'MAIN', 'MC');
  ows.stnd.process_message(ows.sy_process.information, 'MasterCard account is [' || c_mc_account || ']');
  c_mc_account_oppo := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER(contract_number, 'OPPOSITE', 'MC');
  ows.stnd.process_message(ows.sy_process.information, 'MasterCard opposite account is [' || c_mc_account_oppo || ']');
  
  c_mir_account := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER(contract_number, 'MAIN', 'MIR');
  ows.stnd.process_message(ows.sy_process.information, 'Mir account is [' || c_mir_account || ']');
  c_mir_account_oppo := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER(contract_number, 'OPPOSITE', 'MIR');
  ows.stnd.process_message(ows.sy_process.information, 'Mir opposite account is [' || c_mir_account_oppo || ']');
  COMMIT;
  
  ows.stnd.process_message(ows.sy_process.information, 'Get organization account balance');
  n_amount_on_account_local := PROC.ACQINFO_Q.GET_BALANCE(PROC.ROBOT_LIMITER_UTILS.GET_ACCOUNT(c_org_account), PROC.ROBOT_LIMITER_UTILS.GET_BIC(c_org_account));
  ows.stnd.process_message(ows.sy_process.information, 'Loaded balance from CFT = [' || n_amount_on_account_local || ']');
  IF (n_amount_on_account_local IS NOT NULL) THEN
    PROC.ROBOT_LIMITER_UTILS.SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER(n_amount_on_account_local, sysdate, contract_number, 'ORG');
    ows.stnd.process_message(ows.sy_process.information, 'Balance saved in account property');
  ELSE 
    ows.stnd.process_message(ows.sy_process.information, 'Satrt get balance from account property');
    n_amount_on_account_local := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER(contract_number, 'ORG');
	ows.stnd.process_message(ows.sy_process.information, 'Loaded balance from account property = [' || n_amount_on_account_local || ']');
  END IF;
  COMMIT;
  
  ows.stnd.process_message(ows.sy_process.information, 'Get balance in now date');
  n_balance_now := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_BALANCE_ROBOT_LIMITER(contract_number, 'BALANCE');
  ows.stnd.process_message(ows.sy_process.information, 'Balance in now date is [' || n_balance_now || ']');
  
  ows.stnd.process_message(ows.sy_process.information, 'Get turnover by accounts in now date');
  COMMIT;
  
  temp := PROC.ACQINFO_Q.GETDOCS(c_org_account, c_visa_account, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_visa_account, c_org_account, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_org_account, c_visa_account_oppo, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_visa_account_oppo, c_org_account, to_date(sysdate));
    
  temp := PROC.ACQINFO_Q.GETDOCS(c_org_account, c_mc_account, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_mc_account, c_org_account, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_org_account, c_mc_account_oppo, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_mc_account_oppo, c_org_account, to_date(sysdate));
    
  temp := PROC.ACQINFO_Q.GETDOCS(c_org_account, c_mir_account, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_mir_account, c_org_account, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_org_account, c_mir_account_oppo, to_date(sysdate));
  temp := PROC.ACQINFO_Q.GETDOCS(c_mir_account_oppo, c_org_account, to_date(sysdate)); 

  ows.stnd.process_message(ows.sy_process.information, 'Check turnover by accounts in now date');
  COMMIT;
  
  SELECT COUNT(1) into n_entry_count 
  FROM PROC.ACQINFO_DOC d 
  WHERE (d.ACCOUNT_DT = c_org_account or d.ACCOUNT_KT = c_org_account) and d.LOCAL_DATE = to_date(sysdate);

  IF(n_entry_count > 0) THEN
    ows.stnd.process_message(ows.sy_process.information, 'Turnover by accounts in now date is exists');
	COMMIT;
	
    IF(to_date(sysdate+1) - interval '120' minute > sysdate) THEN
	  ows.stnd.process_message(ows.sy_process.information, 'Approve balance per prev date');
	  PROC.ROBOT_LIMITER_UTILS.APPROVE_EXTERNAL_BALANCE_PER_DATE(to_date(sysdate-1));
    END IF;
	
	n_limit := n_amount_on_account_local + n_balance_now;
  ELSE
    ows.stnd.process_message(ows.sy_process.information, 'Turnover by accounts in now date is not exists');
	COMMIT;
	
    n_balance_per_period := PROC.ROBOT_LIMITER_UTILS.GET_EXTERNAL_BALANCE_PER_DATE(sysdate);
	ows.stnd.process_message(ows.sy_process.information, 'Loaded balance per period is [' || n_balance_per_period || ']');
	n_amount_on_account_local := n_amount_on_account_local + n_balance_per_period;
    n_limit := n_amount_on_account_local + n_balance_now;
  END IF;

  ows.stnd.process_message(ows.sy_process.information, 'End calculate auth limit. Limit for add to limit BFKO is [' || n_limit || ']');
  COMMIT;
  PROC.ROBOT_LIMITER_UTILS.SET_EXTERNAL_BALANCE_ROBOT_LIMITER(n_limit, contract_number, 'LIMIT');
  
  n_limit_bfko := PROC.ACQINFO_Q.GET_USG(contract_number);
  ows.stnd.process_message(ows.sy_process.information, 'Now limit for client in BFKO without "calculate auth limit" is [' || n_limit_bfko || ']');
  COMMIT;
  
  n_amount_on_account_local := n_amount_on_account_local + n_limit_bfko;
  
  ows.stnd.process_message(ows.sy_process.information, 'End calculate auth limit. Limit for BPC is [' || n_amount_on_account_local || ']');
  ows.stnd.process_end();
  COMMIT;
  
  n_amount_on_account := n_amount_on_account_local;
  
END CALCULATE_AUTHORIZATION_LIMIT;

END ROBOT_LIMITER_UTILS;

grant EXECUTE, DEBUG on "PROC"."ROBOT_LIMITER_UTILS" to "OWS" ;