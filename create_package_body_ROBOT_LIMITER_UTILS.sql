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

/*
Разработана в рамках TASK 836623
Функции для расчета доступного лимита us14 для клиента Мобильная карта на основе алгоритма pret_ath_usg_limit_cft
p_ac - номер контракта для расчета лимита
*/
FUNCTION GET_USG(p_ac in string) return number
is
  ttid number(12);
  app_n number(12);
  v_appnum string(12);
  v_date_ost date;

  v_c2a_tr number(12,2);
  v_AFT_dt date;
  v_c2a_rate number(12,2);
  v_a2c_tr number(12,2);
  v_OCT_dt date;

  v_a2c_rate number(12,2);
  v_all_acc_amnt number(12,2);

  v_sum_a2c   number(12,2);
  v_sum_c2a   number(12,2);
  v_new_limit number(12,2);

  v_contract varchar2(100);

  v_account_amounts number(12,2);
  v_amnt            number(12,2);
  v_amnt_rur        number(12,2);
  v_fxdt            date;
  v_fx              number(12,2);

  function v(vv in number) return number is begin return nvl(vv,0); end;
  procedure log(t in string, txt in string) is
  begin
    if v_contract is null then
      ows.sy_process.PROCESS_MESSAGE(t,txt);
    else
      ows.sy_process.PROCESS_MESSAGE(t,v_contract||'. '||txt);
    end if;
  end;
  procedure log(txt in string) is
  begin
    log('I',txt);
  end;

function bic(p_account in string) return string is
  begin
    if p_account is null then
      return null;
    end if;
    if (p_account not like '%/%') then
      return '044525297';
    end if;
    return substr(p_account,instr(p_account,'/')+1);
  end;
-- Достаем счет из номера счета
  function acc(p_account in string) return string is
  begin
    if p_account is null then
      return null;
    end if;
    return substr(p_account,1,20);
  end;
  procedure p(pp in string) is
  begin
    ttid:=ttid+1;
    if (length(pp) <= 256) then
     insert into proc.tt_universal tt
      (s7, i1, n1) values
      (pp, ttid,app_n);
     else
      raise_application_error(-20100,'Line '||ttid||' string too long: Len='||length(pp)||' => '||pp);
    end if;
  end;

  function GetLimitDate(p_acc_dt in string, p_acc_kt in string, p_limit_code in string, p_rate out number) return date
  is
    v_hb_date date;
    v_cft_date date;
    v_cnt number(12,2);
  begin
    select min(to_date(h.code,'dd-MON-yy','NLS_DATE_LANGUAGE = American')) D, min(filter2), count(*)
    into v_hb_date, p_rate, v_cnt
    from ows.sy_handbook h where h.amnd_state = 'A' and h.group_code = p_limit_code;
    if (v_cnt=0) then
      log('E','Ошибка настроек: в SY_HANDBOOK отсудсвтует лимитер с кодом '||p_limit_code);
      return null;
    end if;
    if (v_hb_date = trunc(sysdate)) then
      return v_hb_date;
    end if;
    v_cft_date:=nvl(v_hb_date,trunc(sysdate-4));
    if (sysdate-v_cft_date>4) then
      log('W','Последний успешный документ из ЦФТ был слишком давно ('||to_char(v_cft_date,'DD.MM.YYYY')||') - рекомендуем проверить настройки обмена с АБС!');
      v_cft_date:=trunc(sysdate-4);
    end if;
    loop
       v_cft_date:=v_cft_date+1;
       exit when v_cft_date>sysdate;
       if v_cft_date is null then raise_application_error(-20100,'DNA Error in cft date defected :('); end if;
       log('Проверяем, были ли в ЦФТ документы за '||to_char(v_cft_date,'DD.MM.YYYY HH24:MI:SS'));
       v_cnt:=acqinfo_q.getDocs(p_acc_dt,p_acc_kt,v_cft_date);
       select count(*)
        into v_cnt
        from acqinfo_doc ad
       where ad.account_kt=p_acc_kt
         and ad.account_dt=p_acc_dt
         and ad.local_date=v_cft_date;
        if v_cnt=0 then
          log(p_limit_code||' нет документов в ЦФТ за'||to_char(v_cft_date,'DD.MM.YYYY')||': '||p_acc_dt||'=>'||p_acc_kt);
        else
          update ows.SY_HANDBOOK set AMND_DATE=sysdate,
            CODE =to_char(v_cft_date,'DD-MON-YY','NLS_DATE_LANGUAGE = American')
            where GROUP_CODE = p_limit_code and amnd_state = 'A';
          log(p_limit_code||' документ в ЦФТ обнаружен, дата сменена на '||to_char(v_cft_date,'DD-MON-YY','NLS_DATE_LANGUAGE = American')||' '||p_acc_dt||'=>'||p_acc_kt);
          v_hb_date:=v_cft_date;
        end if;
    end loop;
    return v_hb_date;
  end;

