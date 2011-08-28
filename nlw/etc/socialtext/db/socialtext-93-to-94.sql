BEGIN;

-- The contents of this file come from
-- /usr/share/postgresql/8.1/contrib/_int.sql
-- Which is included in the postgresql-contrib-8.1 ubuntu package

--
-- Create the user-defined type for the 1-D integer arrays (_int4)
--

-- Adjust this setting to control where the operators, functions, and
-- opclasses get created.
SET search_path = public;

-- Query type
CREATE FUNCTION bqarr_in(cstring)
RETURNS query_int
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

CREATE FUNCTION bqarr_out(query_int)
RETURNS cstring
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

CREATE TYPE query_int (
	INTERNALLENGTH = -1,
	INPUT = bqarr_in,
	OUTPUT = bqarr_out
);

--only for debug
CREATE FUNCTION querytree(query_int)
RETURNS text
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);


CREATE FUNCTION boolop(_int4, query_int)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

COMMENT ON FUNCTION boolop(_int4, query_int) IS 'boolean operation with array';

CREATE FUNCTION rboolop(query_int, _int4)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

COMMENT ON FUNCTION rboolop(query_int, _int4) IS 'boolean operation with array';

CREATE OPERATOR @@ (
	LEFTARG = _int4,
	RIGHTARG = query_int,
	PROCEDURE = boolop,
	COMMUTATOR = '~~',
	RESTRICT = contsel,
	JOIN = contjoinsel
);

CREATE OPERATOR ~~ (
	LEFTARG = query_int,
	RIGHTARG = _int4,
	PROCEDURE = rboolop,
	COMMUTATOR = '@@',
	RESTRICT = contsel,
	JOIN = contjoinsel
);


--
-- External C-functions for R-tree methods
--

-- Comparison methods

CREATE FUNCTION _int_contains(_int4, _int4)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

COMMENT ON FUNCTION _int_contains(_int4, _int4) IS 'contains';

CREATE FUNCTION _int_contained(_int4, _int4)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

COMMENT ON FUNCTION _int_contained(_int4, _int4) IS 'contained in';

CREATE FUNCTION _int_overlap(_int4, _int4)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

COMMENT ON FUNCTION _int_overlap(_int4, _int4) IS 'overlaps';

CREATE FUNCTION _int_same(_int4, _int4)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

COMMENT ON FUNCTION _int_same(_int4, _int4) IS 'same as';

CREATE FUNCTION _int_different(_int4, _int4)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

COMMENT ON FUNCTION _int_different(_int4, _int4) IS 'different';

-- support routines for indexing

CREATE FUNCTION _int_union(_int4, _int4)
RETURNS _int4
AS '$libdir/_int' LANGUAGE 'C' WITH (isstrict);

