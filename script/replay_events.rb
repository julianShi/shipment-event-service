#!/usr/bin/env ruby

require "csv"
require "json"
require "net/http"
require "optparse"
require "time"
require "uri"
require "thread"

STATUS_RANK = {
  "created" => 0,
  "picked_up" => 1,
  "in_transit" => 2,
  "delivered" => 3,
  "failed" => 3
}.freeze

options = {
  csv: ENV.fetch("CSV_PATH", File.expand_path("../data/carrier_events.csv", __dir__)),
  base_url: ENV.fetch("BASE_URL", "http://localhost:3000"),
  concurrency: 8
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby script/replay_events.rb [options]"
  parser.on("--csv PATH", "CSV fixture path (default: CSV_PATH or workspace data file)") { |value| options[:csv] = value }
  parser.on("--url URL", "Service base URL (default: BASE_URL or http://localhost:3000)") { |value| options[:base_url] = value }
  parser.on("--concurrency N", Integer, "Concurrent POST workers (default: 8)") { |value| options[:concurrency] = value }
end.parse!

abort "Concurrency must be positive" unless options[:concurrency].positive?
abort "CSV not found: #{options[:csv]}" unless File.file?(options[:csv])

rows = CSV.read(options[:csv], headers: true).map(&:to_h)
required = %w[event_id shipment_reference status event_timestamp]
abort "CSV is missing required columns" unless (required - rows.first.to_h.keys).empty?

expected_by_id = {}
rows.each do |event|
  prior = expected_by_id[event.fetch("event_id")]
  if prior && prior != event
    abort "Conflicting CSV rows share event_id #{event.fetch('event_id')}"
  end
  expected_by_id[event.fetch("event_id")] = event
end

def request_json(base_url, method, path, payload = nil)
  uri = URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", path.sub(%r{\A/}, ""))
  request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  if payload
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = JSON.generate(payload)
  end

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 30) do |http|
    http.request(request)
  end
  [ response.code.to_i, response.body.to_s.empty? ? {} : JSON.parse(response.body) ]
end

queue = Queue.new
rows.each { |row| queue << row }
mutex = Mutex.new
stats = Hash.new(0)
errors = Queue.new
workers = [ options[:concurrency], rows.length ].min.times.map do
  Thread.new do
    loop do
      event = queue.pop(true)
      code, = request_json(options[:base_url], :post, "/webhooks/carrier_events", event)
      mutex.synchronize do
        case code
        when 201 then stats[:created] += 1
        when 200 then stats[:duplicates] += 1
        else errors << "POST event_id=#{event['event_id']} returned HTTP #{code}"
        end
      end
    rescue ThreadError
      break
    rescue StandardError => error
      errors << "POST event_id=#{event && event['event_id']}: #{error.class}: #{error.message}"
    end
  end
end
workers.each(&:value)

unless errors.empty?
  messages = []
  messages << errors.pop until errors.empty?
  warn messages.first(10).join("\n")
  abort "Replay failed with #{messages.length} request error(s)"
end

expected_by_shipment = expected_by_id.values.group_by { |event| event.fetch("shipment_reference") }
list_code, list_body = request_json(options[:base_url], :get, "/shipments")
abort "GET /shipments returned HTTP #{list_code}" unless list_code == 200
actual_summaries = list_body.fetch("shipments").each_with_object({}) do |shipment, result|
  result[shipment.fetch("shipment_reference")] = shipment
end

def expected_summary(events)
  statuses = events.map { |event| event.fetch("status") }.uniq
  terminal = statuses & %w[delivered failed]
  if terminal.length > 1
    { "current_status" => nil, "status_resolution" => "undetermined" }
  else
    status = statuses.max_by { |item| STATUS_RANK.fetch(item) }
    { "current_status" => status, "status_resolution" => status ? "determined" : "undetermined" }
  end
end

abort "Expected #{expected_by_shipment.length} shipments; API returned #{actual_summaries.length}" unless actual_summaries.length == expected_by_shipment.length

expected_by_shipment.each do |reference, events|
  expected = expected_summary(events)
  actual = actual_summaries.fetch(reference) { abort "Shipment missing from list: #{reference}" }
  expected.each do |field, value|
    abort "#{reference}: expected #{field}=#{value.inspect}, got #{actual[field].inspect}" unless actual[field] == value
  end

  code, timeline = request_json(options[:base_url], :get, "/shipments/#{URI.encode_www_form_component(reference)}")
  abort "GET /shipments/#{reference} returned HTTP #{code}" unless code == 200
  expected_timeline = events.sort_by do |event|
    [ Time.iso8601(event.fetch("event_timestamp")), event.fetch("event_id") ]
  end.map { |event| event.fetch("event_id") }
  actual_timeline = timeline.fetch("events").map { |event| event.fetch("event_id") }
  abort "#{reference}: event timeline mismatch" unless actual_timeline == expected_timeline
end

puts "Replay complete: #{rows.length} rows, #{expected_by_id.length} unique events, #{expected_by_shipment.length} shipments."
puts "POST results: #{stats[:created]} created, #{stats[:duplicates]} idempotent duplicates."
puts "Verified list status, logical current status, complete timelines, and deterministic timestamp ordering."
