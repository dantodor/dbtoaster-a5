CREATE SEQUENCE pip_var_id;

--------------- VARIABLE PREDECLARATIONS ---------------
CREATE TYPE pip_var;
CREATE TYPE pip_atom;
CREATE TYPE pip_sample_set;
CREATE TYPE pip_conf_tally;
CREATE TYPE pip_value_bundle;
CREATE TYPE pip_world_presence;
CREATE TYPE pip_eqn;
CREATE TYPE pip_expectation;

--------------- pip_var FUNCTIONS ---------------
CREATE FUNCTION pip_var_in(cstring)                        RETURNS pip_var          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_var_in'          LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_var_out(pip_var)                       RETURNS cstring          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_var_out'         LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION create_variable(cstring, integer, cstring) RETURNS pip_eqn          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_var_create_str'  LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION create_variable(cstring, integer, record)  RETURNS pip_eqn          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_var_create_row'  LANGUAGE C VOLATILE  STRICT;

--------------- pip_eqn FUNCTIONS ---------------
CREATE FUNCTION pip_eqn_in(cstring)                                RETURNS pip_eqn          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_in'          LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_out(pip_eqn)                               RETURNS cstring          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_out'         LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION expectation(pip_eqn, record)                       RETURNS double precision AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_expectation'       LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION expectation(pip_eqn, record, integer)              RETURNS double precision AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_expectation'       LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION expectation_max_g(pip_sample_set, pip_eqn, record) RETURNS pip_sample_set   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_expectation_max_g' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION expectation_sum_g(pip_sample_set, pip_eqn, record) RETURNS pip_sample_set   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_expectation_sum_g' LANGUAGE C VOLATILE  STRICT;

CREATE FUNCTION pip_eqn_sum(pip_eqn,pip_eqn)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sum_ee' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sum(pip_eqn,integer)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sum_ei' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sum(integer,pip_eqn)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sum_ie' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sum(pip_eqn,double precision) RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sum_ef' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sum(double precision,pip_eqn) RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sum_fe' LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION pip_eqn_mul(pip_eqn,pip_eqn)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_mul_ee' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_mul(pip_eqn,integer)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_mul_ei' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_mul(integer,pip_eqn)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_mul_ie' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_mul(pip_eqn,double precision) RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_mul_ef' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_mul(double precision,pip_eqn) RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_mul_fe' LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION pip_eqn_neg(pip_eqn)                  RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_neg' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sub(pip_eqn,pip_eqn)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sub_ee' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sub(pip_eqn,integer)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sub_ei' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sub(integer,pip_eqn)          RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sub_ie' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sub(pip_eqn,double precision) RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sub_ef' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_eqn_sub(double precision,pip_eqn) RETURNS pip_eqn AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_eqn_sub_fe' LANGUAGE C IMMUTABLE STRICT;

--------------- pip_expectation FUNCTIONS ---------------
-- Expectation is a semantic sugar hack to cheat the parser...
-- Consequently the IO operations here are identical to those for pip_eqn
CREATE FUNCTION pip_expectation_in(cstring)                 RETURNS pip_expectation  AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_exp_in'     LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_expectation_out(pip_expectation)        RETURNS cstring          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_exp_out'    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_expectation_make(pip_eqn)               RETURNS pip_expectation  AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_exp_make'   LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_expectation_fix(pip_expectation,record) RETURNS pip_expectation  AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_exp_fix'    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_expectation_expect(pip_expectation)     RETURNS double precision AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_exp_expect' LANGUAGE C IMMUTABLE STRICT;

--------------- pip_atom FUNCTIONS ---------------
CREATE FUNCTION pip_atom_in(cstring)                         RETURNS pip_atom AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_in'           LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_atom_out(pip_atom)                       RETURNS cstring  AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_out'          LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_atom_create_gt(pip_eqn,pip_eqn)          RETURNS pip_atom AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_create_gt_ee' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_atom_create_gt(pip_eqn,double precision) RETURNS pip_atom AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_create_gt_ef' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_atom_create_gt(double precision,pip_eqn) RETURNS pip_atom AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_create_gt_fe' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_atom_create_lt(pip_eqn,pip_eqn)          RETURNS pip_atom AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_create_lt_ee' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_atom_create_lt(pip_eqn,double precision) RETURNS pip_atom AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_create_lt_ef' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_atom_create_lt(double precision,pip_eqn) RETURNS pip_atom AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_create_lt_fe' LANGUAGE C VOLATILE  STRICT;

--------------- pip_sample_set FUNCTIONS ---------------
CREATE FUNCTION pip_sample_set_in(cstring)              RETURNS pip_sample_set          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_sample_set_in'       LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_sample_set_out(pip_sample_set)      RETURNS cstring                 AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_sample_set_out'      LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_sample_set_generate(record,integer) RETURNS pip_sample_set          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_sample_set_generate' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_sample_set_explode(pip_sample_set)  RETURNS SETOF double precision AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_sample_set_explode'   LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_sample_set_expect(pip_sample_set)   RETURNS double precision        AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_sample_set_expect'   LANGUAGE C IMMUTABLE STRICT;

