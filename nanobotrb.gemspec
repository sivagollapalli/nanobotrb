# frozen_string_literal: true

require_relative "lib/nanobotrb/version"

Gem::Specification.new do |spec|
  spec.name = "nanobotrb"
  spec.version = Nanobotrb::VERSION
  spec.authors = ["Siva Gollapalli"]
  spec.email = ["sgollapalli@csod.com"]

  spec.summary = "Ultra-lightweight personal AI assistant in Ruby"
  spec.description = "Multi-channel, multi-provider AI assistant framework using async Ruby and RubyLLM"
  spec.homepage = "https://github.com/sgollapalli/nanobotrb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "async-http", "~> 0.75"
  spec.add_dependency "ruby_llm", "~> 1.0"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "telegram-bot-ruby", "~> 2.0"
  spec.add_dependency "json", "~> 2.7"
  spec.add_dependency "logger", "~> 1.6"
  spec.add_dependency "serpapi", "~> 1.0"
end
