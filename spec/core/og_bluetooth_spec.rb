# frozen_string_literal: true

RSpec.describe "OG Bluetooth provisioning", env: "trmnl" do
  def advertised(s)
    eventually("firmware did not advertise", within: 30, every: 0.1) { s.status.dig("bluetooth", "advertising") }
  end

  def pairing_qr(s)
    result = nil
    eventually("firmware pairing QR is not readable", within: 20, every: 0.2) { result = PairingQR.decode(s) }
    result
  end

  def authenticate(central, identity)
    TrmnlSim::Security1.new(central, session: identity.fetch(:session), proof: identity.fetch(:proof))
  end

  describe "Discovery" do
    it "discovers the real NimBLE endpoints and invalidates the connection on reset", :smoke do
      sim(erase: true, extra_args: ["--offline"]) do |s|
        advertised(s)
        expect(s.status.fetch("bluetooth")).to include("active" => "mock", "initialized" => true)
        expect(s.status.fetch("bluetooth")).not_to include("requested", "fallback_reason")
        central = TrmnlSim::Bluetooth.new(s)
        expect(central.characteristics.keys).to include(TrmnlSim::Bluetooth::SECURITY, TrmnlSim::Bluetooth::CONTROL)
        info = JSON.parse(central.endpoint(TrmnlSim::Bluetooth::VERSION, "ESP"))
        expect(info.dig("prov", "sec_ver")).to eq(1)
        expect(info.dig("trmnl", "ver")).to eq(1)
        s.reset
        expect { s.bluetooth_att(central.connection, "\x0a\x01\x00".b) }.to raise_error(TrmnlSim::Error, /409/)
      end
    end
  end

  describe "Security1" do
    it "authenticates from the QR, handles long writes, reconnects, and rejects incorrect proof" do
      sim(erase: true, extra_args: ["--offline"]) do |s|
        advertised(s)
        qr = pairing_qr(s)
        central = TrmnlSim::Bluetooth.new(s)
        session = authenticate(central, qr)
        expect(session.command("status")).not_to have_key("error")
        expect(session.command("status", padding: 300)).not_to have_key("error")
        expect { central.write(TrmnlSim::Bluetooth::CONTROL, "z" * 513) }
          .to raise_error(TrmnlSim::Bluetooth::AttError) do |error|
            handle = central.characteristics.fetch(TrmnlSim::Bluetooth::CONTROL)
            expect(error.packet).to eq([1, 0x18, handle, 0x0d].pack("CCvC"))
          end
        # Rejected writes must not consume the cipher stream.
        expect(session.command("status")).not_to have_key("error")
        old_connection = central.connection
        central.disconnect
        advertised(s)
        central = TrmnlSim::Bluetooth.new(s)
        expect(central.connection).not_to eq(old_connection)
        expect(authenticate(central, qr).command("status")).not_to have_key("error")
        central.disconnect
        advertised(s)
        central = TrmnlSim::Bluetooth.new(s)
        wrong = qr.merge(proof: (qr[:proof].start_with?("0") ? "1" : "0") + qr[:proof][1..])
        expect { authenticate(central, wrong) }.to raise_error(TrmnlSim::Error) do |error|
          expect(error).to be_a(TrmnlSim::Bluetooth::AttError).or have_attributes(message: match(/409/))
          expect(error.message).not_to match(/timed out/)
        end
      end
    end
  end

  describe "EncryptedOnboarding" do
    it "validates credentials, provisions WiFi over TLS, and acknowledges the setup code" do
      device_mock(tls: true) do |mock|
        host = ENV.fetch("PAIRING_HOST", "trmnl.app")
        sim(erase: true, extra_args: ["--offline", "--dns", "#{host}=10.0.2.2"],
            host_ports: { 443 => mock.port }) do |s|
          advertised(s)
          session = authenticate(TrmnlSim::Bluetooth.new(s), pairing_qr(s))
          networks = session.command("networks", offset: 0, limit: 3)
          expect(networks).not_to have_key("error")
          expect(networks.fetch("networks")).to be_an(Array)
          expect(session.command("configure", attempt: 1, ssid: "TRMNL-Sim", password: "short"))
            .to include("error" => "invalid_credentials", "attempt" => 0)
          configured = session.command("configure", attempt: 1, ssid: "TRMNL-Sim", password: "test-password")
          expect(configured).to include("attempt" => 1)
          expect(configured).not_to have_key("error")
          s.set_portal_client(false)
          status = nil
          eventually("provisioning did not produce a setup code", within: 45, every: 0.2) do
            status = session.command("status", attempt: 1)
            expect(status).not_to have_key("error")
            status["state"] == "code_ready"
          end
          expect(status["friendly_id"]).to eq(mock.friendly_id)
          expect(mock.paths).to include("/api/setup")
          acknowledged = session.command("ack_code", attempt: 1)
          expect(acknowledged).to include("state" => "handed_off")
          expect(acknowledged).not_to have_key("error")
        end
      end
    end
  end
end
