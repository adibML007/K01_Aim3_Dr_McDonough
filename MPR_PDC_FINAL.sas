%MACRO MEDAD(lib=, datain=, dataout=, id=, filldt=, daysup=,
class=, ibendt=., fp=., type=, decpct=2, debug=N);
%let debug=%upcase(&debug);
%if (&debug=Y) %then %do;
options mprint mtrace macrogen notes linesize=132 ps=58; %end;
%else %do;
options nonotes nomprint nomacrogen nomtrace nosymbolgen nomlogic
linesize=132 ps=58; %end;
%if %sysfunc(exist(&lib..&datain.))=0 %then %do;
%put ERROR: DATA SET &datain. DOES NOT EXIST.;
%put ERROR- MACRO WILL TERMINATE NOW.;
%return;
%end;
%if (&decpct=4) %then %let decpct=0.0001;
%if (&decpct=3) %then %let decpct=0.001;
%if (&decpct=2) %then %let decpct=0.01;
%if (&decpct=1) %then %let decpct=0.1;
%if (&decpct=) %then %let decpct=1;
/***Step 1***/
/***Remove duplicate dispense record***/
PROC SORT DATA=&lib..&datain. nodupkey out=&datain._dedup; BY &id. &class.
&filldt.; RUN;
/***Identify first dispense record and last dispense record***/
PROC SQL;
CREATE TABLE RXCLM
AS SELECT &ID., &FILLDT., &CLASS.,
MIN(&FILLDT.) AS INDEX_DT,
MAX(&FILLDT.) AS LSTRX_DT,
&DAYSUP.,&IBENDT. AS IB_END
FROM &DATAIN._DEDUP
GROUP BY &ID., &CLASS.
ORDER BY &ID., &CLASS., &FILLDT.;
QUIT;
/***Step 2***/
/**Create a dataset that contains case with one dispense record only**/
DATA ONERX RXCLM1;
SET RXCLM END=EOF1;
BY &ID. &CLASS.;
IF FIRST.&CLASS. AND LAST.&CLASS. THEN OUTPUT ONERX;
ELSE OUTPUT RXCLM1;
RUN;
/***Step 3***/
/**Create end date for each dispense record and for the end of study period**/
DATA MAXEND;
SET RXCLM1;
FILL_END_DT = &FILLDT. +&DAYSUP. - 1 ;
END_DT=MAX(OF IB_END FILL_END_DT);
FORMAT END_DT IB_END;
RUN;
/***Step 4***/
/**Create macro for the earliest start date and latest end date**/
PROC SQL;
SELECT MIN(INDEX_DT), MAX(END_DT)
INTO :START, :TERM
FROM MAXEND;
QUIT;
/**Create dummy var to represent days in study period and flag dummy as 1
if it has drug avaiable**/
DATA AD_1;
ARRAY FLAG(&START. :&TERM. );
SET MAXEND;
BY &ID. &CLASS.;
DO I= &START. to &TERM.;
FLAG(I)=0;
END;
/* move through the days covered */
DO U=&FILLDT. to FILL_END_DT;
FLAG(U)=1;
END;
DROP I U;
RUN;
/***Step 5***/
%LET INTRL= %EVAL(&TERM. - &START. +1);
%PUT &INTRL;
/***Step 6***/
/***Summarize the flagged days in the last record of each class***/
DATA AD_2;
DO UNTIL (LAST.&CLASS.);
SET AD_1;
BY &ID. &CLASS.;
ARRAY FLAG(&INTRL.) FLAG1-FLAG&INTRL.;
ARRAY SUMFLAG(&INTRL.);
DO I=1 TO &INTRL.;
SUMFLAG(I) = SUM(SUMFLAG(I), FLAG(I));
END;
END;
%IF %UPCASE(&TYPE)=PDC %THEN %DO;
DO U=1 TO &INTRL.;
IF SUMFLAG(U) GE 1 THEN SUMFLAG(U)=1; ELSE SUMFLAG(U)=0;
END;
%END;
DROP I FLAG:;
RUN;
/***Step 7***/
/**Adjust the end date based off the types of measurements***/
DATA &DATAOUT.;
SET AD_2;
ARRAY TAT(&INTRL.) SUMFLAG1 - SUMFLAG&INTRL.;
*--Interval based metric;
IF IB_END =. THEN &TYPE._1=.;
ELSE DO;
NUM1=0;
ARRAYEND=IB_END - &START. + 1;
DO H=1 TO ARRAYEND;
NUM1= TAT(H)+ NUM1;
END;
DENO1= IB_END - INDEX_DT +1;
&TYPE._1 = ROUND(MIN((NUM1/DENO1),1), &decpct.);
END;
/**Rx based including last refill**/
NUM2= SUM(OF SUMFLAG1-SUMFLAG&INTRL.);
DENO2=FILL_END_DT - INDEX_DT +1;
&TYPE._2 = ROUND(MIN((NUM2 /DENO2),1), &decpct.);
/**Rx based excluding last refill**/
NUM3= SUM(OF SUMFLAG1-SUMFLAG&INTRL.) - (&DAYSUP.);
DENO3= &FILLDT. - INDEX_DT;
&TYPE._3 = ROUND(MIN((NUM3 /DENO3),1), &decpct.);
KEEP &ID. &CLASS. &TYPE.: ;
FORMAT FILL_END_DT;
RUN;
%MEND;

%MEDAD(lib=mylib, datain=FM_1, dataout=FM_PDC, id=ID, filldt=D_START, daysup=DISPENSE_AMT,
class=DRUG_ID, ibendt=END, fp=., type=PDC, decpct=2, debug=N);
