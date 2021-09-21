CREATE OR REPLACE PACKAGE BODY ROBOT_LIMITER_UTILS is

/*
������� ��� ���������� ������ ��� �� ������ ���������
����� �� ������ acqinfo_q (bic)
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
������� ��� ���������� ������ ����� �� ���������
����� �� ������ acqinfo_q (acc)
*/
FUNCTION GET_ACCOUNT(p_account in string) return string is
BEGIN
    IF p_account IS NULL THEN
      RETURN NULL;
    END IF;
    RETURN SUBSTR(p_account,1,20);
END;

/* ������� ��� ��������� ���������� "��������" ������
contract_number - ����� ��������� (����� � Custom Handbooks AUTH_LIM)
seq - ����������������� ����� "��������" ������, �� ��������� ������ ('1')

���� ��������� �� ��������� �� ���� ������� ������� ����������:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
��� ������������� ������ ������� ���������� ��� ���������� ����� ������� ����������:
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

/*��������� ��� ��������� ���������� "��������" ������
external_balance - ����� �������� ������
contract_number - ����� ��������� (����� � Custom Handbooks AUTH_LIM)
seq - ����������������� ����� "��������" ������, �� ��������� ������ ('1')

���� ��������� �� ��������� �� ���� ������� ������� ����������:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
��� ������������� ������ ������� ���������� ��� ���������� ����� ������� ����������:
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

/*��������� ��� ��������� �������� ������� � ���� � ������� ��������� �������� �� "��������" ����� �����������
external_balance - ����� ������� �� �����
last_operation_date - ���� � ����� ��������� �������� ���������� ��� �������� �� "�������" ����
contract_number - ����� ��������� (����� � Custom Handbooks AUTH_LIM)
seq - ����������������� ����� "��������" ����� �����������, �� ��������� ������ ('1')

���� ��������� �� ��������� �� ���� ������� ������� ����������:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
���� ������� last_operation_date ������ NULL ����� ������� ����������:
(ORA-20008: last_operation_date is null)
��� ������������� ������ ������� ���������� ��� ���������� ����� ������� ����������:
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
  and hb.FILTER2 = seq;
  
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
  and hb.FILTER2 = seq;
  
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
    ows.stnd.process_message(ows.sy_process.error, 'last_operation_date is null');
    ows.stnd.process_reject();
    RAISE_APPLICATION_ERROR(-20008,'last_operation_date is null');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when set external account');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20007,'Error when set external account');
END SET_EXTERNAL_ACCOUNT_BALANCE_ROBOT_LIMITER;

/* ������� ��� ��������� "��������" ����� ����������� � ���
contract_number - ����� ��������� (����� � Custom Handbooks AUTH_LIM)
account_type - ��� ������ ����� ������� ����� �������� �� ���������. ��������� ��������:
               MAIN - ������� ���� �����������
			   OPPOSITE - ���������� ������� ����
seq - ����������������� ����� "��������" ����� �����������, �� ��������� ������ ('1')

���� ��������� �� ��������� �� ���� ������� ������� ����������:
(ORA-20006: External balance configuration for contract [%contract_number] not found)
���� ������� �� ������������ account_type ����� ������� ����������:
(ORA-20008: account_type [%account_type] not found)
��� ������������� ������ ������� ���������� ��� ���������� ����� ������� ����������:
(ORA-20007: Error when get external account)
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
    RAISE_APPLICATION_ERROR(-20006,'External account configuration for contract [' || contract_number || '] not found');
  WHEN ACCESS_INTO_NULL THEN 
    RAISE_APPLICATION_ERROR(-20008,'account_type [' || account_type || '] not found');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20007,'Error when get external account');

END GET_EXTERNAL_ACCOUNT_ROBOT_LIMITER;

/*��������� ��� ���������� �������� "��������" ������ �� ���������� ���
external_balance - �������� "��������" ������
external_balance_date - ���� �� ������� �������� "�������" ������

���� ������� external_balance ��� external_balance_date ������ NULL ����� ������� ����������:
(ORA-20008: external_balance or external_balance_date is null)
��� ������������� ������ ������� ���������� ��� ���������� ����� ������� ����������:
(ORA-20007: Error when set external account)
*/
PROCEDURE SAVE_EXTERNAL_BALANCE_PER_DATE(external_balance number, external_balance_date date) is
  counter number;
  is_exists number(18,0) := 0;
BEGIN
  counter := ows.stnd.process_start('SAVE_EXTERNAL_BALANCE_PER_DATE', '#external_balance = ' || external_balance ||
                                                                 ' #external_balance_date = ' || to_char(external_balance_date),
                            ows.sy_process.uninotunique);
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
  
  ows.stnd.process_end();
  COMMIT;
  
EXCEPTION
  WHEN ACCESS_INTO_NULL THEN 
    ows.stnd.process_message(ows.sy_process.error, 'external_balance or external_balance_date is null');
    ows.stnd.process_reject();
    RAISE_APPLICATION_ERROR(-20008,'external_balance or external_balance_date is null');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when save external balance per date in historyt');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20007,'Error when save external balance per date in history');
END SAVE_EXTERNAL_BALANCE_PER_DATE;

/*��������� ��� ���������� ���������� � ���������� �������� �� ����� � ��� ������������ �������� 
"��������" ������ �� ���������� ���
external_balance_date - ���� �� ������� ���� �������� �� ����� �

���� �� ������� ������ � ������� EXTERNAL_BALANCE_HISTORY � ���� ������ external_balance_date ����� ������� ����������:
(ORA-20006: Day [%external_balance_date%] not found  in table proc.EXTERNAL_BALANCE_HISTORY)
���� ������� external_balance_date ������ NULL ����� ������� ����������:
(ORA-20008: external_balance or external_balance_date is null)
��� ������������� ������ ������� ���������� ��� ���������� ����� ������� ����������:
(ORA-20007: Error when set external account)
*/

PROCEDURE APPROVE_EXTERNAL_BALANCE_PER_DATE(external_balance_date date) is
  counter number;
  is_exists number(18,0) := 0;
BEGIN
  counter := ows.stnd.process_start('APPROVE_EXTERNAL_BALANCE_PER_DATE', '#external_balance_date = ' || to_char(external_balance_date),
                            ows.sy_process.uninotunique);
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
  
  ows.stnd.process_end();
  COMMIT;
  
EXCEPTION
  WHEN NO_DATA_FOUND THEN 
    ows.stnd.process_message(ows.sy_process.error, 'Day [' || to_char(external_balance_date, 'dd.mm.yyyy') || '] not found  in table proc.EXTERNAL_BALANCE_HISTORY');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20006,'Day [' || to_char(external_balance_date, 'dd.mm.yyyy') || '] not found  in table proc.EXTERNAL_BALANCE_HISTORY');
  WHEN ACCESS_INTO_NULL THEN 
    ows.stnd.process_message(ows.sy_process.error, 'external_balance_date is null');
    ows.stnd.process_reject();
    RAISE_APPLICATION_ERROR(-20008,'external_balance_date is null');
  WHEN OTHERS THEN
    ows.stnd.process_message(ows.sy_process.error, 'Error when save external balance per date in historyt');
    ows.stnd.process_reject();
    COMMIT;
    RAISE_APPLICATION_ERROR(-20007,'Error when approve external balance per date in history');
END APPROVE_EXTERNAL_BALANCE_PER_DATE;

END ROBOT_LIMITER_UTILS;

grant EXECUTE, DEBUG on "PROC"."ROBOT_LIMITER_UTILS" to "OWS" ;