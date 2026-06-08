defmodule Lantern.SourceTest do
  use ExUnit.Case, async: true

  alias Lantern.Source

  describe "from/1 with a URL" do
    test "parses a full postgres:// URL" do
      assert {:ok, source} =
               Source.from("postgres://alice:secret@db.example.com:6543/shop?sslmode=require")

      assert source.hostname == "db.example.com"
      assert source.port == 6543
      assert source.username == "alice"
      assert source.password == "secret"
      assert source.database == "shop"
      assert source.ssl == true
    end

    test "accepts the postgresql:// scheme" do
      assert {:ok, source} = Source.from("postgresql://bob@localhost/app")
      assert source.username == "bob"
      assert source.password == nil
      assert source.database == "app"
    end

    test "defaults the port to 5432" do
      assert {:ok, %Source{port: 5432}} = Source.from("postgres://u:p@host/db")
    end

    test "defaults the database to postgres when the path is empty" do
      assert {:ok, %Source{database: "postgres"}} = Source.from("postgres://u:p@host")
      assert {:ok, %Source{database: "postgres"}} = Source.from("postgres://u:p@host/")
    end

    test "url-decodes percent-encoded credentials" do
      assert {:ok, source} = Source.from("postgres://user%40corp:p%40ss@host/db")
      assert source.username == "user@corp"
      assert source.password == "p@ss"
    end

    test "ssl is false for non-tls sslmodes" do
      assert {:ok, %Source{ssl: false}} = Source.from("postgres://u:p@host/db?sslmode=disable")
      assert {:ok, %Source{ssl: false}} = Source.from("postgres://u:p@host/db")
    end

    test "rejects a non-postgres scheme" do
      assert {:error, message} = Source.from("mysql://u:p@host/db")
      assert message =~ "postgres://"
    end

    test "rejects a URL with no host" do
      assert {:error, message} = Source.from("postgres:///db")
      assert message =~ "host"
    end
  end

  describe "from/1 with a map or keyword list" do
    test "accepts a keyword list with host/user aliases" do
      assert {:ok, source} =
               Source.from(host: "h", port: 5432, user: "u", pass: "p", db: "d")

      assert source.hostname == "h"
      assert source.username == "u"
      assert source.password == "p"
      assert source.database == "d"
    end

    test "accepts a map with canonical keys" do
      assert {:ok, source} =
               Source.from(%{hostname: "h", username: "u", password: "p", database: "d"})

      assert source.port == 5432
    end

    test "accepts string keys (e.g. from a struct map)" do
      assert {:ok, source} =
               Source.from(%{"hostname" => "h", "username" => "u", "database" => "d"})

      assert source.hostname == "h"
    end

    test "coerces a string port" do
      assert {:ok, %Source{port: 5555}} =
               Source.from(%{hostname: "h", username: "u", database: "d", port: "5555"})
    end

    test "rejects malformed string ports" do
      assert {:error, message} =
               Source.from(%{hostname: "h", username: "u", database: "d", port: "5555abc"})

      assert message =~ "invalid port"

      assert {:error, message} =
               Source.from(%{hostname: "h", username: "u", database: "d", port: "abc"})

      assert message =~ "invalid port"
    end

    test "defaults database to postgres when absent" do
      assert {:ok, %Source{database: "postgres"}} =
               Source.from(%{hostname: "h", username: "u"})
    end

    test "rejects a map missing a host" do
      assert {:error, message} = Source.from(%{username: "u", database: "d"})
      assert message =~ "host"
    end

    test "rejects a map missing a username" do
      assert {:error, message} = Source.from(%{hostname: "h", database: "d"})
      assert message =~ "username"
    end
  end

  describe "from/1 with an existing struct" do
    test "validates and returns it" do
      source = %Source{hostname: "h", port: 5432, username: "u", password: "p", database: "d"}
      assert {:ok, ^source} = Source.from(source)
    end
  end

  describe "to_postgrex_opts/1" do
    test "produces a single-connection option list" do
      {:ok, source} = Source.from("postgres://u:p@host:5432/db")
      opts = Source.to_postgrex_opts(source)

      assert opts[:hostname] == "host"
      assert opts[:username] == "u"
      assert opts[:password] == "p"
      assert opts[:database] == "db"
      assert opts[:pool_size] == 1
      assert is_integer(opts[:connect_timeout])
    end
  end
end
