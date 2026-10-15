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
def forbidden_path?(path)
  return false unless path
  name = File.basename(path)
  env_file = (name == ".env" || name.start_with?(".env.")) && name != ".env.example"
  secret_or_dump = name.match?(/\A(?:master\.key|demo-secrets\.json|credentials.*\.yml\.enc|[^\/]+\.(?:dump|sql|log))\z/)
  runtime = path.match?(%r{\A(?:log|tmp|storage|coverage)/}) && name != ".keep"
  env_file || secret_or_dump || runtime
end
hazards = paths.select { |path| forbidden_path?(path) }
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
blobs += git("ls-files", "--stage", "-z").split("\0").map do |record|
  metadata, name = record.split("\t", 2)
  [metadata.split[1], name]
end
blobs.each { |_sha, name| hazards << "forbidden historical/staged path: #{name}" if forbidden_path?(name) }
blobs.uniq!(&:first)
blobs.each do |sha, name|
  data = git("cat-file", "blob", sha).b
  hazards << "credential pattern in #{name || sha}" if patterns.any? { |pattern| data.match?(pattern) }
end
abort hazards.uniq.join("\n") unless hazards.empty?
puts "PASS: #{paths.size} tracked paths and #{blobs.size} Git blobs scanned; no configured publication hazards."
puts "Human provenance review remains required for private data and employer material."