begin
  log('Strart "MDM.Расчет ограничителя по логике НКО ПиР" for contract [' || p_ac || ']');
  delete from proc.tt_universal;
  ttid:=0;
  proc.utils.SEQ_NEXT_DAILY(proc.utils.ATHENE,v_AFT_dt,v_appnum);
  v_appnum:='1'||lpad(v_appnum,4,'0');
  update ows.v_local_constants set string_1=v_appnum||'.'||to_char(sysdate,'DDD');
  app_n:=0;
p('<?xml version="1.0" encoding="WINDOWS-1251"?>');
p('<ApplicationFile>');
p('  <FileHeader>');
p('    <FormatVersion>2.0</FormatVersion>');
p('    <Sender>ATHENE</Sender>');
p('    <CreationDate>'||to_char(sysdate,'YYYY-MM-DD')||'</CreationDate>');
p('    <CreationTime>'||to_char(sysdate,'HH24:MI:SS')||'</CreationTime>');
p('    <Number>'||v_appnum||'</Number>');
p('  </FileHeader>');
p('  <ApplicationsList>');
  app_n:=1;
<<LOOP>>
for i in (
select Q.ID
      ,Q.NAME
      ,Q.CONTRACT_NUMBER
      ,Q.DOPEN
      ,NVL(Q.AUTHS, 0) AUTHS
      ,NVL(Q.CAMNT, 0) CAMNT
      ,Q.BCODE
    ,Q.FI_ID
    ,Q.count_ecom
    ,Q.curr
    ,ows.xwdoc('TRANS_CURR',q.curr) as pret_curr
    ,Q.ACC1
    ,Q.ACC2
    ,Q.ACC3
    ,Q.ACC4
  from (select C.ID ID
              ,F.NAME name
        ,F.ID FI_ID
        ,f.cb_code bik
              ,C.CONTRACT_NUMBER CONTRACT_NUMBER
              ,TO_CHAR(C.DATE_OPEN, 'DD.MM.YYYY') DOPEN
              ,(select sum(H.AMOUNT)
                  from OWS.USAGE_TEMPL      T
                      ,OWS.USAGE_LIMITER    L
                      ,OWS.USAGE_HISTORY    H
                      ,OWS.CREDIT_HISTORY   CH
                      ,OWS.SERVICE_APPROVED SA
                 where T.AMND_STATE = 'A'
                   and T.USAGE_CODE = 'us14'
                   and T.ACNT_CONTRACT__OID = C.ID
                   and L.ACNT_CONTRACT__OID = T.ACNT_CONTRACT__OID
                   and L.USAGE_TEMPLATE = T.ID
                   and H.STATUS = 'A'
                   and SA.ID(+) = CH.SERVICE_ID
                   and SA.PARENT_SERVICE is null
                   and CH.ACCOUNT(+) is null
                   and H.EXPIRE_DATE >= TRUNC(sysdate)
                   and H.USAGE_LIMITER__OID = L.ID
                   and CH.DOC__ID(+) = H.DOC
                   and CH.CREDIT_STATUS(+) = 'A') AUTHS
              ,cast(OWS.RPR.USAGE_CURRENT_AMOUNT(T.ID, C.ID) as
                    number(23, 5)) CAMNT
              ,F.BRANCH_CODE BCODE
        ,sh.code count_ecom
        ,sh.id_filter1 curr
        ,sh.filter2 ACC1
        ,sh.filter3 ACC2
        ,sh.filter4 ACC3
        ,sh.filter5 ACC4
          from OWS.ACNT_CONTRACT C
              ,OWS.F_I           F
              ,OWS.USAGE_TEMPL   T
        ,ows.sy_handbook sh
         where 1 = 1
           and C.AMND_STATE = 'A'
           and F.ID = C.F_I
           and T.AMND_STATE = 'A'
           and T.USAGE_CODE = 'us14'
           and T.ACNT_CONTRACT__OID = C.ID
       and sh.GROUP_CODE like 'B2%_ROBOT_LIMITER'
       and c.contract_number=p_ac
       and sh.amnd_state = 'A'
           and C.contract_number = sh.FILTER
    ) Q
) loop
v_contract:=i.contract_number;
log('Расчитываю лимит для контракта');
log('Установлены следующие параметры:');
log(
  'ID='||i.ID||';'||
  'NAME='||i.NAME||';');