CREATE FUNCTION _int_inter(_int4, _int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

--
-- OPERATORS
--

CREATE OPERATOR && (
	LEFTARG = _int4,
	RIGHTARG = _int4,
	PROCEDURE = _int_overlap,
	COMMUTATOR = '&&',
	RESTRICT = contsel,
	JOIN = contjoinsel
);

--CREATE OPERATOR = (
--	LEFTARG = _int4,
--	RIGHTARG = _int4,
--	PROCEDURE = _int_same,
--	COMMUTATOR = '=',
--	NEGATOR = '<>',
--	RESTRICT = eqsel,
--	JOIN = eqjoinsel,
--	SORT1 = '<',
--	SORT2 = '<'
--);

--CREATE OPERATOR <> (
--	LEFTARG = _int4,
--	RIGHTARG = _int4,
--	PROCEDURE = _int_different,
--	COMMUTATOR = '<>',
--	NEGATOR = '=',
--	RESTRICT = neqsel,
--	JOIN = neqjoinsel
--);

CREATE OPERATOR @ (
	LEFTARG = _int4,
	RIGHTARG = _int4,
	PROCEDURE = _int_contains,
	COMMUTATOR = '~',
	RESTRICT = contsel,
	JOIN = contjoinsel
);

CREATE OPERATOR ~ (
	LEFTARG = _int4,
	RIGHTARG = _int4,
	PROCEDURE = _int_contained,
	COMMUTATOR = '@',
	RESTRICT = contsel,
	JOIN = contjoinsel
);

--------------
CREATE FUNCTION intset(int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION icount(_int4)
RETURNS int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE OPERATOR # (
	RIGHTARG = _int4,
	PROCEDURE = icount
);

CREATE FUNCTION sort(_int4, text)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION sort(_int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION sort_asc(_int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION sort_desc(_int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION uniq(_int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION idx(_int4, int4)
RETURNS int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE OPERATOR # (
	LEFTARG = _int4,
	RIGHTARG = int4,
	PROCEDURE = idx
);

CREATE FUNCTION subarray(_int4, int4, int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION subarray(_int4, int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE FUNCTION intarray_push_elem(_int4, int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE OPERATOR + (
	LEFTARG = _int4,
	RIGHTARG = int4,
	PROCEDURE = intarray_push_elem
);

CREATE FUNCTION intarray_push_array(_int4, _int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE OPERATOR + (
	LEFTARG = _int4,
	RIGHTARG = _int4,
	COMMUTATOR = +,
	PROCEDURE = intarray_push_array
);

CREATE FUNCTION intarray_del_elem(_int4, int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE OPERATOR - (
	LEFTARG = _int4,
	RIGHTARG = int4,
	PROCEDURE = intarray_del_elem
);

CREATE FUNCTION intset_union_elem(_int4, int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE OPERATOR | (
	LEFTARG = _int4,
	RIGHTARG = int4,
	PROCEDURE = intset_union_elem
);

CREATE OPERATOR | (
	LEFTARG = _int4,
	RIGHTARG = _int4,
	COMMUTATOR = |,
	PROCEDURE = _int_union
);

CREATE FUNCTION intset_subtract(_int4, _int4)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C' WITH (isStrict, isCachable);

CREATE OPERATOR - (
	LEFTARG = _int4,
	RIGHTARG = _int4,
	PROCEDURE = intset_subtract
);

CREATE OPERATOR & (
	LEFTARG = _int4,
	RIGHTARG = _int4,
	COMMUTATOR = &,
	PROCEDURE = _int_inter
);
--------------

-- define the GiST support methods
CREATE FUNCTION g_int_consistent(internal,_int4,int4)
RETURNS bool
AS '$libdir/_int'
LANGUAGE 'C';

CREATE FUNCTION g_int_compress(internal)
RETURNS internal
AS '$libdir/_int'
LANGUAGE 'C';

CREATE FUNCTION g_int_decompress(internal)
RETURNS internal
AS '$libdir/_int'
LANGUAGE 'C';

CREATE FUNCTION g_int_penalty(internal,internal,internal)
RETURNS internal
AS '$libdir/_int'
LANGUAGE 'C' WITH (isstrict);

CREATE FUNCTION g_int_picksplit(internal, internal)
RETURNS internal
AS '$libdir/_int'
LANGUAGE 'C';

CREATE FUNCTION g_int_union(internal, internal)
RETURNS _int4
AS '$libdir/_int'
LANGUAGE 'C';

CREATE FUNCTION g_int_same(_int4, _int4, internal)
RETURNS internal
AS '$libdir/_int'
LANGUAGE 'C';


-- Create the operator class for indexing

CREATE OPERATOR CLASS gist__int_ops
DEFAULT FOR TYPE _int4 USING gist AS
	OPERATOR	3	&&,
	OPERATOR	6	= (anyarray, anyarray)	RECHECK,
	OPERATOR	7	@,
	OPERATOR	8	~,
	OPERATOR	20	@@ (_int4, query_int),
	FUNCTION	1	g_int_consistent (internal, _int4, int4),
	FUNCTION	2	g_int_union (internal, internal),
	FUNCTION	3	g_int_compress (internal),
	FUNCTION	4	g_int_decompress (internal),
	FUNCTION	5	g_int_penalty (internal, internal, internal),
	FUNCTION	6	g_int_picksplit (internal, internal),
	FUNCTION	7	g_int_same (_int4, _int4, internal);

UPDATE "System"
   SET value = '94'
 WHERE field = 'socialtext-schema-version';

COMMIT;
