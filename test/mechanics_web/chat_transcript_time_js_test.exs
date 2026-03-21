defmodule MechanicsWeb.ChatTranscriptTimeJSTest do
  use ExUnit.Case, async: true

  @assets_js Path.expand("../../assets/js", __DIR__)

  test "chat transcript local-time rules (Node, TZ=America/Phoenix)" do
    test_path = Path.join(@assets_js, "chat_transcript_time.test.mjs")
    assert File.exists?(test_path)

    case System.find_executable("node") do
      nil ->
        IO.warn(
          "skipping assets/js/chat_transcript_time.test.mjs: node not in PATH",
          []
        )

        assert true

      node ->
        env = System.get_env() |> Map.put("TZ", "America/Phoenix") |> Map.to_list()

        {output, code} =
          System.cmd(node, ["--test", "chat_transcript_time.test.mjs"],
            cd: @assets_js,
            env: env
          )

        assert code == 0, output
    end
  end
end