log(
  'DOPEN='||i.DOPEN||';'||
  'AUTHS='||i.AUTHS||';'||
  'CAMNT='||i.CAMNT||';'||
  'BCODE='||i.BCODE||';'||
  'FI_ID='||i.FI_ID||';'||
  'count_ecom='||i.count_ecom||';'||
  'curr='||i.curr||';'||
  'pret_curr='||i.pret_curr||';');
log(
  'ACC1='||i.ACC1||';'||
  'ACC2='||i.ACC2||';'||
  'ACC3='||i.ACC3||';'||
  'ACC4='||i.ACC4||';'
  );






/***************************
  Собираем счета для проверки балансов
***************************/





    log('1. запрашивается остаток на счёте НКО в ЦФТ: '||i.acc2);
    v_all_acc_amnt:=acqinfo_q.get_Balance(acc(i.acc2), bic(i.acc2));

    if (v_all_acc_amnt is null) then
      select min(id_filter2), min(amnd_date)
        into v_all_acc_amnt, v_date_ost
        from ows.sy_handbook h
      where h.amnd_state = 'A' and h.group_code = 'B2B_ROBOT_LIMITER' and h.filter=i.contract_number;
      if (v_all_acc_amnt is null) then
        log('E','1 # Остаток на счете получить невозможно, фомирование ограничителя пропущено!');
        continue LOOP;
      end if;
      log('1 # Остаток получен из буфера way4 : '||(v_all_acc_amnt)||' от '||to_char(v_date_ost,'dd-mm-yyyy hh24:mi'));
    else
      update ows.SY_HANDBOOK set ID_FILTER2 = round(v_all_acc_amnt),amnd_date=sysdate
       where GROUP_CODE ='B2B_ROBOT_LIMITER' and amnd_state = 'A' and FILTER = i.contract_number;
      log('1 # Баланс '||i.acc2||' благополучно найден: '||v_all_acc_amnt);
    end if;
    
    v_account_amounts:=0;
 
    for ii in (
     select h.*,ows.xwdoc('TRANS_CURR',h.id_filter1) as curr from ows.sy_handbook h
      where h.amnd_state = 'A' 
        and h.group_code = 'B2B_ROBOT_ACCOUNT' 
        and h.filter=i.contract_number) loop
      v_amnt:=acqinfo_q.get_Balance(acc(ii.filter3), bic(ii.filter3));
      log('1 # Доп баланс '||ii.filter3||' благополучно найден: '||v_amnt);
      select max(r.valid_date) into v_fxdt from cbfx_rates r where r.code=ii.curr and r.valid_date<=trunc(sysdate);
      select max(r.rate) into v_fx from cbfx_rates r where r.code=ii.curr and r.valid_date=v_fxdt;
      if (v_fxdt is null) then
        log('E','1 # Курс ЦБ для валюты '||ii.id_filter1||'['||ii.curr||'] за дату '||to_char(sysdate,'YYYY-mm-dd')||' отсутствует в системе !');
        continue;
      elsif (v_fxdt!=trunc(sysdate)) then
        log('W','1 # Курс ЦБ '||ii.id_filter1||'['||ii.curr||'] за дату '||
        to_char(sysdate,'YYYY-mm-dd')||' неактуален, для расчета ипользован курс за '||
        to_char(v_fxdt,'YYYY-mm-dd')||' !');
      end if;
      v_amnt_rur:=round(v_amnt*v_fx,2);
      log('1 # Доп баланс '||ii.id_filter1||'['||ii.curr||'] '||v_amnt||
          'по курсу '||v_fx||' = '|| v_amnt_rur);
      v_account_amounts:=v_account_amounts+v_amnt_rur;
    end loop;
    if (v_account_amounts!=0) then
      log('1 # Доп баланс по валютным счетам = '|| v_account_amounts);
    end if;


    log('2. запрашивается наличие документа (расчёты по AFT) в ЦФТ, '||i.acc4||'=>'||i.acc2);
    v_AFT_dt :=GetLimitDate(i.acc4, i.acc2,'LIM_C2A_' ||i.contract_number, v_c2a_rate);
    if (v_AFT_dt is null) then
      log('E','2 # Дату последнего перечисления AFT получить невозможно, фомирование ограничителя пропущено!');
      continue LOOP;
    end if;
    log('2 # Документ (расчёты по AFT) в ЦФТ найден: '||to_char(v_AFT_dt,'YYYY-MM-DD'));

    log('3. запрашивается наличие документа (расчёты по OCT) в ЦФТ, '||i.acc2||'=>'||i.acc3);
    v_OCT_dt :=GetLimitDate(i.acc2, i.acc3,'LIM_A2C_' ||i.contract_number, v_a2c_rate);
    if (v_OCT_dt is null) then
      log('E','3 # Дату последнего перечисления OCT получить невозможно, фомирование ограничителя пропущено!');
      continue LOOP;
    end if;
    log('3 # Документ (расчёты по OCT) в ЦФТ найден: '||to_char(v_OCT_dt,'YYYY-MM-DD'));


    log('4. определяется сумма транзакций AFT c даты '||to_char(v_AFT_dt,'YYYY-MM-DD "0:00"'));
