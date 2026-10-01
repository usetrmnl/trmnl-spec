# frozen_string_literal: true

require "open3"
require "tempfile"

# Decode the displayed QR, without inspecting the firmware's pairing state.
module PairingQR
  module_function

  def decode(sim)
    Tempfile.create(["trmnl-pairing-", ".png"]) do |file|
      sim.screenshot(file.path)
      text, _, status = Open3.capture3("zbarimg", "--quiet", "--raw", file.path)
      next unless status.success?

      payload = text.lines.find { _1.include?("#BLE:") }
      next unless payload

      version, name, session, proof = payload.strip.split("#BLE:", 2).last.split(":")
      raise TrmnlSim::Error, "unsupported pairing QR" unless version == "1" && session&.match?(/\A\h{32}\z/) && proof

      session = session.downcase.sub(/(.{8})(.{4})(.{4})(.{4})(.{12})/, '\1-\2-\3-\4-\5')
      { name:, session:, proof: }
    end
  rescue Errno::ENOENT
    raise TrmnlSim::Error, "Bluetooth QR specs require zbarimg (brew install zbar / apt install zbar-tools)"
  end
end