--------------- INTEGRATION FUNCTIONS ---------------
CREATE FUNCTION conf_one      (record)                                   RETURNS double precision   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','conf_one'                     LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION conf_sample_g (pip_conf_tally,record,pip_sample_set)     RETURNS pip_conf_tally     AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_conf_sample_g'       LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION conf_naive_g  (pip_world_presence,record,pip_sample_set) RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_atom_sample_set_presence' LANGUAGE C IMMUTABLE STRICT;

--------------- pip_conf_tally FUNCTIONS ---------------
CREATE FUNCTION pip_conf_tally_in(cstring)            RETURNS pip_conf_tally   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_conf_tally_in'     LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_conf_tally_out(pip_conf_tally)    RETURNS cstring          AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_conf_tally_out'    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_conf_tally_result(pip_conf_tally) RETURNS double precision AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_conf_tally_result' LANGUAGE C IMMUTABLE STRICT;

--------------- pip_world_presence FUNCTIONS ---------------
CREATE FUNCTION pip_world_presence_in(cstring)                                  RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_world_presence_in'     LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_world_presence_out(pip_world_presence)                      RETURNS cstring            AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_world_presence_out'    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_world_presence_create(integer)                              RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_world_presence_create' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_world_presence_count(pip_world_presence)                    RETURNS double precision   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_world_presence_count'  LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_world_presence_union(pip_world_presence,pip_world_presence) RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_world_presence_union'  LANGUAGE C IMMUTABLE STRICT;

--------------- pip_value_bundle FUNCTIONS ---------------
CREATE FUNCTION pip_value_bundle_in(cstring)                                               RETURNS pip_value_bundle   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_in'     LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_out(pip_value_bundle)                                     RETURNS cstring            AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_out'    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_create(pip_eqn,integer)                                   RETURNS pip_value_bundle   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_create' LANGUAGE C VOLATILE  STRICT;
CREATE FUNCTION pip_value_bundle_cmp(pip_world_presence,integer,pip_value_bundle)          RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_cmp_iv' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_cmp(pip_world_presence,double precision,pip_value_bundle) RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_cmp_fv' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_cmp(pip_world_presence,pip_value_bundle,integer)          RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_cmp_vi' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_cmp(pip_world_presence,pip_value_bundle,double precision) RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_cmp_vf' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_cmp(pip_world_presence,pip_value_bundle,pip_value_bundle) RETURNS pip_world_presence AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_cmp_vv' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_add(pip_value_bundle,double precision)                    RETURNS pip_value_bundle   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_add_vf' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_add(pip_value_bundle,pip_value_bundle)                    RETURNS pip_value_bundle   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_add_vv' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_mul(pip_value_bundle,double precision)                    RETURNS pip_value_bundle   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_mul_vf' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_mul(pip_value_bundle,pip_value_bundle)                    RETURNS pip_value_bundle   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_mul_vv' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_max(pip_value_bundle,pip_value_bundle)                    RETURNS pip_value_bundle   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_max'    LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_expect(pip_value_bundle)                                  RETURNS double precision   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_expect' LANGUAGE C IMMUTABLE STRICT;
CREATE FUNCTION pip_value_bundle_expect(pip_value_bundle,pip_world_presence)               RETURNS double precision   AS '/Users/xthemage/Documents/CornellDB/maybms/pip/pip_plugin/libpip','pip_value_bundle_expect' LANGUAGE C IMMUTABLE STRICT;


--------------- VARIABLE DEFINITIONS ---------------
CREATE TYPE pip_var (
  INPUT =  pip_var_in,
  OUTPUT = pip_var_out,
  STORAGE = external
);
CREATE TYPE pip_atom (
  INPUT =  pip_atom_in,
  OUTPUT = pip_atom_out,
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  STORAGE = external
);
CREATE TYPE pip_sample_set (
  INPUT =  pip_sample_set_in,
  OUTPUT = pip_sample_set_out,
  STORAGE = external
);
CREATE TYPE pip_conf_tally (
  INPUT =  pip_conf_tally_in,
  OUTPUT = pip_conf_tally_out,
  STORAGE = external
);
CREATE TYPE pip_value_bundle (
  INPUT =  pip_value_bundle_in,
  OUTPUT = pip_value_bundle_out,
  STORAGE = external
);
CREATE TYPE pip_world_presence ( 
  INPUT =  pip_world_presence_in,
  OUTPUT = pip_world_presence_out,
  STORAGE = external
);
CREATE TYPE pip_eqn (
  INPUT =  pip_eqn_in,
  OUTPUT = pip_eqn_out,
  STORAGE = external
);
CREATE TYPE pip_expectation (
  INPUT = pip_expectation_in,
  OUTPUT = pip_expectation_out,
  STORAGE = external
);