/***************************
  #подсчет С2А
***************************/
      SELECT NVL(ROUND(SUM(d.settl_amount)), 0) summ
      into v_c2a_tr
          FROM doc d
         WHERE d.amnd_state = 'A'
           AND d.is_authorization = 'N'
           AND d.service_class = 'T'
           AND d.id IN (SELECT /*+ USE_NL(mac ac)
                       USE_NL(ac ds)
                       USE_NL(ds dsd)
                       INDEX(ds device_stat1) */
                     dsd.doc_id
                  FROM acnt_contract mac
                 INNER JOIN acnt_contract ac ON mac.client__id = ac.client__id
                              AND mac.curr = ac.curr
                              AND ac.amnd_state = 'A'
                              AND (ac.contract_number LIKE 'CA%' or ac.contract_number LIKE 'AFT%')
                              AND ac.con_cat = 'M'
                              AND ac.acnt_contract__oid IS NOT NULL
--                              AND ac.contract_number LIKE 'CA%'
                 INNER JOIN device_stat ds ON ac.id = ds.acnt_contract__oid
                              AND ds.request_category = 'P'
                              AND ds.resp_code = 0
                              AND ds.trans_type = 1962
                              AND ds.posting_date >= v_AFT_dt
                 INNER JOIN device_stat_doc dsd ON ds.id = dsd.device_stat__oid
                 WHERE mac.amnd_state = 'A'
                   AND mac.contract_number = i.contract_number
                   and i.acc4 is not null);
      log('I','4 # подсчет AFT(C2A): '||(v_c2a_tr)||'; Date: '||v_AFT_dt);

