# frozen_string_literal: true

# Where the firmware builds are, and the settings every simulator of a run shares.
module Builds
  HERE = File.expand_path("../..", __dir__) # this repository's root
  # What a run leaves behind: coverage (CoverageReport) and artifacts (Artifacts). Gitignored.
  OUT = File.join(HERE, "out")
  # The firmware checkout (FIRMWARE_REPO, else ../trmnl-firmware next to this repository).
  FIRMWARE = File.expand_path(ENV.fetch("FIRMWARE_REPO", File.join(HERE, "../trmnl-firmware")))
  # PlatformIO build directories of the firmware checkout, one per environment.
  DIR = File.join(FIRMWARE, ".pio/build")

  TEST_MAC = "7C:DF:A1:00:00:01"
  # NETWORK=1: tests that reach the real internet run.
  NETWORK = ENV["NETWORK"] == "1"
  # Turbo (network-aware fast-forward) unless REALTIME=1.
  TURBO = ENV["REALTIME"] != "1"
  # SLOW=1: also run the examples marked `slow:`.
  SLOW = ENV["SLOW"] == "1"
  # MEMCHECK=1: every simulator runs with --memcheck=halt, and a test fails on any
  # memory error (the simulator halts at it, or leaving its block raises).
  MEMCHECK = ENV["MEMCHECK"] == "1" ? "halt" : nil
  UPDATE_GOLDEN = ENV["UPDATE_GOLDEN"] == "1"

  module_function

  # The build of PlatformIO environment `env` (it may not exist: see `built?`).
  def for_env(env) = File.expand_path(File.join(DIR, env.to_s))

  def built?(env) = File.exist?(File.join(for_env(env), "firmware.elf"))

  # Why `env`'s tests can't run: its build is missing (nil: they can).
  def missing(env)
    "no #{env} build at #{for_env(env)} (pio run -e #{env})" unless built?(env)
  end

  # The device a build directory is for (nil: unknown).
  def device_of(build)
    Devices::BY_ENV[File.basename(File.expand_path(build.to_s))]
  end
end
