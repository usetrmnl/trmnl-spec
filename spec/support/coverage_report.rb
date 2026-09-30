# frozen_string_literal: true

require "fileutils"

# Every run records firmware coverage: each simulator writes an lcov tracefile into this run's
# directory under tmp/coverage/, one subdirectory per build. When the run is over (all of
# parallel_rspec's processes), they are merged into out/cov/merged.info and out/cov/html/ (TrmnlSim::Lcov),
# and the coverage of the firmware's own src/ and lib/ is printed.
#
# The setup flows run once and are cached (SetupCache): their tracefiles are kept in the cache
# entry and copied into every run that uses it, so a cached run reports the same lines.
module CoverageReport
  DIR = File.join(Builds::OUT, "cov")
  # This run's tracefiles: parallel_rspec's workers share its pid file, a plain rspec is alone.
  RUN = File.join(Builds::HERE, "tmp/coverage",
                  ENV["PARALLEL_PID_FILE"] ? File.basename(ENV["PARALLEL_PID_FILE"]) : "pid-#{Process.pid}")
  # The firmware's own sources, in the tracefiles' paths (relative to its checkout).
  FIRMWARE_SOURCES = %w[src/ lib/].freeze

  module_function

  def install = TrmnlSim::Simulator.coverage_dir = RUN

  # Simulators started in the block write their tracefiles into `dir` (a setup cache entry's).
  def recording_into(dir)
    before = TrmnlSim::Simulator.coverage_dir
    TrmnlSim::Simulator.coverage_dir = dir
    yield
  ensure
    TrmnlSim::Simulator.coverage_dir = before
  end

  # Copy a setup cache entry's tracefiles into this run. Their names are fixed, so workers using
  # the same entry write the same files and the setup is counted once.
  def adopt(entry, dir)
    Dir[File.join(dir, "*/*.info")].each do |f|
      out = File.join(RUN, File.basename(File.dirname(f)), "setup-#{entry}-#{File.basename(f)}")
      FileUtils.mkdir_p(File.dirname(out))
      FileUtils.cp(f, out)
    end
  end

  def print
    return unless Dir.exist?(RUN)

    FileUtils.rm_rf(DIR)
    FileUtils.mkdir_p(DIR)
    all = TrmnlSim::Lcov::Report.load([RUN])
    all.write_lcov(File.join(DIR, TrmnlSim::Lcov::MERGED))
    # Relative paths in the tracefiles are relative to the firmware checkout.
    all.write_html(File.join(DIR, "html"), root: Builds::FIRMWARE)
    warn "\nFirmware coverage (src/, lib/); full report in #{File.join(DIR, 'html')}"
    puts all.total_line
    own = TrmnlSim::Lcov::Report.load([RUN], include: FIRMWARE_SOURCES)
    puts own.summary, "(#{own.tracefiles} tracefiles)"
    builds = Dir[File.join(RUN, "*/")]
    if builds.size > 1
      warn "\nPer build (src/, lib/ lines each build compiles):"
      builds.sort.each do |b|
        warn "  #{File.basename(b).ljust(32)} #{TrmnlSim::Lcov::Report.load([b], include: FIRMWARE_SOURCES).total_line}"
      end
    end
  ensure
    FileUtils.rm_rf(RUN)
  end
end
