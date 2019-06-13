import unittest

import os, strutils, sequtils, times

import norm / sqlite


const
  dbName = "test.db"
  customDbName = "custom_test.db"


db(dbName, "", "", ""):
  type
    User {.table: "users".} = object
      email {.unique.}: string
      ssn: Option[int]
      birthDate {.
        dbType: "INTEGER",
        notNull,
        parseIt: it.i.fromUnix().local(),
        formatIt: dbValue(it.toTime().toUnix())
      .}: DateTime
    Publisher {.table: "publishers".} = object
      title {.unique.}: string
    Book {.table: "books".} = object
      title: string
      authorEmail {.fk: User.email, onDelete: "CASCADE".}: string
      publisherTitle {.fk: Publisher.title.}: string

  proc getBookById(id: DbValue): Book = withDb(Book.getOne int(id.i))

  type
    Edition {.table: "editions".} = object
      title: string
      book {.
        dbCol: "bookId",
        dbType: "INTEGER",
        notNull,
        fk: Book
        parser: getBookById,
        formatIt: dbValue(it.id),
        onDelete: "CASCADE"
      .}: Book

suite "Creating and dropping tables, CRUD":
  setup:
    withDb:
      createTables(force=true)

      for i in 1..9:
        var
          user = User(email: "test-$#@example.com" % $i, ssn: some i,
                      birthDate: parse("200$1-0$1-0$1" % $i, "yyyy-MM-dd"))
          publisher = Publisher(title: "Publisher $#" % $i)
          book = Book(title: "Book $#" % $i, authorEmail: user.email,
                      publisherTitle: publisher.title)
          edition = Edition(title: "Edition $#" % $i)

        user.insert()
        publisher.insert()
        book.insert()

        edition.book = book
        edition.insert()

  teardown:
    withDb:
      dropTables()

  test "Create tables":
    withDb:
      let query = "PRAGMA table_info($#);"

      check dbConn.getAllRows(sql query % "users") == @[
        @[dbValue 0, dbValue "id", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 1],
        @[dbValue 1, dbValue "email", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 2, dbValue "ssn", dbValue "INTEGER", dbValue 0, dbValue nil, dbValue 0],
        @[dbValue 3, dbValue "birthDate", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 0]
      ]
      check dbConn.getAllRows(sql query % "books") == @[
        @[dbValue 0, dbValue "id", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 1],
        @[dbValue 1, dbValue "title", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 2, dbValue "authorEmail", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 3, dbValue "publisherTitle", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
      ]
      check dbConn.getAllRows(sql query % "editions") == @[
        @[dbValue 0, dbValue "id", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 1],
        @[dbValue 1, dbValue "title", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 2, dbValue "bookId", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 0]
      ]

  test "Create records":
    withDb:
      let
        publishers = Publisher.getMany 100
        books = Book.getMany 100
        editions = Edition.getMany 100

      check len(publishers) == 9
      check len(books) == 9
      check len(editions) == 9

      check publishers[3].id == 4
      check publishers[3].title == "Publisher 4"

      check books[5].id == 6
      check books[5].title == "Book 6"

      check editions[7].id == 8
      check editions[7].title == "Edition 8"
      check editions[7].book == books[7]

  test "Read records":
    withDb:
      var
        users = @[
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now()),
          User(birthDate: now())
        ]
        publishers = Publisher().repeat 10
        books = Book().repeat 10
        editions = Edition().repeat 10

      users.getMany(20, offset=5)
      publishers.getMany(20, offset=5)
      books.getMany(20, offset=5)
      editions.getMany(20, offset=5)

      check len(users) == 4
      check users[0].id == 6
      check users[^1].id == 9

      check len(publishers) == 4
      check publishers[0].id == 6
      check publishers[^1].id == 9

      check len(books) == 4
      check books[0].id == 6
      check books[^1].id == 9

      check len(editions) == 4
      check editions[0].id == 6
      check editions[^1].id == 9

      var
        user = User(birthDate: now())
        publisher = Publisher()
        book = Book()
        edition = Edition()

      user.getOne 8
      publisher.getOne 8
      book.getOne 8
      edition.getOne 8

      check user.id == 8
      check publisher.id == 8
      check book.id == 8
      check edition.id == 8

  test "Query records":
    withDb:
      let someBooks = Book.getMany(10, cond="title IN (?, ?) ORDER BY title DESC",
                                   params=[dbValue "Book 1", dbValue "Book 5"])

      check len(someBooks) == 2
      check someBooks[0].title == "Book 5"
      check someBooks[1].authorEmail == "test-1@example.com"

      let someBook = Book.getOne("authorEmail=?", "test-2@example.com")
      check someBook.id == 2

      expect KeyError:
        let notExistingBook = Book.getOne("title=?", "Does not exist")

  test "Update records":
    withDb:
      var
        book = Book.getOne 2
        edition = Edition.getOne 2

      book.title = "New Book"
      edition.title = "New Edition"

      book.update()
      edition.update()

    withDb:
      check Book.getOne(2).title == "New Book"
      check Edition.getOne(2).title == "New Edition"

  test "Delete records":
    withDb:
      var
        book = Book.getOne 2
        edition = Edition.getOne 2

      book.delete()
      edition.delete()

      expect KeyError:
        discard Book.getOne 2

      expect KeyError:
        discard Edition.getOne 2

  test "Drop tables":
    withDb:
      dropTables()

      expect DbError:
        dbConn.exec sql "SELECT NULL FROM users"
        dbConn.exec sql "SELECT NULL FROM publishers"
        dbConn.exec sql "SELECT NULL FROM books"
        dbConn.exec sql "SELECT NULL FROM editions"

  test "Custom DB":
    withCustomDb(customDbName, "", "", ""):
      createTables(force=true)

    withCustomDb(customDbName, "", "", ""):
      let query = "PRAGMA table_info($#);"

      check dbConn.getAllRows(sql query % "users") == @[
        @[dbValue 0, dbValue "id", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 1],
        @[dbValue 1, dbValue "email", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 2, dbValue "ssn", dbValue "INTEGER", dbValue 0, dbValue nil, dbValue 0],
        @[dbValue 3, dbValue "birthDate", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 0]
      ]
      check dbConn.getAllRows(sql query % "books") == @[
        @[dbValue 0, dbValue "id", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 1],
        @[dbValue 1, dbValue "title", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 2, dbValue "authorEmail", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 3, dbValue "publisherTitle", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
      ]
      check dbConn.getAllRows(sql query % "editions") == @[
        @[dbValue 0, dbValue "id", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 1],
        @[dbValue 1, dbValue "title", dbValue "TEXT", dbValue 1, dbValue nil, dbValue 0],
        @[dbValue 2, dbValue "bookId", dbValue "INTEGER", dbValue 1, dbValue nil, dbValue 0]
      ]

    withCustomDb(customDbName, "", "", ""):
      dropTables()

      expect DbError:
        dbConn.exec sql "SELECT NULL FROM users"
        dbConn.exec sql "SELECT NULL FROM publishers"
        dbConn.exec sql "SELECT NULL FROM books"
        dbConn.exec sql "SELECT NULL FROM editions"

    removeFile customDbName

  removeFile dbName
