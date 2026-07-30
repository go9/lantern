defmodule LanternDemo.S3Sandbox.PrefixProviderTest do
  use ExUnit.Case, async: true

  alias LanternDemo.S3Sandbox.PrefixProvider

  describe "new_prefix/0" do
    test "is under sessions/, ends in /, and is unguessable" do
      prefix = PrefixProvider.new_prefix()
      assert String.starts_with?(prefix, "sessions/")
      assert String.ends_with?(prefix, "/")
      # sessions/ + >=16 random chars + /
      assert String.length(prefix) > String.length("sessions//") + 16
    end

    test "is unique per call" do
      assert PrefixProvider.new_prefix() != PrefixProvider.new_prefix()
    end
  end

  describe "provision/0 when unconfigured" do
    test "reports not-configured rather than raising (no creds in test env)" do
      assert {:error, _} = PrefixProvider.provision()
    end
  end

  describe "payload/1" do
    test "exposes only bucket + prefix (never the creds) to the LiveView" do
      resource = %{bucket: "b", prefix: "sessions/x/", config: :secret}
      assert PrefixProvider.payload(resource) == %{bucket: "b", prefix: "sessions/x/"}
    end
  end
end
