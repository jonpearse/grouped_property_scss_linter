# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'grouped_property_scss_linter/version'

Gem::Specification.new do |spec|
  spec.name          = "grouped_property_scss_linter"
  spec.version       = GroupedPropertyScssLinter::VERSION
  spec.authors       = ["Jon Pearse"]
  spec.email         = ["jon@jonpearse.net"]
  spec.summary       = "SCSS Lint plugin"
  spec.description   = "Plugin for SCSS lint that lints the order of properties based on fuzzy groups",
  spec.homepage      = "https://github.com/jonpearse/grouped_property_scss_linter"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"

  spec.add_dependency 'scss_lint'
end
