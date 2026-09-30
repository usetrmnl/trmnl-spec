# trmnl-spec

Integration tests for the [TRMNL firmware](https://github.com/usetrmnl/trmnl-firmware), run in
[trmnl-sim](https://github.com/usetrmnl/trmnl-sim): real, unmodified firmware builds boot in the
simulator against mock TRMNL servers, and RSpec checks what they send, show and do
(onboarding, refreshes, images, button and touch input, errors, faults, OTA updates, memory
bugs, coverage), on the TRMNL devices and on the BYOD boards the firmware supports.

![setup screen as rendered by the simulator](golden/setup_screen.png)

## Setup

The suite expects the simulator and the firmware as sibling checkouts:

```
trmnl/
├─ trmnl-firmware/   PlatformIO project: pio run -e <env> builds .pio/build/<env>
├─ trmnl-sim/        the simulator: cargo build --release (or rake sim from here)
└─ trmnl-spec/       this repository
```

`TRMNL_FIRMWARE` and `TRMNL_SIM_REPO` (or `TRMNL_SIM_BIN`) point elsewhere. It needs Ruby
3.2+ with Bundler; the client library in [lib](lib) is standard library only.

```sh
bundle install
rake sim                     # cargo build --release in ../trmnl-sim
rake "firmware[trmnl]"       # pio run -e trmnl in ../trmnl-firmware (default: the core devices)
rake check                   # rubocop, and every spec loads for every device (no firmware needed)
```

## Running

The tests are plain RSpec; `ENVS` says which devices a run covers:

```sh
bundle exec rspec                                     # the default ENVS, one process
bundle exec parallel_rspec                            # the same, a process per CPU
rake spec                                             # rake sim, then parallel_rspec
rake "spec[-n 4 spec/core]"                           # parallel_rspec's arguments pass through
bundle exec rspec spec/general/setup/portal_spec.rb:42
bundle exec rspec spec/general/refresh -e 'wakes and refreshes on a button press'
ENVS="xteink_x4:full" bundle exec parallel_rspec      # everything for the Xteink X4
```

`ENVS` is a list (spaces or commas) of PlatformIO environments (case-insensitive) or families,
`core` (the TRMNL-branded devices: OG, BWRY, X, and the gen-2 OG and BWRY), `byod` (every
other board) and `all`, each optionally suffixed `:full`. A listed device runs its own specs
and the general specs' `:smoke` examples (one per area: portal, onboarding, identity,
battery, image, timer and button wake, OTA, HTTPS, a server error, an error screen, a save
point, a special function); with `:full`, all the general specs (setup, portal, WiFi, HTTP,
images, errors, faults, OTA, save points, special functions...). The default is

```sh
ENVS="trmnl:full TRMNL_X trmnl_4clr trmnl_gen2 trmnl_gen2_4clr"
```

and `ENVS=all:full` runs everything everywhere. Examples of devices not listed are left out,
as are those of a listed device whose build is missing (with a warning; under CI the run
fails instead). Examples marked `slow:` (e.g. the screen wiper, 100 full refreshes) run with
`TRMNL_SIM_SLOW=1`.

Specs are in [spec/general](spec/general) (every device, by area; each `General.describe`
group is defined once per listed device), [spec/core](spec/core) (the core devices' own) and
[spec/byod](spec/byod) (the BYOD boards'). parallel_rspec balances files by the runtimes it
records in `tmp/parallel_runtime_rspec.log`. The devices the specs start from (a
factory-fresh X, onboarded devices) are cached in `tmp/spec-cache/`, keyed by the firmware,
the simulator and the spec support code, so the first run after any of them changes is
slower; `TRMNL_SPEC_NO_CACHE=1` runs every setup flow in full, as CI does. `rake -T` lists
the tasks; a task's argument is one string, split like a shell command line (quote the task
in zsh).

## What it covers

The suite needs no internet (but for the opt-in trmnl.app examples). For the TRMNL OG it covers:

- the first-boot setup screen and captive portal, and the portal's 15-minute timeout;
- factory QA near a `TRMNL_QA` network (every build but the X's): pass, fail on an
  overheating chip, stopped by the button (needs the firmware's QA fix; see
  [errors_spec.rb](spec/general/errors_spec.rb));
- onboarding, and WiFi failures (unknown SSID, wrong password);
- `/api/setup` and `/api/display` requests and their headers, including the `Panel-Rev`
  read from the panel;
- HTTPS ([https_spec.rb](spec/general/network/https_spec.rb)), and for trmnl.app the TLS
  session resumed across deep sleep;
- pixel-exact image rendering;
- sleep duration from `refresh_rate`;
- timer and button wake sources;
- battery reporting;
- persistence across power cycles;
- long-press WiFi reset;
- WiFi out of range;
- a full **OTA update** into the second app slot, and booting it.
- save points: restoring a sleeping device in a new simulator (same screen, timer and
  button wake, no re-onboarding), in-memory slots, power-off save points, and refusing
  other builds and bad files.

For the TRMNL BWRY ([trmnl_bwry_spec.rb](spec/core/trmnl_bwry_spec.rb); skipped if
there is no `trmnl_4clr` build): the device identity (`Model: og_4clr`), a 4-color image
rendered exactly (compared as RGB), the panel's long refresh, and a save point keeping the
color image.

For the Seeed reTerminal E1002 ([reterminal_e1002_spec.rb](spec/byod/reterminal_e1002_spec.rb);
skipped if there is no `seeed_reTerminal_E1002` build): the setup screen (the OG's
goldens), onboarding, the device identity (`Model: reterminal_e1002`) and switched battery
divider, every PNG pixel format (1/2/4/8-bit gray and palette, truecolor with and without
alpha) reduced to the six inks exactly as the firmware does, the long refresh, button wake,
and a save point keeping the color image.

For the gen-2 OG and BWRY ([og_gen2_spec.rb](spec/core/og_gen2_spec.rb), a class
each; skipped without a `trmnl_gen2` / `trmnl_gen2_4clr` build in `TRMNL_FIRMWARE_BUILDS`):
the BYOD checks (onboarding through the portal, identity headers, a served image), the
fuel gauge's voltage, `USB-Connected`/`Battery-Charging` from the charger lines, timer and
button wake, deep-sleep and power-off save points, onboarding on 5 GHz with the C5's own
radio (`WiFi-Band`), HTTPS on the crypto accelerators, and memcheck and coverage runs; the
BWRY's colors and the long refresh (its image bug is an expected failure).

For the Sensoria C5 ([parallel_spec.rb](spec/byod/parallel_spec.rb)): the
setup screen, onboarding and a 16-gray ramp on its 1280×720 panel, and its reboot on the
way to sleep (an expected failure, see above).

For the BYOD boards ([uc8179_spec.rb](spec/byod/uc8179_spec.rb),
[uc81xx_spec.rb](spec/byod/uc81xx_spec.rb),
[ssd16xx_spec.rb](spec/byod/ssd16xx_spec.rb),
[m5_spec.rb](spec/byod/m5_spec.rb),
[parallel_spec.rb](spec/byod/parallel_spec.rb); a class per board, skipped
if its env isn't built): every board onboards through the portal and is checked for its
`Model`/`Width`/`Height`/`Battery-Voltage` headers and a served image shown exactly
([byod.rb](spec/support/byod.rb)); plus per board 4-gray and 16-gray
images, partial refreshes, button wake, battery from the gauge or PMIC, colors, each E1004
controller's half, and the firmware bugs listed in the trmnl-sim README ("What is simulated").

For the TRMNL X ([trmnl_x_spec.rb](spec/core/trmnl_x/trmnl_x_spec.rb); skipped if there is
no `TRMNL_X` build):

- the factory flow: modem flashing, then shipment mode until docked;
- onboarding on 2.4 GHz (the S3's own radio) and on 5 GHz (through the modem);
- request headers, including `Width`/`Height`/`Model`, the RSSI of the radio in use,
  `USB-Connected`/`Battery-Charging` on and off the dock, and the fuel gauge's readings
  next to the voltage-based estimate;
- an unattended portal timing out back into shipment mode;
- pixel-exact 1-bit PNGs and a 16-level 4-bit gray ramp on the 1872×1404 panel;
- sleep duration;
- a center tap waking the device (`Update-Source: EXT0`);
- a left tap showing the previous cached image without touching the network;
- the touch bar ([touchbar_spec.rb](spec/core/trmnl_x/touchbar_spec.rb)): browsing with
  taps, holds and (slide mode) swipes, the WiFi-reset and power-off confirmations, and
  switching between tap and slide mode;
- a save point restored in a new simulator: identical screen, dock state, and a touch wake
  refreshing over 5 GHz.

The general tests run on the X too (onboarded on 2.4 GHz; all of them with `ENVS=TRMNL_X:full`). Their
factory-fresh device is an *unboxed* X (shipped, then docked once: it restarted into the
setup portal; `TrmnlX.unboxed`), and their button presses are its touch bar gestures
(`TrmnlX::XSim`): a short press is a tap in the middle, a 5 s press the WiFi reset (both
edges, then a middle hold). The OG's double click and 15 s press have no equivalent there,
so those examples are skipped (`needs: :double_click`, `needs: :soft_reset_press`), as is
what the X doesn't have (factory QA, sensors, Panel-Rev). Its goldens are in
[golden/TRMNL_X](golden/TRMNL_X) (`Golden::REGIONS`).

Fault injection ([faults_spec.rb](spec/general/faults_spec.rb) on the device under test,
[faults_spec.rb](spec/core/trmnl_x/faults_spec.rb) on the X): HTTP 500 and malformed
JSON from `/api/display`; truncated, reset and stalled image downloads (also on the X's
modem path); slow, high-latency and lossy links; DNS failure; an access point without
internet; power loss mid-write in NVS (torn pages), in otadata and during an OTA (the old
firmware keeps booting); a stuck panel or failed PMIC; a missing fuel gauge, or one that
loses its configuration (the golden file is rewritten and the current's sign fixed); an
unresponsive modem.

## Code coverage

`TRMNL_SIM_COVERAGE=DIR rake spec` makes every simulator the tests start record firmware
coverage (`trmnl-sim --coverage`) into `DIR/<test>-*.info`. When all of parallel_rspec's
processes are done they are merged into `DIR/merged.info` and an HTML report in
`DIR/html/`, and the coverage of the firmware's `src/` and `lib/` is printed.
`TrmnlSim::Lcov` ([lcov.rb](lib/trmnl_sim/lcov.rb)) does the merging and reporting, also on
its own:

```sh
rake "coverage[DIR --include src/ --include lib/]"                 # per-file table and total
rake "coverage[DIR -o all.info --html cov-html --root ../trmnl-firmware]"
genhtml all.info -o cov-html                                        # lcov's report, if installed
```

## Memory checking

`TRMNL_SIM_MEMCHECK=1 rake spec` runs every simulator with `--memcheck=halt` (see the
trmnl-sim README, "Memory checking"): an example fails on any memory error. Known firmware
bugs are listed in `KNOWN_MEMORY_BUGS` in [firmware_bugs.rb](spec/support/firmware_bugs.rb),
passed as `--memcheck-suppress` so the rest of each run is still checked, with a pending
(expected to fail) example for each in [memcheck_spec.rb](spec/general/tooling/memcheck_spec.rb).

## Environment variables

| Env var | |
|---|---|
| `TRMNL_FIRMWARE_BUILD` | TRMNL OG build dir (default `../trmnl-firmware/.pio/build/trmnl`) |
| `TRMNL_BWRY_BUILD` | TRMNL BWRY build dir (default `../trmnl-firmware/.pio/build/trmnl_4clr`) |
| `TRMNL_X_BUILD` | TRMNL X build dir (default `../trmnl-firmware/.pio/build/TRMNL_X`) |
| `TRMNL_E1002_BUILD` | reTerminal E1002 build dir (default `../trmnl-firmware/.pio/build/seeed_reTerminal_E1002`) |
| `TRMNL_FIRMWARE_BUILDS` | Where the BYOD and gen-2 boards' builds are, one directory per env (default `../trmnl-firmware/.pio/build`) |
| `TRMNL_SIM_REALTIME=1` | Run the tests without turbo |
| `ENVS` | The devices a run covers (see above; default `trmnl:full TRMNL_X trmnl_4clr trmnl_gen2 trmnl_gen2_4clr`) |
| `TRMNL_SIM_SLOW=1` | Also run the examples marked `slow:` |
| `TRMNL_SPEC_NO_CACHE=1` | Build the devices the specs start from (factory flow, onboarding) afresh, as CI does |
| `TRMNL_SIM_UPDATE_GOLDEN=1` | Rewrite golden screenshots from this run |
| `TRMNL_SIM_ARTIFACTS=DIR` | Save every simulator's log and final screen here |
| `TRMNL_SIM_MEMCHECK=1` | Run every simulator with `--memcheck=halt` (see [Memory checking](#memory-checking)); an example fails on any memory error |
| `TRMNL_SIM_COVERAGE=DIR` | Record firmware code coverage in every simulator; merge and report it after the run (see [Code coverage](#code-coverage)) |
| `TRMNL_SIM_NETWORK=1` | Also run the examples against the real trmnl.app |
| `TRMNL_SIM_BIN` | Simulator binary (default: the trmnl-sim checkout's `target/release/trmnl-sim`) |
| `TRMNL_SIM_REPO` | The trmnl-sim checkout: its release build is the default binary, and `rake sim` builds it (default `../trmnl-sim`) |
| `TRMNL_FIRMWARE` | The firmware checkout whose `.pio/build/<env>` the specs run (default `../trmnl-firmware`) |

## Writing tests

A spec file has one top-level group, with the environment it runs as metadata (a general
one: `General.describe`, a group per listed device), and a nested group per scenario:

```ruby
General.describe "Refresh cycle" do                        # general: a group per listed device
  fixture(:dev) { ProvisionedDevice.new(build) }           # onboarded once (cached), shared
  before { dev.reset }                                     # forget requests, faults, queued answers

  describe "RefreshCycle" do
    it "fetches the next image on a timer wake", :smoke do
      _, expected = device_image(dev.mock, "two", device_number("2"))
      dev.mock.display = { image: "two", refresh_rate: 300 }
      dev.boot_asleep do |s|                               # resumed from a save point
        s.wait_for_deep_sleep
        req = dev.mock.next_request("/api/display") { s.wake }
        expect(req).to have_header("Update-Source", "timer")
        s.wait(state: "deep_sleep", display_idle: true, timeout: 120)
        expect(s).to show_image(expected, tolerance: 64)
      end
    end

    it "resets WiFi on a long press", needs: :button,
                                      known_failure: { "seeed_xiao_esp32c3" => "GPIO 9 can't wake a C3 (bl.cpp:2303)" } do
      ...
    end
  end
end
```

Metadata ([metadata.rb](spec/support/metadata.rb)) says where examples
apply: `env: "<env>"` (left out unless `ENVS` lists it; `General.describe` sets it per
device); `needs: :button` (a `Device` feature of the group's device), `skip_if: :shipment,
why:`, `only_on: %w[trmnl], why:`, `needs_build: "trmnl_4clr"`, `slow: "why"`, `:smoke`
(one per area, run on every listed device), and for firmware bugs `known_failure: { env =>
reason }` (expected to fail on those devices) or `pending: reason` (everywhere). A pending
example that passes fails the run, so a firmware fix shows up. Fixtures are built lazily, so
running one nested group only builds what it uses. Helpers and matchers: `device`, `build`, `sim(...)`, `device_image`,
`device_number`, `panel_number`, `device_mock`, `text_lines`, `show_image`, `match_golden`,
`match_screenshot`, `show_message`, `have_header`; see
[spec/support](spec/support).

The Ruby client library (standard library only) lives in
[lib](lib):

- **`TrmnlSim::Simulator`** launches a headless simulator with the control API and
  wraps every action. `Simulator.open(build, ...) { |sim| }` closes it after the block.
- **`TrmnlSim::MockTrmnl`** is a fake TRMNL API server. It serves `/api/setup`,
  `/api/display`, `/api/log`, images and firmware files, and records every request.
  It also generates BMP images (OG), 1/2/4/8-bit gray PNGs (`set_png`, X) and 4-color
  palette PNGs (`set_color_png`, BWRY; `set_spectra6_png`, 4-bit, reTerminal E1002; like the TRMNL server, colors are reduced to the
  panel's four first, since the OG-family PNG decoder can't take 800 px truecolor rows), with
  server-style `plugin-<id>-<timestamp>` filenames the X uses for its image cache, and
  returns the PNG you should expect on screen (`TrmnlSim::Images` has the encoders and test
  pictures). Request header lookups are case-insensitive. `set_fault(path, status:, body:,
  delay:, hang:, truncate:, rate:, close:, redirect:, chunked:, times:)` makes a path (or a
  `prefix*`) misbehave: an HTTP error, a malformed body, a timeout, a body cut short, a slow
  download or a dropped connection; `device_host` lets the device reach it by a name (with
  `--dns NAME=10.0.2.2`). `MockTrmnl.new(tls: true)` serves HTTPS (TLS 1.2, ECDHE-ECDSA with
  a throwaway P-384 certificate); each request's `tls_resumed` says whether its connection
  resumed an earlier TLS session.

```ruby
require "trmnl_sim"   # with lib/ on the load path
include TrmnlSim

MockTrmnl.open do |mock|
  Simulator.open(BUILD, erase: true, turbo: true, extra_args: ["--offline"]) do |sim|
    expected = mock.set_image("hello", Images.big_number("42"))
    mock.display = { image: "hello", refresh_rate: 600 }

    sim.wait(portal: true)                                   # fresh device in setup mode
    sim.portal_connect("TRMNL-Sim", "pw", server: mock.device_url)

    req = mock.wait_for_request("/api/display")
    raise unless req.headers["Access-Token"] == mock.api_key
    sim.wait(state: "deep_sleep")
    raise unless sim.compare_screen(expected)["match"]       # exact pixels

    req = mock.next_request("/api/display") { sim.press(150) }  # a short press wakes it
    raise unless req.headers["Update-Source"] == "button"
  end
end
```

Useful pieces:

- `sim.wait(...)` blocks until all given conditions hold (`timeout:` in seconds):
  - `console:` (a regex over serial output, continuing from the last match)
  - `state:` (`running`, `deep_sleep`, `halted`, …)
  - `min_refreshes:`
  - `display_idle:`
  - `wifi_connected:`
  - `portal:`
  - `min_boots:`
  
  `wait_for_console(/regex/)`, `wait_for_deep_sleep` and `wait_for_refresh` are shortcuts.
- `sim.press(ms)` holds the button for exactly `ms` of *virtual* time, so hold-duration
  logic is deterministic. `button(down)` holds or releases it indefinitely.
- `sim.touch("left" | "center" | "right", ms:)` taps the TRMNL X touch bar the same way;
  `sim.dock(true/false)` puts it on or takes it off the dock; `sim.pause { }` makes what the
  block does happen at one instant of virtual time.
- `expect(sim).to match_screenshot(path, region: [x, y, w, h])` compares against a golden
  PNG. It creates the golden if missing, and writes `*.actual.png` on mismatch;
  `match_golden(name)` picks the device under test's golden (and fails if it is missing).
- `sim.save_point(path = nil, label: nil)` takes a save point (into memory, and to `path`
  if given); `sim.restore(path)` or `sim.restore(id: n)` restores one, `sim.save_points`
  lists the in-memory ones, and `Simulator.new(BUILD, restore: path)` starts from a file. See
  [savepoints_spec.rb](spec/general/refresh/savepoints_spec.rb).
- `ProvisionedDevice` ([provisioned_device.rb](spec/support/provisioned_device.rb))
  onboards once, then boots copies of that flash. Tests start from a registered device in
  seconds. [trmnl_x.rb](spec/support/trmnl_x.rb) does the same for the X:
  `TrmnlX::ShippedX` is a device fresh from the factory (QA done, modem flashed, in shipment
  mode) and `TrmnlX::ProvisionedX` onboards a copy of it on 5 GHz (or `ssid: TrmnlX::SSID_24`).
- `sim.set_faults(net: {...}, power_loss: {...}, ...)`, `sim.set_net_faults(dns: "servfail")`,
  `sim.arm_power_loss("nvs", cut: "torn")`, `sim.clear_faults` and `sim.faults` inject
  faults (trmnl-sim README, "Fault injection"); `Simulator.new(..., faults: {...})` starts with them.
- `Simulator.new(..., memcheck: "halt")` runs under the [memory checker](#memory-checking);
  `sim.memcheck` returns its report and `sim.assert_no_memory_errors` fails on
  violations (also done when an `open` block ends).

## CI

[.github/workflows/ci.yml](.github/workflows/ci.yml) runs `rake check`, then checks out
trmnl-sim and trmnl-firmware, builds the core devices' firmware and the headless simulator,
and runs `rake spec` with every setup flow in full. On failure it uploads simulator logs,
final screens and screen diffs; it always uploads the firmware coverage (merged lcov and
HTML). Other repositories call it (`workflow_call`) to test their PRs: the firmware
repository with [docs/firmware-repo-workflow.yml](docs/firmware-repo-workflow.yml), and
trmnl-sim from its own CI. Adjust the `usetrmnl/...` repository names if they are hosted
elsewhere.