--------------- AGGREGATE FUNCTIONS ---------------
CREATE AGGREGATE expectation_max (pip_eqn, record) 
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = expectation_max_g,
  stype = pip_sample_set,
  finalfunc = pip_sample_set_expect,
  initcond = '?1000/1'
);
CREATE AGGREGATE expectation_max_hist (pip_eqn, record) 
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = expectation_max_g,
  stype = pip_sample_set,
  initcond = '?1000/1'
);

CREATE AGGREGATE expectation_sum (pip_eqn, record) 
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = expectation_sum_g,
  stype = pip_sample_set,
  finalfunc = pip_sample_set_expect,
  initcond = '?1000/1'
);
CREATE AGGREGATE expectation_sum_hist (pip_eqn, record) 
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = expectation_sum_g,
  stype = pip_sample_set,
  initcond = '?1000/1'
);

CREATE AGGREGATE conf_sample (record,pip_sample_set)
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = conf_sample_g,
  stype = pip_conf_tally,
  finalfunc = pip_conf_tally_result,
  initcond = '0:0'
);

CREATE AGGREGATE pip_world_presence_union (pip_world_presence)
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = pip_world_presence_union,
  stype = pip_world_presence
);

CREATE AGGREGATE conf_naive (record,pip_sample_set)
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = conf_naive_g,
  stype = pip_world_presence,
  finalfunc = pip_world_presence_count,
  initcond = '?0'
);
CREATE AGGREGATE expectation_max (pip_value_bundle) 
(
  CONSTRAINTTYPE,  --HACKED_SQL_ONLY
  sfunc = pip_value_bundle_max,
  stype = pip_value_bundle,
  finalfunc = pip_value_bundle_expect
);


--------------- FUNCTIONS IN SQL ---------------
CREATE FUNCTION create_variable(varchar, anyelement)       RETURNS pip_eqn AS $$
  SELECT create_variable(cast($1 as cstring), cast(nextval('pip_var_id') as integer), $2);
  $$ LANGUAGE SQL VOLATILE STRICT;

--------------- VARIABLE OPERATORS ---------------
CREATE OPERATOR + (  PROCEDURE=pip_eqn_sum,  LEFTARG=pip_eqn         ,  RIGHTARG=pip_eqn           );
CREATE OPERATOR + (  PROCEDURE=pip_eqn_sum,  LEFTARG=integer         ,  RIGHTARG=pip_eqn           );
CREATE OPERATOR + (  PROCEDURE=pip_eqn_sum,  LEFTARG=pip_eqn         ,  RIGHTARG=integer           );
CREATE OPERATOR + (  PROCEDURE=pip_eqn_sum,  LEFTARG=double precision,  RIGHTARG=pip_eqn           );
CREATE OPERATOR + (  PROCEDURE=pip_eqn_sum,  LEFTARG=pip_eqn         ,  RIGHTARG=double precision  );

CREATE OPERATOR * (  PROCEDURE=pip_eqn_mul,  LEFTARG=pip_eqn         ,  RIGHTARG=pip_eqn           );
CREATE OPERATOR * (  PROCEDURE=pip_eqn_mul,  LEFTARG=integer         ,  RIGHTARG=pip_eqn           );
CREATE OPERATOR * (  PROCEDURE=pip_eqn_mul,  LEFTARG=pip_eqn         ,  RIGHTARG=integer           );
CREATE OPERATOR * (  PROCEDURE=pip_eqn_mul,  LEFTARG=double precision,  RIGHTARG=pip_eqn           );
CREATE OPERATOR * (  PROCEDURE=pip_eqn_mul,  LEFTARG=pip_eqn         ,  RIGHTARG=double precision  );

CREATE OPERATOR | (  PROCEDURE=pip_world_presence_union,  LEFTARG=pip_world_presence,  RIGHTARG=pip_world_presence  );

CREATE OPERATOR > (  PROCEDURE=pip_atom_create_gt,  LEFTARG=pip_eqn,           RIGHTARG=pip_eqn            );
CREATE OPERATOR > (  PROCEDURE=pip_atom_create_gt,  LEFTARG=double precision,  RIGHTARG=pip_eqn            );
CREATE OPERATOR > (  PROCEDURE=pip_atom_create_gt,  LEFTARG=pip_eqn,           RIGHTARG=double precision   );
CREATE OPERATOR < (  PROCEDURE=pip_atom_create_lt,  LEFTARG=pip_eqn,           RIGHTARG=pip_eqn            );
CREATE OPERATOR < (  PROCEDURE=pip_atom_create_lt,  LEFTARG=pip_eqn,           RIGHTARG=double precision   );
CREATE OPERATOR < (  PROCEDURE=pip_atom_create_lt,  LEFTARG=double precision,  RIGHTARG=pip_eqn            );

--------------- SEMANTIC SUGAR OPERATORS ---------------
CREATE OPERATOR << (  PROCEDURE=pip_expectation_make,                              RIGHTARG=pip_eqn   );
CREATE OPERATOR @ (  PROCEDURE=pip_expectation_fix,     LEFTARG=pip_expectation,  RIGHTARG=record    );
CREATE OPERATOR >> (  PROCEDURE=pip_expectation_expect,  LEFTARG=pip_expectation                      );

