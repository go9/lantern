defmodule LanternDemo.S3Sandbox.LimitsTest do
  use ExUnit.Case, async: true

  alias LanternDemo.S3Sandbox.Limits

  @prefix "sessions/abc123/"

  describe "sanitize_basename/1 — traversal & path defense" do
    test "strips directory components, keeping only the basename" do
      assert {:ok, "cat.png"} = Limits.sanitize_basename("images/cat.png")
      assert {:ok, "passwd.png"} = Limits.sanitize_basename("../../../etc/passwd.png")
      assert {:ok, "cat.png"} = Limits.sanitize_basename("/absolute/cat.png")
    end

    test "rejects empty, dot, and dot-dot names" do
      assert {:error, :invalid_name} = Limits.sanitize_basename("")
      assert {:error, :invalid_name} = Limits.sanitize_basename(".")
      assert {:error, :invalid_name} = Limits.sanitize_basename("..")
    end

    test "rejects hidden dotfiles (even with an allowlisted extension)" do
      assert {:error, :invalid_name} = Limits.sanitize_basename(".env")
      assert {:error, :invalid_name} = Limits.sanitize_basename(".secret.png")
    end

    test "restricts the charset (spaces and oddities become underscores)" do
      assert {:ok, "my_photo.png"} = Limits.sanitize_basename("my photo.png")
      assert {:ok, "a_b_c.png"} = Limits.sanitize_basename("a$b c.png")
    end

    test "rejects non-allowlisted extensions and non-strings" do
      assert {:error, :type_not_allowed} = Limits.sanitize_basename("malware.exe")
      assert {:error, :type_not_allowed} = Limits.sanitize_basename("noext")
      assert {:error, :invalid_name} = Limits.sanitize_basename(nil)
    end
  end

  describe "object_key/2 — stays under the session prefix" do
    test "builds prefix <> sanitized basename" do
      assert {:ok, @prefix <> "cat.png"} = Limits.object_key(@prefix, "sub/dir/cat.png")
    end

    test "a traversal attempt cannot escape the prefix" do
      assert {:ok, key} = Limits.object_key(@prefix, "../../../etc/passwd.png")
      assert String.starts_with?(key, @prefix)
      refute String.contains?(key, "..")
    end

    test "propagates rejection for disallowed names" do
      assert {:error, :type_not_allowed} = Limits.object_key(@prefix, "x.exe")
    end
  end

  describe "validate_upload/2 — type enforcement" do
    test "accepts an allowlisted type with a matching content-type" do
      assert :ok =
               Limits.validate_upload(
                 %{filename: "cat.png", content_type: "image/png", size: 4 * 1_024 * 1_024},
                 %{}
               )
    end

    test "rejects a non-allowlisted extension" do
      assert {:error, :type_not_allowed} =
               Limits.validate_upload(
                 %{filename: "run.exe", content_type: "application/octet-stream", size: 10},
                 %{}
               )
    end

    test "rejects octet-stream / mismatched content-type despite an allowed extension" do
      assert {:error, :type_mismatch} =
               Limits.validate_upload(
                 %{filename: "cat.png", content_type: "application/octet-stream", size: 10},
                 %{}
               )
    end
  end

  describe "validate_upload/2 — size, count, quota" do
    test "rejects a file over 5 MB" do
      assert {:error, :file_too_large} =
               Limits.validate_upload(
                 %{filename: "big.pdf", content_type: "application/pdf", size: 6 * 1_024 * 1_024},
                 %{}
               )
    end

    test "rejects the 6th file in a session" do
      assert {:error, :too_many_files} =
               Limits.validate_upload(
                 %{filename: "cat.png", content_type: "image/png", size: 10},
                 %{count: 5, bytes: 0}
               )
    end

    test "rejects an upload that would exceed the 25 MB session quota" do
      assert {:error, :session_quota_exceeded} =
               Limits.validate_upload(
                 %{filename: "cat.png", content_type: "image/png", size: 2 * 1_024 * 1_024},
                 %{count: 4, bytes: 24 * 1_024 * 1_024}
               )
    end

    test "rejects a non-integer / negative size" do
      assert {:error, :file_too_large} =
               Limits.validate_upload(
                 %{filename: "cat.png", content_type: "image/png", size: nil},
                 %{}
               )
    end
  end

  describe "validate_type/2 — presign-time server-side re-check" do
    test "accepts an allowlisted extension whose content-type matches" do
      assert :ok = Limits.validate_type("PNG", "image/png")
      assert :ok = Limits.validate_type("jpg", "image/jpeg")
    end

    test "rejects a disallowed extension and a mismatched content-type" do
      assert {:error, :type_not_allowed} = Limits.validate_type("exe", "application/octet-stream")
      assert {:error, :type_mismatch} = Limits.validate_type("png", "application/octet-stream")
    end
  end

  describe "content_type/1" do
    test "returns the canonical content-type to pin on the presigned PUT" do
      assert {:ok, "image/jpeg"} = Limits.content_type("JPG")
      assert {:ok, "application/pdf"} = Limits.content_type("pdf")
      assert {:error, :type_not_allowed} = Limits.content_type("exe")
    end
  end
end
