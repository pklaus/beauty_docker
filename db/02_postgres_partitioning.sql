-- Provided by Martin Konrad, TU Darmstadt

-- The sample table can grow very fast if you archive a lot of data and with the
-- table size the index size also grows. This results in poor performance if the
-- index doesn't fit into main memory anymore. One way out of this partitioning
-- of the sample table. PostgreSQL supports partitioning but it's not as easy to
-- setup as on an Oracle DB.
-- Use the SQL statements in this file to setup partitioning on the sample
-- table. The function provided below automatically creates the necessary
-- sub-tables. Run this function regularly to generate new tables as time moves
-- on.
-- Note: Make sure
-- SHOW constraint_exclusion;
-- returns "partition" otherwise your DB server will waste time scanning
-- sub-tables that do not contain relevant data. Constraint exclusion is enabled
-- for partitioned tables by default in PostgreSQL 8.4 and later.

-- We only create the master table explicitly. The sub-tables are created by the
-- function below as they are needed.

\connect archive

DROP TABLE IF EXISTS archive.sample;
CREATE TABLE archive.sample
(
   channel_id BIGINT NOT NULL,
   smpl_time TIMESTAMP NOT NULL,
   nanosecs BIGINT  NOT NULL,
   severity_id BIGINT NOT NULL,
   status_id BIGINT  NOT NULL,
   num_val INT NULL,
   float_val REAL NULL,
   str_val VARCHAR(120) NULL,
   datatype CHAR(1) NULL DEFAULT ' ',
   array_val BYTEA  NULL
);

-- This maintenance function automatically creates partitions according to the
-- specified interval (e.g. weekly or monthly). The first partition starts at
-- <begin_time> and ends a day/week/month/year later. This function has to be
-- called regularly (e.g. daily by cron):
--
--   0 * *   *   *   postgres psql -d mydb -c "SELECT public.update_partitions('2012-06-01'::timestamp, 'archive', 'table_owner', 'week');"
--
-- This function is based on a more generic version by Nicholas Whittier
-- (http://imperialwicket.com/postgresql-automating-monthly-table-partitions).
CREATE OR REPLACE FUNCTION archive.sample_update_partitions(begin_time timestamp without time zone, schema_name text, table_owner text, plan text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare startTime timestamp;
declare endTime timestamp;
declare intervalTime timestamp;
declare createStmts text;
declare createTrigger text;
declare fullTablename text;
declare triggerName text;
declare createdTables integer;
declare dateFormat text;
declare planInterval interval;

BEGIN
dateFormat:=CASE WHEN plan='month' THEN 'YYYYMM'
                 WHEN plan='week' THEN 'IYYYIW'
                 WHEN plan='day' THEN 'YYYYDDD'
                 WHEN plan='year' THEN 'YYYY'
                 ELSE 'error'
            END;
IF dateFormat='error' THEN
  RAISE EXCEPTION 'Invalid plan --> %', plan;
END IF;
-- Store the incoming begin_time, and set the endTime to one month/week/day in the future
-- (this allows use of a cronjob at any time during the month/week/day to generate next month/week/day's table)
startTime:=(date_trunc(plan,begin_time));
planInterval:=('1 '||plan)::interval;
endTime:=(date_trunc(plan,(current_timestamp + planInterval)));
createdTables:=0;

-- Begin creating the trigger function, we're going to generate it backwards.
createTrigger:='
ELSE
RAISE EXCEPTION ''Error in '||schema_name||'.sample_insert_trigger_function(): smpl_time out of range'';
END IF;
RETURN NULL;
END;
$$
LANGUAGE plpgsql;';
            
while (startTime <= endTime) loop

   fullTablename:='sample_'||to_char(startTime, dateFormat);
   intervalTime:= startTime + planInterval;
   
   -- The table creation sql statement
   if not exists(select * from information_schema.tables where table_schema = schema_name AND table_name = fullTablename) then
     createStmts:='CREATE TABLE '||schema_name||'.'||fullTablename||' (CHECK (smpl_time >= '''||startTime||''' AND smpl_time < '''||intervalTime||''')) INHERITS ('||schema_name||'.sample)';

     -- Run the table creation
     EXECUTE createStmts;

     -- Set the table owner
     createStmts :='ALTER TABLE '||schema_name||'.'||fullTablename||' OWNER TO "'||table_owner||'";';
     EXECUTE createStmts;
     
     -- Create an index on the timestamp
     createStmts:='CREATE INDEX '||fullTablename||'_channel_time_pkey ON '||schema_name||'.'||fullTablename||' (channel_id, smpl_time, nanosecs);';
     EXECUTE createStmts;

     -- Create foreign key on column channel_id
     createStmts:='ALTER TABLE '||schema_name||'.'||fullTablename||' ADD constraint sample_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES '||schema_name||'.channel(channel_id) ON DELETE CASCADE;';
     EXECUTE createStmts;
     
     -- Create foreign key on column severity
     createStmts:='ALTER TABLE '||schema_name||'.'||fullTablename||' ADD constraint sample_severity_fkey FOREIGN KEY (severity_id) REFERENCES '||schema_name||'.severity(severity_id) ON DELETE CASCADE;';
     EXECUTE createStmts;

     -- Create foreign key on column status
     createStmts:='ALTER TABLE '||schema_name||'.'||fullTablename||' ADD constraint sample_status_id_fkey FOREIGN KEY (status_id) REFERENCES '||schema_name||'.status(status_id) ON DELETE CASCADE;';
     EXECUTE createStmts;

     -- Track how many tables we are creating (should likely be 1, except for initial run and backfilling efforts).
     createdTables:=createdTables+1;
   end if;
   
   -- Add case for this table to trigger creation sql statement.
   createTrigger:='( NEW.smpl_time >= TIMESTAMP '''||startTime||''' AND NEW.smpl_time < TIMESTAMP '''||intervalTime||''' ) THEN INSERT INTO '||schema_name||'.'||fullTablename||' VALUES (NEW.*); '||createTrigger;
   
   startTime:=intervalTime;
   
   if (startTime <= endTime)
   then
      createTrigger:='
ELSEIF '||createTrigger;
   end if;
   
end loop;

-- Finish creating the trigger function (at the beginning).
createTrigger:='CREATE OR REPLACE FUNCTION '||schema_name||'.sample_insert_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
IF '||createTrigger;

-- Run the trigger replacement;
EXECUTE createTrigger;

-- Create the trigger that uses the trigger function, if it isn't already created
triggerName:='sample_insert_trigger';
if not exists(select * from information_schema.triggers where trigger_name = triggerName) then
  createTrigger:='CREATE TRIGGER sample_insert_trigger BEFORE INSERT ON '||schema_name||'.sample FOR EACH ROW EXECUTE PROCEDURE '||schema_name||'.sample_insert_trigger_function();';
  EXECUTE createTrigger;
END if;
return createdTables;
END;
$function$;


GRANT SELECT, INSERT, UPDATE, DELETE ON sample TO archive;
GRANT SELECT ON sample TO report;
-- GRANT SELECT ON ALL TABLES IN SCHEMA archive TO report;

ALTER TABLE sample OWNER TO archive;

ALTER FUNCTION archive.sample_update_partitions(timestamp without time zone, text, text, text) OWNER TO archive;

commit;
