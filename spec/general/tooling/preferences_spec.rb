# frozen_string_literal: true

require "digest"

General.describe "Firmware preferences" do
  fixture(:dev) { ProvisionedDevice.new(build) }
  before { dev.reset }

  def values(s)
    snapshot = s.preferences
    expect(snapshot.fetch("warnings")).to be_empty
    snapshot.fetch("entries").to_h do |entry|
      [[entry.fetch("partition"), entry.fetch("namespace"), entry.fetch("key")],
       [entry.fetch("type"), entry.fetch("value")]]
    end
  end

  describe "DeepSleepEditing" do
    it "creates, edits, and deletes typed values without waking or changing unrelated preferences", :smoke do
      dev.boot_asleep do |s|
        s.pause
        expect(s.preferences.fetch("editable")).to be(true)
        before = values(s)
        s.set_preference("sim_test", "counter", type: "u64", value: "18446744073709551615")
        s.set_preference("sim_test", "password", type: "string", value: "visible-secret")
        s.set_preference("sim_test", "large_blob", type: "blob", value: "a5" * 5000)
        expect(values(s)).to include(before)
        expect(values(s)).to include(
          %w[nvs sim_test counter] => %w[u64 18446744073709551615],
          %w[nvs sim_test password] => %w[string visible-secret],
          %w[nvs sim_test large_blob] => ["blob", (["a5"] * 5000).join(" ")]
        )
        s.set_preference("sim_test", "counter", type: "u64", value: "42")
        expect(values(s).fetch(%w[nvs sim_test counter])).to eq(%w[u64 42])
        s.delete_preference("sim_test", "counter")
        expect(values(s)).not_to have_key(%w[nvs sim_test counter])
        expect(s.preferences.fetch("editable")).to be(true)
        s.pause(false)
        expect(s.status.fetch("state")).to eq("deep_sleep")
      end
    end

    it "rejects invalid values and writes while active, without altering flash" do
      dev.boot_asleep do |s|
        s.pause
        s.set_preference("sim_test", "counter", type: "u64", value: "42")
        before = Digest::SHA256.file(s.flash).hexdigest
        expect { s.set_preference("sim_test", "counter", type: "u8", value: "256") }
          .to raise_error(TrmnlSim::Error, /409/)
        expect { s.delete_preference("data", "missing_key") }.to raise_error(TrmnlSim::Error, /409/)
        expect(Digest::SHA256.file(s.flash).hexdigest).to eq(before)
        s.reset # The CPU is now powered, but still paused: cached NVS cannot be edited.
        expect(s.preferences.fetch("editable")).to be(false)
        expect { s.set_preference("data", "friendly_id", type: "string", value: "REJECTED") }
          .to raise_error(TrmnlSim::Error, /409.*deep sleep/)
        expect { s.delete_preference("data", "friendly_id") }.to raise_error(TrmnlSim::Error, /409.*deep sleep/)
        expect(Digest::SHA256.file(s.flash).hexdigest).to eq(before)
      end
    end

    it "uses an edited value on wake and persists values and deletion across process restart" do
      Dir.mktmpdir("trmnl-preferences-") do |dir|
        flash = File.join(dir, "flash.bin")
        dev.boot_asleep(flash:) do |s|
          s.pause
          s.set_preference("data", "friendly_id", type: "string", value: "PREFS123")
          s.set_preference("sim_test", "blob", type: "blob", value: "a5" * 5000)
          s.set_preference("sim_test", "removed", type: "u8", value: "1")
          s.delete_preference("sim_test", "removed")
          s.cursor = s.status.fetch("console_total")
          s.wake
          s.pause(false)
          s.wait(console: /friendly_id key exists\. Value - PREFS123/, timeout: 30)
          s.wait(state: "deep_sleep", timeout: 30)
        end
        sim(flash:, host_ports: dev.host_ports, extra_args: ["--offline"]) do |s|
          s.wait(state: "deep_sleep", timeout: 30)
          expect(values(s)).to include(%w[nvs data friendly_id] => %w[string PREFS123],
                                       %w[nvs sim_test blob] => ["blob", (["a5"] * 5000).join(" ")])
          expect(values(s)).not_to have_key(%w[nvs sim_test removed])
        end
      end
    end
  end
end
