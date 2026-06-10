///|
test "save_config writes round-trippable toml" {
  let path = "/tmp/moon_agent_config_save_test.toml"
  let cfg = default_config()
  cfg.model.api_key = "dummy-key"
  cfg.tools.better_edit_tools_args = ["--lang", "zh"]
  cfg.ui.show_timestamps = true
  save_config(path, cfg)
  let loaded = load_config(path)
  @debug.assert_eq(loaded.model.base_url, cfg.model.base_url)
  @debug.assert_eq(loaded.model.model, cfg.model.model)
  @debug.assert_eq(loaded.model.api_key, "dummy-key")
  @debug.assert_eq(loaded.tools.better_edit_tools_args.length(), 2)
  @debug.assert_eq(loaded.ui.show_timestamps, true)
}
