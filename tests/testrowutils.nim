import unittest
import times, options
import norm / rowutils

import ndb/sqlite


suite "Basic object <-> row conversion":
  type
    SimpleUser = object
      name: string
      age: Natural
      height: float
      ssn: Option[int]
      employed: Option[bool]

  let
    user = SimpleUser(name: "Alice", age: 23, height: 168.2, ssn: some 123, employed: some true)
    row = @[dbValue "Alice", dbValue 23, dbValue 168.2, dbValue 123, dbValue 1]
    userWithoutOptionals = SimpleUser(
      name: "Alice",
      age: 23,
      height: 168.2,
      ssn: none int,
      employed: none bool
    )
    rowWithoutOptionals = @[dbValue "Alice", dbValue 23, dbValue 168.2, dbValue nil, dbValue nil]


  test "Object -> row":
    check user.toRow() == row
    check userWithoutOptionals.toRow() == rowWithoutOptionals

  test "Row -> object":
    check row.to(SimpleUser) == user
    check rowWithoutOptionals.to(SimpleUser) == userWithoutOptionals

  test "Object -> row -> object":
    check user.toRow().to(SimpleUser) == user
    check userWithoutOptionals.toRow().to(SimpleUser) == userWithoutOptionals

  test "Row -> object -> row":
    check rowWithoutOptionals.to(SimpleUser).toRow() == rowWithoutOptionals

suite "Conversion with custom parser and formatter expressions":
  type
    UserDatetimeAsString = object
      name: string
      age: Natural
      height: float
      createdAt {.
        formatIt: dbValue(it.format("yyyy-MM-dd HH:mm:sszzz")),
        parseIt: it.s.parse("yyyy-MM-dd HH:mm:sszzz", utc())
      .}: DateTime

  let
    datetimeString = "2019-01-30 12:34:56Z"
    datetime = datetimeString.parse("yyyy-MM-dd HH:mm:sszzz", utc())
    user = UserDatetimeAsString(name: "Alice", age: 23, height: 168.2, createdAt: datetime)
    row = @[dbValue "Alice", dbValue 23, dbValue 168.2, dbValue datetimeString]

  setup:
    var tmpUser {.used.} = UserDatetimeAsString(createdAt: now())

  test "Object -> row":
    check user.toRow() == row

  test "Row -> object":
    row.to(tmpUser)
    check tmpUser == user

  test "Object -> row -> object":
    user.toRow().to(tmpUser)
    check tmpUser == user

  test "Row -> object -> row":
    row.to(tmpUser)
    check tmpUser.toRow() == row

suite "Conversion with custom parser and formatter procs":
  proc toTimestamp(dt: DateTime): DbValue = dbValue dt.toTime().toUnix()

  proc toDatetime(ts: DbValue): DateTime = ts.i.fromUnix().utc()

  type
    UserDatetimeAsTimestamp = object
      name: string
      age: Natural
      height: float
      createdAt {.formatter: toTimestamp, parser: toDatetime.}: DateTime

  let
    datetime = "2019-01-30 12:34:56+04:00".parse("yyyy-MM-dd HH:mm:sszzz")
    user = UserDatetimeAsTimestamp(name: "Alice", age: 23, height: 168.2, createdAt: datetime)
    row = @[dbValue "Alice", dbValue 23, dbValue 168.2, dbValue datetime.toTimestamp()]

  setup:
    var tmpUser {.used.} = UserDatetimeAsTimestamp(createdAt: now())

  test "Object -> row":
    check user.toRow() == row

  test "Row -> object":
    row.to(tmpUser)
    check tmpUser == user

  test "Object -> row -> object":
    user.toRow().to(tmpUser)
    check tmpUser == user

  test "Row -> object -> row":
    row.to(tmpUser)
    check tmpUser.toRow() == row

suite "Basic bulk object <-> row conversion":
  type
    SimpleUser = object
      name: string
      age: Natural
      height: float

  let
    users = @[
      SimpleUser(name: "Alice", age: 23, height: 168.2),
      SimpleUser(name: "Bob", age: 34, height: 172.5),
      SimpleUser(name: "Michael", age: 45, height: 180.0)
    ]
    rows = @[
      @[dbValue "Alice", dbValue 23, dbValue 168.2],
      @[dbValue "Bob", dbValue 34, dbValue 172.5],
      @[dbValue "Michael", dbValue 45, dbValue 180.0]
    ]

  test "Objects -> rows":
    check users.toRows() == rows

  test "Rows -> objects":
    check rows.to(SimpleUser) == users

  test "Objects -> rows -> objects":
    check users.toRows().to(SimpleUser) == users

  test "Rows -> objects -> rows":
    check rows.to(SimpleUser).toRows() == rows

