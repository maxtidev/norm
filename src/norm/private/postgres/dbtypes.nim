##[ Funcs to convert between Nim types and SQLite types and between Nim values and ``lowdb.postgres.DbValue``.

To add support for ``YourType``, define three funcs:
- ``dbType(T: typedesc[YourType]) -> string`` that returns SQL type for given ``YourType``
- ``dbValue(YourType) -> DbValue`` that converts instances of ``YourType`` to ``lowdb.sqlite.DbValue``
- ``to(DbValue, T: typedesc[YourType]) -> T`` that converts ``lowdb.sqlite.DbValue`` instances to ``YourType``.
]##


import std/[options, times, strutils]

import lowdb/postgres

import ../../model
import ../../types


# Funcs that return an SQLite type for a given Nim type:

func dbType*(T: typedesc[int16]): string = "SMALLINT"

func dbType*(T: typedesc[int32 | enum]): string = "INTEGER"

func dbType*(T: typedesc[int64 | Positive | int | Natural]): string = "BIGINT"

func dbType*(T: typedesc[float32]): string = "REAL"

func dbType*(T: typedesc[float64]): string = "DOUBLE PRECISION"

func dbType*(T: typedesc[string]): string = "TEXT"

func dbType*[C](_: typedesc[StringOfCap[C]]): string = "VARCHAR($#)" % $C

func dbType*[C](_: typedesc[PaddedStringOfCap[C]]): string = "CHAR($#)" % $C

func dbType*(T: typedesc[bool]): string = "BOOLEAN"

func dbType*(T: typedesc[DateTime]): string = "TIMESTAMP WITH TIME ZONE"

func dbType*(T: typedesc[Model]): string = "BIGINT"

func dbType*[T](_: typedesc[Option[T]]): string = dbType T


# Converter funcs from Nim values to ``DbValue``:

func dbValue*(val: typeof(nil)): DbValue = DbValue(kind: dvkNull)

func dbValue*[T: Model](val: T): DbValue = dbValue(val.id)

func dbValue*[T: Model](val: Option[T]): DbValue =
  if val.isSome:
    dbValue(get(val))
  else:
    dbValue(nil)

func dbValue*[T](val: StringOfCap[T]): DbValue = dbValue(string(val))

func dbValue*[T](val: PaddedStringOfCap[T]): DbValue = dbValue(string(val))


# Converter funcs from ``DbValue`` instances to Nim types:

using dbVal: DbValue

func to*(dbVal; T: typedesc[SomeInteger | enum]): T = dbVal.i.T

func to*(dbVal; T: typedesc[SomeFloat]): T = dbVal.f.T

func to*(dbVal; T: typedesc[string]): T = dbVal.s

func to*[T1](dbVal; T2: typedesc[StringOfCap[T1]]): T2 = dbVal.o.value.T2

func to*[T1](dbVal; T2: typedesc[PaddedStringOfCap[T1]]): T2 = dbVal.o.value.T2

func to*(dbVal; T: typedesc[bool]): T = dbVal.b

func to*(dbVal; T: typedesc[DateTime]): T = dbVal.t

func to*(dbVal; T: typedesc[Model]): T =
  ## This is never called and exists only to please the compiler.

  discard

proc to*[T](dbVal; O: typedesc[Option[T]]): O =
  case dbVal.kind
  of dvkNull:
    none T
  else:
    some dbVal.to(T)
