import strutils
import sequtils
import options
import macros
import sugar

import ndb/sqlite
export sqlite

import private/sqlite/[dbtypes, rowutils]
import private/dot
import model
import pragmas


type
  RollbackError* = object of CatchableError
    ##[ Raised when transaction is manually rollbacked.

    Do not raise manually, use `rollback <#rollback>`_ proc.
    ]##


using dbConn: DbConn


# Table manupulation

proc dropTables*[T: Model](dbConn; obj: T) =
  ## Drop tables for `Model <model.html#Model>`_ and its `Model`_ fields.

  for fld, val in obj.fieldPairs:
    when val is Model:
      dbConn.dropTables(val)

  let qry = "DROP TABLE IF EXISTS $#" % T.table

  dbConn.exec(sql qry)

proc createTables*[T: Model](dbConn; obj: T, force = false) =
  ##[ Create tables for `Model`_ and its `Model`_ fields.

  If ``force`` is ``true``, drop the table before creation.
  ]##

  if force:
    dbConn.dropTables(obj)

  for fld, val in obj.fieldPairs:
    when val is Model:
      dbConn.createTables(val, force = force)

  var colGroups, fkGroups: seq[string]

  for fld, val in obj.fieldPairs:
    var colShmParts: seq[string]

    colShmParts.add obj.col(fld)

    colShmParts.add typeof(val).dbType

    when val isnot Option:
      colShmParts.add "NOT NULL"

    when obj.dot(fld).hasCustomPragma(pk):
      colShmParts.add "PRIMARY KEY"

    when val is Model:
      fkGroups.add "FOREIGN KEY($#) REFERENCES $#($#)" % [obj.col(fld), typeof(val).table, val.col("id")]

    colGroups.add colShmParts.join(" ")

  let qry = "CREATE TABLE $#($#)" % [T.table, (colGroups & fkGroups).join(", ")]

  dbConn.exec(sql qry)


# Row manupulation

proc insert*[T: Model](dbConn; obj: var T) =
  ## Insert rows for `Model`_ instance and its `Model`_ fields, updating their ``id`` fields.

  for fld, val in obj.fieldPairs:
    when val is Model:
      dbConn.insert(val)

  let
    row = obj.toRow()
    phds = "?".repeat(row.len)
    qry = "INSERT INTO $# ($#) VALUES($#)" % [T.table, obj.cols.join(", "), phds.join(", ")]

  obj.id = dbConn.insertID(sql qry, row).int

proc select*[T: Model](dbConn; obj: var T, cond: string, params: varargs[DbValue, dbValue]) =
  ##[ Populate a `Model`_ instance and its `Model`_ fields from DB.

  ``cond`` is condition for ``WHERE`` clause but with extra features:

  - use ``?`` placeholders and put the actual values in ``params``
  - use `table <model.html#table,typedesc[Model]>`_, \
    `col <model.html#col,T,string>`_, and `fCol <model.html#fCol,T,string>`_ procs \
    instead of hardcoded table and column names
  ]##

  let
    joinStmts = collect(newSeq):
      for grp in obj.joinGroups:
        "JOIN $# ON $# = $#" % [grp.tbl, grp.lFld, grp.rFld]
    qry = "SELECT $# FROM $# $# WHERE $#" % [obj.rfCols.join(", "), T.table, joinStmts.join(" "), cond]
    row = dbConn.getRow(sql qry, params)

  if row.isNone:
    raise newException(KeyError, "Record not found")

  obj.fromRow(get row)

proc select*[T: Model](dbConn; objs: var seq[T], cond: string, params: varargs[DbValue, dbValue]) =
  ##[ Populate a sequence of `Model`_ instances from DB.

  ``objs`` must have at least one item.
  ]##

  if objs.len < 1:
    raise newException(ValueError, "``objs`` must have at least one item.")

  let
    joinStmts = collect(newSeq):
      for grp in objs[0].joinGroups:
        "JOIN $# ON $# = $#" % [grp.tbl, grp.lFld, grp.rFld]
    qry = "SELECT $# FROM $# $# WHERE $#" % [objs[0].rfCols.join(", "), T.table, joinStmts.join(" "), cond]
    rows = dbConn.getAllRows(sql qry, params)

  objs = objs[0].repeat(rows.len)

  for i, row in rows:
    objs[i].fromRow(row)

proc update*[T: Model](dbConn; obj: var T) =
  ## Update rows for `Model`_ instance and its `Model`_ fields.

  for fld, val in obj.fieldPairs:
    when val is Model:
      dbConn.update(val)

  let
    row = obj.toRow()
    phds = collect(newSeq):
      for col in obj.cols:
        "$# = ?" %  col
    qry = "UPDATE $# SET $# WHERE id = $#" % [T.table, phds.join(", "), $obj.id]

  dbConn.exec(sql qry, row)

proc update*[T: Model](dbConn; objs: var openArray[T]) =
  ## Update rows for each `Model`_ instance in open array.

  for obj in objs.mitems:
    dbConn.update(obj)

proc delete*[T: Model](dbConn; obj: var T) =
  ## Delete rows for `Model`_ instance and its `Model`_ fields.

  for fld, val in obj.fieldPairs:
    when val is Model:
      dbConn.delete(val)

  let qry = "DELETE FROM $# WHERE id = $#" % [T.table, $obj.id]

  dbConn.exec(sql qry)

  obj.id = 0

proc delete*[T: Model](dbConn; objs: var openArray[T]) =
  ## Delete rows for each `Model`_ instance in open array.

  for obj in objs.mitems:
    dbConn.delete(obj)

# Transactions

proc rollback* {.raises: RollbackError.} =
  ## Rollback transaction by raising `RollbackError <#RollbackError>`_.

  raise newException(RollbackError, "Rollback transaction.")

template transaction*(dbConn; body: untyped): untyped =
  ##[ Wrap code in DB transaction.

  If an exception is raised, the transaction is rollbacked.

  To rollback manually, call `rollback`_.
  ]##

  try:
    dbConn.exec(sql"BEGIN")

    body

    dbConn.exec(sql"COMMIT")

  except:
    dbConn.exec(sql"ROLLBACK")
    raise
