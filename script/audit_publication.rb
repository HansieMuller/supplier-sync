#!/usr/bin/env ruby
require "open3"

# This heuristic scan complements a human provenance review; it cannot prove that
# arbitrary private material or every possible credential format is absent.
def git(*args)
  output, status = Open3.capture2("git", *args)
  abort "Git command failed" unless status.success?
  output
end

paths = git("ls-files", "-z").split("\0")
forbidden = %r{(?:\A|/)(?:master\.key|demo-secrets\.json|\.env(?!\.example)|[^/]+\.(?:dump|sql|log))\z|\A(?:log|tmp|storage|coverage)/.+(?<!\.keep)\z}
hazards = paths.grep(forbidden)
patterns = [
  /-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY/,
  /gh[pousr]_[A-Za-z0-9]{30,}/,
  /AKIA[0-9A-Z]{16}/,
  /(?:api_key|secret_key|password)\s*[=:]\s*["'][A-Za-z0-9+\/]{24,}/i
]
blobs = git("rev-list", "--objects", "--all").lines.filter_map do |line|
  sha, name = line.strip.split(" ", 2)
  next unless git("cat-file", "-t", sha).strip == "blob"
  [sha, name]
end
# Include staged, not-yet-committed blobs as well as reachable history.
blobs += git("ls-files", "--stage").lines.map { |line| parts = line.split; [parts[1], parts[3..].join(" ")] }
blobs.uniq!(&:first)
blobs.each do |sha, name|
  data = git("cat-file", "blob", sha).b
  hazards << "credential pattern in #{name || sha}" if patterns.any? { |pattern| data.match?(pattern) }
end
abort hazards.uniq.join("\n") unless hazards.empty?
puts "PASS: #{paths.size} tracked paths and #{blobs.size} Git blobs scanned; no configured publication hazards."
puts "Human provenance review remains required for private data and employer material."