suite "Bulk conversion with custom parser and formatter expressions":
  type
    UserDatetimeAsString = object
      name: string
      age: Natural
      height: float
      createdAt {.
        formatIt: dbValue(it.format("yyyy-MM-dd HH:mm:sszzz")),
        parseIt: it.s.parse("yyyy-MM-dd HH:mm:sszzz", utc())
      .}: DateTime

  let
    datetimeString = "2019-01-30 12:34:56Z"
    datetime = datetimeString.parse("yyyy-MM-dd HH:mm:sszzz", utc())
    users = @[
      UserDatetimeAsString(name: "Alice", age: 23, height: 168.2, createdAt: datetime),
      UserDatetimeAsString(name: "Bob", age: 34, height: 172.5, createdAt: datetime),
      UserDatetimeAsString(name: "Michael", age: 45, height: 180.0, createdAt: datetime)
    ]
    rows = @[
      @[dbValue "Alice", dbValue 23, dbValue 168.2, dbValue datetimeString],
      @[dbValue "Bob", dbValue 34, dbValue 172.5, dbValue datetimeString],
      @[dbValue "Michael", dbValue 45, dbValue 180.0, dbValue datetimeString]
    ]

  setup:
    var tmpUsers {.used.} = @[
      UserDatetimeAsString(createdAt: now()),
      UserDatetimeAsString(createdAt: now()),
      UserDatetimeAsString(createdAt: now())
    ]

  test "Objects -> rows":
    check users.toRows() == rows

  test "Rows -> objects":
    rows.to(tmpUsers)
    check tmpUsers == users

  test "Objects -> rows -> objects":
    users.toRows().to(tmpUsers)
    check tmpUsers == users

  test "Rows -> objects -> rows":
    rows.to(tmpUsers)
    check tmpUsers.toRows() == rows

suite "Bulk conversion with custom parser and formatter procs":
  proc toTimestamp(dt: DateTime): DbValue = dbValue dt.toTime().toUnix()

  proc toDatetime(ts: DbValue): DateTime = ts.i.fromUnix().utc()

  type
    UserDatetimeAsTimestamp = object
      name: string
      age: Natural
      height: float
      createdAt {.formatter: toTimestamp, parser: toDatetime.}: DateTime

  let
    datetime = "2019-01-30 12:34:56+04:00".parse("yyyy-MM-dd HH:mm:sszzz")
    users = @[
      UserDatetimeAsTimestamp(name: "Alice", age: 23, height: 168.2, createdAt: datetime),
      UserDatetimeAsTimestamp(name: "Bob", age: 34, height: 172.5, createdAt: datetime),
      UserDatetimeAsTimestamp(name: "Michael", age: 45, height: 180.0, createdAt: datetime)
    ]
    rows = @[
      @[dbValue "Alice", dbValue  23, dbValue 168.2, datetime.toTimestamp()],
      @[dbValue "Bob", dbValue  34, dbValue 172.5, datetime.toTimestamp()],
      @[dbValue "Michael", dbValue  45, dbValue 180.0, datetime.toTimestamp()]
    ]

  setup:
    var tmpUsers {.used.} = @[
      UserDatetimeAsTimestamp(createdAt: now()),
      UserDatetimeAsTimestamp(createdAt: now()),
      UserDatetimeAsTimestamp(createdAt: now())
    ]

  test "Objects -> rows":
    check users.toRows() == rows

  test "Rows -> objects, equal lengths":
    rows.to(tmpUsers)
    check tmpUsers == users

  test "Rows -> objects, more rows than objects":
    discard tmpUsers.pop()

    rows.to(tmpUsers)

    for i in 0..1:
      check tmpUsers[i] == users[i]

  test "Rows -> objects, more objects than rows":
    var u = UserDatetimeAsTimestamp(createdAt: now())

    tmpUsers.add u

    rows.to(tmpUsers)

    for i in 0..2:
      check tmpUsers[i] == users[i]

    check len(tmpUsers) == len(rows)

  test "Objects -> rows -> objects":
    users.toRows().to(tmpUsers)
    check tmpUsers == users

  test "Rows -> objects -> rows":
    rows.to(tmpUsers)
    check tmpUsers.toRows() == rows

suite "Boolean field conversion":
  type
    Car = object
      manufacturer: string
      model: string
      used: bool
      owned: Option[bool]
      yellow: Option[bool]

  let
    car = Car(
      manufacturer: "Toyota",
      model: "true",
      used: false,
      owned: some true,
      yellow: none bool
    )
    row = @[dbValue "Toyota", dbValue "true", dbValue 0, dbValue 1, dbValue nil]

  test "Object -> row":
    check car.toRow() == row

  test "Row -> object":
    check row.to(Car) == car

  test "Object -> row -> object":
    check car.toRow().to(Car) == car

  test "Row -> object -> row":
    check row.to(Car).toRow() == row