/***************************
  #подсчет А2С
***************************/

    log('5. определяется сумма транзакций OCT c даты '||to_char(v_OCT_dt,'YYYY-MM-DD "0:00"'));
      SELECT NVL(ROUND(SUM(d.settl_amount)), 0) summ
       into v_a2c_tr
          FROM doc d
         WHERE d.amnd_state = 'A'
           AND d.is_authorization = 'N'
           AND d.service_class = 'T'
           AND d.id IN (SELECT /*+ USE_NL(mac ac)
                       USE_NL(ac ds)
                       USE_NL(ds dsd)
                       INDEX(ds device_stat1) */
                     dsd.doc_id
                  FROM acnt_contract mac
                 INNER JOIN acnt_contract ac ON mac.client__id = ac.client__id
                              AND mac.curr = ac.curr
                              AND ac.amnd_state = 'A'
                              AND ac.con_cat = 'M'
                              AND (ac.contract_number LIKE 'AC%' or ac.contract_number LIKE 'OCT%')
                              AND ac.acnt_contract__oid IS NOT NULL
                 INNER JOIN device_stat ds ON ac.id = ds.acnt_contract__oid
                              AND ds.request_category = 'P'
                              AND ds.resp_code = 0
                              AND ds.trans_type = 1145
                              AND ds.posting_date >= v_OCT_dt
                 INNER JOIN device_stat_doc dsd ON ds.id = dsd.device_stat__oid
                 WHERE mac.amnd_state = 'A'
                   AND mac.contract_number = i.contract_number);
      log('I','5 # подсчет OCT(А2С): '||(v_a2c_tr)||'; Date: '||v_OCT_dt);

/***************************
  #подсчет суммы лимита
***************************/
      log('6. рассчитывается [сумма устанавливаемого ограничителя] = (сумма остатков на трёх корсчетах, приведённая к рублям) - (сумма неотражённых на корсчёте в USD транзакций ОСТ) - (сумма неотражённых на корсчёте в EUR транзакций ОСТ) - (сумма неотражённых на корсчёте в RUR транзакций ОСТ) + (сумма неотражённых на корсчёте в RUR транзакций AFT)');
      v_sum_c2a :=nvl(v_c2a_rate, 0.9 )*v_c2a_tr ;
      v_sum_a2c :=nvl(v_a2c_rate, 1.03)*v_a2c_tr ;
      log('Сумма AFT= '||         (v_c2a_tr)||'*'||v_c2a_rate);
      log('Сумма OCT= '||         (v_a2c_tr)||'*'||v_a2c_rate);
      log('Справочно AFT/OCT: '|| (v_sum_c2a)||'/'||(v_sum_a2c));
      log('Справочно Остаток GL: '||(v_all_acc_amnt));
      if (v_account_amounts!=0) then
         log('Справочно Остаток по валютным счетам: '|| (v_account_amounts));
      end if;
      v_new_limit :=v(v_all_acc_amnt) + v(v_sum_c2a) - v(v_sum_a2c)+v(v_account_amounts);
      
      log('6 # Итого: Совокупный лимит = '|| (v_new_limit));
      --ows.sy_process.PROCESS_END;
      commit;
      return v_new_limit;
    



  app_n:=app_n+1;
end loop;
return null;
exception
  when others then
    ows.stnd.PROCESS_MESSAGE('E',sqlerrm||' '||chr(13)||dbms_utility.format_error_backtrace);
    ows.stnd.PROCESS_REJECT();
return null; 
END GET_USG;


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
  
  n_limit_bfko := PROC.ROBOT_LIMITER_UTILS.GET_USG(contract_number);
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