#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if command -v rbenv >/dev/null 2>&1; then
  ruby_runner=(rbenv exec bundle exec ruby)
elif command -v bundle >/dev/null 2>&1; then
  ruby_runner=(bundle exec ruby)
else
  printf 'Error: Bundler is required to run this script.\n' >&2
  exit 1
fi

exec "${ruby_runner[@]}" - <<'RUBY'
require "nokogiri"
require "open-uri"

URL = "https://en.wikipedia.org/wiki/List_of_proper_names_of_stars"

def clean_text(node)
  clone = node.dup
  clone.css("script, style, sup").remove
  clone.css("br").each { |br| br.replace(" ") }

  clone.text
    .delete("\u00ad")
    .gsub("\u00a0", " ")
    .gsub(/[[:space:]]+/, " ")
    .strip
end

def display_label(header)
  header.split.map(&:capitalize).join(" ")
end

begin
  html = URI.open(URL, "User-Agent" => "ATLAS random_star.sh", open_timeout: 10, read_timeout: 20).read
  document = Nokogiri::HTML(html)

  table = document.css("table.wikitable").find do |candidate|
    headers = candidate.css("tr").first&.css("th")&.map { |cell| clean_text(cell).downcase } || []
    headers.include?("modern proper name") && headers.include?("designation")
  end

  unless table
    warn "Error: could not find the star proper-name table at #{URL}."
    exit 1
  end

  headers = table.css("tr").first.css("th").map { |cell| clean_text(cell) }
  rows = table.css("tr").filter_map do |row|
    cells = row.xpath("./th|./td")
    next if cells.empty? || row.xpath("./td").empty?
    next unless cells.length == headers.length

    values = cells.map { |cell| clean_text(cell) }
    next if values.first.empty?

    headers.zip(values)
  end

  if rows.empty?
    warn "Error: found the star table, but it did not contain any data rows."
    exit 1
  end

  rows.sample.each do |header, value|
    puts "#{display_label(header)}: #{value}"
  end
rescue OpenURI::HTTPError, SocketError, SystemCallError, Timeout::Error => e
  warn "Error: failed to fetch #{URL}: #{e.message}"
  exit 1
end
RUBY
